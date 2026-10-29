extends Control
## Arbres dessinés de haut en bas (filiations, clans et lignées) : chaque arbre
## est disposé génération par génération, les parents centrés au-dessus de leurs
## enfants ; plusieurs arbres se rangent en lignes. Déplacement à la souris,
## zoom à la molette, appui sur une case pour la choisir, double appui pour
## l'ouvrir. Ne lit ni n'écrit aucune note.
##
## set_forest([{title, nodes: {clé: {label, sub, color, faded, kind}}, roots: [clés],
##   children: {clé: [clés]}, styles: {"a>b": style}, extra: [{a, b, style}]}], clé mise en valeur)
## Styles : "solid", "dashed" (gris, plein ou incertain), "lig", "lig_dashed" (violet :
## lignée déclarée ou déduite), "bad" (rouge pointillé : second sire, lignée incohérente).
## `extra` : liens qui ne servent pas à la disposition (style "bad" par défaut).
## Une case `kind: "group"` (lignée) a un fond violet. Une case qui porte `head`
## (« Chef de la lignée de Karios ») est plus haute : cadre violet, mention en dessous.

signal node_selected(key: String)
signal node_activated(key: String)

const STYLE_COLORS := {"solid": Color("8a7fa0"), "dashed": Color("8a7fa0"), "lig": Color("b79cff"), "lig_dashed": Color("b79cff"), "bad": Color("ff7a6b")}
const NODE_W := 210.0
const NODE_H := 54.0
const HEAD_H := 18.0     ## ligne de plus pour la mention d'un chef de lignée
const HEAD_COLOR := Color("b79cff")
const GAP_X := 26.0
const LEVEL_H := 104.0
const TREE_GAP := 70.0
const ROW_GAP := 90.0
const MAX_ROW_W := 2600.0
const MIN_ZOOM := 0.08
const MAX_ZOOM := 2.5

var trees: Array = []
var pos := {}            ## clé -> Vector2 (centre de la case, coordonnées du monde)
var heights := {}        ## clé -> hauteur de la case (plus haute pour un chef de lignée)
var owner_tree := {}     ## clé -> indice de l'arbre
var titles: Array = []   ## [[texte, Vector2, largeur disponible]]
var selected := ""
var highlight := ""
var zoom := 1.0
var offset := Vector2.ZERO
var _bounds := Rect2()
var _font: Font
var _drag := false
var _moved := false
var _press := Vector2.ZERO
var _last_click := {"key": "", "ms": 0}
var _hover := ""
var _pending := ""      ## cadrage à faire quand la vue aura sa taille : clé à montrer, ou "*" (tout)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_font = ThemeDB.fallback_font
	resized.connect(func():
		if size.x < 10.0 or trees.is_empty():
			return
		if _pending != "":
			var p := _pending
			_pending = ""
			if p != "*" and pos.has(p):
				focus_on(p)
			else:
				fit_view()
		elif _bounds.size != Vector2.ZERO and zoom == 1.0 and offset == Vector2.ZERO:
			fit_view())


func set_forest(p_trees: Array, p_highlight := "") -> void:
	trees = p_trees
	highlight = p_highlight
	selected = p_highlight
	_layout()
	if size.x < 10.0:
		# l'écran n'est pas encore disposé (on vient d'y arriver) : cadrer quand il le sera
		_pending = highlight if highlight != "" and pos.has(highlight) else "*"
	elif highlight != "" and pos.has(highlight):
		focus_on(highlight)
	else:
		fit_view()
	queue_redraw()


func node_count() -> int:
	return pos.size()


# ------------------------------------------------------------------ disposition

