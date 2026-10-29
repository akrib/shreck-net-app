extends "res://tests/base.gd"
## Réparations proposées par « À trancher » (0.20) : lignées notées comme clans,
## noms de fichiers mal encodés, clan qui n'est pas un clan ; doublons
## d'orthographe ; nature d'un groupe créé à la volée d'après son nom.

const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Contra := preload("res://core/analysis/contradictions.gd")
const Mojibake := preload("res://core/format/mojibake.gd")
const Schema := preload("res://core/model/schema.gd")
const Lineage := preload("res://core/analysis/lineage.gd")


func test_mojibake() -> void:
	eq(Mojibake.fix("Karl Kr├Âner"), "Karl Kröner", "ö (OEM 850)")
	eq(Mojibake.fix("Joséphine Du Fr├¬ne"), "Joséphine Du Frêne", "ê, sans toucher au é déjà juste")
	eq(Mojibake.fix("J├ñger Walldhart"), "Jäger Walldhart", "ä")
	eq(Mojibake.fix("Aleksandra Brz─Öczyszczykiewicz"), "Aleksandra Brzęczyszczykiewicz", "ę (lettre hors Latin-1)")
	eq(Mojibake.fix("2025-03-15 Avaline Vasilkovaskaïa envers Ambroisie Cou├½dic (majeure 1)"),
		"2025-03-15 Avaline Vasilkovaskaïa envers Ambroisie Couëdic (majeure 1)", "nom de faveur")
	ok(not Mojibake.suspect("Élise Varga — « l'Ajustée »") and Mojibake.fix("Élise Varga") == "Élise Varga", "accents ordinaires : rien à réparer")
	ok(Mojibake.suspect("⚜ ─── ⚜") and Mojibake.fix("⚜ ─── ⚜") == "⚜ ─── ⚜", "un trait de séparation n'est pas une lettre abîmée")


func test_nature_par_le_nom() -> void:
	eq(Schema.group_nature_from_name("Lignée de Rogue"), "lignee", "Lignée de…")
	eq(Schema.group_nature_from_name("Lignée d'Istvan"), "lignee", "Lignée d'…")
	eq(Schema.group_nature_from_name("lignée du Joueur d’Echecs"), "lignee", "lignée du…, apostrophe typographique")
	eq(Schema.group_nature_from_name("Faction Politique"), "faction", "Faction…")
	eq(Schema.group_nature_from_name("Coterie des Pèlerins"), "coterie", "Coterie…")
	eq(Schema.group_nature_from_name("Toreador"), "", "un clan : le nom ne dit rien")
	eq(Schema.group_nature_from_name("Lignées perdues"), "", "« Lignées » n'est pas « Lignée de »")


func _app(root: String) -> Node:
	var AppService = load("res://core/app/app_service.gd")
	AppService.settings_file = "user://tests_tmp/reglages-reparations.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	var app: Node = AppService.new()
	app.background_jobs = false
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	IndexStore.delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()
	return app


func test_creation_a_la_volee() -> void:
	var root := temp_dir("coffre-nature-volee")
	write_file(root + "/Groupes/Nosferatu.md", "---\ntype: groupe\nid: grp-7d000001\nschema: 1\nnature: clan\n---\n")
	var app := _app(root)
	var a: Dictionary = app.create_stub("groupe", "Lignée de Ferrand")
	ok(a.ok and FileAccess.get_file_as_string(root + "/" + str(a.rel)).contains("nature: lignee"), "« Lignée de Ferrand » sans nature : créée en lignée (et non en clan)")
	var b: Dictionary = app.create_stub("groupe", "Lignée de Carnage", "clan")
	ok(b.ok and FileAccess.get_file_as_string(root + "/" + str(b.rel)).contains("nature: lignee"), "même proposée « clan » par le champ Clan : lignée")
	var c: Dictionary = app.create_stub("groupe", "Faction Bestiale")
	ok(c.ok and FileAccess.get_file_as_string(root + "/" + str(c.rel)).contains("nature: faction"), "« Faction … » : faction")
	var d: Dictionary = app.create_stub("groupe", "Brujah antitribu")
	ok(d.ok and FileAccess.get_file_as_string(root + "/" + str(d.rel)).contains("nature: clan"), "un nom qui ne dit rien garde la valeur par défaut")
	var e: Dictionary = app.create_note("groupe", {"nom": "Lignée de Senecq", "nature": "coterie"})
	ok(e.ok and FileAccess.get_file_as_string(root + "/" + str(e.rel)).contains("nature: coterie"), "une nature choisie (autre que la valeur par défaut) est respectée")
	app.index.close()
	app.free()


