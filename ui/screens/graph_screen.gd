extends VBoxContainer
## Écran « Graphe » : relations entre personnages et groupes, centrées sur une
## fiche (un ou deux cercles) ou sur l'ensemble du coffre (les plus reliés).
## Filtres : relations, faveurs (à part), clan/secte/sire, coprésence aux
## soirées, crédibilité minimale. Un clic sur un sommet montre ses liens et
## leurs sources ; un double-clic le met au centre. Les commandes et la liste
## des liens sont dans un panneau à droite, qui se cache par sa flèche.
##
## Mode « Chemin » : on choisit deux fiches ; l'écran montre les chemins les
## plus probables qui les relient (échelle de l'Amirauté, core/analysis/paths.gd).

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const GraphData := preload("res://core/analysis/graph_data.gd")
const Paths := preload("res://core/analysis/paths.gd")
const GraphView := preload("res://ui/widgets/graph_view.gd")
const Picker := preload("res://ui/widgets/picker.gd")
const SlidePanel := preload("res://ui/widgets/slide_panel.gd")

const CREDS := [["Toutes les crédibilités", 6], ["Crédibilité 1 à 4", 4], ["Crédibilité 1 à 3", 3], ["Crédibilité 1 à 2", 2]]
const MAX_NODES := [["120 fiches les plus reliées", 120], ["300 fiches les plus reliées", 300], ["Toutes les fiches", 100000]]
const PERIODES := [["Toutes les périodes", 0], ["10 dernières années", 10], ["5 dernières années", 5], ["2 dernières années", 2], ["Dernière année", 1]]
const PATH_TYPES := ["personnage", "groupe", "lieu", "objet", "domaine"]

var app: Node
var main: Control
var center := ""
var depth := 1
var opts := {"relations": true, "indices": true, "faveurs": true, "structure": true, "copresence": false, "max_cred": 6, "max_nodes": 120}
var mode := "relations"   ## « relations » ou « chemin »
var path_from := ""
var path_to := ""
var path_opts := {"relations": true, "indices": true, "faveurs": false, "structure": false, "copresence": false,
	"sans_inevaluable": false, "periode": 0, "k": 5, "max_cred": 6, "exclure": []}
var path_result := {}

