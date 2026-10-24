extends "res://tests/base.gd"
## Écriture sûre : vérification, conflits, Git occupé, reprise après interruption.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const SafeWriter := preload("res://core/storage/safe_writer.gd")


func _setup(name: String) -> RefCounted:
	var root := temp_dir(name)
	return RepoAccess.new(root)


func _tmp_empty(repo: RefCounted) -> bool:
	var files := DirAccess.get_files_at(repo.abs_path(".nosferatu/tmp"))
	return files.is_empty()


func test_ecriture_et_conflit() -> void:
	for mode in [false, true]:
		var repo := _setup("sw_%s" % mode)
		var w = SafeWriter.new(repo)
		w.use_backup = mode
		var label := " (mode copie de secours)" if mode else ""
		var r: Dictionary = w.write("Personnages/Test é.md", "v1".to_utf8_buffer(), "")
		ok(r.ok, "création" + label)
		eq(FileAccess.get_file_as_string(repo.abs_path("Personnages/Test é.md")), "v1", "contenu écrit" + label)
		var h1: String = r.hash
		r = w.write("Personnages/Test é.md", "v2".to_utf8_buffer(), h1)
		ok(r.ok, "remplacement avec la bonne empreinte" + label)
		r = w.write("Personnages/Test é.md", "v3".to_utf8_buffer(), h1)
		ok(r.conflict and not r.ok, "conflit détecté avec une empreinte périmée" + label)
		eq(FileAccess.get_file_as_string(repo.abs_path("Personnages/Test é.md")), "v2", "rien d'écrasé" + label)
		eq(r.disk_bytes.get_string_from_utf8(), "v2", "version du disque fournie" + label)
		r = w.write("Personnages/Test é.md", "v4".to_utf8_buffer(), "")
		ok(r.conflict, "création refusée si le fichier existe déjà" + label)
		ok(_tmp_empty(repo), "aucun fichier temporaire restant" + label)


func test_git_occupe() -> void:
	var repo := _setup("sw_git")
	DirAccess.make_dir_recursive_absolute(repo.abs_path(".git"))
	write_file(repo.abs_path(".git/index.lock"), "")
	var r: Dictionary = SafeWriter.new(repo).write("a.md", "x".to_utf8_buffer(), "")
	ok(not r.ok and str(r.error).contains("Git"), "écriture refusée pendant une opération Git")
	ok(not FileAccess.file_exists(repo.abs_path("a.md")), "aucun fichier créé")


func test_reprise_apres_interruption() -> void:
	var repo := _setup("sw_recover")
	var w = SafeWriter.new(repo)
	var tmpd: String = repo.abs_path(".nosferatu/tmp")
	DirAccess.make_dir_recursive_absolute(tmpd)
	# Cas 1 : arrêt après la mise de côté de l'original (Windows) : on restaure.
	write_file(tmpd + "/t1.bak", "ancien")
	write_file(tmpd + "/t1.tmp", "nouveau")
	write_file(tmpd + "/t1.journal", JSON.stringify({"target": "n1.md", "tmp": tmpd + "/t1.tmp",
		"backup": tmpd + "/t1.bak", "new_hash": RepoAccess.hash_bytes("nouveau".to_utf8_buffer()), "old_hash": "x"}))
	# Cas 2 : arrêt avant le remplacement : l'original est intact, la version
	# non confirmée part dans _Conflits/.
	write_file(repo.abs_path("n2.md"), "original")
	write_file(tmpd + "/t2.tmp", "non confirmé")
	write_file(tmpd + "/t2.journal", JSON.stringify({"target": "n2.md", "tmp": tmpd + "/t2.tmp",
		"backup": tmpd + "/t2.bak", "new_hash": RepoAccess.hash_bytes("non confirmé".to_utf8_buffer()), "old_hash": "x"}))
	# Cas 3 : écriture terminée, seul le ménage manquait.
	write_file(repo.abs_path("n3.md"), "fini")
	write_file(tmpd + "/t3.journal", JSON.stringify({"target": "n3.md", "tmp": tmpd + "/t3.tmp",
		"backup": tmpd + "/t3.bak", "new_hash": RepoAccess.hash_bytes("fini".to_utf8_buffer()), "old_hash": "x"}))
	var notes: Array = w.recover()
	eq(notes.size() >= 3, true, "trois journaux traités : %s" % str(notes))
	eq(FileAccess.get_file_as_string(repo.abs_path("n1.md")), "ancien", "cas 1 : version précédente restaurée")
	eq(FileAccess.get_file_as_string(repo.abs_path("n2.md")), "original", "cas 2 : original intact")
	var conflits := DirAccess.get_files_at(repo.abs_path("_Conflits"))
	eq(conflits.size(), 2, "cas 1 et 2 : versions non confirmées conservées dans _Conflits/")
	eq(FileAccess.get_file_as_string(repo.abs_path("n3.md")), "fini", "cas 3 : fichier final intact")
	var restants := Array(DirAccess.get_files_at(tmpd))
	ok(not restants.has("t2.journal") and not restants.has("t3.journal") and not restants.has("t1.journal"),
		"journaux soldés")
	eq(restants.size(), 0, "plus rien dans .nosferatu/tmp : %s" % str(restants))


func test_copie_de_conflit() -> void:
	var repo := _setup("sw_conflit")
	var r: Dictionary = SafeWriter.new(repo).save_conflict_copy("Personnages/Victor Morel.md", "ma version".to_utf8_buffer())
	ok(r.ok, "copie de conflit écrite")
	var files := DirAccess.get_files_at(repo.abs_path("_Conflits"))
	ok(files.size() == 1 and files[0].begins_with("Victor Morel (conflit "), "nommée d'après la note : %s" % str(files))
