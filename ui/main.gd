extends Control
## Coquille de l'application (version PC, plein écran par défaut ; F11 bascule
## entre plein écran et fenêtre) : navigation à gauche, écran à droite.
## La logique est dans AppService ; les écrans ne font qu'afficher et appeler.

const AppService := preload("res://core/app/app_service.gd")
const UiKit := preload("res://ui/ui_kit.gd")
const CoffreScreen := preload("res://ui/screens/coffre_screen.gd")
const FichesScreen := preload("res://ui/screens/fiches_screen.gd")
const NoteScreen := preload("res://ui/screens/note_screen.gd")
const DiagScreen := preload("res://ui/screens/diag_screen.gd")
const BancScreen := preload("res://ui/screens/banc_screen.gd")
const AccueilScreen := preload("res://ui/screens/accueil_screen.gd")
const NewNoteScreen := preload("res://ui/screens/new_note_screen.gd")
const EnqueteScreen := preload("res://ui/screens/enquete_screen.gd")
const GraphScreen := preload("res://ui/screens/graph_screen.gd")
const SeanceScreen := preload("res://ui/screens/seance_screen.gd")
const EchangesScreen := preload("res://ui/screens/echanges_screen.gd")
const RapportScreen := preload("res://ui/screens/rapport_screen.gd")
const HypothesesScreen := preload("res://ui/screens/hypotheses_screen.gd")
const StatsScreen := preload("res://ui/screens/stats_screen.gd")
const SlidePanel := preload("res://ui/widgets/slide_panel.gd")

var app: Node
var screens := {}
var current := ""
var history: Array[String] = []

var _margin: MarginContainer
var _shell: BoxContainer
var _nav: BoxContainer
var _nav_panel: PanelContainer
var _nav_slide: Control      ## le menu de gauche, escamotable (flèche, Ctrl+B)
var _content: PanelContainer
var _status: Label
var _nav_buttons := {}
var _last_focus_sync := 0
var _overlays: Array[Control] = []
var _badge: Label

const NAV := [["accueil", "Accueil", "Notes à traiter, nouvelle note, soirée du jour"],
	["fiches", "Fiches", "Rechercher et parcourir les notes"],
	["note", "Note", "Note ouverte"],
	["enquete", "Enquête", "Alertes, chronologie, alibis, faveurs, indices, dossiers, informateurs, tâches"],
	["coffre", "Réglages", "Dossier du coffre, taille de l'interface, diagnostic"]]


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	theme = UiKit.theme()
	app = AppService.new()
	app.name = "App"
	add_child(app)
	_apply_scale()
	_apply_fullscreen()
	_build_shell()
	screens = {
		"accueil": AccueilScreen.new(), "coffre": CoffreScreen.new(), "fiches": FichesScreen.new(),
		"note": NoteScreen.new(), "enquete": EnqueteScreen.new(), "nouvelle": NewNoteScreen.new(),
		"diag": DiagScreen.new(), "banc": BancScreen.new(), "graphe": GraphScreen.new(), "seance": SeanceScreen.new(),
		"echanges": EchangesScreen.new(), "rapport": RapportScreen.new(), "hypotheses": HypothesesScreen.new(), "stats": StatsScreen.new(),
	}
	for k in screens:
		screens[k].setup(app, self)
	app.job_started.connect(func(job): _set_status("%s en cours…" % job.capitalize()))
	app.job_progress.connect(func(t): _set_status(t))
	app.job_finished.connect(_on_job_finished)
	app.notes_changed.connect(refresh_badge)
	refresh_badge()
	if app.repo_path() == "":
		show_screen("coffre")
	else:
		var check: Dictionary = app.open_repo()
		if check.get("readable", false):
			show_screen("accueil")
			app.start_sync()
		else:
			show_screen("coffre")


func _exit_tree() -> void:
	for k in screens:
		if is_instance_valid(screens[k]) and not screens[k].is_inside_tree():
			screens[k].free()


func _apply_scale() -> void:
	var base := maxf(1.0, DisplayServer.screen_get_scale())
	var zoom := float(app.settings.get_value("interface", "zoom", 1.0))
	get_window().content_scale_factor = base * zoom


func set_zoom(z: float) -> void:
	app.settings.set_value("interface", "zoom", z)
	app.save_settings()
	_apply_scale()


## Plein écran (réglage gardé d'une session à l'autre ; plein écran par défaut).
func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var full := is_fullscreen()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)


