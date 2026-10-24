extends PanelContainer
## Sélecteur plein écran : choisir une fiche (ou un élément) dans une liste
## filtrée au fil de la frappe, sans accents ni majuscules. Si la fiche
## n'existe pas encore, un bouton la crée aussitôt (fiche minimale).
##
## Usage : Picker.open_in(main, app, "Présents", "notes", ["personnage"], func(v): …)
## Le rappel reçoit "[[Nom]]" (fiche) ou "[[Note#^el-…]]" (élément).

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")

## Types qu'on peut créer d'un geste depuis le sélecteur (il suffit d'un nom).
const STUB_TYPES := ["personnage", "groupe", "lieu", "domaine", "objet", "concept"]

var app: Node
var main: Control
var mode := "notes"
var types: Array = []
var natures: Array = []
var on_pick := Callable()

var _search: LineEdit
var _list: ItemList
var _create_row: HBoxContainer
var _create_btn: Button
var _create_type: OptionButton
var _create_types: Array = []
var _timer: Timer
var _info: Label


static func open_in(p_main: Control, p_app: Node, title: String, p_mode: String, p_types: Array,
		cb: Callable, initial := "", p_natures: Array = []) -> Control:
	var p = load("res://ui/widgets/picker.gd").new()
	p.natures = p_natures
	p._setup(p_app, p_main, title, p_mode, p_types, cb, initial)
	p_main.open_overlay(p)
	return p


func _setup(p_app: Node, p_main: Control, title: String, p_mode: String, p_types: Array, cb: Callable, initial: String) -> void:
	app = p_app
	main = p_main
	mode = p_mode
	types = p_types
	on_pick = cb
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("16131a")
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var v := UiKit.vbox([], 10)
	add_child(v)
	var head := UiKit.hbox([])
	var t := UiKit.heading(title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiKit.button("Annuler", close))
	v.add_child(head)
	_search = UiKit.line_edit("Tapez quelques lettres (accents facultatifs)…" if mode == "notes" else "Mots de l'élément cherché…", initial)
	_search.text_changed.connect(func(_t): _timer.start())
	_search.text_submitted.connect(func(_t): _pick_first())
	v.add_child(_search)
	# création d'une fiche manquante
	for ty in (types if not types.is_empty() else STUB_TYPES):
		if ty in STUB_TYPES:
			_create_types.append(ty)
	_create_row = UiKit.hbox([])
	_create_btn = UiKit.button("", _create)
	_create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_create_row.add_child(_create_btn)
	if _create_types.size() > 1:
		var labels := []
		for ty in _create_types:
			labels.append(Schema.type_label(ty))
		_create_type = UiKit.option_button(labels)
		_create_type.size_flags_horizontal = Control.SIZE_SHRINK_END
		_create_type.custom_minimum_size.x = 150
		_create_row.add_child(_create_type)
	_create_row.visible = false
	v.add_child(_create_row)
	_info = UiKit.muted("")
	v.add_child(_info)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("v_separation", 14)
	_list.add_theme_font_size_override("font_size", 17)
	_list.item_clicked.connect(func(i, _p, _b): _pick(i))
	_list.item_activated.connect(_pick)
	v.add_child(_list)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.15
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	_refresh()
	_search.grab_focus.call_deferred()


func close() -> void:
	main.close_overlay(self)


func _refresh() -> void:
	_list.clear()
	if app.index == null:
		_info.text = "Index indisponible : synchronisez d'abord le coffre."
		return
	var q := _search.text.strip_edges()
	if mode == "elements":
		for r in app.index.find_elements(q, 60):
			var i := _list.add_item("%s\n— %s · crédibilité %s" % [Schema.display_text(str(r.text)).left(160), r.name, str(r.cred)])
			_list.set_item_metadata(i, "[[%s#^%s]]" % [r.name, r.block])
		_info.text = "Éléments récents" if q == "" else "%d élément(s)" % _list.item_count
	else:
		var exact := false
		for r in app.index.find_notes(q, types, 60, natures):
			var i := _list.add_item("%s   · %s" % [r.name, Schema.type_label(str(r.type))])
			_list.set_item_metadata(i, "[[%s]]" % r.name)
			if str(r.name).to_lower() == q.to_lower():
				exact = true
		_info.text = ("Fiches récentes" if q == "" else "%d fiche(s)" % _list.item_count)
		var can_create := q != "" and not exact and not _create_types.is_empty()
		_create_row.visible = can_create
		if can_create:
			_create_btn.text = "+ Créer la fiche « %s »" % Schema.clean_name(q)


func _pick(i: int) -> void:
	var v: String = str(_list.get_item_metadata(i))
	close()
	on_pick.call(v)


func _pick_first() -> void:
	if _list.item_count > 0:
		_pick(0)
	elif _create_row.visible:
		_create()


func _create() -> void:
	var name := Schema.clean_name(_search.text)
	if name == "":
		return
	var ty: String = _create_types[_create_type.selected] if _create_type != null else _create_types[0]
	var r: Dictionary = app.create_stub(ty, name, str(natures[0]) if not natures.is_empty() else "")
	if not r.ok:
		_info.text = "Création impossible : " + str(r.error)
		return
	close()
	on_pick.call("[[%s]]" % r.name)
