extends RefCounted
## Accès au dossier du coffre par chemin classique (bureau, et Android avec
## « Accès à tous les fichiers »). C'est le seul composant qui sait où sont
## les fichiers. Il ne supprime jamais rien.

## Toujours ignorés, même pas listés comme pièces jointes. `_Export` contient
## les exports pour Claude (fichiers .txt, copies de notes) : ni notes, ni liens.
const ALWAYS_IGNORED := [".git", ".obsidian", ".nosferatu", ".trash", "_Export"]
const DEFAULT_IGNORED := ["_Import", "_Conflits", "Modeles", "Tableaux", "Pieces"]

var root := ""            ## chemin absolu, avec des « / », sans « / » final
var ignored_top := DEFAULT_IGNORED.duplicate()
var config := {}          ## contenu de .nosferatu/config.json (vocabulaires), ou {}


func _init(path: String = "") -> void:
	if path != "":
		set_root(path)


func set_root(path: String) -> void:
	var p := path.strip_edges().replace("\\", "/")
	while p.length() > 1 and p.ends_with("/"):
		p = p.substr(0, p.length() - 1)
	root = p
	_load_config()


func abs_path(rel: String) -> String:
	return root + "/" + rel


func rel_path(abs: String) -> String:
	return abs.trim_prefix(root + "/")


func _load_config() -> void:
	ignored_top = DEFAULT_IGNORED.duplicate()
	config = {}
	var cfg := abs_path(".nosferatu/config.json")
	if not FileAccess.file_exists(cfg):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(cfg))
	if typeof(data) == TYPE_DICTIONARY:
		config = data
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("dossiers_ignores")) == TYPE_ARRAY:
		ignored_top = []
		for d in data["dossiers_ignores"]:
			ignored_top.append(str(d))


## Vérifie le dossier : existence, lecture, écriture, marqueurs Git et Nosferatu.
## N'écrit qu'un fichier de test dans .nosferatu/tmp/ (puis le supprime).
func check() -> Dictionary:
	var r := {"exists": false, "readable": false, "writable": false, "git": false,
		"config": false, "tmp_ignored": false, "md_count_top": 0, "error": ""}
	if root == "":
		r.error = "aucun chemin configuré"
		return r
	if not DirAccess.dir_exists_absolute(root):
		r.error = "dossier introuvable : " + root
		return r
	r.exists = true
	var d := DirAccess.open(root)
	if d == null:
		r.error = "lecture impossible (permission ?) : " + error_string(DirAccess.get_open_error())
		return r
	r.readable = true
	r.git = DirAccess.dir_exists_absolute(abs_path(".git"))
	r.config = FileAccess.file_exists(abs_path(".nosferatu/config.json"))
	r.tmp_ignored = _gitignore_has_tmp()
	var tmp := abs_path(".nosferatu/tmp")
	var err := DirAccess.make_dir_recursive_absolute(tmp)
	if err == OK:
		var probe := tmp + "/sonde-ecriture.tmp"
		var f := FileAccess.open(probe, FileAccess.WRITE)
		if f != null:
			f.store_string("ok")
			f.close()
			r.writable = FileAccess.get_file_as_string(probe) == "ok"
			DirAccess.remove_absolute(probe)
	if not r.writable and r.error == "":
		r.error = "écriture impossible dans le dossier"
	return r


func _gitignore_has_tmp() -> bool:
	var gi := abs_path(".gitignore")
	if not FileAccess.file_exists(gi):
		return false
	for l in FileAccess.get_file_as_string(gi).split("\n"):
		var t := l.strip_edges().trim_prefix("/")
		if t == ".nosferatu/tmp/" or t == ".nosferatu/tmp" or t == ".nosferatu/" or t == ".nosferatu":
			return true
	return false


## Ajoute « .nosferatu/tmp/ » au .gitignore (action explicite de l'utilisateur).
func add_tmp_to_gitignore() -> Error:
	var gi := abs_path(".gitignore")
	var content := FileAccess.get_file_as_string(gi) if FileAccess.file_exists(gi) else ""
	if content != "" and not content.ends_with("\n"):
		content += "\n"
	if not content.contains(".nosferatu/tmp/"):
		content += "# Écritures temporaires de l'application Nosferatu\n.nosferatu/tmp/\n"
	if not content.contains("_Export/"):
		content += "# Exports pour Claude (copies de notes, à ne pas versionner)\n_Export/\n"
	var f := FileAccess.open(gi, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(content)
	f.close()
	return OK


## Signes d'une opération Git en cours (heuristique).
func git_busy() -> String:
	for marker in [".git/index.lock", ".git/MERGE_HEAD", ".git/rebase-merge", ".git/rebase-apply"]:
		var p := abs_path(marker)
		if FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p):
			return marker
	return ""


