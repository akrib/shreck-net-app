extends Control
## Vue du graphe : disposition par forces (calculée progressivement, image par
## image), déplacement au doigt ou à la souris, zoom (pincement, molette,
## boutons), appui sur un sommet pour le sélectionner, double appui pour le
## mettre au centre. Ne lit ni n'écrit aucune note : reçoit GraphData.build().

signal node_selected(key: String)
signal node_activated(key: String)

const Lineage := preload("res://core/analysis/lineage.gd")
const GraphData := preload("res://core/analysis/graph_data.gd")

const IDEAL := 110.0
const ITERATIONS := 320
const MIN_ZOOM := 0.01      ## assez bas pour voir tout un grand coffre d'un coup
const MAX_ZOOM := 4.0
const LABEL_ZOOM := 0.55    ## en dessous, seuls les noms utiles restent écrits
const GRID_FROM := 120      ## au-delà, les voisins se trouvent par une grille
const CUTOFF := IDEAL * 3.0 ## la répulsion ne joue qu'entre points proches : sinon un grand
							## graphe « explose » et ne tient plus à l'écran
const FRAME_BUDGET_MS := 12

var data := {"nodes": {}, "edges": [], "center": ""}
var pos := {}
var selected := ""
var zoom := 1.0
var offset := Vector2.ZERO

var _iter := 0
var _pinned := {}
var _keys: Array = []
var _drag_node := ""
var _dragging := false
var _moved := false
var _press_at := Vector2.ZERO
var _last_tap := {"key": "", "ms": 0}
var _touches := {}
var _pinch := 0.0
var _font: Font
var _user_view := false   ## l'utilisateur a zoomé ou déplacé la vue : on ne recadre plus tout seul
var _ends := {}           ## extrémités d'un chemin (mises en valeur)
var _ea := PackedInt32Array()     ## liens, en indices de _keys (disposition)
var _eb := PackedInt32Array()
var _ew := PackedFloat32Array()
var _hover_node := ""          ## point sous la souris : son nom s'écrit même à faible zoom
var _hover_pair := ""          ## couple de points dont un lien est sous la souris
var _mouse := Vector2.ZERO


func _ready() -> void:
	mouse_exited.connect(func():
		if _hover_node != "" or _hover_pair != "":
			_hover_node = ""
			_hover_pair = ""
			queue_redraw())
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_font = ThemeDB.fallback_font
	set_process(false)


func set_data(d: Dictionary) -> void:
	data = d
	pos.clear()
	_pinned.clear()
	_keys = data.nodes.keys()
	_keys.sort()
	var idx := {}
	for i in _keys.size():
		idx[_keys[i]] = i
	_ea = PackedInt32Array()
	_eb = PackedInt32Array()
	_ew = PackedFloat32Array()
	for e in data.edges:
		if idx.has(e.a) and idx.has(e.b):
			_ea.append(idx[e.a])
			_eb.append(idx[e.b])
			_ew.append(0.35 if e.kind == "copresence" else 1.0)
	var center: String = str(data.get("center", ""))
	var n := _keys.size()
	# position de départ déterministe : spirale (angle d'or), les premiers cercles
	# autour du centre d'abord ; les points sont déjà répartis, sans se chevaucher
	var order := _keys.duplicate()
	order.sort_custom(func(x, y):
		var rx: int = int(data.nodes[x].get("ring", 1))
		var ry: int = int(data.nodes[y].get("ring", 1))
		return rx < ry if rx != ry else str(x) < str(y))
	var k := 0
	for key in order:
		if key == center:
			pos[key] = Vector2.ZERO
			continue
		var angle := float(k) * 2.399963 + float(hash(key) % 100) / 400.0
		pos[key] = Vector2(cos(angle), sin(angle)) * IDEAL * 0.9 * sqrt(float(k) + 1.0)
		k += 1
	if center != "" and pos.has(center):
		_pinned[center] = true
	if selected != "" and not pos.has(selected):
		selected = ""
	_hover_node = ""
	_hover_pair = ""
	_ends.clear()
	for k2 in data.get("ends", []):
		_ends[str(k2)] = true
	for k2 in _ends:
		if pos.has(k2):
			_pinned[k2] = true
	if _ends.size() == 2:
		# chemin : départ à gauche, arrivée à droite
		var e: Array = _ends.keys()
		if pos.has(e[0]) and pos.has(e[1]):
			pos[e[0]] = Vector2(-IDEAL * 2.5, 0)
			pos[e[1]] = Vector2(IDEAL * 2.5, 0)
	_iter = 0
	zoom = 1.0
	offset = Vector2.ZERO
	_user_view = false
	var fixed: Dictionary = data.get("fixed_pos", {})
	if not fixed.is_empty():
		# disposition imposée (chemins) : pas de calcul de forces
		for key in _keys:
			if fixed.has(key):
				pos[key] = fixed[key]
		_iter = ITERATIONS
	set_process(n > 1 and fixed.is_empty())
	queue_redraw()
	if n <= 1 or not fixed.is_empty():
		fit_view.call_deferred()