func _layout() -> void:
	pos.clear()
	heights.clear()
	owner_tree.clear()
	titles.clear()
	var cursor := Vector2.ZERO
	var row_h := 0.0
	for ti in trees.size():
		var t: Dictionary = trees[ti]
		var local := {}
		var next := [0.0]
		var seen := {}
		var depth := [0]
		for r in t.get("roots", []):
			_place(str(r), 0, t, local, next, seen, depth)
		# des cases jamais atteintes depuis une racine (boucle) : à la suite
		for k in t.nodes:
			if not local.has(k):
				_place(str(k), 0, t, local, next, seen, depth)
		var w: float = next[0] * (NODE_W + GAP_X) - GAP_X
		# le titre peut déborder un peu un arbre étroit, sans chevaucher le suivant
		var title_w: float = ThemeDB.fallback_font.get_string_size(str(t.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		w = maxf(w, minf(title_w, 2.0 * NODE_W + GAP_X))
		var h: float = (depth[0] + 1) * LEVEL_H
		if cursor.x > 0.0 and cursor.x + w > MAX_ROW_W:
			cursor = Vector2(0.0, cursor.y + row_h + ROW_GAP)
			row_h = 0.0
		var origin := cursor + Vector2(0.0, 34.0)
		for k in local:
			var lp: Vector2 = local[k]
			pos[k] = origin + Vector2(lp.x * (NODE_W + GAP_X) + NODE_W / 2.0, lp.y * LEVEL_H + NODE_H / 2.0)
			if str((t.nodes as Dictionary).get(k, {}).get("head", "")) != "":
				heights[k] = NODE_H + HEAD_H
				pos[k].y += HEAD_H / 2.0  # même haut que les autres cases du niveau, la mention en dessous
			owner_tree[k] = ti
		titles.append([str(t.get("title", "")), cursor + Vector2(0.0, 14.0), w])
		cursor.x += maxf(w, 160.0) + TREE_GAP
		row_h = maxf(row_h, h + 34.0)
	_bounds = Rect2()
	var first := true
	for k in pos:
		var r := node_rect(k)
		_bounds = r if first else _bounds.merge(r)
		first = false
	for t in titles:
		_bounds = _bounds.expand(t[1]) if not first else Rect2(t[1], Vector2.ONE)
		first = false


## Case d'un nœud, en coordonnées du monde.
func node_rect(k: String) -> Rect2:
	var h: float = heights.get(k, NODE_H)
	return Rect2(pos[k] - Vector2(NODE_W, h) / 2.0, Vector2(NODE_W, h))


func _half(k: String) -> float:
	return float(heights.get(k, NODE_H)) / 2.0


## Disposition « bien rangée » : les feuilles côte à côte, chaque parent au milieu de ses enfants.
func _place(k: String, level: int, t: Dictionary, local: Dictionary, next: Array, seen: Dictionary, depth: Array) -> float:
	if seen.has(k):
		return local[k].x if local.has(k) else next[0]
	seen[k] = true
	depth[0] = maxi(depth[0], level)
	var xs := []
	for c in t.get("children", {}).get(k, []):
		if not seen.has(str(c)):
			xs.append(_place(str(c), level + 1, t, local, next, seen, depth))
	var x: float
	if xs.is_empty():
		x = next[0]
		next[0] += 1.0
	else:
		x = (float(xs[0]) + float(xs[-1])) / 2.0
	local[k] = Vector2(x, level)
	return x


# ------------------------------------------------------------------ vue

func fit_view() -> void:
	if pos.is_empty() or size.x < 10.0:
		zoom = 1.0
		offset = Vector2.ZERO
		queue_redraw()
		return
	var r := _bounds.grow(30.0)
	zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y), MIN_ZOOM, 1.2)
	offset = size / 2.0 - r.get_center() * zoom
	queue_redraw()


func focus_on(key: String) -> void:
	if not pos.has(key):
		return
	# l'arbre entier de cette personne, centré
	var ti: int = owner_tree[key]
	var r := Rect2()
	var first := true
	for k in pos:
		if owner_tree[k] == ti:
			var b := node_rect(k)
			r = b if first else r.merge(b)
			first = false
	r = r.grow(60.0)
	zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y), 0.35, 1.1) if size.x > 10.0 else 1.0
	offset = size / 2.0 - r.get_center() * zoom
	# un grand arbre ne tient pas à l'écran : la case choisie reste visible, en haut
	# (sa descendance est en dessous)
	var kr := node_rect(key)
	var on_screen := Rect2(to_screen(kr.position), kr.size * zoom)
	if size.x > 10.0 and not Rect2(Vector2.ZERO, size).encloses(on_screen):
		offset = Vector2(size.x / 2.0, size.y * 0.22) - pos[key] * zoom
	queue_redraw()


func zoom_by(f: float, at: Vector2) -> void:
	var world := (at - offset) / zoom
	zoom = clampf(zoom * f, MIN_ZOOM, MAX_ZOOM)
	offset = at - world * zoom
	queue_redraw()


func to_screen(p: Vector2) -> Vector2:
	return p * zoom + offset


func key_at(p: Vector2) -> String:
	var w := (p - offset) / zoom
	for k in pos:
		if node_rect(k).has_point(w):
			return k
	return ""


