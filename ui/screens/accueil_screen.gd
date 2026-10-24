extends VBoxContainer
## Écran « Accueil » : ce qu'on fait le plus souvent, en gros boutons.
##  - alertes : échéances, faveurs en retard, sanctions, personnes surveillées ;
##  - notes rapides à traiter (seulement s'il y en a) ;
##  - nouvelle note, note rapide, soirée du jour, rapport, séance, graphe, alibis, recherche ;
##  - deux colonnes : dernières soirées (avec leur rapport) et notes modifiées récemment.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const AlertList := preload("res://ui/widgets/alert_list.gd")

var app: Node
var main: Control
var _col: VBoxContainer
var _todo_card: PanelContainer
var _todo_label: Label
var _todo_list: VBoxContainer
var _todo_btn: Button
var _quick_btn: Button
var _soirees: VBoxContainer
var _alert_card: PanelContainer
var _alert_label: Label
var _alert_box: VBoxContainer
var _soiree_btn: Button
var _grid: GridContainer
var _recent: VBoxContainer
var _status: Label
var _show_todo := false


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col = UiKit.vbox([], 14)
	add_child(UiKit.scroll(_col))
	# alertes
	_alert_label = UiKit.label("", true, 19)
	_alert_box = UiKit.vbox([], 6)
	var all_btn := UiKit.button("Toutes les alertes", func():
		main.show_screen("enquete")
		main.screens.enquete.show_tab("alertes"))
	_alert_card = UiKit.card([UiKit.hbox([_alert_label, all_btn]), _alert_box], Color("ff7a6b"))
	_alert_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_child(_alert_card)
	# notes rapides à traiter (carte masquée quand il n'y en a pas)
	_todo_label = UiKit.label("", true, 19)
	_todo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_todo_btn = UiKit.button("Voir la liste", _toggle_todo)
	_todo_list = UiKit.vbox([], 6)
	_todo_card = UiKit.card([UiKit.hbox([_todo_label, _todo_btn]), _todo_list], Color("e0b04a"))
	_col.add_child(_todo_card)
	# actions principales
	_grid = UiKit.grid(4)
	_grid.add_child(UiKit.tile("+ Nouvelle note", "Choisir le type", func(): main.new_note(), Color("9be3a8")))
	_quick_btn = UiKit.tile("Note rapide", "Bloc-notes, à trier plus tard", _quick, Color("e0b04a"))
	_grid.add_child(_quick_btn)
	_soiree_btn = UiKit.tile("Soirée du jour", "", _soiree, Color("c8b6ff"))
	_grid.add_child(_soiree_btn)
	_grid.add_child(UiKit.tile("Rapport de soirée", "Présents, informations, texte", func(): main.show_report(), Color("9be3a8")))
	_grid.add_child(UiKit.tile("Préparer la séance", "Qui sera là, faveurs, questions", func(): main.show_screen("seance"), Color("ff8aa8")))
	_grid.add_child(UiKit.tile("Graphe", "Relations et faveurs", func(): main.show_graph(""), Color("d7a6ff")))
	_grid.add_child(UiKit.tile("Alibis", "Qui était où, telle nuit", func(): main.show_alibis(), Color("f5e08a")))
	_grid.add_child(UiKit.tile("Rechercher", "Fiches, textes, alias", func():
		main.show_screen("fiches")
		main.screens.fiches.focus_search(), Color("8fd3ff")))
	_col.add_child(_grid)
	# deux colonnes : dernières soirées | modifiées récemment
	_soirees = UiKit.vbox([], 4)
	_recent = UiKit.vbox([], 4)
	var all_soirees := UiKit.button("Toutes", func():
		main.show_screen("fiches")
		main.screens.fiches.select_type("soiree"), "Toutes les soirées, de la plus récente à la plus ancienne")
	var left := UiKit.vbox([UiKit.hbox([_expand(UiKit.heading("Dernières soirées")), all_soirees]), _soirees], 8)
	var right_head := UiKit.hbox([UiKit.heading("Modifiées récemment")])
	right_head.custom_minimum_size.y = UiKit.TOUCH  # titres alignés sur ceux de gauche
	var right := UiKit.vbox([right_head, _recent], 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_child(UiKit.hbox([left, right], 24))
	_status = UiKit.muted("")
	_col.add_child(_status)


func on_show() -> void:
	refresh()


func on_job_finished(_job: String, _result: Dictionary) -> void:
	if is_inside_tree():
		refresh()


func _expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func refresh() -> void:
	for box in [_recent, _soirees, _todo_list]:
		for c in box.get_children():
			c.queue_free()
	if app.index == null:
		_todo_label.text = "Aucun coffre ouvert : réglez le dossier dans Réglages."
		_todo_card.visible = true
		_todo_btn.visible = false
		UiKit.set_tile(_soiree_btn, "Soirée du jour", "")
		return
	var n: int = app.index.quick_notes_todo_count()
	_todo_label.text = "Aucune note rapide à traiter ✓" if n == 0 else ("%d note%s rapide%s à traiter" % [n, "s" if n > 1 else "", "s" if n > 1 else ""])
	_todo_card.visible = n > 0
	_todo_btn.visible = n > 0
	_todo_btn.text = "Masquer" if _show_todo else "Voir la liste"
	UiKit.set_tile(_quick_btn, "Note rapide", "Bloc-notes · rien à trier ✓" if n == 0 else "Bloc-notes · %d à trier" % n)
	_todo_list.visible = _show_todo and n > 0
	if _todo_list.visible:
		for r in app.index.quick_notes_todo(50):
			var p: String = r.path
			_todo_list.add_child(UiKit.list_row(str(r.name), "", func(): main.open_note(p)))
	# alertes
	for c in _alert_box.get_children():
		c.queue_free()
	var al: Array = app.alerts()
	_alert_card.visible = not al.is_empty()
	var urgent := al.filter(func(a): return a.level == "urgent").size()
	_alert_label.text = "%d alerte%s%s" % [al.size(), "s" if al.size() > 1 else "", (" dont %d urgente%s" % [urgent, "s" if urgent > 1 else ""]) if urgent > 0 else ""]
	_alert_box.add_child(AlertList.build(app, main, al, 5, refresh))
	# soirée du jour
	var dom := str(app.schema_ctx().last_domaine)
	var today: String = app.today_soiree(dom) if dom != "" else app.today_soiree()
	if today == "" and dom != "":
		today = app.today_soiree()
	if today != "":
		UiKit.set_tile(_soiree_btn, "Soirée du jour", "Ouvrir : " + today.get_file().get_basename())
	else:
		UiKit.set_tile(_soiree_btn, "Soirée du jour", "Créer" + ((" — " + dom) if dom != "" else ""))
	# dernières soirées : ouvrir la note, ou directement son rapport
	var soirees: Array = app.index.list_by_type("soiree", 8, true)
	if soirees.is_empty():
		_soirees.add_child(UiKit.muted("Aucune soirée pour l'instant."))
	for r in soirees:
		var p: String = r.path
		var rep := UiKit.button("Rapport", func(): main.show_report(p), "Rapport de cette soirée : présents, informations, texte")
		_soirees.add_child(UiKit.hbox([UiKit.list_row(str(r.name), "", func(): main.open_note(p), p), rep], 6))
	var now := int(Time.get_unix_time_from_system())
	for r in app.index.recent_notes(8):
		var p: String = r.path
		var d := "%s · %s" % [Schema.type_label(str(r.type)), when(int(r.get("mtime", 0)), now, _tz_offset())]
		_recent.add_child(UiKit.list_row(str(r.name), d, func(): main.open_note(p), p))
	var last := int(app.index.meta_get("last_scan", "0"))
	_status.text = "Dernière synchronisation : " + (Time.get_datetime_string_from_unix_time(last + _tz_offset()).replace("T", " à ") if last > 0 else "jamais")


## Date de modification lisible : « à 17:31 », « hier à 09:12 », « 12 oct. », « 12 oct. 2025 ».
static func when(unix: int, now: int, tz := 0) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(unix + tz)
	var day := int((unix + tz) / 86400)
	var today := int((now + tz) / 86400)
	if day == today:
		return "à %02d:%02d" % [d.hour, d.minute]
	if day == today - 1:
		return "hier à %02d:%02d" % [d.hour, d.minute]
	const MOIS := ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
	var n := Time.get_datetime_dict_from_unix_time(now + tz)
	var s := "%d %s" % [d.day, MOIS[d.month - 1]]
	return s if d.year == n.year else "%s %d" % [s, d.year]


func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _toggle_todo() -> void:
	_show_todo = not _show_todo
	refresh()


func _quick() -> void:
	var r: Dictionary = app.create_quick_note()
	if r.ok:
		main.open_note(r.rel)
	else:
		_status.text = "Création impossible : " + str(r.error)


func _soiree() -> void:
	var dom := str(app.schema_ctx().last_domaine)
	var today: String = app.today_soiree(dom) if dom != "" else app.today_soiree()
	if today == "" and dom != "":
		today = app.today_soiree()
	if today != "":
		main.open_note(today)
	else:
		main.new_note("soiree")