var _view: Control
var _center_btn: Button
var _depth: OptionButton
var _info_title: Label
var _info_list: VBoxContainer
var _info_box: VBoxContainer
var _status: Label
var _rel_bar: Control
var _rel_fold: FoldableContainer
var _legend: VBoxContainer
var _path_bar: VBoxContainer
var _from_btn: Button
var _to_btn: Button
var _mode_btn: Button
var _side: VBoxContainer     ## commandes, filtres et liens du point touché, dans un panneau escamotable
var _side_panel: Control


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_side = UiKit.vbox([], 6)
	var row := UiKit.flow(6)
	row.add_child(UiKit.button("← Enquête", func(): main.show_screen("enquete")))
	_mode_btn = UiKit.button("Chemin entre deux fiches", _toggle_mode, "Les liens les plus probables entre deux fiches")
	row.add_child(_mode_btn)
	_side.add_child(row)
	# --- barre du mode « relations »
	var rel_row := UiKit.flow(6)
	_center_btn = UiKit.button("", _pick_center, "Choisir la fiche au centre")
	rel_row.add_child(_center_btn)
	_depth = UiKit.option_button(["1 cercle", "2 cercles"], 0)
	_depth.size_flags_horizontal = Control.SIZE_FILL
	_depth.custom_minimum_size.x = 120
	_depth.item_selected.connect(func(i):
		depth = i + 1
		refresh())
	rel_row.add_child(_depth)
	_rel_bar = rel_row
	_side.add_child(rel_row)
	_rel_fold = FoldableContainer.new()
	_rel_fold.title = "Filtres et légende"
	_rel_fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # titre long : jamais plus large que l'écran
	_rel_fold.folded = true
	var inner := UiKit.vbox([], 6)
	_rel_fold.add_child(inner)
	var filters := UiKit.flow(6)
	filters.add_child(UiKit.button("Tout le coffre", func(): set_center("")))
	for f in [["relations", "Relations"], ["faveurs", "Faveurs"], ["structure", "Clan, secte, sire"], ["copresence", "Vus ensemble"]]:
		filters.add_child(_toggle(opts, f[0], f[1], refresh))
	var labels := []
	for c in CREDS:
		labels.append(c[0])
	var cred := UiKit.option_button(labels, 0)
	cred.size_flags_horizontal = Control.SIZE_FILL
	cred.custom_minimum_size.x = 190
	cred.item_selected.connect(func(i):
		opts.max_cred = CREDS[i][1]
		refresh())
	filters.add_child(cred)
	var mn := UiKit.option_button(MAX_NODES.map(func(x): return x[0]), 0)
	mn.size_flags_horizontal = Control.SIZE_FILL
	mn.custom_minimum_size.x = 220
	mn.tooltip_text = "Sans fiche au centre : combien de fiches afficher"
	mn.item_selected.connect(func(i):
		opts.max_nodes = MAX_NODES[i][1]
		refresh())
	filters.add_child(mn)
	inner.add_child(filters)
	_side.add_child(_rel_fold)
	# légende toujours visible : couleur des liens, puis des points
	var legend := UiKit.vbox([], 2)
	for it in [["7fd59b", "alliance, service, appartenance", false], ["ff7a6b", "hostilité", false], ["b9b2c4", "autre lien", false],
			["e0b04a", "faveur (débiteur → créancier)", true], ["b9b2c4", "indice (lien à vérifier)", true],
			["9c86c9", "clan, secte, sire", false], ["5d8fb8", "vus ensemble en soirée", false]]:
		legend.add_child(_legend_row(Color(it[0]), it[1], it[2], false))
	for it in [["8fd3ff", "personnage"], ["c8b6ff", "groupe"], ["9be3a8", "domaine, lieu"], ["f5e08a", "autre note"], ["6b6475", "sans fiche"]]:
		var lr := _legend_row(Color(it[0]), it[1], false, true)
		(lr.get_child(0) as _Swatch).ring = it[1] == "sans fiche"
		legend.add_child(lr)
	legend.add_child(UiKit.muted("Passez la souris sur un lien pour lire ce qu'il dit et d'où il vient."))
	_legend = legend
	_side.add_child(legend)
	# --- barre du mode « chemin »
	_build_path_bar()
	_status = UiKit.muted("")
	_side.add_child(_status)
	_view = GraphView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.custom_minimum_size.y = 260
	_view.node_selected.connect(_on_select)
	_view.node_activated.connect(func(k):
		if mode == "relations":
			set_center(str(_view.data.nodes[k].name)))
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size.y = 260
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_view)
	var zoom_box := UiKit.vbox([], 6)
	for z in [["+", 1.25, "Zoomer"], ["−", 0.8, "Dézoomer"]]:
		var f: float = z[1]
		var zb := UiKit.button(z[0], func(): _view.zoom_by(f), z[2])
		zb.custom_minimum_size = Vector2(UiKit.TOUCH, UiKit.TOUCH)
		zb.size_flags_horizontal = Control.SIZE_SHRINK_END
		zoom_box.add_child(zb)
	var fit := UiKit.button("Voir tout", func(): _view.show_all(), "Cadrer tous les points")
	fit.custom_minimum_size = Vector2(UiKit.TOUCH, UiKit.TOUCH)
	fit.size_flags_horizontal = Control.SIZE_SHRINK_END
	zoom_box.add_child(fit)
	stack.add_child(zoom_box)
	zoom_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zoom_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	_info_box = UiKit.vbox([], 4)
	_info_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_title = UiKit.label("", true, 15)
	_info_box.add_child(_info_title)
	_info_list = UiKit.vbox([], 4)
	var sc := UiKit.scroll(_info_list)
	sc.custom_minimum_size.y = 170
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_box.add_child(sc)
	_side.add_child(_info_box)
	# le graphe prend toute la place ; le panneau de droite se cache par sa flèche
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stack)
	_side_panel = SlidePanel.make(app, "graphe", "right", 420, _side, true, Color("1b1721"))
	body.add_child(_side_panel)
	add_child(body)
	_update_center_btn()
	_apply_mode()


