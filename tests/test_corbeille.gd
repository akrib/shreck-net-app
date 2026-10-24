extends "res://tests/base.gd"
## Corbeille : une note supprimée part dans `.trash/` (jamais effacée), sort de
## l'index, se restaure à sa place sans rien écraser ; seul « effacer
## définitivement » supprime un fichier, et seulement dans `.trash/`.

const AppService := preload("res://core/app/app_service.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const RepoAccess := preload("res://core/storage/repo_access.gd")

var app: Node
var root := ""


func _prepare() -> void:
	AppService.settings_file = "user://tests_tmp/reglages-corbeille.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	root = temp_dir("coffre-corbeille")
	write_file(root + "/Personnages/Alix.md", "---\ntype: personnage\nid: per-c0rbe001\nschema: 1\n---\n# Alix\n")
	write_file(root + "/Sources/Notes/Cour.md", "---\ntype: source\nid: src-c0rbe002\nschema: 1\nnature: note\n---\n## Éléments\n- [[Alix]] parle. [nature:: observe] [credibilite:: 2] ^el-c0rbe003\n")
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


func _hash(rel: String) -> String:
	return RepoAccess.hash_bytes(FileAccess.get_file_as_bytes(root + "/" + rel))


func test_mise_a_la_corbeille_et_restauration() -> void:
	_prepare()
	var rel := "Personnages/Alix.md"
	var info: Dictionary = app.delete_info(rel)
	eq(info.count, 1, "une note cite encore Alix")
	eq(str(info.backlinks[0].name), "Cour", "la note qui la cite")
	var before := FileAccess.get_file_as_bytes(root + "/" + rel)
	var r: Dictionary = app.trash_note(rel, _hash(rel))
	ok(r.ok, "mise à la corbeille : " + str(r.error))
	eq(str(r.trash_rel), ".trash/Personnages/Alix.md", "chemin d'origine conservé dans .trash/")
	ok(not FileAccess.file_exists(root + "/" + rel), "la note a quitté son dossier")
	ok(FileAccess.get_file_as_bytes(root + "/.trash/Personnages/Alix.md") == before, "contenu intact dans la corbeille")
	eq(app.index.path_of_name("Alix"), "", "la note sort de l'index")
	var lst: Array = app.trash_list()
	eq(lst.size(), 1, "un élément dans la corbeille")
	ok(lst[0].connue and str(lst[0].origine) == rel and str(lst[0].type) == "personnage", "origine et type gardés : " + str(lst[0]))
	# une seconde suppression du même nom ne remplace rien
	write_file(root + "/" + rel, "---\ntype: personnage\nid: per-c0rbe009\nschema: 1\n---\n# Alix bis\n")
	Scanner.new(app.repo, app.index).scan()
	var r2: Dictionary = app.trash_note(rel, _hash(rel))
	eq(str(r2.trash_rel), ".trash/Personnages/Alix (2).md", "homonyme dans la corbeille : « (2) »")
	# restauration
	var back: Dictionary = app.restore_note(".trash/Personnages/Alix.md")
	ok(back.ok and str(back.rel) == rel, "restaurée à sa place : " + str(back))
	ok(FileAccess.get_file_as_bytes(root + "/" + rel) == before, "contenu restauré à l'identique")
	ok(app.index.path_of_name("Alix") == rel, "la note revient dans l'index")
	var again: Dictionary = app.restore_note(".trash/Personnages/Alix (2).md")
	ok(not again.ok and str(again.error).contains("s'appelle déjà"), "pas de restauration par-dessus une note du même nom : " + str(again.error))
	ok(FileAccess.file_exists(root + "/.trash/Personnages/Alix (2).md"), "l'homonyme reste dans la corbeille")
	_done()


func test_conflit_et_effacement() -> void:
	_prepare()
	var rel := "Sources/Notes/Cour.md"
	var r: Dictionary = app.trash_note(rel, "empreinte-perimee")
	ok(not r.ok and r.conflict, "note modifiée ailleurs : rien n'est déplacé")
	ok(FileAccess.file_exists(root + "/" + rel), "la note est toujours là")
	ok(app.trash_note(rel, _hash(rel)).ok, "mise à la corbeille avec la bonne empreinte")
	# un fichier mis à la corbeille par Obsidian (hors journal)
	write_file(root + "/.trash/Vieille note.md", "# vieille\n")
	var lst: Array = app.trash_list()
	eq(lst.size(), 2, "la corbeille d'Obsidian est listée aussi")
	var obs: Array = lst.filter(func(e): return not e.connue)
	eq(str(obs[0].origine), "Vieille note.md", "origine supposée : la racine du coffre")
	var p: Dictionary = app.purge_trash([".trash/Sources/Notes/Cour.md", "Personnages/Alix.md", ".trash/../Personnages/Alix.md"])
	eq(p.done, [".trash/Sources/Notes/Cour.md"], "seuls les fichiers de la corbeille sont effacés")
	ok(FileAccess.file_exists(root + "/Personnages/Alix.md"), "une note du coffre n'est jamais effacée")
	ok(not DirAccess.dir_exists_absolute(root + "/.trash/Sources"), "dossiers vides retirés de la corbeille")
	eq(app.trash_list().size(), 1, "reste la note d'Obsidian")
	_done()