# ------------------------------------------------------------------ dessin

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("141118"))
	if pos.is_empty():
		return
	var fs_title := int(clampf(15.0 * zoom, 9.0, 22.0))
	if zoom >= 0.18:
		for t in titles:
			draw_string(_font, to_screen(t[1]), _fit(str(t[0]), float(t[2]) * zoom, fs_title), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_title, Color("c8b6ff"))
	# liens parent → enfant, en équerre
	for t in trees:
		var styles: Dictionary = t.get("styles", {})
		for a in t.get("children", {}):
			for b in t.children[a]:
				if not pos.has(a) or not pos.has(b):
					continue
				var st := str(styles.get("%s>%s" % [a, b], "solid"))
				_elbow(pos[a] + Vector2(0, _half(a)), pos[b] - Vector2(0, _half(b)), STYLE_COLORS.get(st, Color("8a7fa0")), st in ["dashed", "lig_dashed", "bad"])
		for e in t.get("extra", []):
			if pos.has(e.a) and pos.has(e.b):
				var st := str(e.get("style", "bad"))
				var pa: Vector2 = to_screen(pos[e.a] + Vector2(0, _half(e.a)))
				var pb: Vector2 = to_screen(pos[e.b] - Vector2(0, _half(e.b)))
				var col: Color = STYLE_COLORS.get(st, Color("ff7a6b"))
				if st in ["dashed", "lig_dashed", "bad"]:
					draw_dashed_line(pa, pb, col, 2.0, 8.0 * zoom + 2.0, true)
				else:
					draw_line(pa, pb, col, 2.0, true)
	# cases
	var fs := int(clampf(14.0 * zoom, 6.0, 20.0))
	var fs_sub := int(clampf(11.5 * zoom, 5.0, 16.0))
	for ti in trees.size():
		var nodes: Dictionary = trees[ti].nodes
		for k in nodes:
			if not pos.has(k):
				continue
			var n: Dictionary = nodes[k]
			var wr := node_rect(k)
			var r := Rect2(to_screen(wr.position), wr.size * zoom)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("2a2333") if not n.get("faded", false) else Color("1f1b25")
			if str(n.get("kind", "")) == "group":
				sb.bg_color = Color("3a2d52")
			elif str(n.get("head", "")) != "":
				sb.bg_color = Color("2f2640") if not n.get("faded", false) else Color("261f33")
			sb.set_corner_radius_all(int((14.0 if str(n.get("kind", "")) == "group" else 6.0) * zoom))
			var col: Color = n.get("color", Color("8a7fa0"))
			sb.border_color = col
			sb.border_width_left = maxi(2, int(5.0 * zoom))
			if k == selected or k == highlight or k == _hover:
				sb.border_color = Color.WHITE if k == selected else (Color("e0b04a") if k == highlight else col.lightened(0.3))
				sb.set_border_width_all(maxi(1, int(2.0 * zoom)))
				sb.border_width_left = maxi(2, int(5.0 * zoom))
			draw_style_box(sb, r)
			if str(n.get("head", "")) != "" and not (k == selected or k == highlight or k == _hover):
				draw_rect(r.grow(-0.5), HEAD_COLOR, false, maxf(1.0, 1.5 * zoom), true)
			if zoom < 0.22:
				continue
			var inner := r.grow_individual(-10.0 * zoom, 0, -6.0 * zoom, 0)
			var txt_col := Color("eae4f2") if not n.get("faded", false) else Color("9a91a8")
			draw_string(_font, Vector2(inner.position.x, r.position.y + 22.0 * zoom), _fit(str(n.label), inner.size.x, fs), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)
			var sub := str(n.get("sub", ""))
			if sub != "" and zoom >= 0.4:
				draw_string(_font, Vector2(inner.position.x, r.position.y + 42.0 * zoom), _fit(sub, inner.size.x, fs_sub), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sub, Color("a59cb3"))
			var head := str(n.get("head", ""))
			if head != "" and zoom >= 0.3:
				draw_string(_font, Vector2(inner.position.x, r.position.y + 61.0 * zoom), _fit(head, inner.size.x, fs_sub), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sub, HEAD_COLOR)


## Texte raccourci avec « … » s'il dépasse la largeur.
func _fit(text: String, width: float, fs: int) -> String:
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return text
	var t := text
	while t.length() > 1 and _font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		t = t.left(t.length() - 1)
	return t.strip_edges() + "…"


## Lien en équerre du bas d'une case (`a`) au haut d'une autre (`b`), en coordonnées du monde.
func _elbow(a: Vector2, b: Vector2, col: Color, dashed: bool) -> void:
	var p0 := to_screen(a)
	var p3 := to_screen(b)
	var mid := (p0.y + p3.y) / 2.0
	var pts := [p0, Vector2(p0.x, mid), Vector2(p3.x, mid), p3]
	for i in 3:
		if dashed:
			draw_dashed_line(pts[i], pts[i + 1], col, 2.0, 7.0 * zoom + 2.0, true)
		else:
			draw_line(pts[i], pts[i + 1], col, 2.0, true)


# ------------------------------------------------------------------ souris

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.12, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 / 1.12, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_moved = false
				_press = mb.position
			else:
				_drag = false
				if not _moved:
					_click(key_at(mb.position))
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag:
			if mm.position.distance_to(_press) > 4.0:
				_moved = true
			if _moved:
				offset += mm.relative
				queue_redraw()
		else:
			var h := key_at(mm.position)
			if h != _hover:
				_hover = h
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
				queue_redraw()


func _click(k: String) -> void:
	var now := Time.get_ticks_msec()
	if k != "" and k == str(_last_click.key) and now - int(_last_click.ms) < 400:
		node_activated.emit(k)
		_last_click = {"key": "", "ms": 0}
		return
	_last_click = {"key": k, "ms": now}
	select(k)


func select(k: String) -> void:
	selected = k
	queue_redraw()
	node_selected.emit(k)
