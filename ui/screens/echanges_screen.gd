extends VBoxContainer
## Écran « Échanges avec Claude » :
##  - Exporter : une sélection de notes, avec consignes et annuaire, copiée
##    dans le presse-papiers et rangée dans `_Export/` ;
##  - Importer : les lots de `_Import/`, contrôlés note par note ; vous cochez
##    ce que vous acceptez, puis « Intégrer ». Rien n'est écrasé, rien n'est
##    supprimé.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const Exporter := preload("res://core/exchange/exporter.gd")
const Picker := preload("res://ui/widgets/picker.gd")

var app: Node
var main: Control
var scope := "fiche"
var subject := ""
var _last_export := {}
var _lot_rel := ""
var _analysis := {}
var _checks := {}

var _col: VBoxContainer
var _scope: OptionButton
var _subject_btn: Button
var _export_info: Label
var _lots_box: VBoxContainer
var _lot_box: VBoxContainer


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col = UiKit.vbox([], 12)
	add_child(UiKit.scroll(_col, 1100))
	var title := UiKit.heading("Échanges avec Claude")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_child(UiKit.hbox([UiKit.button("← Enquête", func(): main.show_screen("enquete")), title]))
	# ---- export
	_col.add_child(UiKit.heading("Exporter pour Claude"))
	_col.add_child(UiKit.muted("Prépare un texte à coller dans une conversation avec Claude : consignes, annuaire de vos fiches et notes choisies. Rien n'est envoyé : c'est vous qui collez."))
	var labels := []
	for s in Exporter.SCOPES:
		labels.append(s[1])
	_scope = UiKit.option_button(labels, 0)
	_scope.item_selected.connect(func(i):
		scope = Exporter.SCOPES[i][0]
		subject = ""
		_refresh_subject())
	_col.add_child(_scope)
	_subject_btn = UiKit.button("", _pick_subject)
	_col.add_child(_subject_btn)
	var row := UiKit.hbox([UiKit.button("Préparer et copier", _export), UiKit.button("Enregistrer dans _Export/", _save_export)])
	for btn in row.get_children():
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # deux boutons côte à côte, même sur un petit écran
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_child(row)
	_export_info = UiKit.label("")
	_col.add_child(_export_info)
	# ---- import
	_col.add_child(UiKit.heading("Importer un lot préparé par Claude"))
	_col.add_child(UiKit.muted("Déposez le dossier du lot dans _Import/ (par Git, GitSync ou l'explorateur de fichiers). Chaque note est contrôlée ; vous choisissez ce que vous intégrez."))
	_lots_box = UiKit.vbox([], 6)
	_col.add_child(_lots_box)
	_lot_box = UiKit.vbox([], 8)
	_col.add_child(_lot_box)
	_refresh_subject()


func on_show() -> void:
	_refresh_lots()


func on_job_finished(_job: String, _r: Dictionary) -> void:
	if is_inside_tree() and _lot_rel == "":
		_refresh_lots()


func _refresh_subject() -> void:
	_subject_btn.visible = scope in ["fiche", "domaine"]
	if scope == "fiche":
		_subject_btn.text = ("Fiche : " + subject) if subject != "" else "Choisir la fiche…"
	elif scope == "domaine":
		_subject_btn.text = ("Domaine : " + subject) if subject != "" else "Choisir le domaine…"


func _pick_subject() -> void:
	var types := ["domaine"] if scope == "domaine" else []
	Picker.open_in(main, app, "Sujet de l'export", "notes", types, func(v):
		subject = Schema.link_name(v)
		_refresh_subject())


func _label() -> String:
	match scope:
		"fiche", "domaine":
			return subject
		"rapides":
			return "notes rapides"
	return "notes récentes"


func _export() -> void:
	if scope in ["fiche", "domaine"] and subject == "":
		_export_info.text = "Choisissez d'abord le sujet."
		return
	_last_export = app.export_preview(scope, subject, _label())
	if _last_export.has("error"):
		_export_info.text = str(_last_export.error)
		return
	DisplayServer.clipboard_set(_last_export.text)
	_export_info.text = "Copié ✓ — %d note(s), %d fiche(s) dans l'annuaire, %d caractères%s. Collez-le dans une conversation avec Claude." % [
		_last_export.notes, _last_export.annuaire, _last_export.chars, " (limité : affinez le périmètre)" if _last_export.truncated else ""]


