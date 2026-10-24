extends RefCounted
## Corbeille du coffre : le dossier `.trash/`, celui qu'Obsidian utilise quand on
## choisit « Déplacer dans la corbeille d'Obsidian ».
##
## Supprimer une note depuis l'application la déplace dans `.trash/` en gardant
## son chemin (`.trash/Personnages/X.md`) : ni l'application ni Obsidian ne la
## lisent plus (les dossiers qui commencent par un point sont ignorés), Git voit
## un simple déplacement, et rien n'est perdu. Le journal
## `.nosferatu/corbeille.json` garde l'emplacement d'origine et la date.
## Les fichiers mis à la corbeille par Obsidian lui-même y figurent aussi.
##
## Restaurer remet la note à sa place d'origine, sans jamais écraser un fichier.
## Seul « Supprimer définitivement » efface un fichier, et seulement dans `.trash/`.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const SafeWriter := preload("res://core/storage/safe_writer.gd")

const DIR := ".trash"
const JOURNAL := ".nosferatu/corbeille.json"


static func _journal(repo: RefCounted) -> Dictionary:
	var rb: Dictionary = repo.read_bytes(JOURNAL)
	if rb.error != OK:
		return {}
	var v: Variant = JSON.parse_string(rb.bytes.get_string_from_utf8())
	if typeof(v) == TYPE_DICTIONARY and typeof(v.get("notes", null)) == TYPE_DICTIONARY:
		return v.notes
	return {}


static func _save_journal(repo: RefCounted, notes: Dictionary) -> Dictionary:
	var cur: Dictionary = repo.read_bytes(JOURNAL)
	var h := RepoAccess.hash_bytes(cur.bytes) if cur.error == OK else ""
	var text := JSON.stringify({"notes": notes}, "\t", true) + "\n"
	return SafeWriter.new(repo).write(JOURNAL, text.to_utf8_buffer(), h)


## Chemin libre dans la corbeille pour `rel` : `.trash/<rel>`, sinon « (2) », « (3) »…
static func free_path(repo: RefCounted, rel: String) -> String:
	var base := DIR + "/" + rel.get_basename()
	var p := base + ".md"
	var k := 2
	while repo.exists(p):
		p = "%s (%d).md" % [base, k]
		k += 1
	return p


## Met une note à la corbeille. `expected_hash` : empreinte connue à l'ouverture
## ("" pour ne pas contrôler). `info` : {name, type} gardés dans le journal.
## Renvoie {ok, conflict, error, trash_rel}.
static func move_to_trash(repo: RefCounted, rel: String, expected_hash := "", info := {}) -> Dictionary:
	var r := {"ok": false, "conflict": false, "error": "", "trash_rel": ""}
	if rel.begins_with(DIR + "/") or rel.begins_with("."):
		r.error = "cette note est déjà hors du coffre visible"
		return r
	var busy: String = repo.git_busy()
	if busy != "":
		r.error = "opération Git en cours (%s) : réessayez dans un instant" % busy
		return r
	if not repo.exists(rel):
		r.conflict = expected_hash != ""
		r.error = "la note n'existe plus (déplacée ou supprimée ailleurs)"
		return r
	if expected_hash != "":
		var cur: Dictionary = repo.read_bytes(rel)
		if cur.error != OK or RepoAccess.hash_bytes(cur.bytes) != expected_hash:
			r.conflict = true
			r.error = "la note a été modifiée ailleurs depuis son ouverture : rien n'a été déplacé"
			return r
	var dst := free_path(repo, rel)
	var src_abs: String = repo.abs_path(rel)
	var dst_abs: String = repo.abs_path(dst)
	var err := DirAccess.make_dir_recursive_absolute(dst_abs.get_base_dir())
	if err != OK:
		r.error = "impossible de créer %s : %s" % [dst.get_base_dir(), error_string(err)]
		return r
	err = DirAccess.rename_absolute(src_abs, dst_abs)
	if err != OK or not FileAccess.file_exists(dst_abs) or FileAccess.file_exists(src_abs):
		r.error = "déplacement impossible : " + error_string(err)
		return r
	var j := _journal(repo)
	j[dst] = {"origine": rel, "date": Time.get_datetime_string_from_system(false, true),
		"nom": str(info.get("name", rel.get_file().get_basename())), "type": str(info.get("type", ""))}
	var w := _save_journal(repo, j)
	r.ok = true
	r.trash_rel = dst
	if not w.ok:
		r.error = "note déplacée, mais journal de la corbeille non écrit : " + str(w.error)
	return r