func is_fullscreen() -> bool:
	return bool(app.settings.get_value("interface", "plein_ecran", true))


func toggle_fullscreen() -> void:
	app.settings.set_value("interface", "plein_ecran", not is_fullscreen())
	app.save_settings()
	_apply_fullscreen()


func _build_shell() -> void:
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var bg := PanelContainer.new()
	_margin.add_child(bg)
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 0)
	bg.add_child(root_v)
	_status = UiKit.muted("")
	_status.visible = false
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_v.add_child(_status)
	_shell = HBoxContainer.new()
	_shell.add_theme_constant_override("separation", 0)
	_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(_shell)
	_content = PanelContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 12
	empty.content_margin_right = 12
	empty.content_margin_top = 10
	empty.content_margin_bottom = 10
	_content.add_theme_stylebox_override("panel", empty)
	_nav_panel = PanelContainer.new()
	_nav_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 6)
	_nav_panel.add_child(_nav)
	for item in NAV:
		var b := UiKit.button(item[1], show_screen.bind(item[0]), item[2])
		b.toggle_mode = true
		_nav_buttons[item[0]] = b
		_nav.add_child(b)
	# Pastille : nombre de notes rapides à traiter, sur le bouton Accueil.
	_badge = Label.new()
	_badge.visible = false
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.add_theme_color_override("font_color", Color("1b1620"))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("e0b04a")
	bsb.set_corner_radius_all(9)
	bsb.content_margin_left = 6
	bsb.content_margin_right = 6
	_badge.add_theme_stylebox_override("normal", bsb)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.position = Vector2(-2, -5)
	_nav_buttons.accueil.add_child(_badge)
	_nav_slide = SlidePanel.make(app, "nav", "left", 180, _nav_panel)
	_shell.add_child(_nav_slide)
	_shell.add_child(_content)


func _label_of(k: String) -> String:
	for item in NAV:
		if item[0] == k:
			return item[1]
	return k


func show_screen(key: String, remember := true) -> void:
	_close_all_overlays()
	if key == "note" and not screens.note.has_note():
		key = "fiches"
	if current != "" and current != key and remember:
		history.append(current)
		if history.size() > 30:
			history.pop_front()
	for c in _content.get_children():
		_content.remove_child(c)
	_content.add_child(screens[key])
	current = key
	var nav_key: String = {"diag": "coffre", "banc": "coffre", "nouvelle": "accueil", "graphe": "enquete",
		"seance": "enquete", "echanges": "enquete", "rapport": "enquete", "hypotheses": "enquete", "stats": "enquete"}.get(key, key)
	for k in _nav_buttons:
		_nav_buttons[k].button_pressed = k == nav_key
	_nav_buttons.note.disabled = not screens.note.has_note()
	if screens[key].has_method("on_show"):
		screens[key].on_show()


## `from_creation` : la note vient d'être créée ; « retour » ne ramène pas au formulaire.
func open_note(rel: String, from_creation := false) -> void:
	if screens.note.open(rel):
		show_screen("note", not from_creation)
	refresh_badge()


## Nouvelle note : choix du type, ou formulaire direct d'un type donné.
func new_note(type_name := "", preset := {}) -> void:
	if type_name == "":
		screens.nouvelle.start()
	else:
		screens.nouvelle.start_type(type_name, preset)
	show_screen("nouvelle")


## Graphe des relations, centré sur une fiche ("" = tout le coffre).
func show_graph(center := "") -> void:
	screens.graphe.set_center(center)
	show_screen("graphe")


## Chemins les plus probables entre deux fiches (noms ; "" = à choisir).
func show_paths(from := "", to := "") -> void:
	screens.graphe.set_path(from, to)
	show_screen("graphe")


## Enquête → Alibis : « personne » (nom), « nuit » (AAAA-MM-JJ) ou « incidents » (chemin à cocher).
func show_alibis(mode := "", value := "") -> void:
	screens.enquete.open_alibis(mode, value)
	show_screen("enquete")


## Statistiques : « personnages » ou « informations ».
func show_stats(tab := "personnages") -> void:
	screens.stats.tab = tab
	show_screen("stats")


## Tableau des hypothèses concurrentes d'un dossier (chemin de la note).
func show_hypotheses(rel: String) -> void:
	screens.hypotheses.open(rel)
	show_screen("hypotheses")