func _vault() -> String:
	var root := temp_dir("coffre-reparations")
	write_file(root + "/Groupes/Nosferatu.md", "---\ntype: groupe\nid: grp-7e000001\nschema: 1\nnature: clan\n---\n")
	write_file(root + "/Groupes/Lignée de Stanislas.md", "---\ntype: groupe\nid: grp-7e000002\nschema: 1\nnature: clan\nclan: \"[[Nosferatu]]\"\n---\n# Lignée de Stanislas\n")
	write_file(root + "/Groupes/Lignée de Rogue.md", "---\ntype: groupe\nid: grp-7e000003\nschema: 1\nnature: lignee\nclan: \"[[Nosferatu]]\"\n---\n")
	write_file(root + "/Groupes/Faction Humaniste.md", "---\ntype: groupe\nid: grp-7e000004\nschema: 1\nnature: faction\n---\n")
	write_file(root + "/Personnages/Rogue.md", "---\ntype: personnage\nid: per-7e000005\nschema: 1\nclan: \"[[Nosferatu]]\"\n---\n")
	write_file(root + "/Personnages/Le Blanc.md", "---\ntype: personnage\nid: per-7e000006\nschema: 1\nclan: \"[[Nosferatu]]\"\n---\n")
	write_file(root + "/Personnages/Danielle.md", "---\ntype: personnage\nid: per-7e000007\nschema: 1\nclan: \"[[Faction Humaniste]]\"\n---\n")
	write_file(root + "/Personnages/Karl Kr├Âner.md", "---\ntype: personnage\nid: per-7e000008\nschema: 1\n---\n")
	write_file(root + "/Personnages/Louis-Joseph de Calonne.md", "---\ntype: personnage\nid: per-7e000009\nschema: 1\n---\n")
	write_file(root + "/Personnages/Louis Joseph de Calonne.md", "---\ntype: personnage\nid: per-7e00000a\nschema: 1\n---\n")
	write_file(root + "/Personnages/Marc (Lyon).md", "---\ntype: personnage\nid: per-7e00000b\nschema: 1\n---\n")
	write_file(root + "/Personnages/Marc (Lille).md", "---\ntype: personnage\nid: per-7e00000c\nschema: 1\n---\n")
	write_file(root + "/Sources/Notes/2026-10-28 Notes.md", "---\ntype: source\nid: src-7e00000d\nschema: 1\nnature: note\nfiabilite: B\n---\n## Éléments\n"
		+ "- [[Le Blanc]] est membre de [[Lignée de Stanislas]]. [nature:: rapporte] [credibilite:: 3] [relation:: membre_de] [de:: [[Le Blanc]]] [vers:: [[Lignée de Stanislas]]] ^el-7e00000e\n"
		+ "- [[Le Blanc]] est membre de [[Lignée de Rogue]]. [nature:: rapporte] [credibilite:: 3] [relation:: membre_de] [de:: [[Le Blanc]]] [vers:: [[Lignée de Rogue]]] ^el-7e00000f\n"
		+ "- [[Karl Kröner]] vend des secrets. [nature:: rumeur] [credibilite:: 4] ^el-7e00000g\n")
	return root