func _save_export() -> void:
	if _last_export.is_empty() or _last_export.has("error"):
		_export()
	if _last_export.is_empty() or _last_export.has("error"):
		return
	var r: Dictionary = app.export_save(_last_export.text, _label())
	_export_info.text = ("Enregistré dans %s ✓ (fichier texte, ignoré par Obsidian et par l'index)." % r.rel) if r.ok else "Non enregistré : " + str(r.error)


# ------------------------------------------------------------------ import

func _refresh_lots() -> void:
	for c in _lots_box.get_children():
		c.queue_free()
	var lots: Array = app.list_lots()
	if lots.is_empty():
		_lots_box.add_child(UiKit.muted("Aucun lot dans _Import/."))
		return
	for l in lots:
		var rel: String = l.rel
		var b := UiKit.button("%s — %d note(s)%s%s" % [l.name, l.notes, "" if l.report else " · sans _lot.md",
			" · déjà intégré en partie" if l.journal else ""], func(): open_lot(rel))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lots_box.add_child(b)


func open_lot(rel: String) -> void:
	_lot_rel = rel
	_analysis = app.analyse_lot(rel)
	_checks.clear()
	for c in _lot_box.get_children():
		c.queue_free()
	var c: Dictionary = _analysis.counts
	_lot_box.add_child(UiKit.label("Lot %s : %d prêt(s), %d avec avertissement, %d avec erreur (non intégrables)." % [rel.get_file(), c.ok, c.avert, c.erreur], true, 16))
	if str(_analysis.report) != "":
		var fold := FoldableContainer.new()
		fold.title = "Rapport du lot (_lot.md)"
		fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # titre long : jamais plus large que l'écran
		fold.folded = true
		var box := UiKit.report_box(220)
		box.text = str(_analysis.report)
		fold.add_child(UiKit.vbox([UiKit.muted("Les modifications proposées sur vos notes existantes sont à faire à la main."), box], 6))
		_lot_box.add_child(fold)
	var row := UiKit.hbox([UiKit.button("Tout cocher", func(): _check_all(true)), UiKit.button("Tout décocher", func(): _check_all(false))])
	_lot_box.add_child(row)
	for it in _analysis.items:
		var item: Dictionary = it
		var cb := CheckBox.new()
		cb.text = "%s  · %s" % [item.target_rel, Schema.type_label(str(item.type)) if item.is_note else "pièce jointe"]
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.custom_minimum_size.y = UiKit.TOUCH
		cb.button_pressed = item.level != "erreur"
		cb.disabled = item.level == "erreur"
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_checks[item.target_rel] = cb
		var line := UiKit.hbox([cb])
		if item.is_note:
			var preview := UiKit.report_box(200)
			preview.text = str(item.text)
			preview.visible = false
			line.add_child(UiKit.button("Voir", func(): preview.visible = not preview.visible))
			_lot_box.add_child(line)
			_lot_box.add_child(preview)
		else:
			_lot_box.add_child(line)
		for m in item.messages:
			_lot_box.add_child(UiKit.error("  " + m) if item.level == "erreur" else UiKit.warn("  " + m))
	var go := UiKit.tile("Intégrer les notes cochées", "Copiées à leur place dans le coffre, sans rien écraser", _import, Color("9be3a8"), 64)
	_lot_box.add_child(go)
	_lot_box.add_child(UiKit.button("Fermer ce lot", func():
		_lot_rel = ""
		for x in _lot_box.get_children():
			x.queue_free()
		_refresh_lots()))


func _check_all(on: bool) -> void:
	for k in _checks:
		if not _checks[k].disabled:
			_checks[k].button_pressed = on


func _import() -> void:
	var chosen := []
	for it in _analysis.get("items", []):
		if _checks.has(it.target_rel) and _checks[it.target_rel].button_pressed and not _checks[it.target_rel].disabled:
			chosen.append(it)
	if chosen.is_empty():
		_lot_box.add_child(UiKit.warn("Rien de coché."))
		return
	var r: Dictionary = app.import_lot(_lot_rel, chosen)
	var rel := _lot_rel
	open_lot(rel)
	_lot_box.add_child(UiKit.label("%d élément(s) intégré(s) ✓%s. Le lot reste dans _Import/ (journal : _import.journal.md) : supprimez-le quand vous voulez." % [
		r.done.size(), ("" if r.failed.is_empty() else ", %d refusé(s)" % r.failed.size())]))
	_lot_box.move_child(_lot_box.get_child(_lot_box.get_child_count() - 1), 0)
