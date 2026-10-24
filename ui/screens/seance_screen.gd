extends VBoxContainer
## Écran « Préparer une séance » : choix du domaine, puis une fiche de séance
## calculée, en deux colonnes. À gauche : alertes et personnes probables (un
## tableau triable). À droite : questions pour la soirée (points à trancher,
## dossiers, indices, trous des fiches), faveurs en cours, tâches, nouveautés
## depuis la dernière soirée. Copiable.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const SessionPrep := preload("res://core/analysis/session_prep.gd")
const SortTable := preload("res://ui/widgets/sort_table.gd")

var app: Node
var main: Control
var domaine := ""
var last := {}
var _dom: OptionButton
var _codes: Array = []
var _col: VBoxContainer
var _left: VBoxContainer
var _table: Tree
var _others_btn: Button
var _with_others := false
var _info: Label


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	add_child(UiKit.heading("Préparer une séance"))
	_dom = UiKit.option_button([])
	_dom.item_selected.connect(func(i):
		domaine = str(_codes[i])
		refresh())
	add_child(UiKit.hbox([_dom, UiKit.button("Copier", _copy, "Copier la fiche de séance (texte)")]))
	_info = UiKit.muted("")
	add_child(_info)
	# à gauche : alertes, personnes probables
	_left = UiKit.vbox([], 8)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.size_flags_stretch_ratio = 1.6
	_table = SortTable.new()
	_table.setup([{"key": "name", "title": "Personne", "ratio": 2.0}, {"key": "clan", "title": "Clan", "ratio": 1.0},
		{"key": "rang", "title": "Âge", "ratio": 0.9, "min": 110}, {"key": "titres", "title": "Postes", "ratio": 2.0},
		{"key": "count", "title": "Fois", "ratio": 0.5, "min": 64, "numeric": true}, {"key": "last", "title": "Dernière fois", "ratio": 1.0, "min": 130},
		{"key": "note", "title": "Présence", "ratio": 1.0, "min": 110}])
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.custom_minimum_size.y = 260
	_table.row_opened.connect(func(p): main.open_note(p))
	_others_btn = UiKit.button("", func():
		_with_others = not _with_others
		_fill_people(), "Ajouter au tableau les personnes vues il y a plus d'un an, ou seulement rattachées au domaine")
	# à droite : le reste, qui défile
	_col = UiKit.vbox([], 8)
	var right := UiKit.scroll(_col)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := UiKit.hbox([_left, right], 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)


func on_show() -> void:
	_fill_domaines()
	refresh()


func _fill_domaines() -> void:
	_dom.clear()
	_codes = []
	if app.index == null:
		return
	var doms: Array = app.index.find_notes("", ["domaine"], 300)
	doms.sort_custom(func(a, b): return str(a.name) < str(b.name))
	for d in doms:
		_codes.append(str(d.name))
		_dom.add_item(str(d.name))
	if domaine == "":
		domaine = str(app.schema_ctx().last_domaine)
	if domaine == "" or not _codes.has(domaine):
		# sinon : le domaine de la soirée la plus récente
		var last: Array = app.index.list_by_type("soiree", 1, true)
		if not last.is_empty():
			var p: Dictionary = app.index.props_for([str(last[0].path)], ["domaine"]).get(str(last[0].path), {})
			var d := Schema.link_name(p.get("domaine", ""))
			if _codes.has(d):
				domaine = d
	var idx := _codes.find(domaine)
	if idx < 0 and not _codes.is_empty():
		idx = 0
		domaine = _codes[0]
	if idx >= 0:
		_dom.select(idx)