func test_a_reparer() -> void:
	var root := _vault()
	var app := _app(root)
	var all: Array = Contra.build(app.index)
	var rep: Array = all.filter(func(c): return c.kind == "reparer")
	var nat: Array = rep.filter(func(c): return c.has("fix") and c.fix.action == "nature")
	ok(nat.size() == 1 and nat[0].fix.value == "lignee" and nat[0].fix.paths == ["Groupes/Lignée de Stanislas.md"],
		"« Lignée de Stanislas » notée clan : à passer en lignée (Lignée de Rogue, déjà lignée, n'y est pas)")
	ok(nat[0].detail[0].contains("Lignée de Stanislas (clan)"), "le détail dit la nature actuelle")
	var ren: Array = rep.filter(func(c): return c.has("fix") and c.fix.action == "rename")
	ok(ren.size() == 1 and ren[0].fix.pairs == [["Personnages/Karl Kr├Âner.md", "Personnages/Karl Kröner.md"]], "nom mal encodé : renommage proposé")
	var cl: Array = rep.filter(func(c): return str(c.title).begins_with("Danielle"))
	ok(cl.size() == 1 and str(cl[0].title).contains("faction") and not cl[0].has("fix"), "clan qui est une faction : signalé, sans réparation automatique")
	var ids: Array = all.filter(func(c): return c.kind == "identite")
	ok(ids.size() == 1 and ids[0].who.has("Louis-Joseph de Calonne") and ids[0].who.has("Louis Joseph de Calonne"),
		"doublon d'orthographe (tiret) proposé à la fusion ; pas les homonymes « Marc (Ville) »")
	ok(all[0].kind == "reparer", "« À réparer » vient en tête")
	# Le Blanc : la lignée de Stanislas est ignorée tant qu'elle est notée clan
	ok(not Lineage.lignees(app.index).has("lig:" + "lignée de stanislas"), "avant : la lignée notée clan n'est pas une lignée")
	# réparations
	var r1: Dictionary = app.repair_group_natures(nat[0].fix.paths, "lignee")
	ok(r1.done.size() == 1 and FileAccess.get_file_as_string(root + "/Groupes/Lignée de Stanislas.md").contains("nature: lignee"), "nature réparée")
	ok(FileAccess.get_file_as_string(root + "/Groupes/Lignée de Stanislas.md").contains("# Lignée de Stanislas"), "le reste de la note est intact")
	ok(Lineage.lignees(app.index).size() == 2, "après : les deux lignées comptent")
	var r2: Dictionary = app.repair_file_names(ren[0].fix.pairs)
	ok(r2.done.size() == 1 and FileAccess.file_exists(root + "/Personnages/Karl Kröner.md") and not FileAccess.file_exists(root + "/Personnages/Karl Kr├Âner.md"), "fichier renommé")
	eq(app.index.path_of_name("Karl Kröner"), "Personnages/Karl Kröner.md", "l'index suit : le lien [[Karl Kröner]] trouve sa note")
	var after: Array = Contra.build(app.index).filter(func(c): return c.kind == "reparer")
	ok(after.size() == 1 and str(after[0].title).begins_with("Danielle"), "il ne reste que le clan de Danielle")
	# un nom déjà pris n'est jamais écrasé
	write_file(root + "/Personnages/Ab├¬l.md", "---\ntype: personnage\nid: per-7e00000h\nschema: 1\n---\n")
	write_file(root + "/Personnages/Abêl.md", "---\ntype: personnage\nid: per-7e00000j\nschema: 1\n---\n")
	Scanner.new(app.repo, app.index).scan()
	var r3: Dictionary = app.repair_file_names([["Personnages/Ab├¬l.md", "Personnages/Abêl.md"]])
	ok(r3.done.is_empty() and r3.failed.size() == 1 and FileAccess.file_exists(root + "/Personnages/Ab├¬l.md"), "nom réparé déjà pris : refusé, rien n'est écrasé")
	app.index.close()
	app.free()
