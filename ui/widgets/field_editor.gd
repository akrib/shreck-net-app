extends VBoxContainer
## Éditeur d'un champ de note, adapté à son genre (Schema.FIELDS) :
## liste déroulante, case à cocher, date avec « Aujourd'hui », choix de fiches
## dans un sélecteur, pastilles pour les listes… Utilisé par le formulaire de
## création et par l'éditeur de note.
##
## get_value() renvoie la valeur typée à écrire (texte, nombre, booléen, liste
## ou null) ; is_modified() la compare à la valeur de départ.

signal changed

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const Picker := preload("res://ui/widgets/picker.gd")

var app: Node
var main: Control
var type_name := ""
var field := ""
var kind := "text"
var required := false
var initial: Variant = null

var _value: Variant = null
var _line: LineEdit
var _text: TextEdit
var _option: OptionButton
var _option_codes: Array = []
var _check: CheckButton
var _link_btn: Button
var _flow: HFlowContainer
var _checks := {}
var _suggest: MenuButton


static func make(p_app: Node, p_main: Control, p_type: String, p_field: String, value: Variant, p_required := false) -> VBoxContainer:
	var e = load("res://ui/widgets/field_editor.gd").new()
	e._setup(p_app, p_main, p_type, p_field, value, p_required)
	return e


func _setup(p_app: Node, p_main: Control, p_type: String, p_field: String, value: Variant, p_required: bool) -> void:
	app = p_app
	main = p_main
	type_name = p_type
	field = p_field
	required = p_required
	var def: Dictionary = Schema.FIELDS.get(field, {"label": field, "kind": "text"})
	kind = def.kind
	initial = value
	_value = value
	add_theme_constant_override("separation", 3)
	var label := label_of(type_name, field)
	if kind != "bool":
		add_child(UiKit.muted(label + ("  ★" if required else "")))
	match kind:
		"date":
			_line = UiKit.line_edit("AAAA-MM-JJ", _str(value))
			_line.clear_button_enabled = false
			_line.text_changed.connect(func(_t): _emit())
			add_child(UiKit.hbox([_line, UiKit.button("Aujourd'hui", _today)]))
		"date_floue":
			_line = UiKit.line_edit("ex. 2026-10, 2026-10~, inconnue", _str(value))
			_line.text_changed.connect(func(_t): _emit())
			add_child(_line)
			add_child(UiKit.muted(str(def.get("help", ""))))
		"link":
			_link_btn = UiKit.button("", _pick_one)
			_link_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_link_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_link_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var clear := UiKit.button("×", func(): _set_link(null), "Vider")
			clear.custom_minimum_size.x = UiKit.TOUCH
			add_child(UiKit.hbox([_link_btn, clear]))
			_refresh_link()
		"links", "elements":
			_value = _as_list(value)
			_flow = UiKit.flow()
			add_child(_flow)
			_refresh_chips()
		"enum", "fiabilite", "credibilite", "relation":
			_build_option(value)
		"multi":
			_value = _as_list(value)
			_flow = UiKit.flow()
			add_child(_flow)
			var opts: Array = Schema.options(type_name, field).duplicate()
			for x in _value:
				if not _has_code(opts, x):
					opts.append([str(x), str(x)])
			for o in opts:
				var cb := CheckBox.new()
				cb.text = o[1]
				cb.custom_minimum_size.y = UiKit.TOUCH
				cb.button_pressed = _value.has(o[0])
				cb.toggled.connect(func(_on): _emit())
				_checks[o[0]] = cb
				_flow.add_child(cb)
		"bool":
			_check = CheckButton.new()
			_check.text = label
			_check.custom_minimum_size.y = UiKit.TOUCH
			_check.button_pressed = value == true
			_check.toggled.connect(func(_on): _emit())
			add_child(_check)
		"textlist":
			_text = TextEdit.new()
			_text.text = "\n".join(PackedStringArray(_as_list(value)))
			_text.scroll_fit_content_height = true
			_text.custom_minimum_size.y = UiKit.TOUCH
			_text.placeholder_text = "un par ligne"
			_text.text_changed.connect(_emit)
			_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if def.has("suggest_list"):
				# Menu des valeurs prévues par les règles (postes, influences) : ajoute une ligne.
				_suggest = MenuButton.new()
				_suggest.text = "+ Poste" if def.suggest_list == "postes" else "+ Choisir"
				_suggest.custom_minimum_size = Vector2(UiKit.TOUCH * 2, UiKit.TOUCH)
				_suggest.about_to_popup.connect(_fill_list_suggestions.bind(str(def.suggest_list)))
				_suggest.get_popup().index_pressed.connect(_on_list_suggestion)
				add_child(UiKit.hbox([_text, _suggest]))
			else:
				add_child(_text)
		"number":
			_line = UiKit.line_edit("nombre", _str(value))
			_line.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
			_line.text_changed.connect(func(_t): _emit())
			add_child(_line)
		_:
			_line = UiKit.line_edit("", _str(value))
			_line.text_changed.connect(func(_t): _emit())
			if def.get("suggest", false):
				_suggest = MenuButton.new()
				_suggest.text = "▼"
				_suggest.custom_minimum_size = Vector2(UiKit.TOUCH, UiKit.TOUCH)
				_suggest.tooltip_text = "Valeurs déjà utilisées"
				_suggest.about_to_popup.connect(_fill_suggestions)
				_suggest.get_popup().index_pressed.connect(_on_suggestion)
				add_child(UiKit.hbox([_line, _suggest]))
			else:
				add_child(_line)


