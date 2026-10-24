extends Control
## Panneau escamotable : il sort de l'écran par son bord (gauche ou droite) et
## y rentre, avec une flèche toujours visible sur le bord. L'espace libéré va
## au reste de l'écran. L'état (ouvert ou caché) est retenu dans les réglages.
##
## Usage, dans un HBoxContainer :
##   var p = SlidePanel.make(app, "nav", "left", 190, contenu)
##   hbox.add_child(p)

signal toggled(open: bool)

const HANDLE := 22.0      ## largeur de la languette à flèche, toujours visible
const DURATION := 0.18    ## durée de l'animation, en secondes

var side := "left"
var panel_width := 260.0
var key := ""
var app: Node = null
var content: Control

var _inner: PanelContainer
var _handle: Button
var _t := 1.0
var _open := true
var _tween: Tween


## `p_key` : nom du réglage qui retient l'état ("" = non retenu).
static func make(p_app: Node, p_key: String, p_side: String, p_width: float, p_content: Control,
		default_open := true, bg := Color("221d29")) -> Control:
	var p = load("res://ui/widgets/slide_panel.gd").new()
	p._setup(p_app, p_key, p_side, p_width, p_content, default_open, bg)
	return p


func _setup(p_app: Node, p_key: String, p_side: String, p_width: float, p_content: Control,
		default_open: bool, bg: Color) -> void:
	app = p_app
	key = p_key
	side = p_side
	panel_width = p_width
	content = p_content
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_FILL
	_inner = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_content_margin_all(8)
	_inner.add_theme_stylebox_override("panel", sb)
	_inner.add_child(content)
	add_child(_inner)
	_handle = Button.new()
	_handle.focus_mode = Control.FOCUS_NONE
	_handle.add_theme_font_size_override("font_size", 20)
	var hs := StyleBoxFlat.new()
	hs.bg_color = bg.darkened(0.25)
	var hh := hs.duplicate()
	hh.bg_color = Color("3a3146")
	for st in ["normal", "focus", "disabled"]:
		_handle.add_theme_stylebox_override(st, hs)
	_handle.add_theme_stylebox_override("hover", hh)
	_handle.add_theme_stylebox_override("pressed", hh)
	_handle.add_theme_color_override("font_color", Color("a59cb3"))
	_handle.add_theme_color_override("font_hover_color", Color("eae4f2"))
	_handle.pressed.connect(toggle)
	add_child(_handle)
	var start := default_open
	if app != null and key != "":
		start = bool(app.settings.get_value("panneaux", key, default_open))
	_open = start
	_t = 1.0 if start else 0.0
	resized.connect(_layout)
	_apply()


func is_open() -> bool:
	return _open


func toggle() -> void:
	set_open(not _open)


func set_open(open: bool, animate := true) -> void:
	if open == _open and _tween == null:
		return
	_open = open
	if app != null and key != "":
		app.settings.set_value("panneaux", key, open)
		app.save_settings()
	if _tween != null:
		_tween.kill()
		_tween = null
	var target := 1.0 if open else 0.0
	if animate and is_inside_tree():
		_inner.visible = true
		_tween = create_tween()
		_tween.tween_method(_set_t, _t, target, DURATION * absf(target - _t)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.finished.connect(func(): _tween = null)
	else:
		_set_t(target)
	toggled.emit(open)


func _set_t(t: float) -> void:
	_t = clampf(t, 0.0, 1.0)
	_apply()


func _apply() -> void:
	custom_minimum_size.x = HANDLE + panel_width * _t
	_inner.visible = _t > 0.001
	var left := side == "left"
	# flèche : vers le bord quand le panneau est ouvert (pour le cacher), vers l'écran sinon
	if left:
		_handle.text = "‹" if _open else "›"
	else:
		_handle.text = "›" if _open else "‹"
	var what := "le menu" if key == "nav" else "le panneau"
	_handle.tooltip_text = ("Cacher " + what) if _open else ("Afficher " + what)
	if key == "nav":
		_handle.tooltip_text += " (Ctrl+B)"
	_layout()


func _layout() -> void:
	var h := size.y
	var w := panel_width
	if side == "left":
		# le panneau glisse vers la gauche, hors de l'écran ; la languette le suit
		_inner.position = Vector2(-(1.0 - _t) * w, 0)
		_handle.position = Vector2(w * _t, 0)
	else:
		# le panneau glisse vers la droite, hors de l'écran
		_handle.position = Vector2(0, 0)
		_inner.position = Vector2(HANDLE, 0)
	_inner.size = Vector2(w, h)
	_handle.size = Vector2(HANDLE, h)
