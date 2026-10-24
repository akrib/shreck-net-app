extends VBoxContainer
## Tableau des hypothèses concurrentes d'un dossier (core/analysis/hypotheses.gd).
## Colonnes : les hypothèses (indices du dossier), classées de la moins
## contredite à la plus contredite. Lignes : les éléments, ceux qui départagent
## d'abord. Une case : ✓ cohérent, ✗ incohérent, · pas jugé. Un appui sur une
## case la fait tourner et l'écrit dans l'indice (`pour`, `contre`).

const UiKit := preload("res://ui/ui_kit.gd")
const Hyp := preload("res://core/analysis/hypotheses.gd")
const Picker := preload("res://ui/widgets/picker.gd")

const C_POUR := Color("7fd59b")
const C_CONTRE := Color("ff7a6b")
const C_MUTED := Color("a59cb3")
const EL_WIDTH := 560.0
const HYP_WIDTH := 210.0

var app: Node
var main: Control
var rel := ""
var table := {}
var _title: Label
var _info: Label
var _grid: GridContainer
var _new_hyp: LineEdit
## Ordre des lignes et des colonnes gardé pendant qu'on juge : le tableau ne
## bouge pas sous la souris ; le rang de chaque hypothèse reste écrit.
var _row_order: Array = []
var _col_order: Array = []
var _status: Label


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var back := UiKit.button("←", func(): main.go_back(), "Retour")
	back.custom_minimum_size.x = UiKit.TOUCH + 8
	_title = UiKit.label("Hypothèses concurrentes", false, 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = 60
	add_child(UiKit.hbox([back, _title, UiKit.button("Ouvrir le dossier", func():
		if rel != "":
			main.open_note(rel))]))
	_info = UiKit.muted("")
	add_child(_info)
	# ajouter une hypothèse (un indice du dossier) ou un élément à examiner
	_new_hyp = UiKit.line_edit("Nouvelle hypothèse : une affirmation (« Victor est un agent double »)")
	_new_hyp.text_submitted.connect(func(_t): _add_hypothesis())
	add_child(UiKit.hbox([_new_hyp, UiKit.button("+ Hypothèse", _add_hypothesis, "Crée un indice non vérifié et l'ajoute au dossier"),
		UiKit.button("+ Élément à examiner", _add_element, "Un élément d'une note, à juger face à chaque hypothèse")]))
	_status = UiKit.muted("")
	add_child(_status)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	add_child(UiKit.scroll(_grid))


func open(p_rel: String) -> void:
	rel = p_rel
	_row_order = []
	_col_order = []
	refresh()


func on_show() -> void:
	refresh()


func on_job_finished(_job: String, _result: Dictionary) -> void:
	if is_inside_tree():
		refresh()


func refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	if app.index == null or rel == "":
		_info.text = "Choisissez un dossier d'enquête (Enquête → Dossiers)."
		return
	table = Hyp.build(app.index, rel, app.repo.config if app.repo != null else {})
	_title.text = "Hypothèses — " + (str(table.question) if str(table.question) != "" else str(table.dossier))
	var n: int = table.hypotheses.size()
	if n == 0:
		_info.text = "Ce dossier n'a pas encore d'hypothèse. Écrivez-en une ci-dessous : elle devient un indice du dossier, que vous jugerez face aux éléments."
		return
	var diag: int = table.rows.filter(func(r): return r.diagnostic).size()
	_info.text = "%d hypothèse(s), %d élément(s), dont %d qui départagent. Le rang (1, 2…) classe de la moins contredite à la plus contredite : on ne retient pas l'hypothèse la plus confirmée, mais la moins contredite. Poids d'un élément : fiabilité × crédibilité. ✓ cohérent · ✗ incohérent · « · » pas jugé." % [n, table.rows.size(), diag]
	_grid.columns = n + 1
	# ordre stable : celui du premier affichage, les nouveautés à la suite
	var names: Array = table.hypotheses.map(func(h): return str(h.name))
	for hi in table.ranking:
		if not _col_order.has(names[hi]):
			_col_order.append(names[hi])
	var cols: Array = range(n)
	cols.sort_custom(func(a, b): return _col_order.find(names[a]) < _col_order.find(names[b]))
	for r in table.rows:
		if not _row_order.has(str(r.key)):
			_row_order.append(str(r.key))
	var rows: Array = table.rows.duplicate()
	rows.sort_custom(func(a, b): return _row_order.find(str(a.key)) < _row_order.find(str(b.key)))
	var rank := {}
	for i in table.ranking.size():
		rank[table.ranking[i]] = i + 1
	# en-tête : les hypothèses, avec leur rang (1 = la moins contredite)
	var corner := UiKit.label("Élément (source, cote)", true, 15)
	corner.custom_minimum_size.x = EL_WIDTH
	corner.add_theme_color_override("font_color", C_MUTED)
	_grid.add_child(corner)
	for hi in cols:
		var h: Dictionary = table.hypotheses[hi]
		var place: int = rank[hi]
		var hb := UiKit.button("%d. %s\n✓ %d · ✗ %d (poids %s)" % [place, h.name, h.n_pour, h.n_contre, _num(h.w_contre)], _opener(str(h.path)),
			"Indice « %s » : %s, crédibilité %s. Somme des poids des éléments incohérents : %s" % [h.name, h.statut, h.credibilite, _num(h.w_contre)])
		hb.custom_minimum_size.x = HYP_WIDTH
		hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hb.add_theme_color_override("font_color", C_POUR if place == 1 else Color("c8b6ff"))
		_grid.add_child(hb)
	# lignes : les éléments
	for r in rows:
		var cote := ("%s%s" % [r.fiab, r.cred]) if str(r.fiab) != "" or str(r.cred) != "" else "?"
		var eb := UiKit.button("%s\n%s · %s" % [r.text, str(r.note), cote], _opener(str(r.path)), "%s — poids %s%s" % [r.ref, _num(r.weight), "" if r.diagnostic else " — ne départage pas les hypothèses"])
		eb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		eb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eb.custom_minimum_size.x = EL_WIDTH
		if r.missing:
			eb.add_theme_color_override("font_color", Color("e0b04a"))
		elif not r.diagnostic:
			eb.add_theme_color_override("font_color", C_MUTED)
		_grid.add_child(eb)
		for hi in cols:
			_grid.add_child(_cell(r, hi))


## Nombre à la française : 0,32.
static func _num(x: float) -> String:
	return ("%.2f" % x).replace(".", ",")


func _opener(path: String) -> Callable:
	return func():
		if path != "":
			main.open_note(path)


func _cell(r: Dictionary, hi: int) -> Button:
	var v := str(r.cells.get(hi, ""))
	var b := Button.new()
	b.custom_minimum_size = Vector2(HYP_WIDTH, UiKit.TOUCH)
	b.text = {"pour": "✓ cohérent", "contre": "✗ incohérent"}.get(v, "·")
	b.add_theme_color_override("font_color", {"pour": C_POUR, "contre": C_CONTRE}.get(v, C_MUTED))
	b.tooltip_text = "Un appui : cohérent, puis incohérent, puis pas jugé"
	b.disabled = r.missing or str(table.hypotheses[hi].path) == ""
	var ipath: String = str(table.hypotheses[hi].path)
	var ref: String = str(r.ref)
	# dernier jugement retiré d'un élément que le dossier ne cite pas : il reste
	# dans le tableau, comme élément examiné
	var keep: bool = not r.examined and r.cells.size() == 1 and r.cells.has(hi)
	b.pressed.connect(func(): _cycle(ipath, ref, v, keep))
	return b


## Un appui : pas jugé → cohérent → incohérent → pas jugé ; écrit dans l'indice.
func _cycle(indice_rel: String, ref: String, current: String, keep := false) -> void:
	var nv := Hyp.next_cell(current)
	if nv == "" and keep:
		app.add_examined_element(rel, ref)
	var r: Dictionary = app.set_hypothesis_cell(indice_rel, ref, nv)
	_status.text = ("Écrit dans « %s » ✓" % indice_rel.get_file().get_basename()) if r.ok else "NON enregistré : " + str(r.get("error", "?"))
	refresh()


func _add_hypothesis() -> void:
	var t := _new_hyp.text.strip_edges()
	if t == "" or rel == "":
		_status.text = "Écrivez d'abord l'hypothèse."
		_new_hyp.grab_focus()
		return
	var r: Dictionary = app.add_hypothesis(rel, t)
	if r.ok:
		_new_hyp.text = ""
		_status.text = "Hypothèse ajoutée au dossier ✓ (%s)" % str(r.rel)
	else:
		_status.text = "NON enregistré : " + str(r.get("error", "?"))
	refresh()


func _add_element() -> void:
	if rel == "":
		return
	Picker.open_in(main, app, "Élément à examiner", "elements", [], func(v):
		var r: Dictionary = app.add_examined_element(rel, str(v))
		_status.text = "Élément ajouté au dossier ✓ (section « Éléments examinés »)" if r.ok else "NON enregistré : " + str(r.get("error", "?"))
		refresh())
