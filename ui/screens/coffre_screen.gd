extends VBoxContainer
## Écran « Réglages » : chemin du dépôt de notes, état du dossier, affichage
## (plein écran, taille de l'interface), outils avancés.

const UiKit := preload("res://ui/ui_kit.gd")

var app: Node
var main: Control
var _path: LineEdit
var _status: VBoxContainer
var _gitignore_btn: Button
var _dialog: FileDialog
var _zoom: HSlider
var _zoom_label: Label
var _trash_box: VBoxContainer
var _trash_head: Label
var _confirm: ConfirmationDialog
var _pending_purge: Array = []


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := UiKit.vbox([], 14)
	add_child(UiKit.scroll(col, 1100))

	col.add_child(UiKit.heading("Réglages — dossier du coffre"))
	col.add_child(UiKit.muted("Le dossier qui contient vos notes Markdown : votre dépôt Git sur l'ordinateur. L'application n'y crée, ne déplace et n'y supprime aucune note sans action de votre part."))
	_path = UiKit.line_edit("Chemin du dossier, par ex. C:\\Users\\vous\\Documents\\Coffre", app.repo_path())
	col.add_child(_path)
	col.add_child(UiKit.hbox([
		UiKit.button("Parcourir…", _browse),
		UiKit.button("Enregistrer et ouvrir", _save_path),
	]))

	col.add_child(UiKit.heading("État du dossier"))
	_status = UiKit.vbox([], 4)
	col.add_child(_status)
	_gitignore_btn = UiKit.button("Ajouter .nosferatu/tmp/ au .gitignore", func(): app.add_tmp_to_gitignore())
	_gitignore_btn.visible = false
	col.add_child(UiKit.hbox([UiKit.button("Resynchroniser maintenant", func(): app.start_sync(),
		"Relire les notes modifiées hors de l'application (Obsidian, Git…)"), _gitignore_btn]))

	col.add_child(UiKit.heading("Affichage"))
	col.add_child(UiKit.hbox([UiKit.button("Plein écran / fenêtre", func(): main.toggle_fullscreen(), "F11")]))
	col.add_child(UiKit.muted("Taille de l'interface"))
	_zoom = HSlider.new()
	_zoom.min_value = 0.75
	_zoom.max_value = 2.0
	_zoom.step = 0.125
	_zoom.value = float(app.settings.get_value("interface", "zoom", 1.0))
	_zoom.custom_minimum_size.y = UiKit.TOUCH
	_zoom_label = UiKit.label("%d %%" % int(_zoom.value * 100), false)
	_zoom.drag_ended.connect(func(_c): main.set_zoom(_zoom.value))
	_zoom.value_changed.connect(func(v): _zoom_label.text = "%d %%" % int(v * 100))
	var zrow := UiKit.hbox([_zoom, _zoom_label])
	_zoom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(zrow)

	_trash_head = UiKit.heading("Corbeille")
	col.add_child(_trash_head)
	col.add_child(UiKit.muted("Les notes supprimées depuis l'application sont déplacées dans le dossier .trash du coffre, comme la corbeille d'Obsidian (dont les fichiers apparaissent ici aussi). Rien n'est effacé tant que vous ne le demandez pas."))
	_trash_box = UiKit.vbox([], 6)
	col.add_child(_trash_box)
	_confirm = UiKit.confirm_dialog("Effacer définitivement")
	_confirm.confirmed.connect(_purge_confirmed)
	add_child(_confirm)
	app.notes_changed.connect(_on_notes_changed)

	col.add_child(UiKit.heading("Outils avancés"))
	col.add_child(UiKit.hbox([
		UiKit.button("Diagnostic", func(): main.show_screen("diag"), "Vérification, reconstruction de l'index, rapport"),
		UiKit.button("Banc de mesure", func(): main.show_screen("banc"), "Mesures de performance sur un jeu fictif"),
	]))
	col.add_child(UiKit.muted("Nosferatu Intelligence — %s" % app.VERSION))
	app.repo_checked.connect(_on_check)


func on_show() -> void:
	_path.text = app.repo_path()
	_on_check(app.last_check)
	_refresh_trash()