## Rapport d'une soirée (chemin de la note ; "" = soirée du jour ou la plus récente).
func show_report(rel := "") -> void:
	screens.rapport.open(rel)
	show_screen("rapport")


## Transformer une note rapide : choix du type, texte et date repris.
func transform_quick(rel: String, text: String, preset: Dictionary) -> void:
	screens.nouvelle.start(rel, text, preset)
	show_screen("nouvelle")


## Compteur de notes rapides à traiter, sur le bouton Accueil.
func refresh_badge() -> void:
	if not _nav_buttons.has("accueil"):
		return
	var n: int = app.index.quick_notes_todo_count() if app != null and app.index != null else 0
	_badge.text = str(n)
	_badge.visible = n > 0
	_nav_buttons.accueil.tooltip_text = ("%d note(s) rapide(s) à traiter" % n) if n > 0 else "Accueil"


# ------------------------------------------------------------------ calques (sélecteurs)

func open_overlay(c: Control) -> void:
	_margin.add_child(c)
	_overlays.append(c)


func close_overlay(c: Control) -> void:
	_overlays.erase(c)
	if is_instance_valid(c):
		c.queue_free()


func _close_all_overlays() -> void:
	for c in _overlays.duplicate():
		close_overlay(c)


func go_back() -> void:
	if not _overlays.is_empty():
		close_overlay(_overlays[-1])
		return
	if current == "nouvelle" and screens.nouvelle.back_step():
		return
	if current == "note" and screens.note.is_dirty():
		screens.note.save_draft()
	while not history.is_empty():
		var k: String = history.pop_back()
		if k != current:
			show_screen(k, false)
			return
	if current != "accueil":
		show_screen("accueil", false)
	else:
		get_tree().quit()


func _set_status(t: String) -> void:
	_status.text = t
	_status.visible = t != ""


func _on_job_finished(job: String, result: Dictionary) -> void:
	if result.has("error"):
		_set_status("%s : erreur — %s" % [job.capitalize(), result.error])
	elif job == "synchronisation" or job == "reconstruction":
		var parts := PackedStringArray()
		for k in [["new", "nouvelle"], ["modified", "modifiée"], ["deleted", "supprimée"]]:
			var n: int = int(result.get(k[0], 0))
			if n > 0:
				parts.append("%d %s%s" % [n, k[1], "s" if n > 1 else ""])
		if result.get("renamed", []).size() > 0:
			parts.append("%d renommée(s)" % result.renamed.size())
		var errs: int = result.get("read_errors", []).size()
		if errs > 0:
			parts.append("%d illisible(s) : voir Diagnostic" % errs)
		_set_status(("À jour · %d notes" % result.get("files", 0)) if parts.is_empty() else
			("Synchronisé · " + ", ".join(parts)))
	else:
		_set_status("%s terminé." % job.capitalize())
	for k in screens:
		if screens[k].has_method("on_job_finished"):
			screens[k].on_job_finished(job, result)
	refresh_badge()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			go_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if screens.has("note") and screens.note.is_dirty():
				screens.note.save_draft()
		NOTIFICATION_APPLICATION_RESUMED:
			_resync_on_return()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if Time.get_ticks_msec() - _last_focus_sync > 30000:
				_resync_on_return()


## Au retour dans l'application (Git ou Obsidian ont pu modifier des fichiers) :
## on revérifie le dossier, puis on resynchronise.
func _resync_on_return() -> void:
	_last_focus_sync = Time.get_ticks_msec()
	if app == null or app.busy() or app.repo_path() == "":
		return
	var check: Dictionary = app.open_repo()
	if check.get("readable", false):
		app.start_sync()
	if screens.has(current) and screens[current].has_method("on_show"):
		screens[current].on_show()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if k.ctrl_pressed or k.meta_pressed:
		match k.keycode:
			KEY_S:
				if current == "note":
					screens.note.save()
					get_viewport().set_input_as_handled()
			KEY_N:
				new_note()
				get_viewport().set_input_as_handled()
			KEY_F, KEY_K:
				show_screen("fiches")
				screens.fiches.focus_search()
				get_viewport().set_input_as_handled()
			KEY_R:
				app.start_sync()
				get_viewport().set_input_as_handled()
			KEY_B:
				_nav_slide.toggle()
				get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F11:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE and (current in ["note", "nouvelle"] or not _overlays.is_empty()):
		go_back()
		get_viewport().set_input_as_handled()