## Ligne de légende : un trait (plein ou en tirets) ou un point, puis son sens.
func _legend_row(col: Color, text: String, dashed: bool, dot: bool) -> Control:
	var sw := _Swatch.new()
	sw.col = col
	sw.dashed = dashed
	sw.dot = dot
	sw.custom_minimum_size = Vector2(30, 18)
	var l := UiKit.label(text, false, 13)
	l.add_theme_color_override("font_color", Color("b3a9c2"))
	return UiKit.hbox([sw, l], 8)


class _Swatch extends Control:
	var col := Color.WHITE
	var dashed := false
	var dot := false
	var ring := false

	func _draw() -> void:
		var y := size.y / 2.0
		if dot and ring:
			draw_arc(Vector2(size.x / 2.0, y), 6.0, 0, TAU, 24, col, 2.0, true)
		elif dot:
			draw_circle(Vector2(size.x / 2.0, y), 6.0, col)
		elif dashed:
			draw_dashed_line(Vector2(2, y), Vector2(size.x - 2, y), col, 2.0, 5.0)
		else:
			draw_line(Vector2(2, y), Vector2(size.x - 2, y), col, 2.0, true)


func _toggle(target: Dictionary, key: String, text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, func(): pass)
	b.toggle_mode = true
	b.button_pressed = bool(target[key])
	b.toggled.connect(func(on):
		target[key] = on
		cb.call())
	return b


