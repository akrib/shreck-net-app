extends SceneTree
## Parcours automatique de l'interface, sans écran (outil de développement) :
##   godot --headless --path . --script res://tools/smoke_ui.gd
## Travaille sur une copie du coffre d'exemple, avec des réglages séparés :
## les réglages et le coffre réels ne sont jamais touchés.

const UiKit := preload("res://ui/ui_kit.gd")

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + msg)
	if not cond:
		failures += 1


func _wait_jobs(app: Node) -> void:
	for i in 600:
		await process_frame
		if not app.busy():
			return


func _copy(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	d.include_hidden = true
	for f in d.get_files():
		if f != ".gdignore":
			var out := FileAccess.open(dst + "/" + f, FileAccess.WRITE)
			out.store_buffer(FileAccess.get_file_as_bytes(src + "/" + f))
			out.close()
	for s in d.get_directories():
		_copy(src + "/" + s, dst + "/" + s)


func _rm(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	var d := DirAccess.open(p)
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(p + "/" + f)
	for s in d.get_directories():
		_rm(p + "/" + s)
	DirAccess.remove_absolute(p)


func _read(vault: String, rel: String) -> String:
	return FileAccess.get_file_as_string(vault + "/" + rel)


func _find_overlay(main: Control) -> Control:
	return main._overlays[-1] if not main._overlays.is_empty() else null


func _run() -> void:
	print("== Parcours de l'interface (sans écran) ==")
	# Garde-fou : une erreur de script interrompt le parcours ; on ne reste pas bloqué.
	create_timer(240.0).timeout.connect(func():
		print("== DÉLAI DÉPASSÉ : parcours interrompu (voir l'erreur plus haut) ==")
		quit(2))
	var vault := OS.get_user_data_dir() + "/tests_tmp/coffre-ui"
	_rm(vault)
	_copy(ProjectSettings.globalize_path("res://tests/fixtures/coffre-exemple"), vault)
	load("res://core/app/app_service.gd").settings_file = "user://tests_tmp/reglages-parcours.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tests_tmp/reglages-parcours.cfg"))
	var main: Control = load("res://ui/main.tscn").instantiate()
	print("  (fenêtre sans écran : %s, mise à 1920 × 1080)" % str(root.size))
	root.size = Vector2i(1920, 1080)  # plein écran d'un PC
	root.add_child(main)
	await process_frame
	var app: Node = main.app
	app.set_repo_path(vault)
	app.start_rebuild()
	await _wait_jobs(app)
	_ok(app.index != null and app.index.stats().files == 21, "coffre indexé (21 notes)")
	for k in ["accueil", "fiches", "enquete", "coffre", "diag", "banc", "nouvelle"]:
		main.show_screen(k)
		await process_frame
		_ok(main.current == k, "écran %s affiché" % k)

	# --- recherche au clavier : ↓ choisit la première ligne, Entrée ouvre le premier résultat
	main.show_screen("fiches")
	var fsc = main.screens.fiches
	fsc._search.text = "valomb"
	fsc._focus_table()
	await process_frame
	_ok(fsc._table.has_focus() and fsc._table.get_selected() != null, "recherche : ↓ passe au tableau, première ligne choisie")
	fsc.submit()
	await process_frame
	_ok(main.current == "note" and main.screens.note.rel == "Domaines/Valombre.md", "recherche : Entrée ouvre le premier résultat, le nom qui commence par la recherche (%s)" % main.screens.note.rel)
	main.go_back()
	await process_frame
	fsc._search.text = ""
	fsc._refresh()

	# --- note rapide depuis l'accueil, puis transformation
	main.show_screen("accueil")
	var acc = main.screens.accueil
	acc.refresh()
	_ok(acc._todo_label.text.begins_with("Aucune note rapide"), "accueil : rien à traiter")
	acc._quick()
	await process_frame
	var note = main.screens.note
	_ok(main.current == "note" and note.doc.type_name() == "en_cours", "note rapide créée et ouverte")
	var quick_rel: String = note.rel
	note._body.text = "Croisé [[Victor Morel]] avec une inconnue aux cheveux rouges, quai nord."
	note._mark_dirty()
	note.save()
	await process_frame
	_ok(_read(vault, quick_rel).contains("cheveux rouges"), "texte de la note rapide enregistré")
	_ok(main._badge.visible and main._badge.text == "1", "pastille sur le bouton Accueil : " + main._badge.text)
	note._transform()
	await process_frame
	var nn = main.screens.nouvelle
	_ok(main.current == "nouvelle" and nn.step == 1 and nn.from_quick == quick_rel, "transformer : choix du type")
	_ok(nn._grid.get_child_count() == 12, "12 types proposés (sans « note rapide »)")
	nn._choose("personnage")
	await process_frame
	_ok(nn.step == 2 and nn.editors.has("nom"), "formulaire du personnage")
	_ok(nn._error.text == "", "formulaire : pas de « À compléter » avant la première saisie")
	_ok(nn.editors.nature.get_value() == "vampire" and nn.editors.fiabilite.get_value() == "F", "valeurs par défaut affichées (vampire, fiabilité F)")
	_ok(nn.editors.has("rang") and nn.editors.has("secte") and nn.editors.has("titres"), "formulaire : statut d'âge, secte, postes")
	var fopt: OptionButton = nn.editors.fiabilite._option
	_ok(fopt.item_count == 7 and fopt.get_item_text(1).begins_with("A —") and fopt.get_item_text(6).begins_with("F —"), "liste A à F (plus « — » : champ facultatif)")
	nn.editors.nom.set_value("Inconnue aux cheveux rouges")
	nn.editors.identite.set_value("inconnue")
	nn._create()
	await process_frame
	_ok(main.current == "note" and note.rel == "Personnages/Inconnue aux cheveux rouges.md", "personnage créé et ouvert")
	_ok(_read(vault, note.rel).contains("## Notes\nCroisé [[Victor Morel]]"), "texte de la note rapide repris")
	_ok(_read(vault, quick_rel).contains("statut: traitee"), "note rapide marquée traitée")
	_ok(not main._badge.visible, "pastille masquée quand il n'y a plus rien à traiter")
	main.go_back()
	await process_frame
	_ok(main.current != "nouvelle", "retour : pas de retour au formulaire après création (écran %s)" % main.current)

	# --- soirée du jour depuis l'accueil
	main.show_screen("accueil")
	acc._soiree()
	await process_frame
	_ok(main.current == "nouvelle" and nn.type_name == "soiree", "soirée du jour : formulaire")
	var d := Time.get_date_dict_from_system()
	var today := "%04d-%02d-%02d" % [d.year, d.month, d.day]
	_ok(nn.editors.date.get_value() == today, "date du jour préremplie")
	_ok(nn.editors.fiabilite.get_value() == "A" and nn.editors.moi_present.get_value() == true, "fiabilité A, présent")
	# domaine choisi dans le sélecteur
	nn.editors.domaine._pick_one()
	await process_frame
	var picker := _find_overlay(main)
	_ok(picker != null, "sélecteur ouvert")
	picker._search.text = "valomb"
	picker._refresh()
	_ok(picker._list.item_count == 1, "sélecteur : « valomb » trouve Valombre")
	picker._pick(0)
	await process_frame
	_ok(nn.editors.domaine.get_value() == "[[Valombre]]", "domaine choisi : " + str(nn.editors.domaine.get_value()))
	_ok(main._overlays.is_empty(), "sélecteur refermé")
	# présents : un existant et une fiche créée à la volée
	nn.editors.presents._pick_many()
	await process_frame
	picker = _find_overlay(main)
	picker._search.text = "elise"
	picker._refresh()
	picker._pick(0)
	nn.editors.presents._pick_many()
	await process_frame
	picker = _find_overlay(main)
	picker._search.text = "Bastien Roux"
	picker._refresh()
	_ok(picker._create_row.visible, "personne inconnue : « Créer la fiche » proposé")
	picker._create()
	await process_frame
	_ok(FileAccess.file_exists(vault + "/Personnages/Bastien Roux.md"), "fiche créée depuis le sélecteur")
	_ok(nn.editors.presents.get_value() == ["[[Élise Varga]]", "[[Bastien Roux]]"], "présents : " + str(nn.editors.presents.get_value()))
	nn._create()
	await process_frame
	var srel := "Soirees/%04d/%s Valombre - Assemblée.md" % [d.year, today]
	_ok(note.rel == srel, "soirée créée : " + note.rel)
	var stxt := _read(vault, srel)
	_ok(stxt.contains("presents:\n  - \"[[Élise Varga]]\"\n  - \"[[Bastien Roux]]\"\n"), "présents écrits dans la soirée")
	# élément : nature « rumeur » -> crédibilité 4 proposée
	_ok(note._el_nature.get_item_text(note._el_nature.selected).begins_with("Observé"), "soirée : nature « observé » par défaut")
	note._el_text.text = "[[Bastien Roux]] parlait de quitter la ville."
	note._el_nature.select(2)
	note._el_nature.item_selected.emit(2)
	_ok(note._el_cred.selected == 3, "rumeur : crédibilité 4 proposée")
	note._add_element()
	await process_frame
	stxt = _read(vault, srel)
	_ok(stxt.contains("[[Bastien Roux]] parlait de quitter la ville. [nature:: rumeur] [credibilite:: 4] ^el-"), "élément ajouté avec les listes déroulantes")
	# accueil : la soirée du jour existe maintenant
	main.show_screen("accueil")
	acc.refresh()
	_ok(UiKit.tile_text(acc._soiree_btn).contains("Ouvrir"), "accueil : « Ouvrir » la soirée du jour")

	# --- édition d'une fiche existante (listes déroulantes) et conflit
	var rel := "Personnages/Victor Morel.md"
	main.open_note(rel)
	await process_frame
	_ok(note._typed.has("statut") and note._typed.statut._option != null, "statut : liste déroulante")
	note._typed.statut.set_value("disparu")
	note.save()
	await process_frame
	var txt := _read(vault, rel)
	_ok(txt.contains("statut: disparu"), "propriété enregistrée dans le fichier")
	_ok(txt.contains("# Victor Morel\n\n> Exemple fictif"), "corps intact")
	_ok(str(note._status.text).begins_with("Enregistré"), "statut : " + note._status.text)
	note._typed.statut.set_value("actif")
	var f := FileAccess.open(vault + "/" + rel, FileAccess.WRITE)
	f.store_string(txt.replace("fiabilite: C", "fiabilite: D"))
	f.close()
	note.save()
	await process_frame
	_ok(_read(vault, rel).contains("fiabilite: D"), "conflit : la version externe n'est pas écrasée")
	_ok(note._confirm.visible or note._pending == "conflict", "conflit : confirmation demandée")
	note._on_confirmed()
	await process_frame
	_ok(DirAccess.get_files_at(vault + "/_Conflits").size() == 1, "conflit : ma version conservée dans _Conflits/")
	# renseignements calculés
	main.open_note(rel)
	await process_frame
	var titles := []
	for c in note._col.get_children():
		if c is VBoxContainer:
			for cc in c.get_children():
				if cc is FoldableContainer:
					titles.append(cc.title)
	_ok(titles.any(func(t): return str(t).begins_with("Où était-il ?")), "fiche : où était-il ? (présences)")
	_ok(titles.any(func(t): return str(t).begins_with("Faveurs (1)")), "fiche : faveurs (%s)" % str(titles))
	_ok(titles.any(func(t): return str(t).begins_with("Relations connues")), "fiche : relations")
	_ok(note._side_panel.visible and note._typed.has("clan") and note._side_col.is_ancestor_of(note._typed.clan), "formulaire dans le panneau de droite, synthèse dans la colonne large")
	note._side_panel.set_open(false, false)
	await process_frame
	_ok(note._col.get_parent().size.x > 1500.0 and note._col.size.x <= 1100.0, "panneau de la fiche caché : colonne de lecture de %d px, centrée sur %d px" % [note._col.size.x, note._col.get_parent().size.x])
	note._side_panel.set_open(true, false)

	# --- graphe depuis la fiche, puis préparation de séance
	main.show_graph("Victor Morel")
	await process_frame
	var gs = main.screens.graphe
	_ok(main.current == "graphe" and gs._view.data.nodes.has("victor morel"), "graphe centré sur Victor Morel (%d fiches)" % gs._view.data.nodes.size())
	_ok(gs._legend.visible and gs._legend.get_child_count() >= 12, "graphe : légende visible sans la déplier")
	for i in 30:
		await process_frame
	var gv = gs._view
	var e0: Dictionary = gv.data.edges.filter(func(e): return gv.to_screen(gv.pos[e.a]).distance_to(gv.to_screen(gv.pos[e.b])) > 90.0)[0]
	var mm := InputEventMouseMotion.new()
	mm.position = (gv.to_screen(gv.pos[e0.a]) + gv.to_screen(gv.pos[e0.b])) / 2
	gv._gui_input(mm)
	_ok(gv._hover_pair != "" and gv._hover_node == "", "graphe : la souris sur un lien affiche ce qu'il dit (%s)" % gv._hover_pair)
	gv._hover_pair = ""
	gs._view._tap("cercle des lanternes")
	await process_frame
	_ok(gs._info_title.text.begins_with("Cercle des Lanternes"), "sommet sélectionné : " + gs._info_title.text)
	_ok(gs._info_list.get_child_count() >= 2, "liens du sommet listés")
	for i in 40:
		await process_frame
	_ok(gs._view.pos["victor morel"] == Vector2.ZERO, "le centre reste au centre")
	gs._view.zoom_by(0.01)
	_ok(gs._view.zoom < 0.05, "dézoom bien plus fort qu'avant (%.3f)" % gs._view.zoom)
	gs._view.show_all()
	var all_in := true
	for k in gs._view.pos:
		var sp: Vector2 = gs._view.to_screen(gs._view.pos[k])
		if sp.x < 0 or sp.y < 0 or sp.x > gs._view.size.x or sp.y > gs._view.size.y:
			all_in = false
	_ok(all_in and gs._view.size.x > 600.0, "« Voir tout » : tous les points à l'écran (vue de %d × %d)" % [gs._view.size.x, gs._view.size.y])
	main.show_graph("")
	await process_frame
	gs._view._tap("victor morel")
	await process_frame
	var labels_sel := []
	for c in gs._info_list.get_children():
		if c is HFlowContainer:
			for b in c.get_children():
				if b is Button:
					labels_sel.append(b.text)
	_ok(labels_sel.has("Chemin depuis ici"), "un point propose « Chemin depuis ici »")
	main.show_paths("Victor Morel", "Cercle des Lanternes")
	await process_frame
	_ok(gs.mode == "chemin" and gs._path_bar.visible and not gs._rel_fold.visible, "mode chemin")
	_ok(not gs.path_result.is_empty() and gs.path_result.paths.size() >= 1, "chemin Victor Morel → Cercle des Lanternes : %s" % gs._status.text)
	_ok(gs._view.data.edges.size() >= 1 and gs._info_list.get_child_count() >= 1, "chemins dessinés et listés")
	gs.set_path("Victor Morel", "Armand Lescure")
	_ok(gs.path_result.paths.is_empty() and gs._status.text.contains("Armand Lescure n'a aucun lien"), "pas de chemin : expliqué")
	gs.path_opts.copresence = true
	gs.refresh()
	_ok(gs.path_result.paths.size() >= 1, "avec « vus ensemble » : %s" % gs._status.text)
	gs.path_opts.copresence = false
	gs._toggle_mode()
	_ok(gs.mode == "relations", "retour aux relations")

	# --- rapport de soirée, depuis la fiche de soirée
	main.open_note("Soirees/2026/2026-10-10 Valombre - Assemblée.md")
	await process_frame
	var rbtn: Button = null
	for c in note._col.get_children():
		if c is Button and c.text == "Rapport de soirée":
			rbtn = c
	_ok(rbtn != null, "bouton « Rapport de soirée » sur la soirée")
	rbtn.pressed.emit()
	await process_frame
	var rs = main.screens.rapport
	_ok(main.current == "rapport" and rs.rep.people.size() == 3, "rapport : 3 présents (%d)" % rs.rep.people.size())
	_ok(rs.rep.items.size() >= 5, "rapport : %d informations" % rs.rep.items.size())
	var first_text: String = rs.rep.items[0].text
	rs._move(0, 1)
	await process_frame
	_ok(rs.rep.items[1].text == first_text, "information descendue d'un cran")
	var srel_r := "Soirees/2026/2026-10-10 Valombre - Assemblée.md"
	_ok(_read(vault, srel_r).contains("rapport:"), "ordre écrit dans la soirée (propriété rapport)")
	var it0: Dictionary = rs.rep.items[0]
	rs._set_cred(it0, 4)
	await process_frame
	_ok(_read(vault, it0.path).contains("[credibilite:: 4] ") or _read(vault, it0.path).contains("[credibilite:: 4]"), "crédibilité écrite dans la note d'origine")
	rs._copy()
	_ok(rs._status.text.begins_with("Rapport copié"), "rapport copié")
	rs._toggle_form()
	rs._f_text.text = "Nouvelle information du rapport."
	rs._add_info()
	await process_frame
	_ok(_read(vault, srel_r).contains("- Nouvelle information du rapport. [nature:: observe] [credibilite:: 2]"), "information ajoutée à la soirée")
	main.show_screen("seance")
	await process_frame
	var se = main.screens.seance
	se.domaine = "Valombre"
	se.refresh()
	_ok(se.last.people.size() >= 2 and se._table.row_count() == se.last.people.size() and se._col.get_child_count() >= 4, "préparation de séance : %d personnes dans le tableau" % se._table.row_count())
	se._copy()
	_ok(se._info.text.begins_with("Fiche de séance copiée"), "fiche de séance copiée")

	# --- échanges avec Claude : export, puis import d'un petit lot
	main.show_screen("echanges")
	await process_frame
	var ex = main.screens.echanges
	ex.subject = "Victor Morel"
	ex._export()
	_ok(ex._export_info.text.begins_with("Copié"), "export préparé : " + ex._export_info.text.left(60))
	ex._save_export()
	_ok(ex._export_info.text.begins_with("Enregistré"), "export rangé dans _Export/")
	var lot := vault + "/_Import/2026-10-19 parcours"
	DirAccess.make_dir_recursive_absolute(lot + "/Personnages")
	var lf := FileAccess.open(lot + "/Personnages/Odile Ferrand.md", FileAccess.WRITE)
	lf.store_string("---\ntype: personnage\nid: per-0d11ef00\nschema: 1\n---\n# Odile Ferrand\n")
	lf.close()
	ex.on_show()
	await process_frame
	_ok(ex._lots_box.get_child_count() == 1, "lot listé")
	ex.open_lot("_Import/2026-10-19 parcours")
	_ok(ex._checks.size() == 1 and ex._checks.values()[0].button_pressed, "note du lot cochée d'office")
	ex._import()
	await _wait_jobs(app)
	_ok(FileAccess.file_exists(vault + "/Personnages/Odile Ferrand.md"), "note du lot intégrée au coffre")

	# --- brouillon
	main.open_note(srel)
	await process_frame
	note._body.text += "\nTexte non enregistré."
	note._mark_dirty()
	note.save_draft()
	_ok(not app.load_draft(srel).is_empty(), "brouillon conservé")
	main.open_note(srel)
	await process_frame
	_ok(note._col.get_child(0) is VBoxContainer, "brouillon proposé à la réouverture")
	app.clear_draft(srel)

	# --- alertes : une reconnaissance qui expire dans 10 jours
	var in10 := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + 10 * 86400).substr(0, 10)
	DirAccess.make_dir_recursive_absolute(vault + "/Sources/Notes")
	var af := FileAccess.open(vault + "/Sources/Notes/2026-10-20 Notes - Cour.md", FileAccess.WRITE)
	af.store_string("---\ntype: source\nid: src-0a1e0a1e\nschema: 1\nnature: note\nfiabilite: B\ndate: 2026-10-20\n---\n## Éléments\n- [[Armand Lescure]] reconnaît [[Élise Varga]] « Avisée » pour dix jours. [nature:: observe] [credibilite:: 2] [relation:: reconnait] [de:: [[Armand Lescure]]] [vers:: [[Élise Varga]]] [qualificatif:: Avisée] [jusqu_au:: %s] ^el-0a1e0a1e\n" % in10)
	af.close()
	app.start_sync()
	await _wait_jobs(app)
	main.show_screen("accueil")
	await process_frame
	var accueil_s = main.screens.accueil
	_ok(accueil_s._alert_card.visible and accueil_s._alert_label.text.begins_with("1 alerte"), "accueil : %s" % accueil_s._alert_label.text)
	main.show_screen("enquete")
	main.screens.enquete.show_tab("alertes")
	await process_frame
	var abox: Control = main.screens.enquete._list.get_child(0)
	var atext: String = abox.get_child(0).get_child(1).text
	_ok(atext.begins_with("Reconnaissance « Avisée » d'Élise Varga par Armand Lescure") and atext.contains("expire dans 10 jours"), "onglet Alertes : " + atext.replace("\n", " — "))

	# --- surveiller une personne
	var vrel := "Personnages/Victor Morel.md"
	main.open_note(vrel)
	await process_frame
	var wbtn: Button = null
	for c in note._col.get_children():
		if c is HFlowContainer:
			for b in c.get_children():
				if b is Button and b.text == "Surveiller":
					wbtn = b
	_ok(wbtn != null, "bouton « Surveiller » sur la fiche")
	wbtn.pressed.emit()
	await process_frame
	_ok(_read(vault, vrel).contains("  - surveille"), "étiquette « surveille » écrite dans la fiche")
	_ok(app.alerts().filter(func(a): return a.kind == "surveille").is_empty(), "les éléments déjà connus ne font pas d'alerte")
	app.append_element("Sources/Presse/2026-10-12 Gazette de Valombre - Nominations.md", "- [[Victor Morel]] a quitté la ville cette nuit. [nature:: rumeur] [credibilite:: 4] ^el-0b5e0b5e")
	var watch_alerts: Array = app.alerts().filter(func(a): return a.kind == "surveille")
	_ok(watch_alerts.size() == 1 and watch_alerts[0].title == "Victor Morel : 1 nouvel élément", "nouvel élément sur une personne surveillée : %s" % (watch_alerts[0].title if not watch_alerts.is_empty() else "aucune alerte"))
	main.open_note(vrel)
	await process_frame
	_ok(app.alerts().filter(func(a): return a.kind == "surveille").is_empty(), "ouvrir la fiche, c'est l'avoir vue")
	for c in note._col.get_children():
		if c is HFlowContainer:
			for b in c.get_children():
				if b is Button and b.text == "Ne plus surveiller":
					b.pressed.emit()
	await process_frame
	_ok(not _read(vault, vrel).contains("surveille"), "ne plus surveiller : étiquette retirée")

	# --- fiabilité calculée des informateurs
	var vf := FileAccess.open(vault + "/Sources/Notes/2026-10-19 Notes - Confidences de Victor.md", FileAccess.WRITE)
	vf.store_string("---\ntype: source\nid: src-0f1ab1e0\nschema: 1\nnature: conversation\nfiabilite: C\ndate: 2026-10-19\nauteur: \"[[Victor Morel]]\"\n---\n## Éléments\n- v1 [nature:: rapporte] [credibilite:: 1] ^el-0f1ab1e1\n- v2 [nature:: rapporte] [credibilite:: 1] ^el-0f1ab1e2\n- v3 [nature:: rapporte] [credibilite:: 1] ^el-0f1ab1e3\n- v4 [nature:: rapporte] [credibilite:: 1] ^el-0f1ab1e4\n- v5 [nature:: rapporte] [credibilite:: 5] ^el-0f1ab1e5\n")
	vf.close()
	app.start_sync()
	await _wait_jobs(app)
	main.show_screen("enquete")
	main.screens.enquete.show_tab("informateurs")
	await process_frame
	var icard: PanelContainer = main.screens.enquete._list.get_child(0)
	var irow: HBoxContainer = icard.get_child(0).get_child(1)
	var itext: String = irow.get_child(0).text
	_ok(itext.begins_with("Victor Morel — proposée B, actuelle ") and not itext.begins_with("Victor Morel — proposée B, actuelle B") and itext.contains("5 confirmées, 1 réfutée"), "onglet Informateurs, à revoir : " + itext)
	var itable = main.screens.enquete._list.get_child(1)
	_ok(itable.has_method("sort_by") and itable.row_count() >= 1, "onglet Informateurs : tableau de %d informateur(s)" % itable.row_count())
	irow.get_child(1).pressed.emit()
	await process_frame
	_ok(_read(vault, "Personnages/Victor Morel.md").contains("fiabilite: B"), "« Appliquer B » écrit la fiabilité dans la fiche")
	main.open_note("Personnages/Victor Morel.md")
	await process_frame
	var ibox: FoldableContainer = null
	for c in note._side_col.get_children():
		if c is FoldableContainer and str(c.title).begins_with("Fiabilité comme informateur"):
			ibox = c
	_ok(ibox != null and ibox.title == "Fiabilité comme informateur : B proposée (actuelle B)", "sur la fiche : %s" % (ibox.title if ibox != null else "absent"))

	# --- alibis
	app.append_element("Sources/Discord/2026-10-14 Discord Valombre - Salon de la Harpie.md",
		"- [[Armand Lescure]] a été vu à l'entrepôt des quais ce soir-là. [nature:: observe] [credibilite:: 2] [relation:: present_a] [de:: [[Armand Lescure]]] [vers:: [[Entrepôt des quais]]] [date_faits:: 2026-10-10] ^el-0a11b1a1")
	main.show_alibis("nuit", "2026-10-10")
	await process_frame
	var av: Control = main.screens.enquete._list.get_child(0)
	var acards := []
	var aconf := ""
	var stack := [av]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is PanelContainer:
			acards.append(nd)
			var l0: Node = nd.get_child(0).get_child(0)
			if l0 is Label and l0.text == "Vus à deux endroits cette nuit-là":
				aconf = nd.get_child(0).get_child(1).text
		stack.append_array(nd.get_children())
	_ok(acards.size() == 3, "telle nuit (10 octobre) : 2 lieux et un encadré des contradictions (%d cadres)" % acards.size())
	_ok(aconf.begins_with("Armand Lescure : Valombre - Assemblée (Élysée de Valombre, Valombre) — présent (constaté) ; Entrepôt des quais"), "vu à deux endroits : %s" % aconf)
	main.show_alibis("incidents", "Evenements/2026-09 Incendie de l'entrepôt des quais.md")
	await process_frame
	var enq_a = main.screens.enquete
	_ok(enq_a.tab == "alibis" and enq_a._alibi_state.sel.size() == 1, "fiche d'un événement → incidents en commun, l'incident coché")
	main.show_alibis("incidents", "Soirees/2026/2026-10-10 Valombre - Assemblée.md")
	await process_frame
	var grids := []
	stack = [enq_a._list]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is GridContainer:
			grids.append(nd)
		stack.append_array(nd.get_children())
	_ok(grids.size() == 1 and grids[0].columns == 3 and grids[0].get_child_count() == 15, "tableau 4 personnes × 2 incidents (%d cases)" % (grids[0].get_child_count() if not grids.is_empty() else 0))
	main.open_note("Personnages/Armand Lescure.md")
	await process_frame
	var pbox: FoldableContainer = null
	stack = [note._col]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is FoldableContainer and str(nd.title).begins_with("Où était-il ?"):
			pbox = nd
		stack.append_array(nd.get_children())
	_ok(pbox != null and pbox.title.contains("1 nuit à deux endroits"), "sur la fiche : %s" % (pbox.title if pbox != null else "absent"))
	main.open_note("Soirees/2026/2026-10-10 Valombre - Assemblée.md")
	await process_frame
	var nightb: Button = null
	stack = [note._side_col]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is Button and nd.text == "Qui était où cette nuit-là":
			nightb = nd
		stack.append_array(nd.get_children())
	_ok(nightb != null, "bouton « Qui était où cette nuit-là » sur la soirée")
	if nightb != null:
		nightb.pressed.emit()
		await process_frame
	_ok(main.current == "enquete" and enq_a._alibi_state.mode == "nuit" and enq_a._alibi_state.day == "2026-10-10", "→ Alibis, nuit du 10 octobre")
	main.show_alibis("personne", "Armand Lescure")
	await process_frame
	var ptl: Node = null
	stack = [enq_a._list]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd.has_method("add_entry"):
			ptl = nd
		stack.append_array(nd.get_children())
	_ok(ptl != null and ptl.get_child_count() == 2, "une personne : ligne de temps (%d entrées)" % (ptl.get_child_count() if ptl != null else 0))

	# --- enquête
	main.show_screen("enquete")
	var enq = main.screens.enquete
	# --- à trancher : Armand Lescure noté à deux endroits le 10 octobre (cf. alibis)
	enq.show_tab("trancher")
	await process_frame
	var contra: Array = app.contradictions()
	var armand: Array = contra.filter(func(c): return c.kind == "deux_endroits" and str(c.title).begins_with("Armand Lescure"))
	_ok(armand.size() == 1 and enq._list.get_child_count() >= 2, "à trancher : %d point(s), dont Armand Lescure à deux endroits" % contra.size())
	app.dismiss_contradiction(str(armand[0].key) if not armand.is_empty() else "")
	_ok(app.contradictions().size() == contra.size() - 1, "« Écarter » retire le point (sur cet ordinateur)")
	app.restore_contradictions()
	_ok(app.contradictions().size() == contra.size(), "« Tout réafficher »")
	# --- tableau des hypothèses concurrentes du dossier d'exemple
	main.show_hypotheses("Dossiers/Dossier - Allégeances de Victor Morel.md")
	await process_frame
	var hs = main.screens.hypotheses
	_ok(main.current == "hypotheses" and hs.table.hypotheses.size() == 1 and hs.table.rows.size() == 2 and hs._grid.get_child_count() == 6,
		"tableau des hypothèses : %d hypothèse(s), %d élément(s)" % [hs.table.hypotheses.size(), hs.table.rows.size()])
	var cell_of := func() -> Button:
		for c in hs._grid.get_children():
			if c is Button and not c.is_queued_for_deletion() and str(c.text) in ["✓ cohérent", "✗ incohérent", "·"]:
				return c
		return null
	var ind_rel := "Indices/Victor Morel membre du Cercle des Lanternes.md"
	var before_ind := _read(vault, ind_rel)
	(cell_of.call() as Button).pressed.emit()
	await process_frame
	_ok(str((cell_of.call() as Button).text) == "✗ incohérent" and _read(vault, ind_rel).contains("contre:\n  - "), "une case touchée devient « incohérent » et s'écrit dans l'indice")
	(cell_of.call() as Button).pressed.emit()
	await process_frame
	(cell_of.call() as Button).pressed.emit()
	await process_frame
	_ok(str((cell_of.call() as Button).text) == "✓ cohérent" and hs.table.hypotheses[0].n_pour == 2, "trois appuis : retour à « cohérent »")
	# --- statistiques : personnages (camembert, filtres) puis informations (Amirauté)
	main.show_stats("personnages")
	await process_frame
	var ss = main.screens.stats
	var n_people: int = ss._people.size()
	_ok(main.current == "stats" and n_people > 0 and ss._pie.total == n_people and ss._table.row_count() == n_people,
		"statistiques : %d personnage(s), %d part(s) par statut" % [n_people, ss._pie.slices.size()])
	ss._pie.select(0)
	await process_frame
	_ok(ss._table.row_count() == int(ss._pie.slices[0].value), "une part choisie détaille ses %d personnage(s)" % ss._table.row_count())
	ss._p_min_infos = 1
	ss._refresh_people_data()
	await process_frame
	var with_info: int = ss._p_filtered.size()
	_ok(with_info > 0 and with_info < n_people and ss._p_filtered.all(func(p): return int(p.infos) >= 1), "filtre « au moins une information » : %d" % with_info)
	ss._p_min_infos = 0
	ss._p_dim = "discipline"
	ss._hide_empty["p:discipline"] = false
	ss._refresh()
	await process_frame
	_ok(ss._pie.slices.size() >= 1 and ss._pie.total >= n_people, "répartition par discipline : %d part(s), chacun compté au moins une fois" % ss._pie.slices.size())
	ss._hide_empty["p:discipline"] = true
	ss._refresh()
	await process_frame
	_ok(ss._pie.slices.all(func(sl): return not sl.keys.has("")) and ss._table.row_count() < n_people, "« Masquer « Aucune connue » » : %d personnage(s) listé(s)" % ss._table.row_count())
	ss._p_dim = "statut"
	main.show_stats("informations")
	await process_frame
	_ok(ss._grid.get_child_count() == 64 and ss._table.row_count() == mini(1000, ss._infos.size()) and ss._pie.total == ss._infos.size(),
		"informations : %d élément(s), grille de l'Amirauté" % ss._infos.size())
	var cell_btn: Button = null
	for c in ss._grid.get_children():
		if c is Button and not c.disabled:
			cell_btn = c
			break
	var cell_n := int(cell_btn.text)
	cell_btn.pressed.emit()
	await process_frame
	_ok(ss._i_cell != "" and ss._table.row_count() == cell_n, "une case de la grille liste ses %d information(s) (%s)" % [cell_n, ss._i_cell])
	main.show_screen("enquete")
	await process_frame
	for t in ["trancher", "chrono", "alibis", "faveurs", "indices", "dossiers", "taches"]:
		enq.show_tab(t)
		await process_frame
		_ok(enq._list.get_child_count() > 0, "enquête, onglet %s : %d ligne(s)" % [t, enq._list.get_child_count()])
	enq.show_tab("chrono")
	await process_frame
	var tl = enq._list.get_child(0)
	_ok(tl.has_method("add_entry") and tl.get_child_count() >= 5, "chronologie en ligne verticale : %d entrées" % tl.get_child_count())
	var row0: Control = tl.get_child(0)
	var cell = row0.get_child(0)
	var btn0: Button = row0.get_child(1).get_child(0)
	_ok(cell.date_text != "" and not btn0.text.contains(cell.date_text) and not btn0.text.begins_with("2026"), "pas de date écrite dans l'entrée : « %s »" % btn0.text.left(40))
	btn0.mouse_entered.emit()
	_ok(cell.hover, "la date s'affiche au survol : %s" % cell.date_text)
	btn0.mouse_exited.emit()
	enq.show_tab("taches")
	await process_frame
	var tasks: Array = app.index.open_tasks()
	var tk: Dictionary = tasks[0]
	enq._toggle_task(tk, true)
	await process_frame
	_ok(_read(vault, tk.path).contains("- [x]"), "tâche cochée depuis l'enquête")

	# --- identifiants manquants, puis fusion d'un inconnu identifié
	var nid_rel := "Sources/Notes/2026-10-21 Notes - Sans identifiant.md"
	DirAccess.make_dir_recursive_absolute(vault + "/Sources/Notes")
	var nf := FileAccess.open(vault + "/" + nid_rel, FileAccess.WRITE)
	nf.store_string("---\ntype: source\nid: src-0abc0def\nschema: 1\nnature: note\nfiabilite: B\ndate: 2026-10-21\n---\n## Éléments\n- Sans identifiant. [nature:: observe] [credibilite:: 2]\n")
	nf.close()
	app.start_sync()
	await _wait_jobs(app)
	main.open_note(nid_rel)
	await process_frame
	note._assign_ids()
	_ok(RegEx.create_from_string("Sans identifiant\\. \\[nature:: observe\\] \\[credibilite:: 2\\] \\^el-[a-z0-9]{8}").search(_read(vault, nid_rel)) != null, "identifiant attribué depuis la note")
	main.open_note("Personnages/Inconnu - Manteau gris.md")
	await process_frame
	var fz = preload("res://ui/widgets/fusion_dialog.gd").open_in(main, app, "Inconnu - Manteau gris", "Victor Morel", func(k): main.open_note(k))
	_ok(not fz._go.disabled and fz.plan.writes.size() == 4, "aperçu de la fusion : %d note(s) à écrire" % fz.plan.writes.size())
	fz._apply()
	await process_frame
	_ok(_read(vault, "Personnages/Victor Morel.md").contains("Inconnu - Manteau gris") and main.current == "note", "fusion faite, fiche gardée ouverte")
	_ok(_read(vault, "Personnages/Inconnu - Manteau gris.md").begins_with("---\nfusionnee_dans:"), "ancienne fiche devenue un renvoi")

	# --- corbeille : suppression depuis la note, restauration depuis les Réglages
	main.open_note(nid_rel)
	await process_frame
	note._ask_delete()
	_ok(note._confirm.visible and note._confirm.ok_button_text == "Mettre à la corbeille", "confirmation de suppression affichée")
	note._confirm.hide()
	note._on_confirmed()
	await process_frame
	_ok(not FileAccess.file_exists(vault + "/" + nid_rel) and FileAccess.file_exists(vault + "/.trash/" + nid_rel), "note déplacée dans .trash/")
	_ok(main.current != "note" and app.index.path_of_name(nid_rel.get_file().get_basename()) == "", "note fermée et sortie de l'index")
	main.show_screen("coffre")
	await process_frame
	var cs = main.screens.coffre
	_ok(cs._trash_head.text == "Corbeille (1)", "Réglages : %s" % cs._trash_head.text)
	cs._restore(".trash/" + nid_rel)
	await process_frame
	_ok(FileAccess.file_exists(vault + "/" + nid_rel) and app.index.path_of_name(nid_rel.get_file().get_basename()) == nid_rel, "note restaurée à sa place")
	_ok(cs._trash_head.text == "Corbeille (0)", "corbeille vide")

	# --- diagnostic, vérification, reconstruction
	main.show_screen("diag")
	app.start_verify()
	await _wait_jobs(app)
	await process_frame
	_ok(main.screens.diag._report.text.contains("identique à l'index : OUI"), "vérification : reconstruction identique")
	app.start_rebuild()
	await _wait_jobs(app)
	_ok(app.index != null and app.index.stats().files == 29, "reconstruction : 29 notes (%d)" % app.index.stats().files)
	# --- plein écran : réglage mémorisé, F11 bascule
	var was: bool = main.is_fullscreen()
	main.toggle_fullscreen()
	_ok(main.is_fullscreen() != was, "F11 : bascule plein écran / fenêtre mémorisée")
	main.toggle_fullscreen()
	# --- menus escamotables
	var nav = main._nav_slide
	nav.set_open(false, false)
	await process_frame
	_ok(nav.custom_minimum_size.x < 30.0 and not nav._inner.visible, "menu de gauche caché : seule la flèche reste")
	_ok(app.settings.get_value("panneaux", "nav", true) == false, "état du menu retenu")
	nav._handle.pressed.emit()
	for i in 30:
		await process_frame
	_ok(nav.is_open() and nav.custom_minimum_size.x > 150.0, "la flèche fait revenir le menu (%d px)" % nav.custom_minimum_size.x)
	print("== %s ==" % ("PARCOURS RÉUSSI" if failures == 0 else "%d ÉCHEC(S)" % failures))
	main.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
