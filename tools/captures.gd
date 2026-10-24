extends SceneTree
## Captures d'écran de l'interface (outil de développement, nécessite un affichage) :
##   godot --path . --script res://tools/captures.gd -- <dossier> [largeur] [hauteur]

var out := ""


func _init() -> void:
	_run.call_deferred()


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("capture ", name)


func _scroll_of(c: Node) -> ScrollContainer:
	var p := c.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	return p


func _copy(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	d.include_hidden = true
	for f in d.get_files():
		if f != ".gdignore":
			var o := FileAccess.open(dst + "/" + f, FileAccess.WRITE)
			o.store_buffer(FileAccess.get_file_as_bytes(src + "/" + f))
			o.close()
	for s in d.get_directories():
		_copy(src + "/" + s, dst + "/" + s)


func _rm(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(p + "/" + f)
	for s in d.get_directories():
		_rm(p + "/" + s)
	DirAccess.remove_absolute(p)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	OS.low_processor_usage_mode = false  # sinon pas de nouvelle image tant que rien ne change
	var w := int(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 1920
	var h := int(OS.get_cmdline_user_args()[2]) if OS.get_cmdline_user_args().size() > 2 else 1080
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	var vault := OS.get_user_data_dir() + "/tests_tmp/coffre-captures"
	_rm(vault)  # coffre de capture repris à neuf à chaque fois
	_copy(ProjectSettings.globalize_path("res://tests/fixtures/coffre-exemple"), vault)
	# de quoi montrer des alertes : une reconnaissance qui expire bientôt, une Chasse au Sang
	var in10 := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + 10 * 86400).substr(0, 10)
	var past5 := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 5 * 86400).substr(0, 10)
	DirAccess.make_dir_recursive_absolute(vault + "/Sources/Notes")
	var af := FileAccess.open(vault + "/Sources/Notes/2026-10-20 Notes - Cour.md", FileAccess.WRITE)
	af.store_string("---\ntype: source\nid: src-0a1e0a1e\nschema: 1\nnature: note\nfiabilite: B\ndate: 2026-10-20\n---\n## Éléments\n- [[Armand Lescure]] reconnaît [[Élise Varga]] « Avisée » pour dix jours. [nature:: observe] [credibilite:: 2] [relation:: reconnait] [de:: [[Armand Lescure]]] [vers:: [[Élise Varga]]] [qualificatif:: Avisée] [jusqu_au:: %s] ^el-0a1e0a1e\n- [[Armand Lescure]] tance [[Victor Morel]] « Bavard ». [nature:: observe] [credibilite:: 2] [relation:: sobriquet] [de:: [[Armand Lescure]]] [vers:: [[Victor Morel]]] [qualificatif:: Bavard] [jusqu_au:: %s] ^el-0a1e0a1f\n" % [in10, past5])
	af.close()
	var vf := FileAccess.open(vault + "/Sources/Notes/2026-10-19 Notes - Confidences de Victor.md", FileAccess.WRITE)
	vf.store_string("---\ntype: source\nid: src-0f1ab1e0\nschema: 1\nnature: conversation\nfiabilite: C\ndate: 2026-10-19\nauteur: \"[[Victor Morel]]\"\n---\n## Éléments\n- [[Victor Morel]] dit que le Prince recevra à l'Élysée samedi. [nature:: rapporte] [credibilite:: 1] ^el-0f1ab1e1\n- Il dit qu'[[Élise Varga]] a payé sa dette. [nature:: rapporte] [credibilite:: 1] ^el-0f1ab1e2\n- Il dit que l'entrepôt des quais appartient au [[Cercle des Lanternes]]. [nature:: rapporte] [credibilite:: 1] ^el-0f1ab1e3\n- Il dit qu'[[Armand Lescure]] tiendra le registre ce mois-ci. [nature:: rapporte] [credibilite:: 1] ^el-0f1ab1e4\n- Il jure n'avoir jamais rencontré l'inconnu au manteau gris. [nature:: rapporte] [credibilite:: 5] ^el-0f1ab1e5\n")
	vf.close()
	var cf := FileAccess.open(vault + "/Personnages/Corvin Malet.md", FileAccess.WRITE)
	cf.store_string("---\ntype: personnage\nid: per-0c0b0a1e\nschema: 1\ndomaine: \"[[Valombre]]\"\nsanctions:\n  - chasse_au_sang\n---\n# Corvin Malet\n")
	cf.close()
	# de quoi montrer les alibis : une agression aux quais la nuit de l'assemblée, des témoins
	DirAccess.make_dir_recursive_absolute(vault + "/Evenements")
	var ef := FileAccess.open(vault + "/Evenements/2026-10-10 Agression sur les quais.md", FileAccess.WRITE)
	ef.store_string("---\ntype: evenement\nid: evt-0a11b1e0\nschema: 1\ndescription: Un goule du Prince agressé près de l'entrepôt\ndate_floue: \"2026-10-10\"\nstatut: corrobore\ncredibilite: 2\ndomaine: \"[[Valombre]]\"\nlieu: \"[[Entrepôt des quais]]\"\nparticipants:\n  - \"[[Corvin Malet]]\"\n---\n# Agression sur les quais\n")
	ef.close()
	var tf := FileAccess.open(vault + "/Sources/Notes/2026-10-11 Notes - Témoins des quais.md", FileAccess.WRITE)
	tf.store_string("---\ntype: source\nid: src-0a11b1e1\nschema: 1\nnature: note\nfiabilite: B\ndate: 2026-10-11\n---\n## Éléments\n" +
		"- [[Armand Lescure]] a été vu sur les quais pendant l'assemblée. [nature:: rapporte] [credibilite:: 2] [relation:: present_a] [de:: [[Armand Lescure]]] [vers:: [[Entrepôt des quais]]] [date_faits:: 2026-10-10] ^el-0a11b1e2\n" +
		"- Un homme en manteau gris rôdait au moment de l'agression. [nature:: rapporte] [credibilite:: 3] [relation:: present_a] [de:: [[Inconnu - Manteau gris]]] [vers:: [[2026-10-10 Agression sur les quais]]] ^el-0a11b1e3\n" +
		"- Le même manteau gris aurait été vu à l'entrepôt en septembre. [nature:: rumeur] [credibilite:: 4] [relation:: present_a] [de:: [[Inconnu - Manteau gris]]] [vers:: [[Entrepôt des quais]]] [date_faits:: 2026-09] ^el-0a11b1e4\n" +
		"- [[Victor Morel]] fréquentait l'entrepôt en septembre. [nature:: rumeur] [credibilite:: 4] [relation:: present_a] [de:: [[Victor Morel]]] [vers:: [[Entrepôt des quais]]] [date_faits:: 2026-09] ^el-0a11b1e5\n")
	tf.close()
	var lot_src := OS.get_environment("NOSF_LOT")  # facultatif : un lot réel à montrer dans _Import/
	if lot_src != "":
		_copy(lot_src, vault + "/_Import/" + lot_src.get_file())
	load("res://core/app/app_service.gd").settings_file = "user://tests_tmp/reglages-captures.cfg"
	var main: Control = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var app: Node = main.app
	app.set_repo_path(vault)
	var db: String = app.db_path()  # index de capture repris à neuf, lui aussi
	app.index.close()
	load("res://core/index/index_store.gd").delete_files(db)
	app._open_read_index()
	app.start_rebuild()
	print("rebuild lancé")
	for i in 300:
		await process_frame
		if i % 20 == 0:
			print("frame ", i, " busy ", app.busy())
		if not app.busy():
			break
	print("rebuild fini")
	app.start_sync()  # dernier message d'état : celui d'un coffre à jour
	for i in 300:
		await process_frame
		if not app.busy():
			break
	main.show_screen("accueil")
	if app.index.quick_notes_todo_count() == 0:
		var q: Dictionary = app.create_quick_note()
		var rd: Dictionary = app.read_note(q.rel)
		rd.doc.set_body("Croisé Victor avec une inconnue aux cheveux rouges, quai nord.\nElle portait la broche des Lanternes.\n")
		app.save_note(q.rel, rd.doc, rd.hash)
	main.show_screen("accueil")
	await _snap("01-accueil")
	main.new_note()
	await _snap("02-types")
	main.new_note("soiree", {"domaine": "[[Valombre]]"})
	await _snap("03-formulaire-soiree")
	_scroll_of(main.screens.nouvelle._col).scroll_vertical = 600
	await _snap("03b-formulaire-soiree-bas")
	main.new_note("source")
	await _snap("04-formulaire-source")
	main.open_note("Soirees/2026/2026-10-10 Valombre - Assemblée.md")
	await _snap("05-note-soiree")
	_scroll_of(main.screens.note._col).scroll_vertical = 700
	await _snap("05b-note-soiree-presents")
	var quick: Array = app.index.quick_notes_todo()
	if not quick.is_empty():
		main.open_note(quick[0].path)
		await _snap("06-note-rapide")
	main.open_note("Personnages/Victor Morel.md")
	await _snap("07-fiche-victor")
	_scroll_of(main.screens.note._side_col).scroll_vertical = 1400
	await _snap("07b-fiche-victor-renseignements")
	main.screens.note._typed.clan._pick_one()
	await _snap("08-selecteur")
	main._close_all_overlays()
	main.show_screen("enquete")
	main.screens.enquete.show_tab("chrono")
	await process_frame
	var tl0 = main.screens.enquete._list.get_child(0)
	if tl0 != null and tl0.get_child_count() > 2:
		tl0.get_child(2).get_child(0).set_hover(true)
	await _snap("09-chronologie")
	main.screens.enquete.show_tab("faveurs")
	await _snap("10-faveurs")
	main.screens.enquete.show_tab("taches")
	await _snap("11-a-faire")
	main.show_graph("Victor Morel")
	for i in 60:
		await process_frame
	main.screens.graphe._view._tap("cercle des lanternes")
	await _snap("13-graphe")
	# 0.7 : vue d'ensemble dézoomée, chemin entre deux fiches, rapport de soirée
	main.show_graph("")
	for i in 60:
		await process_frame
	main.screens.graphe._view.show_all()
	await _snap("13b-graphe-voir-tout")
	main.show_paths("Armand Lescure", "Cercle des Lanternes")
	main.screens.graphe.path_opts.copresence = true
	main.screens.graphe.refresh()
	for i in 60:
		await process_frame
	await _snap("13c-chemin")
	main.screens.graphe._info_list.get_parent().scroll_vertical = 0
	main.screens.graphe.path_opts.copresence = false
	main.show_report("Soirees/2026/2026-10-10 Valombre - Assemblée.md")
	await _snap("18-rapport-soiree")
	_scroll_of(main.screens.rapport._col2).scroll_vertical = 400
	await _snap("18b-rapport-informations")
	main.new_note("source")
	await process_frame
	main.screens.nouvelle.editors.nature._option.show_popup()
	await _snap("19-nature-source-A-F")
	main._close_all_overlays()
	main.screens.nouvelle.editors.nature._option.get_popup().hide()
	main.open_note("Personnages/Inconnu - Manteau gris.md")
	await process_frame
	preload("res://ui/widgets/fusion_dialog.gd").open_in(main, app, "Inconnu - Manteau gris", "Victor Morel")
	await _snap("20-fusion-apercu")
	main._close_all_overlays()
	main.show_screen("seance")
	main.screens.seance.domaine = "Valombre"
	main.screens.seance.refresh()
	await _snap("14-seance")
	main.show_screen("echanges")
	await _snap("15-echanges")
	if lot_src != "":
		main.screens.echanges.open_lot("_Import/" + lot_src.get_file())
		await _snap("16-lot")
		var ex: Dictionary = app.analyse_lot("_Import/" + lot_src.get_file())
		var ok_items: Array = (ex.items as Array).filter(func(x): return x.level == "ok")
		app.import_lot("_Import/" + lot_src.get_file(), ok_items)
		app.start_sync()
		for i in 300:
			await process_frame
			if not app.busy():
				break
		for n in ["Dissimulation", "Prévôt", "Nosferatu"]:
			main.open_note(app.index.path_of_name(n))
			for i in 10:
				await process_frame
			await _snap("17-fiche-" + n.to_lower().replace("é", "e"))
	main.open_note("Personnages/Victor Morel.md")
	await process_frame
	main.screens.note._toggle_watch()
	await process_frame
	for c in main.screens.note._side_col.get_children():
		if c is FoldableContainer and str(c.title).begins_with("Fiabilité comme informateur"):
			c.folded = false
	await _snap("24-fiche-surveillee")
	app.append_element("Sources/Presse/2026-10-12 Gazette de Valombre - Nominations.md", "- [[Victor Morel]] a quitté la ville cette nuit. [nature:: rumeur] [credibilite:: 4] ^el-0b5e0b5e")
	main.show_screen("accueil")
	await _snap("22-alertes-accueil")
	main.show_screen("enquete")
	main.screens.enquete.show_tab("informateurs")
	await _snap("25-informateurs")
	main.show_alibis("nuit", "2026-10-10")
	await _snap("26-alibis-nuit")
	for rel in ["Evenements/2026-09 Incendie de l'entrepôt des quais.md", "Evenements/2026-10-10 Agression sur les quais.md",
			"Soirees/2026/2026-10-10 Valombre - Assemblée.md"]:
		main.show_alibis("incidents", rel)
	await _snap("27-alibis-incidents")
	main.show_alibis("personne", "Armand Lescure")
	await _snap("28-alibis-personne")
	main.open_note("Personnages/Armand Lescure.md")
	await process_frame
	var stack: Array = [main.screens.note._side_col]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is FoldableContainer:
			nd.folded = not str(nd.title).begins_with("Où était-il ?")
		stack.append_array(nd.get_children())
	await _snap("29-fiche-presences")
	main.show_screen("enquete")
	main.screens.enquete.show_tab("alertes")
	await _snap("23-alertes-enquete")
	main.show_screen("coffre")
	await _snap("12-reglages")
	main._nav_slide.set_open(false, false)
	main.show_graph("Victor Morel")
	for i in 40:
		await process_frame
	main.screens.graphe._view.show_all()
	await _snap("21-menu-cache")
	main._nav_slide.set_open(true, false)
	main.queue_free()
	await process_frame
	quit()