func _build_path_bar() -> void:
	_path_bar = UiKit.vbox([], 6)
	var ends := UiKit.flow(6)
	_from_btn = UiKit.button("", func(): _pick_end(true), "Fiche de départ")
	_to_btn = UiKit.button("", func(): _pick_end(false), "Fiche d'arrivée")
	ends.add_child(_from_btn)
	ends.add_child(_to_btn)
	ends.add_child(UiKit.button("⇄", func():
		var t := path_from
		path_from = path_to
		path_to = t
		_update_ends()
		refresh(), "Inverser"))
	_path_bar.add_child(ends)
	var fold := FoldableContainer.new()
	fold.title = "Filtres du chemin"
	fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fold.folded = true
	var inner := UiKit.vbox([], 6)
	fold.add_child(inner)
	var fl := UiKit.flow(6)
	for f in [["relations", "Relations"], ["indices", "Indices"], ["faveurs", "Faveurs (levier)"],
			["structure", "Clan, secte, domaine"], ["copresence", "Vus ensemble"], ["sans_inevaluable", "Ignorer F et 6"]]:
		fl.add_child(_toggle(path_opts, f[0], f[1], refresh))
	var per := UiKit.option_button(PERIODES.map(func(x): return x[0]), 0)
	per.size_flags_horizontal = Control.SIZE_FILL
	per.custom_minimum_size.x = 200
	per.item_selected.connect(func(i):
		path_opts.periode = PERIODES[i][1]
		refresh())
	fl.add_child(per)
	var pc := UiKit.option_button(CREDS.map(func(x): return x[0]), 0)
	pc.size_flags_horizontal = Control.SIZE_FILL
	pc.custom_minimum_size.x = 190
	pc.item_selected.connect(func(i):
		path_opts.max_cred = CREDS[i][1]
		refresh())
	fl.add_child(pc)
	# relations à exclure (cochées = prises en compte)
	var rels := MenuButton.new()
	rels.text = "Types de relations…"
	rels.custom_minimum_size.y = UiKit.TOUCH
	rels.flat = false
	var pop := rels.get_popup()
	pop.hide_on_checkable_item_selection = false
	var codes := []
	for o in Schema.options("", "relation"):
		if o[0] == "present_a":
			continue
		codes.append(o[0])
		pop.add_check_item(str(o[1]))
		pop.set_item_checked(pop.item_count - 1, true)
	pop.index_pressed.connect(func(i):
		pop.set_item_checked(i, not pop.is_item_checked(i))
		var ex := []
		for k in codes.size():
			if not pop.is_item_checked(k):
				ex.append(codes[k])
		path_opts.exclure = ex
		rels.text = "Types de relations…" if ex.is_empty() else "Relations : %d exclue(s)" % ex.size()
		refresh())
	fl.add_child(rels)
	var kk := UiKit.option_button(["3 chemins", "5 chemins", "8 chemins"], 1)
	kk.size_flags_horizontal = Control.SIZE_FILL
	kk.custom_minimum_size.x = 120
	kk.item_selected.connect(func(i):
		path_opts.k = [3, 5, 8][i]
		refresh())
	fl.add_child(kk)
	inner.add_child(fl)
	inner.add_child(UiKit.muted("Chaque lien vaut fiabilité de la source × crédibilité de l'information : A ou 1 = 0,95 ; B ou 2 = 0,8 ; C ou 3 = 0,6 ; D ou 4 = 0,4 ; E ou 5 = 0,2 ; F ou 6 (impossible à juger) = 0,5. Exemple : une conversation C sur une information 2 vaut 0,6 × 0,8 = 48 %. Un lien attesté par plusieurs notes ou personnes différentes est renforcé ; deux mentions de la même note ou de la même personne ne comptent qu'une fois. Par défaut, un clan, une secte ou un domaine ne sert pas d'étape : sinon tout le monde est relié par la Camarilla. La table se règle dans .nosferatu/config.json (section « amiraute »)."))
	_path_bar.add_child(fold)
	_side.add_child(_path_bar)
	_update_ends()


func on_show() -> void:
	refresh()


func on_job_finished(_job: String, _r: Dictionary) -> void:
	if is_inside_tree():
		refresh()


func set_center(name: String) -> void:
	center = name
	_update_center_btn()
	if mode != "relations":
		mode = "relations"
		_apply_mode()
	if is_inside_tree():
		refresh()


## Ouvre le mode chemin entre deux fiches (noms ; "" = à choisir).
func set_path(from: String, to: String) -> void:
	path_from = Schema.link_name(from)
	path_to = Schema.link_name(to)
	mode = "chemin"
	_apply_mode()
	_update_ends()
	if is_inside_tree():
		refresh()


func _toggle_mode() -> void:
	mode = "chemin" if mode == "relations" else "relations"
	if mode == "chemin" and path_from == "" and center != "":
		path_from = center
	_apply_mode()
	_update_ends()
	refresh()


func _apply_mode() -> void:
	var chemin := mode == "chemin"
	_rel_bar.visible = not chemin
	_rel_fold.visible = not chemin
	_legend.visible = not chemin
	_path_bar.visible = chemin
	_mode_btn.text = "Retour aux relations" if chemin else "Chemin entre deux fiches"


func _update_center_btn() -> void:
	_center_btn.text = ("Centre : " + center) if center != "" else "Choisir le centre…"


func _update_ends() -> void:
	_from_btn.text = ("De : " + path_from) if path_from != "" else "De : choisir…"
	_to_btn.text = ("À : " + path_to) if path_to != "" else "À : choisir…"


func _pick_center() -> void:
	Picker.open_in(main, app, "Mettre au centre", "notes", ["personnage", "groupe"], func(v):
		set_center(Schema.link_name(v)))


