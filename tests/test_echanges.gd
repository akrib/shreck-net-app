extends "res://tests/base.gd"
## Export pour Claude et import des lots (_Import/), sur une copie du coffre d'exemple.

const AppService := preload("res://core/app/app_service.gd")
const Scanner := preload("res://core/sync/scanner.gd")

var app: Node
var root := ""


func _prepare() -> void:
	AppService.settings_file = "user://tests_tmp/reglages-echanges.cfg"
	root = temp_dir("coffre-echanges")
	copy_tree(example_vault(), root)
	app = AppService.new()
	app.background_jobs = false
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	preload("res://core/index/index_store.gd").delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()


func _done() -> void:
	app.index.close()
	app.free()


func test_export() -> void:
	_prepare()
	var r: Dictionary = app.export_preview("fiche", "Victor Morel", "Victor Morel")
	ok(r.paths[0] == "Personnages/Victor Morel.md", "la fiche d'abord")
	ok(r.paths.has("Groupes/Toreador.md") and r.paths.has("Soirees/2026/2026-10-10 Valombre - Assemblée.md"), "liens sortants et rétroliens : %s" % str(r.paths))
	ok(r.text.contains("- Victor Morel · personnage · per-12m0sc1s"), "annuaire avec les identifiants")
	ok(r.text.contains("### Personnages/Victor Morel.md\n```markdown\n---\ntype: personnage"), "contenu intégral des notes")
	ok(r.text.contains("N'invente aucune information de jeu"), "consignes de prudence")
	var d: Dictionary = app.export_preview("domaine", "Valombre", "Valombre")
	ok(d.paths.has("Soirees/2026/2026-10-10 Valombre - Assemblée.md"), "export d'un domaine")
	eq(app.export_preview("rapides", "", "notes rapides").notes, 0, "aucune note rapide à exporter")
	var files_before: int = app.index.stats().files
	var s: Dictionary = app.export_save(r.text, "Victor Morel")
	ok(s.ok and s.rel.begins_with("_Export/") and s.rel.ends_with(".txt"), "export rangé dans _Export/ : " + str(s.rel))
	Scanner.new(app.repo, app.index).scan()
	eq(app.index.stats().files, files_before, "l'export n'est pas indexé")
	eq(app.index.rows("SELECT path FROM attachments WHERE path LIKE '_Export/%'").size(), 0, "… ni compté comme pièce jointe")
	_done()


func test_import_lot() -> void:
	_prepare()
	var lot := "_Import/2026-10-19 essai"
	write_file(root + "/" + lot + "/_lot.md", "# Lot 2026-10-19 essai\n\n## Modifications proposées sur des notes existantes\n- Victor Morel : ajouter l'alias « le Notaire ».\n")
	write_file(root + "/" + lot + "/Personnages/Bastien Roux.md", "---\ntype: personnage\nid: per-b4st13nr\nschema: 1\nclan: \"[[Toreador]]\"\n---\n# Bastien Roux\n\nVu avec [[Victor Morel]] et [[Inconnue jamais vue]].\n")
	write_file(root + "/" + lot + "/Personnages/Victor Morel.md", "---\ntype: personnage\nid: per-00000000\nschema: 1\n---\n# Doublon\n")
	write_file(root + "/" + lot + "/Indices/Bastien Roux est Toreador.md", "---\ntype: indice\nid: ind-b4st13nr\nschema: 1\nstatut: non_verifie\ncredibilite: 3\n---\n# Bastien Roux est Toreador\n")
	write_file(root + "/" + lot + "/Personnages/Sans identifiant.md", "---\ntype: personnage\nschema: 1\n---\n# Sans identifiant\n")
	write_file(root + "/" + lot + "/Pieces/2026-10-19 brut.txt", "texte brut\n")
	write_file(root + "/" + lot + "/Groupes/Toréador.md", "---\ntype: groupe\nid: grp-t0r3ad0r\nschema: 1\naliases:\n  - Toreador\nnature: clan\n---\n# Toréador\n")
	var lots: Array = app.list_lots()
	ok(lots.size() == 1 and lots[0].notes == 5 and lots[0].report, "lot listé : %s" % str(lots))
	var a: Dictionary = app.analyse_lot(lot)
	var by := {}
	for it in a.items:
		by[it.target_rel] = it
	eq(by["Personnages/Bastien Roux.md"].level, "avert", "note neuve : prête, avec un lien vers une fiche absente")
	ok(str(by["Personnages/Bastien Roux.md"].messages).contains("Inconnue jamais vue"), "le lien absent est nommé")
	eq(by["Personnages/Victor Morel.md"].level, "erreur", "nom déjà pris : refusée")
	eq(by["Indices/Bastien Roux est Toreador.md"].level, "erreur", "indice sans élément « pour » : refusé")
	eq(by["Personnages/Sans identifiant.md"].level, "erreur", "note sans identifiant : refusée")
	eq(by["Pieces/2026-10-19 brut.txt"].level, "ok", "pièce jointe : prête")
	ok(str(a.report).contains("le Notaire"), "rapport du lot lisible")
	var tor: Dictionary = by["Groupes/Toréador.md"]
	eq(tor.level, "avert", "nom presque identique à une fiche existante : averti, pas refusé")
	ok(str(tor.messages).contains("presque identique") and str(tor.messages).contains("Groupes/Toreador.md"), "le nom proche est signalé : %s" % str(tor.messages))
	ok(" ".join(PackedStringArray(tor.messages)).contains("l'alias « Toreador »"), "l'alias qui reprend un nom existant est signalé : %s" % str(tor.messages))
	var chosen: Array = (a.items as Array).filter(func(x): return x.target_rel != "Groupes/Toréador.md")
	var r: Dictionary = app.import_lot(lot, chosen)
	eq(r.done.size(), 2, "2 éléments intégrés (la note neuve et la pièce jointe)")
	eq(r.failed.size(), 3, "3 refusés")
	ok(not FileAccess.file_exists(root + "/Groupes/Toréador.md"), "une note décochée n'est pas intégrée")
	ok(FileAccess.file_exists(root + "/Personnages/Bastien Roux.md") and FileAccess.file_exists(root + "/Pieces/2026-10-19 brut.txt"), "copiés à leur place")
	ok(FileAccess.get_file_as_string(root + "/Personnages/Victor Morel.md").contains("Exemple fictif"), "la note existante n'est pas écrasée")
	ok(FileAccess.file_exists(root + "/" + lot + "/Personnages/Bastien Roux.md"), "le lot n'est pas vidé")
	ok(FileAccess.get_file_as_string(root + "/" + lot + "/_import.journal.md").contains("intégrée : Personnages/Bastien Roux.md"), "journal d'intégration")
	var again: Dictionary = app.analyse_lot(lot)
	for it in again.items:
		if it.target_rel == "Personnages/Bastien Roux.md":
			eq(it.level, "erreur", "réimporter la même note est refusé")
	_done()