# ------------------------------------------------------------------ valeur

func get_value() -> Variant:
	match kind:
		"date", "date_floue", "text":
			var t := _line.text.strip_edges()
			return null if t == "" else t
		"link":
			return _value
		"links", "elements":
			return _value.duplicate()
		"enum", "fiabilite", "credibilite", "relation":
			var code: Variant = _option_codes[_option.selected] if _option.selected >= 0 else null
			return code
		"multi":
			var out := []
			for code in _checks:
				if _checks[code].button_pressed:
					out.append(code)
			return out
		"bool":
			return _check.button_pressed
		"textlist":
			var out := []
			for l in _text.text.split("\n"):
				if l.strip_edges() != "":
					out.append(l.strip_edges())
			return out
		"number":
			var t := _line.text.strip_edges()
			if t.is_valid_int():
				return t.to_int()
			return null if t == "" else t
	return _value


func set_value(v: Variant) -> void:
	match kind:
		"date", "date_floue", "text":
			_line.text = _str(v)
		"link":
			_value = v
			_refresh_link()
		"links", "elements":
			_value = _as_list(v)
			_refresh_chips()
		"enum", "fiabilite", "credibilite", "relation":
			var idx := _option_codes.find(v)
			if idx < 0 and v != null and str(v) != "":
				_option.add_item(str(v))
				_option_codes.append(v)
				idx = _option_codes.size() - 1
			_option.select(maxi(idx, 0))
		"multi":
			for code in _checks:
				_checks[code].button_pressed = _as_list(v).has(code)
		"bool":
			_check.button_pressed = v == true
		"textlist":
			_text.text = "\n".join(PackedStringArray(_as_list(v)))
		"number":
			_line.text = _str(v)
	_emit()


## Vrai si la valeur diffère de celle de départ (vide, null et liste vide sont équivalents).
func is_modified() -> bool:
	return _norm(get_value()) != _norm(initial)


func _norm(v: Variant) -> String:
	if v == null:
		return "bool:false" if kind == "bool" else ""
	if typeof(v) == TYPE_ARRAY:
		var parts := PackedStringArray()
		for x in v:
			parts.append(str(x))
		return "\n".join(parts)
	if typeof(v) == TYPE_BOOL:
		return "bool:" + ("true" if v else "false")
	return str(v).strip_edges()


func _emit() -> void:
	changed.emit()


func _str(v: Variant) -> String:
	return "" if v == null else str(v)


func _as_list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v.duplicate()
	if str(v).strip_edges() == "":
		return []
	return [v]


func _has_code(opts: Array, code: Variant) -> bool:
	for o in opts:
		if str(o[0]) == str(code):
			return true
	return false


# ------------------------------------------------------------------ genres