func _pick_end(is_from: bool) -> void:
	Picker.open_in(main, app, "Départ du chemin" if is_from else "Arrivée du chemin", "notes", PATH_TYPES, func(v):
		if is_from:
			path_from = Schema.link_name(v)
		else:
			path_to = Schema.link_name(v)
		_update_ends()
		refresh())


func refresh() -> void:
	if app.index == null:
		_status.text = "Aucun coffre ouvert."
		return
	if mode == "chemin":
		_refresh_path()
		return
	var o := opts.duplicate()
	o["center"] = center
	o["depth"] = depth
	var t0 := Time.get_ticks_msec()
	var d: Dictionary = GraphData.build(app.index, o)
	_view.set_data(d)
	var total := ""
	if center == "":
		total = " (les plus reliées)" if int(opts.max_nodes) < 100000 else " (toutes)"
	_status.text = "%d fiche(s), %d lien(s)%s — calcul %d ms" % [d.nodes.size(), d.edges.size(), total, Time.get_ticks_msec() - t0]
	_on_select(_view.selected)


func _refresh_path() -> void:
	path_result = {}
	if path_from == "" or path_to == "":
		_view.set_data({"nodes": {}, "edges": [], "center": ""})
		_status.text = "Choisissez la fiche de départ et la fiche d'arrivée (ou cliquez sur un point du graphe des relations, puis « Chemin depuis ici »)."
		_show_paths()
		return
	var o := path_opts.duplicate()
	o["config"] = app.repo.config if app.repo != null else {}
	if int(o.periode) > 0:
		var d := Time.get_date_dict_from_system()
		o["depuis"] = "%04d-%02d-%02d" % [d.year - int(o.periode), d.month, d.day]
	var t0 := Time.get_ticks_msec()
	path_result = Paths.find(app.index, path_from, path_to, o)
	var ms := Time.get_ticks_msec() - t0
	if path_result.paths.is_empty():
		_view.set_data({"nodes": {}, "edges": [], "center": ""})
		_status.text = "Aucun chemin : %s. Essayez d'autres filtres (clan et secte, faveurs, vus ensemble, période)." % path_result.error
	else:
		var g := Paths.to_graph(path_result)
		_view.set_data(g)
		_status.text = "%d chemin(s) — le plus probable : %d %% — calcul %d ms" % [path_result.paths.size(),
			roundi(float(path_result.paths[0].p) * 100.0), ms]
	_show_paths()


func _name_of(key: String) -> String:
	if path_result.has("names") and path_result.names.has(key):
		return str(path_result.names[key].name)
	if _view.data.nodes.has(key):
		return str(_view.data.nodes[key].name)
	return key


## Liste des chemins trouvés : chaque étape, avec ses attestations (note, A–F/1–6).
func _show_paths() -> void:
	for c in _info_list.get_children():
		c.queue_free()
	if path_result.is_empty() or path_result.paths.is_empty():
		_info_title.text = "Chemins les plus probables"
		return
	_info_title.text = "Chemins les plus probables, du plus sûr au moins sûr"
	for pi in path_result.paths.size():
		var p: Dictionary = path_result.paths[pi]
		var names := PackedStringArray()
		for n in p.nodes:
			names.append(_name_of(n))
		var fold := FoldableContainer.new()
		fold.title = "%d. %d %% — %s" % [pi + 1, roundi(float(p.p) * 100.0), " → ".join(names)]
		fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		fold.folded = pi > 0
		var inner := UiKit.vbox([], 4)
		fold.add_child(inner)
		for hi in p.links.size():
			var l: Dictionary = path_result.links[p.links[hi]]
			var a: String = p.nodes[hi]
			var b: String = p.nodes[hi + 1]
			var head := UiKit.label("%s → %s · %d %%%s" % [_name_of(a), _name_of(b), roundi(float(l.p) * 100.0),
				(" (%d attestations)" % l.att.size()) if l.att.size() > 1 else ""], true, 15)
			inner.add_child(head)
			var shown := 0
			for at in l.att:
				if shown >= 4:
					inner.add_child(UiKit.muted("… et %d autre(s)" % (l.att.size() - shown)))
					break
				shown += 1
				var path: String = str(at.path)
				var b2 := UiKit.button("   " + Paths.describe(at), func():
					if path != "":
						main.open_note(path))
				b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				b2.add_theme_color_override("font_color", GraphData.edge_color({"kind": at.kind, "code": at.code, "active": true}).lightened(0.2))
				inner.add_child(b2)
		_info_list.add_child(fold)