func refresh() -> void:
	# le tableau et son bouton sont gardés d'un affichage à l'autre
	if _others_btn.get_parent() != null:
		_others_btn.get_parent().remove_child(_others_btn)
	for box in [_col, _left]:
		for c in box.get_children():
			if c != _table:
				c.queue_free()
	if _table.get_parent() == _left:
		_left.remove_child(_table)
	_table.set_rows([])
	if app.index == null or domaine == "":
		_info.text = "Aucun domaine : créez d'abord une fiche de domaine (ou une soirée)."
		return
	last = SessionPrep.build(app.index, domaine, "", app.contradictions())
	_info.text = ("Dernière soirée : %s (%s) · %d soirée(s) connue(s) à %s" % [last.last_soiree.name, last.last_soiree.date, last.soirees, domaine]) \
		if not last.last_soiree.is_empty() else "Aucune soirée connue à %s pour l'instant." % domaine
	if not (last.gone as Array).is_empty():
		_info.text += " · %d mort(s) ou disparu(s) écarté(s) des personnes probables" % (last.gone as Array).size()
	if not last.last_soiree.is_empty():
		var p: String = last.last_soiree.path
		_left.add_child(UiKit.hbox([UiKit.button("Ouvrir la dernière soirée", func(): main.open_note(p)),
			UiKit.button("Son rapport", func(): main.show_report(p), "Rapport de la dernière soirée : présents, informations")]))
	_section("Alertes", last.alerts, Color("ff9b8a"), false, _left)
	var head := UiKit.heading("Personnes probables")
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.add_child(UiKit.hbox([head, _others_btn]))
	_left.add_child(_table)
	_fill_people()
	_section("Faveurs en cours", last.faveurs, Color("e0b04a"))
	_section("Questions pour la soirée", last.questions, Color(0, 0, 0, 0), false, null, true)
	_section("Tâches", last.tasks)
	_section("Depuis la dernière soirée", last.since)


## Le tableau des personnes : vues depuis moins d'un an ; avec le bouton, aussi
## les moins probables (en gris).
func _fill_people() -> void:
	var others: Array = last.get("others", [])
	_others_btn.text = ("Sans les moins probables" if _with_others else "Avec les moins probables (%d)" % others.size())
	_others_btn.visible = not others.is_empty()
	var rows := []
	for e in last.get("people", []):
		rows.append(_person_row(e, false))
	if _with_others:
		for e in others:
			rows.append(_person_row(e, true))
	_table.set_rows(rows)


func _person_row(e: Dictionary, old: bool) -> Dictionary:
	var kind := SessionPrep.presence_kind(e)
	var notes := PackedStringArray([kind])
	var cells := {"name": str(e.name), "clan": str(e.get("clan", "")), "rang": str(e.get("rang", "")),
		"titres": ", ".join(PackedStringArray(e.get("titres", []))), "count": str(e.count) if int(e.count) > 0 else "",
		"last": str(e.last), "note": " · ".join(notes)}
	var row := {"path": str(e.get("path", "")), "cells": cells}
	if kind == "vue":
		row["colors"] = {"note": Color("7fd59b")}
	elif kind == "incertaine":
		row["colors"] = {"note": Color("e0b04a")}
	if old:
		var grey := Color("7d748a")
		row["colors"] = {"name": grey, "clan": grey, "rang": grey, "titres": grey, "count": grey, "last": grey, "note": grey}
	return row


func _section(title: String, rows: Array, accent := Color(0, 0, 0, 0), folded := false, target: Control = null, first := false) -> void:
	var fold := FoldableContainer.new()
	fold.title = "%s (%d)" % [title, rows.size()]
	fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # titre long : jamais plus large que l'écran
	fold.folded = folded or rows.is_empty()
	var inner := UiKit.vbox([], 6)
	fold.add_child(inner)
	for r in rows:
		var path: String = str(r.get("path", ""))
		var text := str(r.text).replace("\n", " — ")
		var b := UiKit.list_row(text, "", func():
			if path != "":
				main.open_note(path), text)
		if accent.a > 0:
			(b.get_meta("title") as Label).add_theme_color_override("font_color", accent)
		inner.add_child(b)
	if rows.is_empty():
		inner.add_child(UiKit.muted("Rien pour l'instant."))
	var box: Control = target if target != null else _col
	box.add_child(fold)
	if first:
		box.move_child(fold, 0)


func _copy() -> void:
	if last.is_empty():
		return
	var d := Time.get_date_dict_from_system()
	DisplayServer.clipboard_set(SessionPrep.to_markdown(last, "%02d/%02d/%04d" % [d.day, d.month, d.year]))
	_info.text = "Fiche de séance copiée ✓ (à coller dans une note ou dans une conversation avec Claude)."