## Contenu de la corbeille, le plus récent d'abord :
## [{trash_rel, origine, nom, type, date, connue}] (`connue` : passée par l'application).
static func list(repo: RefCounted) -> Array:
	var out := []
	var j := _journal(repo)
	var files := []
	_walk(repo, DIR, files)
	for f in files:
		var e: Dictionary = j.get(f, {})
		var origin := str(e.get("origine", f.substr(DIR.length() + 1)))
		var date := str(e.get("date", ""))
		if date == "":
			date = Time.get_datetime_string_from_unix_time(repo.mtime(f), true)
		out.append({"trash_rel": f, "origine": origin, "nom": str(e.get("nom", f.get_file().get_basename())),
			"type": str(e.get("type", "")), "date": date, "connue": not e.is_empty()})
	out.sort_custom(func(a, b): return str(a.date) > str(b.date))
	return out


static func _walk(repo: RefCounted, rel_dir: String, out: Array) -> void:
	var d := DirAccess.open(repo.abs_path(rel_dir))
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		if f.get_extension().to_lower() == "md":
			out.append(rel_dir + "/" + f)
	for s in d.get_directories():
		_walk(repo, rel_dir + "/" + s, out)


## Remet une note à sa place. N'écrase jamais rien. Renvoie {ok, error, rel}.
static func restore(repo: RefCounted, trash_rel: String) -> Dictionary:
	var r := {"ok": false, "error": "", "rel": ""}
	if not trash_rel.begins_with(DIR + "/") or not repo.exists(trash_rel):
		r.error = "introuvable dans la corbeille"
		return r
	var busy: String = repo.git_busy()
	if busy != "":
		r.error = "opération Git en cours (%s) : réessayez dans un instant" % busy
		return r
	var j := _journal(repo)
	var origin := str(j.get(trash_rel, {}).get("origine", trash_rel.substr(DIR.length() + 1)))
	if repo.exists(origin):
		r.error = "un fichier existe déjà à cet endroit (%s) : rien n'a été écrasé" % origin
		return r
	var dst_abs: String = repo.abs_path(origin)
	DirAccess.make_dir_recursive_absolute(dst_abs.get_base_dir())
	var err := DirAccess.rename_absolute(repo.abs_path(trash_rel), dst_abs)
	if err != OK or not FileAccess.file_exists(dst_abs):
		r.error = "déplacement impossible : " + error_string(err)
		return r
	j.erase(trash_rel)
	_save_journal(repo, j)
	_prune_dirs(repo, trash_rel.get_base_dir())
	r.ok = true
	r.rel = origin
	return r


## Efface définitivement des fichiers de la corbeille (et seulement de la corbeille).
## Renvoie {ok, done, error}.
static func purge(repo: RefCounted, trash_rels: Array) -> Dictionary:
	var r := {"ok": true, "done": [], "error": ""}
	var j := _journal(repo)
	for t in trash_rels:
		var tr := str(t)
		if not tr.begins_with(DIR + "/") or tr.contains("..") or not repo.exists(tr):
			continue
		var err := DirAccess.remove_absolute(repo.abs_path(tr))
		if err != OK:
			r.ok = false
			r.error = "%s : %s" % [tr, error_string(err)]
			continue
		j.erase(tr)
		r.done.append(tr)
		_prune_dirs(repo, tr.get_base_dir())
	_save_journal(repo, j)
	return r


## Retire les dossiers vides laissés dans la corbeille (jamais `.trash` lui-même).
static func _prune_dirs(repo: RefCounted, rel_dir: String) -> void:
	var cur := rel_dir
	while cur.begins_with(DIR + "/"):
		var abs: String = repo.abs_path(cur)
		var d := DirAccess.open(abs)
		if d == null:
			return
		d.include_hidden = true
		if not d.get_files().is_empty() or not d.get_directories().is_empty():
			return
		DirAccess.remove_absolute(abs)
		cur = cur.get_base_dir()