func _process(_delta: float) -> void:
	if _iter >= ITERATIONS:
		set_process(false)
		if not _user_view:
			fit_view()
		return
	# autant d'itérations que le budget de l'image le permet (au moins une)
	var t0 := Time.get_ticks_msec()
	while _iter < ITERATIONS:
		_step()
		_iter += 1
		if Time.get_ticks_msec() - t0 >= FRAME_BUDGET_MS:
			break
	if not _user_view:
		fit_view()
	queue_redraw()


## Une itération de Fruchterman-Reingold, avec une légère attraction vers le centre.
func _step() -> void:
	var n := _keys.size()
	# tableaux compacts : beaucoup plus rapides que des dictionnaires en GDScript
	var P := PackedVector2Array()
	P.resize(n)
	for i in n:
		P[i] = pos[_keys[i]]
	var D := PackedVector2Array()
	D.resize(n)
	var k2 := IDEAL * IDEAL
	if n > GRID_FROM:
		_repel_grid(P, D)
	else:
		for i in n:
			var pa := P[i]
			for j in range(i + 1, n):
				var delta := pa - P[j]
				var d := maxf(delta.length(), 0.5)
				if d > CUTOFF:
					continue
				var push := delta * (k2 / (d * d))
				D[i] += push
				D[j] -= push
	for m in _ea.size():
		var a := _ea[m]
		var b := _eb[m]
		var delta := P[a] - P[b]
		var pull := delta * (delta.length() / IDEAL) * _ew[m]
		D[a] -= pull
		D[b] += pull
	var temp := 30.0 * (1.0 - float(_iter) / ITERATIONS) + 1.5
	for i in n:
		var key: String = _keys[i]
		if _pinned.has(key):
			continue
		var dv := D[i] - P[i] * 0.03
		var l := dv.length()
		if l > 0.0:
			pos[key] = P[i] + dv / l * minf(l, temp)


