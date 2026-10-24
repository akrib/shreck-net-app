extends Control
## Camembert en anneau. Les parts suivent l'ordre des données ; au-delà de
## MAX_SLICES parts, les plus petites sont réunies en « Autres ». Survol : la part
## s'éclaircit et son nom s'affiche au centre ; appui : la part est choisie
## (signal `slice_selected`, -1 pour aucune) et se détache.

signal slice_selected(index: int)

const PALETTE := [Color("8fd3ff"), Color("c8b6ff"), Color("9be3a8"), Color("f5e08a"), Color("ff8aa8"),
	Color("ffb38a"), Color("7fd59b"), Color("d7a6ff"), Color("e0b04a"), Color("5d8fb8"), Color("b9b2c4")]
const MAX_SLICES := 10
const OTHERS := "Autres"

## Parts : [{label, value, color, keys}] ; `keys` : les valeurs d'origine réunies dans la part.
var slices: Array = []
var total := 0
var selected := -1
var hover := -1
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		hover = -1
		queue_redraw())


## `rows` : [[clé, libellé, nombre]] (comme Stats.breakdown), déjà dans l'ordre voulu.
## `grey_keys` : clés dessinées en gris (non renseigné).
func set_rows(rows: Array, grey_keys := [""]) -> void:
	slices = []
	total = 0
	var main_rows := rows
	var rest := []
	if rows.size() > MAX_SLICES:
		var sorted := rows.duplicate()
		sorted.sort_custom(func(a, b): return a[2] > b[2])
		var keep := {}
		for r in sorted.slice(0, MAX_SLICES - 1):
			keep[r[0]] = true
		main_rows = rows.filter(func(r): return keep.has(r[0]))
		rest = rows.filter(func(r): return not keep.has(r[0]))
	var ci := 0
	for r in main_rows:
		var grey: bool = grey_keys.has(r[0])
		slices.append({"label": str(r[1]), "value": int(r[2]), "keys": [r[0]],
			"color": Color("6b6475") if grey else PALETTE[ci % PALETTE.size()]})
		if not grey:
			ci += 1
		total += int(r[2])
	if not rest.is_empty():
		var v := 0
		for r in rest:
			v += int(r[2])
		slices.append({"label": "%s (%d)" % [OTHERS, rest.size()], "value": v, "keys": rest.map(func(r): return r[0]), "color": Color("4b3f5c")})
		total += v
	selected = -1
	hover = -1
	queue_redraw()


func select(i: int) -> void:
	selected = i if i != selected else -1
	queue_redraw()
	slice_selected.emit(selected)


func _geom() -> Array:
	var c := size / 2.0
	var r_out := minf(size.x, size.y) / 2.0 - 12.0
	return [c, r_out, r_out * 0.56]


func _draw() -> void:
	var g := _geom()
	var c: Vector2 = g[0]
	var r_out: float = g[1]
	var r_in: float = g[2]
	if total <= 0 or r_out <= 10.0:
		draw_string(_font, Vector2(8, size.y / 2.0), "Aucune donnée avec ces filtres.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("a59cb3"))
		return
	var a := -PI / 2.0
	for i in slices.size():
		var s: Dictionary = slices[i]
		var span := TAU * float(s.value) / float(total)
		var col: Color = s.color
		if i == hover:
			col = col.lightened(0.18)
		if selected >= 0 and i != selected:
			col = col.darkened(0.35)
		var mid := a + span / 2.0
		var off := Vector2(cos(mid), sin(mid)) * (10.0 if i == selected else 0.0)
		var steps := maxi(4, int(span / TAU * 128.0))
		draw_arc(c + off, (r_out + r_in) / 2.0, a, a + span, steps, col, r_out - r_in, true)
		if span > 0.02 and slices.size() > 1:
			# fine séparation entre les parts
			draw_line(c + Vector2(cos(a), sin(a)) * r_in, c + Vector2(cos(a), sin(a)) * r_out, Color("16131a"), 2.0, true)
		a += span
	# au centre : la part survolée ou choisie, sinon le total
	var i := hover if hover >= 0 else selected
	var big := str(total) if i < 0 else str(slices[i].value)
	var small := "au total" if i < 0 else "%s · %s" % [slices[i].label, pct(slices[i].value)]
	var fs_big := 30
	var w := _font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_big).x
	draw_string(_font, c + Vector2(-w / 2.0, 4), big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_big, Color("eae4f2"))
	var fs := 14
	var maxw := r_in * 1.7
	var txt := small
	while _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw and txt.length() > 4:
		txt = txt.left(txt.length() - 2)
	if txt != small:
		txt = txt.strip_edges() + "…"
	w = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, c + Vector2(-w / 2.0, 26), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("b3a9c2"))


func pct(v: int) -> String:
	return ("%.1f %%" % (100.0 * float(v) / float(maxi(total, 1)))).replace(".", ",")


func _slice_at(p: Vector2) -> int:
	var g := _geom()
	var d: float = p.distance_to(g[0])
	if d < g[2] or d > g[1] + 10.0 or total <= 0:
		return -1
	var ang := fposmod(atan2(p.y - g[0].y, p.x - g[0].x) + PI / 2.0, TAU)
	var acc := 0.0
	for i in slices.size():
		acc += TAU * float(slices[i].value) / float(total)
		if ang <= acc:
			return i
	return slices.size() - 1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _slice_at((event as InputEventMouseMotion).position)
		if h != hover:
			hover = h
			tooltip_text = "" if h < 0 else "%s : %d (%s)" % [slices[h].label, slices[h].value, pct(slices[h].value)]
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var i := _slice_at((event as InputEventMouseButton).position)
		select(i if i >= 0 else selected)
		accept_event()