func _today() -> void:
	var d := Time.get_date_dict_from_system()
	_line.text = "%04d-%02d-%02d" % [d.year, d.month, d.day]
	_emit()


func _build_option(value: Variant) -> void:
	var opts: Array = Schema.options(type_name, field)
	var labels := []
	_option_codes = []
	if not required or value == null:
		labels.append("—")
		_option_codes.append(null)
	for o in opts:
		labels.append(Schema.choice_label(type_name, field, o[0], o[1]))
		_option_codes.append(o[0])
	var sel := 0
	if value != null and str(value) != "":
		sel = -1
		for k in _option_codes.size():
			if _option_codes[k] != null and str(_option_codes[k]) == str(value):
				sel = k
		if sel < 0:  # valeur hors liste : conservée telle quelle
			labels.append(str(value) + " (hors liste)")
			_option_codes.append(value)
			sel = _option_codes.size() - 1
	_option = UiKit.option_button(labels, sel)
	_option.item_selected.connect(func(_i): _emit())
	add_child(_option)


func select_code(code: Variant) -> void:
	set_value(code)


func _targets() -> Array:
	return Schema.FIELDS.get(field, {}).get("targets", [])


func _natures() -> Array:
	return Schema.FIELDS.get(field, {}).get("natures", [])


## Libellé d'un champ, éventuellement propre au type (ex. « Créature » pour un personnage).
static func label_of(p_type: String, p_field: String) -> String:
	var t: Dictionary = Schema.TYPES.get(p_type, {})
	if t.has("labels") and t.labels.has(p_field):
		return str(t.labels[p_field])
	return str(Schema.FIELDS.get(p_field, {"label": p_field}).get("label", p_field))


func _fill_list_suggestions(list_name: String) -> void:
	var pop := _suggest.get_popup()
	pop.clear()
	var dom := str(app.schema_ctx().get("last_domaine", "")) if list_name == "postes" else ""
	for v in Schema.suggestions(list_name, dom):
		pop.add_item(str(v))


func _on_list_suggestion(i: int) -> void:
	var v := _suggest.get_popup().get_item_text(i)
	var lines := Array(_text.text.split("\n")).filter(func(l): return str(l).strip_edges() != "")
	if not lines.has(v):
		lines.append(v)
	_text.text = "\n".join(PackedStringArray(lines))
	_emit()


func _refresh_link() -> void:
	var n := Schema.link_name(_value)
	_link_btn.text = n if n != "" else "Choisir…"
	_link_btn.tooltip_text = "" if _value == null else str(_value)


func _pick_one() -> void:
	Picker.open_in(main, app, label_of(type_name, field), "notes", _targets(),
		func(v): _set_link(v), "", _natures())


func _set_link(v: Variant) -> void:
	_value = v
	_refresh_link()
	_emit()


func _refresh_chips() -> void:
	for c in _flow.get_children():
		c.queue_free()
	for x in _value:
		var item: Variant = x
		var label := Schema.link_name(item)
		if kind == "elements":
			label = label.replace("#^", " · ^")
		_flow.add_child(UiKit.chip(label, func(): _remove(item)))
	var add := UiKit.button("+ Ajouter", _pick_many)
	_flow.add_child(add)


func _pick_many() -> void:
	Picker.open_in(main, app, label_of(type_name, field),
		"elements" if kind == "elements" else "notes", _targets(), _add_item, "", _natures())


func _add_item(v: Variant) -> void:
	if not _value.has(v):
		_value.append(v)
	_refresh_chips()
	_emit()


func _remove(item: Variant) -> void:
	_value.erase(item)
	_refresh_chips()
	_emit()


func _on_suggestion(i: int) -> void:
	_line.text = _suggest.get_popup().get_item_text(i)
	_emit()


func _fill_suggestions() -> void:
	var pop := _suggest.get_popup()
	pop.clear()
	if app.index == null:
		return
	var vals: Array = app.index.distinct_values(Schema.prop_key(field), type_name)
	if vals.is_empty():
		pop.add_item("(aucune valeur déjà utilisée)")
		pop.set_item_disabled(0, true)
	for v in vals:
		pop.add_item(str(v))
