extends VBoxContainer
## Chronologie en ligne verticale : une ligne continue, un point par entrée,
## et la date seulement au survol (à gauche de la ligne). Un point plein
## signale une date exacte, un cercle vide une date approximative ou
## incertaine. Un trait horizontal marque le changement d'année.
##
## Usage : t.add_entry(date_floue, texte, couleur, rappel)
## Dans une colonne étroite (fiche), `compact = true` : la ligne est au bord
## et la date s'affiche à sa droite, par-dessus le texte, au survol.

const UiKit := preload("res://ui/ui_kit.gd")
const Dates := preload("res://core/model/dates.gd")

const GUTTER := 210.0     ## colonne de la ligne ; la date s'affiche à sa gauche au survol
const LINE_X := 196.0
const LINE_COLOR := Color("4b3f5c")
const TEXT_COLOR := Color("eae4f2")

var _font: Font
var compact := false


func _init() -> void:
	add_theme_constant_override("separation", 0)
	_font = ThemeDB.fallback_font


func clear() -> void:
	for c in get_children():
		c.queue_free()


## Une date floue (FORMAT §7) est-elle exacte au jour ?
static func is_exact(edtf: String) -> bool:
	return RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(edtf.strip_edges()) != null


## Ajoute une entrée. `year_break` : vrai pour la première entrée d'une année.
func add_entry(edtf: String, text: String, color: Color, on_press: Callable, year_break := false, extra: Control = null) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cell := _Rail.new()
	cell.custom_minimum_size = Vector2(28.0 if compact else GUTTER, 0)
	cell.line_x = 12.0 if compact else LINE_X
	cell.pill_right = compact
	if compact:
		cell.z_index = 1
	cell.size_flags_vertical = Control.SIZE_FILL
	cell.date_text = Dates.label(edtf)
	cell.exact = is_exact(edtf)
	cell.dot_color = color if color.a > 0 else Color("c8b6ff")
	cell.year_break = year_break
	cell.font = _font
	cell.tooltip_text = cell.date_text
	row.add_child(cell)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 3)
	pad.add_theme_constant_override("margin_bottom", 3)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := UiKit.button(text, on_press)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.tooltip_text = cell.date_text
	if color.a > 0:
		b.add_theme_color_override("font_color", color)
	pad.add_child(b)
	row.add_child(pad)
	if extra != null:
		row.add_child(extra)
	# la date apparaît dès que la souris passe sur l'entrée (le point ou le texte)
	for c in [b, cell]:
		c.mouse_entered.connect(func(): cell.set_hover(true))
		c.mouse_exited.connect(func(): cell.set_hover(false))
	add_child(row)
	return b


class _Rail extends Control:
	var date_text := ""
	var exact := true
	var dot_color := Color.WHITE
	var year_break := false
	var font: Font
	var hover := false
	var line_x := LINE_X
	var pill_right := false

	func set_hover(on: bool) -> void:
		hover = on
		queue_redraw()

	func _draw() -> void:
		var x := line_x
		var cy := size.y / 2.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), LINE_COLOR, 2.0)
		if year_break:
			draw_line(Vector2(x - 16, 1), Vector2(x + 16, 1), Color("a59cb3"), 3.0)
		var r := 7.0 if hover else 6.0
		if exact:
			draw_circle(Vector2(x, cy), r, dot_color)
		else:
			draw_circle(Vector2(x, cy), r, Color("16131a"))
			draw_arc(Vector2(x, cy), r, 0, TAU, 24, dot_color, 2.0, true)
		if hover and date_text != "":
			var fs := 14
			var tw := font.get_string_size(date_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var box := Rect2(Vector2(x + 14, cy - 13), Vector2(tw + 16, 26)) if pill_right \
				else Rect2(Vector2(x - 14 - tw - 16, cy - 13), Vector2(tw + 16, 26))
			draw_style_box(_pill(), box)
			draw_string(font, Vector2(box.position.x + 8, cy + 5), date_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT_COLOR)

	func _pill() -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("2d2636")
		sb.border_color = dot_color.darkened(0.2)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		return sb