func _on_select(key: String) -> void:
	if mode == "chemin":
		_on_select_path(key)
		return
	for c in _info_list.get_children():
		c.queue_free()
	if key == "" or not _view.data.nodes.has(key):
		_info_title.text = "Cliquez sur un point pour voir ses liens ; double-cliquez pour le mettre au centre."
		return
	var n: Dictionary = _view.data.nodes[key]
	_info_title.text = "%s · %s" % [n.name, ("fiche absente" if n.missing else Schema.type_label(str(n.type)))]
	var actions := UiKit.flow(6)
	if not n.missing:
		var p: String = n.path
		actions.add_child(UiKit.button("Ouvrir la fiche", func(): main.open_note(p)))
	actions.add_child(UiKit.button("Mettre au centre", func(): set_center(str(n.name))))
	var nm := str(n.name)
	actions.add_child(UiKit.button("Chemin depuis ici", func(): set_path(nm, path_to if path_to != nm else "")))
	if path_from != "" and path_from != nm:
		actions.add_child(UiKit.button("Chemin jusqu'ici", func(): set_path(path_from, nm)))
	_info_list.add_child(actions)
	for e in _view.data.edges:
		if e.a != key and e.b != key:
			continue
		var other: String = e.b if e.a == key else e.a
		var oname := str(_view.data.nodes[other].name) if _view.data.nodes.has(other) else other
		var txt := ""
		if e.kind == "copresence":
			txt = "%s — %s" % [oname, e.label]
		elif e.kind == "faveur":
			txt = ("Doit une faveur %s à %s (%s)" % [e.niv, oname, e.st]) if e.a == key else ("%s lui doit une faveur %s (%s)" % [oname, e.niv, e.st])
		elif e.a == key:
			txt = "%s %s%s" % [e.label, oname, e.get("suffix", "")]
		else:
			txt = "%s %s %s%s" % [oname, e.label, n.name, e.get("suffix", "")]
		if str(e.source) != "" and e.kind in ["relation", "indice"]:
			txt += "\n— %s, crédibilité %s" % [e.source, str(e.cred)]
		var path: String = str(e.path)
		var b := UiKit.button(txt, func():
			if path != "":
				main.open_note(path))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_color_override("font_color", GraphData.edge_color(e).lightened(0.2))
		_info_list.add_child(b)


## Mode chemin : un clic sur un point propose d'en faire le départ ou l'arrivée.
func _on_select_path(key: String) -> void:
	if key == "" or not _view.data.nodes.has(key):
		_show_paths()
		return
	_show_paths()
	var n: Dictionary = _view.data.nodes[key]
	var nm := str(n.name)
	var actions := UiKit.flow(6)
	actions.add_child(UiKit.label(nm, false, 15))
	if not n.missing:
		var p: String = n.path
		actions.add_child(UiKit.button("Ouvrir la fiche", func(): main.open_note(p)))
	if nm != path_from:
		actions.add_child(UiKit.button("Partir d'ici", func(): set_path(nm, path_to)))
	if nm != path_to:
		actions.add_child(UiKit.button("Arriver ici", func(): set_path(path_from, nm)))
	_info_list.add_child(actions)
	_info_list.move_child(actions, 0)