func _refresh_trash() -> void:
	for c in _trash_box.get_children():
		c.queue_free()
	var lst: Array = app.trash_list()
	_trash_head.text = "Corbeille (%d)" % lst.size()
	if lst.is_empty():
		_trash_box.add_child(UiKit.muted("La corbeille est vide."))
		return
	for e in lst.slice(0, 200):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var when := str(e.date).substr(0, 10)
		var where := str(e.origine).get_base_dir()
		var l := UiKit.label("%s — %s · %s%s" % [e.nom, where if where != "" else "racine du coffre", when,
			"" if e.connue else " · corbeille d'Obsidian"], true, 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var tr := str(e.trash_rel)
		row.add_child(UiKit.button("Restaurer", func(): _restore(tr), "Remettre la note à sa place (rien n'est écrasé)"))
		row.add_child(UiKit.button("Effacer…", func(): _ask_purge([tr], "Effacer définitivement « %s » ? Ce fichier sera supprimé du disque (Git en garde la trace si le coffre est suivi)." % e.nom)))
		_trash_box.add_child(UiKit.card([row], Color("ff9b8a")))
	if lst.size() > 200:
		_trash_box.add_child(UiKit.muted("… et %d autre(s)." % (lst.size() - 200)))
	var all := lst.map(func(x): return str(x.trash_rel))
	_trash_box.add_child(UiKit.hbox([UiKit.button("Vider la corbeille…", func(): _ask_purge(all, "Effacer définitivement les %d fichier(s) de la corbeille ? Ils seront supprimés du disque." % all.size()))]))


func _on_notes_changed() -> void:
	if is_visible_in_tree():
		_refresh_trash()


func _restore(trash_rel: String) -> void:
	var r: Dictionary = app.restore_note(trash_rel)
	main._set_status(("Restaurée : " + str(r.rel)) if r.ok else ("NON restaurée : " + str(r.error)))
	_refresh_trash()


func _ask_purge(rels: Array, text: String) -> void:
	_pending_purge = rels
	UiKit.confirm(_confirm, text)


func _purge_confirmed() -> void:
	var r: Dictionary = app.purge_trash(_pending_purge)
	main._set_status("%d fichier(s) effacé(s) définitivement%s" % [r.done.size(), "" if r.ok else " — " + str(r.error)])
	_pending_purge = []
	_refresh_trash()


func _on_check(c: Dictionary) -> void:
	for ch in _status.get_children():
		ch.queue_free()
	if c.is_empty():
		_status.add_child(UiKit.label("Aucun dossier configuré."))
		return
	var lines := [
		[c.get("exists"), "Dossier trouvé"],
		[c.get("readable"), "Lecture possible"],
		[c.get("writable"), "Écriture possible (test dans .nosferatu/tmp/)"],
		[c.get("git"), "Dépôt Git détecté (.git)"],
		[c.get("config"), "Coffre Nosferatu reconnu (.nosferatu/config.json) — facultatif"],
		[c.get("tmp_ignored"), ".nosferatu/tmp/ ignoré par Git"],
	]
	for l in lines:
		_status.add_child(UiKit.label("%s %s" % [UiKit.check_mark(l[0]), l[1]]))
	if str(c.get("error", "")) != "":
		var e := UiKit.label("⚠ " + str(c.error))
		e.add_theme_color_override("font_color", Color("ff9b8a"))
		_status.add_child(e)
	if app.repo != null:
		var top: Dictionary = app.repo.top_entries()
		var noms := ", ".join(PackedStringArray(top.dirs.slice(0, 8)))
		_status.add_child(UiKit.label("Visible à la racine : %d dossier(s)%s, %d fichier(s), %d élément(s) cachés" % [
			top.dirs.size(), (" (" + noms + ")") if noms != "" else "", top.files.size(), top.hidden.size()]))
	var nb := -1
	if app.last_report.has("files"):
		nb = int(app.last_report.files)
		_status.add_child(UiKit.label("Notes .md trouvées à la dernière synchronisation : %d" % nb))
	_gitignore_btn.visible = c.get("git", false) and not c.get("tmp_ignored", false)


func on_job_finished(job: String, _result: Dictionary) -> void:
	if job == "synchronisation" or job == "reconstruction":
		_on_check(app.last_check)


func _save_path() -> void:
	var c: Dictionary = app.set_repo_path(_path.text)
	if c.get("readable", false):
		app.start_sync()


func _browse() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.title = "Choisir le dossier du coffre"
		_dialog.use_native_dialog = true
		_dialog.dir_selected.connect(func(d): _path.text = d)
		add_child(_dialog)
	var start := _path.text if _path.text != "" else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_dialog.current_dir = start
	_dialog.popup_centered_ratio(0.9)
