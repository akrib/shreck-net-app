extends RefCounted
## Écriture sûre d'une note (architecture §5 « Enregistrement ») :
##   1. contrôle de conflit : le fichier sur disque doit avoir l'empreinte
##      connue à l'ouverture ;
##   2. écriture dans .nosferatu/tmp/ (ignoré par Git), relecture, vérification ;
##   3. journal de l'opération, puis remplacement du fichier ;
##   4. relecture et vérification du fichier final.
##
## Sous Windows, Godot remplace un fichier en supprimant d'abord la cible :
## on passe donc par une copie de secours, restaurée au prochain lancement si
## l'application s'arrête au mauvais moment (voir recover()).

const RepoAccess := preload("res://core/storage/repo_access.gd")

var repo: RefCounted
var use_backup := OS.get_name() == "Windows"


func _init(p_repo: RefCounted) -> void:
	repo = p_repo


func _tmp_dir() -> String:
	return repo.abs_path(".nosferatu/tmp")


## expected_hash : empreinte du fichier quand il a été ouvert ("" = nouveau fichier).
## Renvoie {ok, conflict, error, hash, size, mtime, disk_bytes}.
func write(rel: String, bytes: PackedByteArray, expected_hash: String, allow_git_busy := false) -> Dictionary:
	var r := {"ok": false, "conflict": false, "error": "", "hash": "", "size": 0, "mtime": 0,
		"disk_bytes": PackedByteArray()}
	var target: String = repo.abs_path(rel)
	if not allow_git_busy:
		var busy: String = repo.git_busy()
		if busy != "":
			r.error = "opération Git en cours (%s) : réessayez dans un instant" % busy
			return r
	# 1. conflit ?
	if FileAccess.file_exists(target):
		var cur := FileAccess.get_file_as_bytes(target)
		var cur_hash := RepoAccess.hash_bytes(cur)
		if expected_hash == "" or cur_hash != expected_hash:
			r.conflict = true
			r.disk_bytes = cur
			r.error = "le fichier a été modifié ailleurs depuis son ouverture"
			return r
	elif expected_hash != "":
		r.conflict = true
		r.error = "le fichier a été supprimé ou renommé ailleurs depuis son ouverture"
		return r
	# 2. fichier temporaire
	var err := DirAccess.make_dir_recursive_absolute(_tmp_dir())
	if err != OK:
		r.error = "impossible de créer .nosferatu/tmp : " + error_string(err)
		return r
	var token := "%d-%d" % [Time.get_ticks_usec(), randi() % 1000000]
	var tmp := _tmp_dir() + "/" + token + ".tmp"
	var new_hash := RepoAccess.hash_bytes(bytes)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		r.error = "écriture temporaire impossible : " + error_string(FileAccess.get_open_error())
		return r
	f.store_buffer(bytes)
	f.flush()
	var werr := f.get_error()
	f.close()
	if werr != OK or RepoAccess.hash_bytes(FileAccess.get_file_as_bytes(tmp)) != new_hash:
		DirAccess.remove_absolute(tmp)
		r.error = "écriture temporaire incomplète (%s)" % error_string(werr)
		return r
	# 3. journal puis remplacement
	var backup := _tmp_dir() + "/" + token + ".bak"
	var journal := _tmp_dir() + "/" + token + ".journal"
	var jf := FileAccess.open(journal, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify({"target": rel, "tmp": tmp, "backup": backup,
			"new_hash": new_hash, "old_hash": expected_hash}))
		jf.close()
	var had_target := FileAccess.file_exists(target)
	var parent := target.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	if use_backup and had_target:
		err = DirAccess.rename_absolute(target, backup)
		if err != OK:
			_cleanup([tmp, journal])
			r.error = "remplacement impossible (sauvegarde) : " + error_string(err)
			return r
	err = DirAccess.rename_absolute(tmp, target)
	if err != OK:
		if use_backup and had_target and FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, target)
		_cleanup([tmp, journal])
		r.error = "remplacement impossible : " + error_string(err)
		return r
	# 4. vérification finale
	var final_bytes := FileAccess.get_file_as_bytes(target)
	if RepoAccess.hash_bytes(final_bytes) != new_hash:
		r.error = "vérification après écriture échouée : le fichier est conservé, " + \
			"la copie de secours aussi (.nosferatu/tmp)"
		return r
	_cleanup([backup, journal])
	r.ok = true
	r.hash = new_hash
	r.size = final_bytes.size()
	r.mtime = FileAccess.get_modified_time(target)
	return r


func _cleanup(paths: Array) -> void:
	for p in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## À appeler au démarrage : termine ou annule les écritures interrompues.
## Ne supprime jamais une version qui n'existe nulle part ailleurs.
func recover() -> Array:
	var notes := []
	var dir := _tmp_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return notes
	for name in DirAccess.get_files_at(dir):
		if not name.ends_with(".journal"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + name))
		if typeof(data) != TYPE_DICTIONARY:
			notes.append("journal illisible conservé : " + name)
			continue
		var target: String = repo.abs_path(data.target)
		var tmp: String = data.tmp
		var backup: String = data.backup
		var target_ok: bool = FileAccess.file_exists(target) and \
			RepoAccess.hash_bytes(FileAccess.get_file_as_bytes(target)) == data.new_hash
		if target_ok:
			_cleanup([tmp, backup, dir + "/" + name])
			notes.append("écriture terminée confirmée : " + str(data.target))
		elif not FileAccess.file_exists(target) and FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, target)
			notes.append("version précédente restaurée : " + str(data.target))
			if FileAccess.file_exists(tmp):
				var c := save_conflict_copy(str(data.target), FileAccess.get_file_as_bytes(tmp))
				if c.ok:
					DirAccess.remove_absolute(tmp)
					notes.append("version non confirmée de %s conservée dans _Conflits/" % data.target)
			_cleanup([dir + "/" + name])
		elif not FileAccess.file_exists(target) and FileAccess.file_exists(tmp):
			DirAccess.rename_absolute(tmp, target)
			_cleanup([dir + "/" + name])
			notes.append("écriture interrompue terminée : " + str(data.target))
		else:
			# La cible existe mais ne porte pas la nouvelle version : on garde la
			# version non confirmée dans _Conflits/ plutôt que de la jeter.
			for extra in [tmp, backup]:
				if FileAccess.file_exists(extra):
					var b := FileAccess.get_file_as_bytes(extra)
					if FileAccess.file_exists(target) and \
							RepoAccess.hash_bytes(b) == RepoAccess.hash_bytes(FileAccess.get_file_as_bytes(target)):
						DirAccess.remove_absolute(extra)
					else:
						var c := save_conflict_copy(str(data.target), b)
						if c.ok:
							DirAccess.remove_absolute(extra)
							notes.append("version non confirmée de %s conservée dans _Conflits/" % data.target)
						else:
							notes.append("version non confirmée conservée dans .nosferatu/tmp : " + extra.get_file())
			_cleanup([dir + "/" + name])
			notes.append("écriture interrompue examinée : " + str(data.target))
	return notes


## Sauvegarde une version en conflit dans _Conflits/ (jamais d'écrasement).
func save_conflict_copy(rel: String, bytes: PackedByteArray) -> Dictionary:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", " ")
	var name := rel.get_file().get_basename() + " (conflit " + stamp + ").md"
	var out_rel := "_Conflits/" + name
	DirAccess.make_dir_recursive_absolute(repo.abs_path("_Conflits"))
	return write(out_rel, bytes, "", true)