## Répulsion approchée pour les grands graphes : seuls les sommets des cases
## voisines se repoussent (grille de la taille du rayon d'action). O(n) au lieu de O(n²).
func _repel_grid(P: PackedVector2Array, D: PackedVector2Array) -> void:
	var cell := CUTOFF
	var grid := {}
	for i in P.size():
		var c := Vector2i(floori(P[i].x / cell), floori(P[i].y / cell))
		if not grid.has(c):
			grid[c] = PackedInt32Array()
		var arr: PackedInt32Array = grid[c]
		arr.append(i)
		grid[c] = arr
	var k2 := IDEAL * IDEAL
	var offs := [Vector2i(0, 0), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for c in grid:
		var here: PackedInt32Array = grid[c]
		for o in offs:
			var oc: Vector2i = c + o
			if not grid.has(oc):
				continue
			var there: PackedInt32Array = grid[oc]
			var same: bool = o == Vector2i(0, 0)
			for ii in here.size():
				var a := here[ii]
				var pa := P[a]
				var j0 := ii + 1 if same else 0
				for jj in range(j0, there.size()):
					var b := there[jj]
					var delta := pa - P[b]
					var d := maxf(delta.length(), 0.5)
					if d > CUTOFF:
						continue
					var push := delta * (k2 / (d * d))
					D[a] += push
					D[b] -= push


## Cadre tous les points (« Voir tout »), quel que soit le nombre de fiches.
func fit_view() -> void:
	if pos.is_empty() or size.x < 10:
		return
	var r := Rect2(pos.values()[0], Vector2.ZERO)
	for p in pos.values():
		r = r.expand(p)
	r = r.grow(20)
	var sz := Vector2(maxf(size.x - 24.0, 10.0), maxf(size.y - 40.0, 10.0))
	zoom = clampf(minf(sz.x / maxf(r.size.x, 1.0), sz.y / maxf(r.size.y, 1.0)), MIN_ZOOM, 2.5)
	# marge pour les noms écrits sous les points les plus à gauche et à droite
	# (seulement quand ils sont écrits : peu de points ou zoom suffisant)
	if _keys.size() <= 30 or zoom >= LABEL_ZOOM:
		var half := 0.0
		for key in _keys:
			var p: Vector2 = pos[key]
			if absf(p.x - r.position.x) < 30.0 or absf(p.x - r.end.x) < 30.0:
				var lw := _font.get_string_size(str(data.nodes[key].name).left(26), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				half = maxf(half, lw / 2.0)
		if half > 0.0:
			sz.x = maxf(sz.x - 2.0 * half, 10.0)
			zoom = clampf(minf(sz.x / maxf(r.size.x, 1.0), sz.y / maxf(r.size.y, 1.0)), MIN_ZOOM, 2.5)
	offset = -r.get_center() * zoom + Vector2(0, -10)
	queue_redraw()


## « Voir tout » à la demande : recadre et reprend le recadrage automatique.
func show_all() -> void:
	_user_view = false
	fit_view()


func zoom_by(f: float, at := Vector2(-1, -1)) -> void:
	var pivot := at if at.x >= 0 else size / 2
	var world := to_world(pivot)
	zoom = clampf(zoom * f, MIN_ZOOM, MAX_ZOOM)
	offset = pivot - size / 2 - world * zoom
	_user_view = true
	queue_redraw()


func to_screen(p: Vector2) -> Vector2:
	return p * zoom + offset + size / 2


func to_world(s: Vector2) -> Vector2:
	return (s - size / 2 - offset) / zoom


func _radius(key: String) -> float:
	return 14.0 if key == str(data.get("center", "")) or _ends.has(key) else 10.0


func _hit(s: Vector2) -> String:
	var best := ""
	var best_d := 30.0
	for key in _keys:
		var d := to_screen(pos[key]).distance_to(s)
		if d < best_d:
			best_d = d
			best = key
	return best


# ------------------------------------------------------------------ dessin

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("120f16"))
	if _keys.is_empty():
		draw_string(_font, Vector2(16, 32), "Aucune relation à afficher avec ces filtres.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("a59cb3"))
		return
	var pair_count := {}
	var has_sel := selected != ""
	var neighbours := {}
	if has_sel:
		for e in data.edges:
			if e.a == selected:
				neighbours[e.b] = true
			elif e.b == selected:
				neighbours[e.a] = true
	for e in data.edges:
		if not pos.has(e.a) or not pos.has(e.b):
			continue
		var pk := "%s|%s" % [mini(hash(e.a), hash(e.b)), maxi(hash(e.a), hash(e.b))]
		var idx: int = int(pair_count.get(pk, 0))
		pair_count[pk] = idx + 1
		var a := to_screen(pos[e.a])
		var b := to_screen(pos[e.b])
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var shift := normal * (float(idx) * 6.0 - 3.0 * float(mini(idx, 1)))
		a += shift
		b += shift
		var col: Color = GraphData.edge_color(e)
		var w := 1.6
		if e.kind == "copresence":
			w = 1.0 + minf(float(e.weight), 5.0) * 0.6
		var touches_sel: bool = has_sel and (e.a == selected or e.b == selected)
		if e.has("rank"):
			# chemin : le meilleur en épais, les autres plus discrets
			w = 4.0 if int(e.rank) == 0 else 2.0
			if int(e.rank) > 0:
				col.a = 0.75
		if has_sel and not touches_sel:
			col.a = 0.18
		elif touches_sel:
			w += 1.4
		var ra := _radius(e.a) * zoom + 2
		var rb := _radius(e.b) * zoom + 2
		var start := a + dir * ra
		var end := b - dir * rb
		if e.kind == "faveur" or e.kind == "indice" or e.kind == "lignee":
			draw_dashed_line(start, end, col, w, 6.0 if e.kind == "faveur" else 3.0, true, true)
		else:
			draw_line(start, end, col, w, true)
		if e.directed:
			var tip := end
			var head := (7.0 + w) * clampf(zoom, 0.5, 1.0)
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * head + normal * head * 0.5, tip - dir * head - normal * head * 0.5]), col)
		# probabilité écrite sur le meilleur chemin, et sur les liens du point touché
		if e.has("plabel") and zoom >= 0.22 and (int(e.get("rank", 0)) == 0 or touches_sel):
			var mid := (start + end) / 2 + normal * 12.0
			var pl := str(e.plabel)
			var pw := _font.get_string_size(pl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_rect(Rect2(mid - Vector2(pw / 2 + 3, 12), Vector2(pw + 6, 16)), Color(0.07, 0.06, 0.09, 0.85))
			draw_string(_font, mid + Vector2(-pw / 2, 0), pl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.3))
	for key in _keys:
		var n: Dictionary = data.nodes[key]
		var p := to_screen(pos[key])
		var r := _radius(key) * clampf(zoom, 0.35, 1.6)
		var col := GraphData.node_color(n)
		var dim: bool = has_sel and key != selected and not neighbours.has(key)
		if dim:
			col.a = 0.35
		if n.missing:
			draw_arc(p, r, 0, TAU, 24, col, 2.0, true)
		else:
			draw_circle(p, r, col)
		if key == selected or _ends.has(key):
			draw_arc(p, r + 4, 0, TAU, 32, Color.WHITE if key == selected else Color("e0b04a"), 2.0, true)
		# à faible zoom, on n'écrit que les noms utiles (sélection, centre, voisins, extrémités)
		if zoom < LABEL_ZOOM and _keys.size() > 30 and key != selected and key != str(data.get("center", "")) \
				and not _ends.has(key) and not neighbours.has(key) and key != _hover_node:
			continue
		var label := str(n.name)
		if label.length() > 26:
			label = label.left(24) + "…"
		var fs := 13 if zoom < 1.3 else 15
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tcol := Color(1, 1, 1, 0.35) if dim else Color("eae4f2")
		draw_string(_font, p + Vector2(-tw / 2, r + fs + 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tcol)
		# chef de lignée : la lignée est montrée par lui (anneau violet, mention sous le nom)
		var heads: Array = n.get("heads", [])
		if not heads.is_empty():
			var lc := Color("b79cff")
			if dim:
				lc.a = 0.35
			draw_arc(p, r + 3, 0, TAU, 32, lc, 2.0, true)
			var mention := Lineage.chef_mention(heads.map(func(h): return str(h.name)))
			if mention.length() > 40:
				mention = mention.left(38) + "…"
			var fs2 := fs - 2
			var mw := _font.get_string_size(mention, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			draw_string(_font, p + Vector2(-mw / 2, r + fs + fs2 + 6), mention, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, lc)
	if _hover_pair != "":
		_draw_pair_box()


## Les liens entre deux points, quand la souris passe sur l'un d'eux :
## « Victor Morel → Élise Varga : doit une faveur mineure (active) », etc.
func _draw_pair_box() -> void:
	var lines := PackedStringArray()
	var cols := []
	for e in data.edges:
		if _pair_of(e) != _hover_pair:
			continue
		var na := str(data.nodes.get(e.a, {}).get("name", e.a))
		var nb := str(data.nodes.get(e.b, {}).get("name", e.b))
		var t := "%s %s %s : %s" % [na, "→" if e.directed else "—", nb, str(e.get("label", ""))]
		if str(e.get("source", "")) != "" and str(e.kind) != "faveur":
			t += " (selon %s%s)" % [str(e.source), (", crédibilité %d" % int(e.cred)) if e.has("cred") and int(e.cred) < 6 else ""]
		lines.append(t)
		cols.append(GraphData.edge_color(e).lightened(0.25))
		if lines.size() >= 8:
			break
	if lines.is_empty():
		return
	var fs := 14
	var w := 0.0
	for l in lines:
		w = maxf(w, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var h := lines.size() * (fs + 6) + 10
	var at := _mouse + Vector2(16, 16)
	at.x = clampf(at.x, 4, maxf(4, size.x - w - 24))
	at.y = clampf(at.y, 4, maxf(4, size.y - h - 4))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.11, 0.09, 0.14, 0.95)
	box.border_color = Color("4b3f5c")
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	draw_style_box(box, Rect2(at, Vector2(w + 20, h)))
	for i in lines.size():
		draw_string(_font, at + Vector2(10, 6 + (i + 1) * (fs + 6) - 6), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[i])


func _pair_of(e: Dictionary) -> String:
	var a := str(e.a)
	var b := str(e.b)
	return a + "|" + b if a < b else b + "|" + a


## Couple dont un lien passe à moins de 6 pixels de `s` ("" sinon).
func _hit_pair(s: Vector2) -> String:
	var best := ""
	var best_d := 6.0
	for e in data.edges:
		if not pos.has(e.a) or not pos.has(e.b):
			continue
		var a := to_screen(pos[e.a])
		var b := to_screen(pos[e.b])
		var q := Geometry2D.get_closest_point_to_segment(s, a, b)
		var d := q.distance_to(s)
		if d < best_d:
			best_d = d
			best = _pair_of(e)
	return best


func _linked(a: String, b: String) -> bool:
	for e in data.edges:
		if (e.a == a and e.b == b) or (e.a == b and e.b == a):
			return true
	return false


# ------------------------------------------------------------------ interaction

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		_pinch = 0.0
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var dist: float = pts[0].distance_to(pts[1])
			if _pinch > 0.0 and dist > 0.0:
				zoom_by(dist / _pinch, (pts[0] + pts[1]) / 2)
			_pinch = dist
			_moved = true
			accept_event()
		return
	if event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		zoom_by(g.factor, g.position)
		accept_event()
		return
	if event is InputEventPanGesture:
		_user_view = true
		offset -= (event as InputEventPanGesture).delta * 8.0
		queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 / 1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_at = mb.position
				_moved = false
				_drag_node = _hit(mb.position)
				_dragging = true
			else:
				_dragging = false
				if not _moved and _touches.size() < 2:
					_tap(_hit(mb.position))
				_drag_node = ""
			accept_event()
		return
	if event is InputEventMouseMotion and not _dragging:
		_mouse = (event as InputEventMouseMotion).position
		var hn := _hit(_mouse)
		var hp := "" if hn != "" else _hit_pair(_mouse)
		if hn != _hover_node or hp != _hover_pair or hp != "":
			_hover_node = hn
			_hover_pair = hp
			queue_redraw()
		return
	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if _touches.size() >= 2:
			return
		if mm.position.distance_to(_press_at) > 8.0:
			_moved = true
		if not _moved:
			return
		_user_view = true
		if _drag_node != "":
			pos[_drag_node] = to_world(mm.position)
			_pinned[_drag_node] = true
		else:
			offset += mm.relative
		queue_redraw()
		accept_event()


func _tap(key: String) -> void:
	var now := Time.get_ticks_msec()
	if key != "" and _last_tap.key == key and now - int(_last_tap.ms) < 450:
		node_activated.emit(key)
		_last_tap = {"key": "", "ms": 0}
		return
	_last_tap = {"key": key, "ms": now}
	selected = key
	node_selected.emit(key)
	queue_redraw()