## Extensions de fichiers courantes dans un coffre : une entrée qui porte
## l'une d'elles est prise pour un fichier sans le demander au système (sur
## Android, chaque question « est-ce un dossier ? » coûte un appel Java et un
## accès disque). Pour les autres noms, on demande.
const FILE_EXTENSIONS := {"md": true, "png": true, "jpg": true, "jpeg": true, "gif": true,
	"webp": true, "svg": true, "bmp": true, "avif": true, "heic": true, "pdf": true, "txt": true,
	"json": true, "csv": true, "base": true, "canvas": true, "mp3": true, "m4a": true, "ogg": true,
	"opus": true, "wav": true, "flac": true, "mp4": true, "mov": true, "webm": true, "mkv": true,
	"html": true, "htm": true, "docx": true, "odt": true, "xlsx": true, "ods": true, "pptx": true,
	"zip": true, "py": true, "yml": true, "yaml": true, "gitkeep": true}


## Liste récursive, séquentielle. Renvoie {md: [rel…], other: [rel…], errors: [msg…]}.
##  - les noms commençant par « . » sont ignorés (fichiers et dossiers), sur
##    toutes les plateformes ;
##  - dans les dossiers ignorés de premier niveau (Modeles, Pieces…), rien
##    n'est indexé comme note, mais les fichiers sont listés comme pièces jointes
##    pour que les liens vers eux ne soient pas signalés comme cassés.
## Séquentielle exprès : sur Android, Godot sérialise tous les accès aux
## dossiers derrière un même verrou, et la version parallèle était plus lente.
func list_files() -> Dictionary:
	var res := {"md": [], "other": [], "errors": []}
	_walk("", true, res)
	res.md.sort()
	res.other.sort()
	return res


func _walk(rel_dir: String, notes: bool, res: Dictionary) -> void:
	var d := DirAccess.open(root if rel_dir == "" else abs_path(rel_dir))
	if d == null:
		res.errors.append("dossier illisible : " + (rel_dir if rel_dir != "" else "/"))
		return
	# Filtrage des noms cachés par nos soins : évite une question au système par entrée.
	d.include_hidden = true
	d.include_navigational = false
	if d.list_dir_begin() != OK:
		res.errors.append("dossier illisible : " + (rel_dir if rel_dir != "" else "/"))
		return
	var prefix := "" if rel_dir == "" else rel_dir + "/"
	var subs := []
	var name := d.get_next()
	while name != "":
		if not name.begins_with("."):
			var ext := name.get_extension().to_lower()
			if not FILE_EXTENSIONS.has(ext) and d.current_is_dir():
				subs.append(name)
			elif notes and ext == "md":
				res.md.append(prefix + name)
			else:
				res.other.append(prefix + name)
		name = d.get_next()
	d.list_dir_end()
	for sub in subs:
		if sub in ALWAYS_IGNORED:
			continue
		var sub_notes: bool = notes and not (rel_dir == "" and sub in ignored_top)
		_walk(prefix + sub, sub_notes, res)


## Contenu visible à la racine (pour le diagnostic).
func top_entries() -> Dictionary:
	var r := {"dirs": [], "files": [], "hidden": []}
	var d := DirAccess.open(root)
	if d == null:
		return r
	d.include_hidden = true
	d.include_navigational = false
	for sub in d.get_directories():
		(r.hidden if sub.begins_with(".") else r.dirs).append(sub)
	for f in d.get_files():
		(r.hidden if f.begins_with(".") else r.files).append(f)
	return r


## Date de modification (secondes). La taille n'est pas lue ici : sur Android
## et Windows, la lire oblige à ouvrir le fichier, ce qui coûte cher.
func mtime(rel: String) -> int:
	return FileAccess.get_modified_time(abs_path(rel))


func stat(rel: String) -> Dictionary:
	var p := abs_path(rel)
	return {"size": FileAccess.get_size(p), "mtime": FileAccess.get_modified_time(p)}


## Lecture complète. Utilisable depuis un fil de travail.
func read_bytes(rel: String) -> Dictionary:
	var f := FileAccess.open(abs_path(rel), FileAccess.READ)
	if f == null:
		return {"bytes": PackedByteArray(), "error": FileAccess.get_open_error()}
	var bytes := f.get_buffer(f.get_length())
	var err := f.get_error()
	f.close()
	return {"bytes": bytes, "error": OK if err == ERR_FILE_EOF else err}


func exists(rel: String) -> bool:
	return FileAccess.file_exists(abs_path(rel))


static func hash_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		ctx.update(bytes)
	return ctx.finish().hex_encode()
