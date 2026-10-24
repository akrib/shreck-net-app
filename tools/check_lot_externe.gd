extends SceneTree
## Vérifie un lot d'import réel dans l'application, sur une copie du coffre
## d'exemple : analyse, intégration de tout ce qui est intégrable, réindexation.
##   godot --headless --path . --script res://tools/check_lot_externe.gd -- <dossier du lot>
## Le lot n'est pas modifié ; rien n'est écrit hors du dossier de test.

const AppService := preload("res://core/app/app_service.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Base := preload("res://tests/base.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage : -- <dossier du lot>")
		quit(2)
		return
	var src: String = args[0]
	var b = Base.new()
	AppService.settings_file = "user://tests_tmp/reglages-lot-externe.cfg"
	var root: String = b.temp_dir("coffre-lot-externe")
	b.copy_tree(b.example_vault(), root)
	var lot := "_Import/" + src.get_file()
	b.copy_tree(src, root + "/" + lot)
	var app = AppService.new()
	app.background_jobs = false
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	preload("res://core/index/index_store.gd").delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()
	var before: int = app.index.stats().files
	var a: Dictionary = app.analyse_lot(lot)
	print("Analyse : %d élément(s) — %s" % [a.items.size(), str(a.counts)])
	for it in a.items:
		if it.level != "ok":
			print("  [%s] %s : %s" % [it.level, it.target_rel, " | ".join(PackedStringArray(it.messages))])
	var chosen: Array = (a.items as Array).filter(func(x): return x.level == "ok")
	var r: Dictionary = app.import_lot(lot, chosen)
	print("Intégration : %d intégré(s), %d refusé(s)" % [r.done.size(), r.failed.size()])
	Scanner.new(app.repo, app.index).scan()
	print("Fichiers indexés : %d -> %d" % [before, app.index.stats().files])
	var bad: Array = app.index.rows("SELECT path, nb_err, nb_warn FROM files WHERE (nb_err > 0 OR nb_warn > 0) AND path NOT LIKE '_Import/%'")
	print("Notes avec erreurs ou avertissements après intégration : %d" % bad.size())
	for x in bad:
		print("  %s (%d err, %d avert)" % [x.path, x.nb_err, x.nb_warn])
	for d in ["Dissimulation", "Thaumaturgie", "Force d'âme"]:
		var who := []
		for row in app.index.linked_from(d, ["disciplines"]):
			who.append(str(row.name))
		print("%s ← %s" % [d, ", ".join(PackedStringArray(who))])
	print("Toreador (coffre) -> %s ; Toréador (lot) -> %s" % [app.index.path_of_name("Toreador"), app.index.path_of_name("Toréador")])
	print("Victor Morel, clan -> %s" % str(app.index.props_of("Personnages/Victor Morel.md").get("clan", "")))
	app.index.close()
	app.free()
	quit(0)
