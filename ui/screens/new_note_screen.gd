extends VBoxContainer
## Écran « Nouvelle note » :
##   1. choix du type, en grosses tuiles faciles à toucher ;
##   2. formulaire prérempli (date du jour, dernier domaine, valeurs par
##      défaut) avec listes déroulantes et sélecteurs de fiches.
## Sert aussi à transformer une note rapide : son texte est repris dans la
## nouvelle note, et la note rapide est marquée « traitée » (jamais supprimée).

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const FieldEditor := preload("res://ui/widgets/field_editor.gd")

var app: Node
var main: Control
var step := 1
var type_name := ""
var from_quick := ""
var quick_text := ""
var preset := {}
var editors := {}

var _col: VBoxContainer
var _grid: GridContainer
var _error: Label
var _preview: Label
var _fiab_touched := false
var _touched := false   ## « À compléter » n'apparaît qu'après une première saisie ou un essai de création
var _direct := false


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col = UiKit.vbox([], 12)
	add_child(UiKit.scroll(_col, 1100))


## Ouvre le choix du type. `p_from_quick` : note rapide à transformer.
func start(p_from_quick := "", p_text := "", p_preset := {}) -> void:
	from_quick = p_from_quick
	quick_text = p_text
	preset = p_preset
	_direct = false
	_step_types()


## Ouvre directement le formulaire d'un type (ex. : soirée du jour).
func start_type(p_type: String, p_preset := {}) -> void:
	from_quick = ""
	quick_text = ""
	preset = p_preset
	_direct = true
	_step_form(p_type)


## Retour : du formulaire au choix du type. Renvoie true si géré ici.
func back_step() -> bool:
	if step == 2 and not _direct:
		_step_types()
		return true
	return false


func _clear() -> void:
	for c in _col.get_children():
		c.queue_free()
	editors.clear()
	_grid = null


func _step_types() -> void:
	step = 1
	_clear()
	if from_quick != "":
		_col.add_child(UiKit.heading("Transformer la note rapide en…"))
		_col.add_child(UiKit.muted("Le texte de la note rapide sera repris dans la nouvelle note. La note rapide est gardée comme trace et sort de la liste « à traiter »."))
	else:
		_col.add_child(UiKit.heading("Quel type de note ?"))
	_grid = UiKit.grid(3)
	for t in Schema.TYPE_ORDER:
		if t == "en_cours" and from_quick != "":
			continue
		var d: Dictionary = Schema.TYPES[t]
		var ty: String = t
		_grid.add_child(UiKit.tile(d.label, d.desc, func(): _choose(ty), Color(d.get("color", "c8b6ff"))))
	_col.add_child(_grid)


func _choose(t: String) -> void:
	if t == "en_cours":
		var r: Dictionary = app.create_quick_note()
		if r.ok:
			main.open_note(r.rel)
		else:
			_col.add_child(UiKit.error("Création impossible : " + str(r.error)))
		return
	_step_form(t)


func _step_form(t: String) -> void:
	step = 2
	type_name = t
	_fiab_touched = false
	_touched = false
	_clear()
	var d: Dictionary = Schema.TYPES[t]
	var head := UiKit.hbox([])
	if not _direct:
		head.add_child(UiKit.button("← Types", _step_types))
	var h := UiKit.heading(("Transformer en : " if from_quick != "" else "Nouvelle note : ") + str(d.label))
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	head.add_child(UiKit.button("Créer", _create, "Créer la note"))
	_col.add_child(head)
	var values := Schema.defaults(t, app.schema_ctx())
	for k in preset:
		if preset[k] != null and str(preset[k]) != "" and (d.fields as Array).has(k):
			values[k] = preset[k]
	for f in Schema.form_fields(t):
		var ed = FieldEditor.make(app, main, t, f, values.get(f), (d.required as Array).has(f))
		ed.changed.connect(_on_change.bind(f))
		editors[f] = ed
		_col.add_child(ed)
	if quick_text.strip_edges() != "":
		_col.add_child(UiKit.muted("Texte repris de la note rapide :"))
		var box := UiKit.report_box(100)
		box.text = quick_text
		_col.add_child(box)
	_preview = UiKit.muted("")
	_col.add_child(_preview)
	_error = UiKit.error("")
	_col.add_child(_error)
	var create := UiKit.tile("Créer la note", "", _create, Color("9be3a8"), 64)
	(create.get_meta("title") as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(create)
	_update_preview()
	# le premier champ texte reçoit le curseur : on peut taper le nom tout de suite
	for f in editors:
		var le: Variant = editors[f].get("_line")
		if le is LineEdit and (le as LineEdit).visible:
			(le as LineEdit).grab_focus.call_deferred()
			(le as LineEdit).text_submitted.connect(func(_t): _create())
			break


func _on_change(f: String) -> void:
	_touched = true
	if type_name == "source":
		if f == "fiabilite":
			_fiab_touched = true
		elif f == "nature" and not _fiab_touched and editors.has("fiabilite"):
			var nat: Variant = editors.nature.get_value()
			editors.fiabilite.set_value(Schema.FIABILITE_PAR_NATURE.get(str(nat), "F"))
			_fiab_touched = false
	_update_preview()


func values() -> Dictionary:
	var v := {}
	for f in editors:
		v[f] = editors[f].get_value()
	return v


func _update_preview() -> void:
	if _preview == null:
		return
	var v := values()
	var now := Time.get_datetime_dict_from_system()
	var name := Schema.build_name(type_name, v, now)
	_preview.text = "Fichier : %s/%s.md" % [Schema.folder(type_name, v, now), name if name != "" else "…"]
	var probs := Schema.check(type_name, v)
	_error.text = "" if probs.is_empty() or not _touched else "À compléter : " + " ; ".join(probs)


func _create() -> void:
	_touched = true
	_update_preview()
	var r: Dictionary = app.create_note(type_name, values(), quick_text, from_quick)
	if not r.ok:
		_error.text = "Non créée : " + str(r.error)
		return
	if r.has("warning"):
		app._log(str(r.warning))
	main.open_note(r.rel, true)
