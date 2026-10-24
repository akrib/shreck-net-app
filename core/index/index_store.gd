extends RefCounted
## Index SQLite dérivé des notes (jetable, reconstructible à tout moment).
## Les identifiants canoniques viennent des notes ; `fid` n'est qu'un numéro
## interne à l'index, jamais écrit dans une note ni exporté.

const TextNorm := preload("res://core/format/text_norm.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")

const INDEX_SCHEMA := 4
const BATCH := 400

var db: Object = null
var path := ""
var fts := false
var last_error := ""

const _TABLES := [
	"CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)",
	"CREATE TABLE files(fid INTEGER PRIMARY KEY, path TEXT UNIQUE, size INTEGER, mtime INTEGER, hash TEXT, name TEXT, name_key TEXT, name_fold TEXT, type TEXT, id TEXT, state TEXT, nb_err INTEGER, nb_warn INTEGER)",
	"CREATE INDEX files_id ON files(id)",
	"CREATE INDEX files_name_key ON files(name_key)",
	"CREATE INDEX files_type ON files(type)",
	"CREATE TABLE props(fid INTEGER, key TEXT, idx INTEGER, value TEXT)",
	"CREATE INDEX props_fid ON props(fid)",
	"CREATE TABLE aliases(fid INTEGER, alias TEXT, alias_key TEXT, alias_fold TEXT)",
	"CREATE INDEX aliases_fid ON aliases(fid)",
	"CREATE INDEX aliases_key ON aliases(alias_key)",
	"CREATE TABLE links(fid INTEGER, line INTEGER, target_key TEXT, target TEXT, sub TEXT, origin TEXT)",
	"CREATE INDEX links_fid ON links(fid)",
	"CREATE INDEX links_target ON links(target_key)",
	"CREATE TABLE elements(fid INTEGER, block TEXT, line INTEGER, kind TEXT, nature TEXT, cred INTEGER, relation TEXT, de_key TEXT, vers_key TEXT, text TEXT, text_fold TEXT, fields TEXT)",
	"CREATE INDEX elements_fid ON elements(fid)",
	"CREATE INDEX elements_block ON elements(block)",
	"CREATE INDEX elements_de ON elements(de_key)",
	"CREATE INDEX elements_vers ON elements(vers_key)",
	"CREATE INDEX props_key ON props(key, value)",
	"CREATE TABLE tasks(fid INTEGER, line INTEGER, done INTEGER, text TEXT)",
	"CREATE INDEX tasks_fid ON tasks(fid)",
	"CREATE TABLE problems(fid INTEGER, line INTEGER, level TEXT, message TEXT, origin TEXT)",
	"CREATE INDEX problems_fid ON problems(fid)",
	"CREATE TABLE attachments(path TEXT PRIMARY KEY, name_key TEXT)",
	"CREATE INDEX attachments_key ON attachments(name_key)",
]
const _CHILD_TABLES := ["props", "aliases", "links", "elements", "tasks"]


static func sqlite_available() -> bool:
	return ClassDB.class_exists("SQLite")


func open(db_path: String) -> bool:
	if not sqlite_available():
		last_error = "le module SQLite n'est pas disponible pour cette plateforme"
		return false
	path = db_path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(db_path.get_base_dir()))
	if not _open_raw():
		return false
	fts = db.compileoption_used("SQLITE_ENABLE_FTS5") == 1
	var wanted := INDEX_SCHEMA * 10 + (1 if fts else 0)
	if _scalar("PRAGMA user_version") != wanted:
		close()
		delete_files(db_path)
		if not _open_raw():
			return false
		_create_schema(wanted)
	return true


func _open_raw() -> bool:
	db = ClassDB.instantiate("SQLite")
	db.path = path
	db.default_extension = ""
	db.verbosity_level = 0
	if not db.open_db():
		last_error = "ouverture de l'index impossible : " + str(db.error_message)
		db = null
		return false
	db.query("PRAGMA busy_timeout=5000")
	db.query("PRAGMA journal_mode=WAL")
	db.query("PRAGMA synchronous=NORMAL")
	db.query("PRAGMA temp_store=MEMORY")
	return true


func _create_schema(version: int) -> void:
	db.query("BEGIN")
	for sql in _TABLES:
		db.query(sql)
	if fts:
		db.query("CREATE VIRTUAL TABLE search_fts USING fts5(title, body, tokenize = 'unicode61 remove_diacritics 2')")
	else:
		db.query("CREATE TABLE search_plain(fid INTEGER PRIMARY KEY, title_fold TEXT, body_fold TEXT)")
	db.query("PRAGMA user_version = %d" % version)
	db.query("COMMIT")


func close() -> void:
	if db != null:
		db.close_db()
		db = null


static func delete_files(db_path: String) -> void:
	for suffix in ["", "-wal", "-shm", "-journal"]:
		var p := ProjectSettings.globalize_path(db_path + suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _scalar(sql: String, params := []) -> Variant:
	if params.is_empty():
		db.query(sql)
	else:
		db.query_with_bindings(sql, params)
	var r: Array = db.query_result
	if r.is_empty():
		return null
	return r[0].values()[0]


func rows(sql: String, params := []) -> Array:
	if params.is_empty():
		db.query(sql)
	else:
		db.query_with_bindings(sql, params)
	return db.query_result


func exec(sql: String, params := []) -> bool:
	var ok: bool = db.query(sql) if params.is_empty() else db.query_with_bindings(sql, params)
	if not ok:
		last_error = str(db.error_message)
	return ok


## Insertion groupée : une requête pour plusieurs lignes (beaucoup plus rapide).
func _insert_many(table: String, columns: Array, values: Array) -> void:
	if values.is_empty():
		return
	var marks := PackedStringArray()
	for _c in columns:
		marks.append("?")
	var row_ph := "(" + ",".join(marks) + ")"
	var cols := ",".join(PackedStringArray(columns))
	var start := 0
	while start < values.size():
		var end := mini(start + BATCH, values.size())
		var params := []
		var phs := PackedStringArray()
		for k in range(start, end):
			params.append_array(values[k])
			phs.append(row_ph)
		exec("INSERT INTO %s(%s) VALUES %s" % [table, cols, ",".join(phs)], params)
		start = end


func begin() -> void:
	db.query("BEGIN")


func commit() -> void:
	db.query("COMMIT")


func rollback() -> void:
	db.query("ROLLBACK")


func meta_get(key: String, default := "") -> String:
	var v: Variant = _scalar("SELECT value FROM meta WHERE key = ?", [key])
	return default if v == null else str(v)


func meta_set(key: String, value: String) -> void:
	exec("INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?)", [key, value])


## path -> {size, mtime, hash, id}
func manifest() -> Dictionary:
	var out := {}
	for r in rows("SELECT path, size, mtime, hash, id FROM files"):
		out[r.path] = {"size": r.size, "mtime": r.mtime, "hash": r.hash,
			"id": "" if r.id == null else r.id}
	return out


func id_of(rel: String) -> String:
	var v: Variant = _scalar("SELECT id FROM files WHERE path = ?", [rel])
	return "" if v == null else str(v)


func update_stat(rel: String, size: int, mtime: int) -> void:
	exec("UPDATE files SET size = ?, mtime = ? WHERE path = ?", [size, mtime, rel])


func remove_path(rel: String) -> void:
	delete_fids(fids_of([rel]).values())


## path -> fid pour les chemins donnés (ceux absents de l'index sont omis).
func fids_of(paths: Array) -> Dictionary:
	var out := {}
	for start in range(0, paths.size(), BATCH):
		var chunk := paths.slice(start, start + BATCH)
		var marks := PackedStringArray()
		marks.resize(chunk.size())
		marks.fill("?")
		for r in rows("SELECT path, fid FROM files WHERE path IN (%s)" % ",".join(marks), chunk):
			out[r.path] = int(r.fid)
	return out


## Supprime de l'index toutes les lignes des notes données (une requête par table et par lot).
func delete_fids(fids: Array) -> void:
	for start in range(0, fids.size(), BATCH):
		var chunk := fids.slice(start, start + BATCH)
		var list := ",".join(PackedStringArray(chunk))
		for t in _CHILD_TABLES:
			exec("DELETE FROM %s WHERE fid IN (%s)" % [t, list])
		exec("DELETE FROM problems WHERE fid IN (%s)" % list)
		if fts:
			exec("DELETE FROM search_fts WHERE rowid IN (%s)" % list)
		else:
			exec("DELETE FROM search_plain WHERE fid IN (%s)" % list)
		exec("DELETE FROM files WHERE fid IN (%s)" % list)


## Indexe une seule note déjà lue (après un enregistrement dans l'application).
func index_note(rel: String, size: int, mtime: int, hash: String, doc: RefCounted, parsed: Dictionary) -> void:
	write_notes([{"rel": rel, "size": size, "mtime": mtime, "hash": hash,
		"prep": prepare(rel, doc, parsed, fts)}])


## Écrit un lot de notes préparées par prepare() : [{rel, size, mtime, hash, prep}].
## Les anciennes lignes de ces chemins sont retirées, puis chaque table reçoit
## ses lignes en quelques requêtes groupées.
func write_notes(items: Array) -> void:
	if items.is_empty():
		return
	var paths := []
	for it in items:
		paths.append(it.rel)
	delete_fids(fids_of(paths).values())
	var next_fid := int(_scalar("SELECT COALESCE(MAX(fid), 0) + 1 FROM files"))
	var t := {"files": [], "props": [], "aliases": [], "links": [], "elements": [], "tasks": [],
		"problems": [], "search": []}
	for it in items:
		var fid := next_fid
		next_fid += 1
		var pr: Dictionary = it.prep
		var row := [fid, it.rel, it.size, it.mtime, it.hash]
		row.append_array(pr.file)
		t.files.append(row)
		for k in ["props", "aliases", "links", "elements", "tasks", "problems"]:
			for r in pr[k]:
				var full := [fid]
				full.append_array(r)
				t[k].append(full)
		t.search.append([fid, pr.search[0], pr.search[1]])
	_insert_many("files", ["fid", "path", "size", "mtime", "hash", "name", "name_key", "name_fold", "type", "id", "state", "nb_err", "nb_warn"], t.files)
	_insert_many("props", ["fid", "key", "idx", "value"], t.props)
	_insert_many("aliases", ["fid", "alias", "alias_key", "alias_fold"], t.aliases)
	_insert_many("links", ["fid", "line", "target_key", "target", "sub", "origin"], t.links)
	_insert_many("elements", ["fid", "block", "line", "kind", "nature", "cred", "relation", "de_key", "vers_key", "text", "text_fold", "fields"], t.elements)
	_insert_many("tasks", ["fid", "line", "done", "text"], t.tasks)
	_insert_many("problems", ["fid", "line", "level", "message", "origin"], t.problems)
	if fts:
		_insert_many("search_fts", ["rowid", "title", "body"], t.search)
	else:
		_insert_many("search_plain", ["fid", "title_fold", "body_fold"], t.search)


## Calcule les lignes d'index d'une note, sans toucher à SQLite : utilisable
## depuis un fil de travail. `with_fts` : texte brut (FTS5) ou replié (recherche simple).
static func prepare(rel: String, doc: RefCounted, parsed: Dictionary, with_fts: bool) -> Dictionary:
	var props: Dictionary = doc.properties()
	var fm: Dictionary = doc.fm
	var state := "libre"
	if doc.unclosed or not doc.utf8_ok or (doc.has_frontmatter and not fm.ok):
		state = "illisible"
	elif doc.type_name() != "":
		state = "typee"
	var problems := []
	if not doc.utf8_ok:
		problems.append({"line": 0, "level": "ERREUR", "msg": "le fichier n'est pas en UTF-8 valide (lecture seule)"})
	if doc.unclosed:
		problems.append({"line": 1, "level": "ERREUR", "msg": "frontmatter non fermé (ligne « --- » finale manquante)"})
	for e in fm.get("errors", []):
		problems.append({"line": e.line + 2, "level": "ERREUR", "msg": e.msg})
	for w in fm.get("warnings", []):
		problems.append({"line": w.line + 2, "level": "AVERTISSEMENT", "msg": w.msg})
	if fm.get("has_comments", false):
		problems.append({"line": 2, "level": "INFO", "msg": "commentaires YAML : accord demandé avant réécriture des propriétés"})
	problems.append_array(parsed.problems)
	var nb_err := 0
	var nb_warn := 0
	var pb_rows := []
	for p in problems:
		if p.level == "ERREUR":
			nb_err += 1
		elif p.level == "AVERTISSEMENT":
			nb_warn += 1
		pb_rows.append([p.line, p.level, p.msg, "note"])
	var name := rel.get_file().get_basename()
	var nid: String = doc.note_id()
	var prop_rows := []
	var alias_rows := []
	var link_rows := []
	var seen_links := {}
	var search_parts := PackedStringArray()
	for key in fm.get("order", []):
		var v: Variant = props.get(key)
		var values: Array = v if typeof(v) == TYPE_ARRAY else [v]
		var idx := 0
		for x in values:
			var sx := "" if x == null else str(x)
			prop_rows.append([key, idx, sx])
			idx += 1
			if sx != "":
				search_parts.append(sx)
			for l in StructuredLines.links_in(sx):
				_add_link(link_rows, seen_links, int(fm.ranges[key][0]) + 2, l, "propriété " + key)
			if key == "aliases" and sx != "":
				alias_rows.append([sx, TextNorm.name_key(sx), TextNorm.fold(sx)])
	for l in parsed.links:
		_add_link(link_rows, seen_links, l.line, l, l.get("origin", "corps"))
	var el_rows := []
	for e in parsed.elements:
		el_rows.append(_element_row(e, "el"))
	for m in parsed.movements:
		el_rows.append(_element_row(m, "mv"))
	var task_rows := []
	for tk in parsed.tasks:
		task_rows.append([tk.line, 1 if tk.done else 0, tk.text])
	var text_all: String = " ".join(search_parts) + "\n" + str(doc.body_for_edit())
	return {
		"id": nid,
		"file": [name, TextNorm.name_key(name), TextNorm.fold(name), doc.type_name(), nid if nid != "" else null, state, nb_err, nb_warn],
		"props": prop_rows, "aliases": alias_rows, "links": link_rows, "elements": el_rows,
		"tasks": task_rows, "problems": pb_rows,
		"search": [name, text_all] if with_fts else [TextNorm.fold(name), TextNorm.fold(text_all)],
	}


## Un même lien n'est compté qu'une fois par ligne (texte + champ de/vers).
static func _add_link(out: Array, seen: Dictionary, line: int, l: Dictionary, origin: String) -> void:
	var key := TextNorm.name_key(l.target)
	var k := "%d|%s|%s" % [line, key, l.sub]
	if seen.has(k):
		return
	seen[k] = true
	out.append([line, key, l.target, l.sub, origin])


static func _element_row(e: Dictionary, kind: String) -> Array:
	var f: Dictionary = e.fields
	var cred: Variant = null
	if str(f.get("credibilite", "")).is_valid_int():
		cred = int(f.credibilite)
	return [e.block, e.line, kind, f.get("nature", f.get("mv", "")), cred, f.get("relation", ""),
		TextNorm.name_key(StructuredLines.link_target(f.get("de", ""))),
		TextNorm.name_key(StructuredLines.link_target(f.get("vers", ""))),
		e.text, TextNorm.fold(e.text), JSON.stringify(f, "", true)]


func replace_attachments(paths: Array) -> void:
	exec("DELETE FROM attachments")
	var r := []
	for p in paths:
		# Une note .md d'un dossier ignoré (Pieces…) se lie sans extension, comme dans Obsidian.
		var f := str(p).get_file()
		if f.to_lower().ends_with(".md"):
			f = f.substr(0, f.length() - 3)
		r.append([p, TextNorm.name_key(f)])
	_insert_many("attachments", ["path", "name_key"], r)


## Problèmes qui dépendent de plusieurs notes : identifiants et noms en double.
func recompute_global_problems() -> void:
	exec("DELETE FROM problems WHERE origin = 'global'")
	var out := []
	for r in rows("SELECT id, group_concat(path, ' | ' ORDER BY path) AS paths, group_concat(fid, ',' ORDER BY path) AS fids, count(*) AS n FROM files WHERE id IS NOT NULL GROUP BY id HAVING n > 1"):
		for f in str(r.fids).split(","):
			out.append([int(f), 0, "ERREUR", "identifiant %s en double (%s)" % [r.id, r.paths], "global"])
	for r in rows("SELECT group_concat(path, ' | ' ORDER BY path) AS paths, group_concat(fid, ',' ORDER BY path) AS fids, count(*) AS n FROM files GROUP BY name_key HAVING n > 1"):
		for f in str(r.fids).split(","):
			out.append([int(f), 0, "ERREUR", "nom de note en double (%s)" % r.paths, "global"])
	for r in rows("SELECT e.block, group_concat(f.path, ' | ' ORDER BY f.path) AS paths, group_concat(e.fid, ',' ORDER BY f.path) AS fids, count(*) AS n FROM elements e JOIN files f ON f.fid = e.fid WHERE e.block != '' GROUP BY e.block HAVING n > 1"):
		for f in str(r.fids).split(","):
			out.append([int(f), 0, "ERREUR", "identifiant ^%s en double (%s)" % [r.block, r.paths], "global"])
	_insert_many("problems", ["fid", "line", "level", "message", "origin"], out)


const _BROKEN := "FROM links l JOIN files f ON f.fid = l.fid WHERE l.target_key != '' AND NOT EXISTS (SELECT 1 FROM files g WHERE g.name_key = l.target_key) AND NOT EXISTS (SELECT 1 FROM attachments a WHERE a.name_key = l.target_key)"


func broken_link_count() -> int:
	return int(_scalar("SELECT count(*) " + _BROKEN))


func broken_links(limit := 100) -> Array:
	return rows("SELECT f.path, l.line, l.target " + _BROKEN + " ORDER BY f.path, l.line LIMIT ?", [limit])


func stats() -> Dictionary:
	var s := {"types": {}, "files": 0, "elements": 0, "movements": 0, "links": 0, "tasks_open": 0,
		"errors": 0, "warnings": 0, "fts": fts}
	for r in rows("SELECT CASE WHEN type = '' THEN '(libre)' ELSE type END AS t, count(*) AS n FROM files GROUP BY t ORDER BY t"):
		s.types[r.t] = r.n
		s.files += r.n
	s.elements = int(_scalar("SELECT count(*) FROM elements WHERE kind = 'el'"))
	s.movements = int(_scalar("SELECT count(*) FROM elements WHERE kind = 'mv'"))
	s.links = int(_scalar("SELECT count(*) FROM links"))
	s.tasks_open = int(_scalar("SELECT count(*) FROM tasks WHERE done = 0"))
	s.errors = int(_scalar("SELECT count(*) FROM problems WHERE level = 'ERREUR'"))
	s.warnings = int(_scalar("SELECT count(*) FROM problems WHERE level = 'AVERTISSEMENT'"))
	return s


func problems(limit := 200) -> Array:
	return rows("SELECT f.path, p.line, p.level, p.message FROM problems p JOIN files f ON f.fid = p.fid WHERE p.level != 'INFO' ORDER BY CASE p.level WHEN 'ERREUR' THEN 0 ELSE 1 END, f.path, p.line LIMIT ?", [limit])


func problems_of(rel: String) -> Array:
	return rows("SELECT p.line, p.level, p.message FROM problems p JOIN files f ON f.fid = p.fid WHERE f.path = ? ORDER BY p.line", [rel])


func list_by_type(type_name: String, limit := 200, newest_first := false) -> Array:
	# du plus récent au plus ancien : les noms datés d'abord, puis les autres par ordre alphabétique
	var order := "(name_key GLOB '[0-9]*') DESC, CASE WHEN name_key GLOB '[0-9]*' THEN name_key END DESC, name_key" if newest_first else "name_key"
	if type_name == "":
		return rows("SELECT path, name, type FROM files ORDER BY %s LIMIT ?" % order, [limit])
	return rows("SELECT path, name, type FROM files WHERE type = ? ORDER BY %s LIMIT ?" % order, [type_name, limit])


## Quelques propriétés de plusieurs notes d'un coup : {path: {clé: valeur ou liste}}.
func props_for(paths: Array, keys: Array) -> Dictionary:
	var out := {}
	if paths.is_empty() or keys.is_empty():
		return out
	if paths.size() > 400:  # pas trop de paramètres par requête SQLite
		for i in range(0, paths.size(), 400):
			out.merge(props_for(paths.slice(i, i + 400), keys))
		return out
	var params := []
	var qk := PackedStringArray()
	for k in keys:
		qk.append("?")
		params.append(str(k))
	var qp := PackedStringArray()
	for p in paths:
		qp.append("?")
		params.append(str(p))
	for r in rows("SELECT f.path, p.key, p.idx, p.value FROM props p JOIN files f ON f.fid = p.fid WHERE p.key IN (%s) AND f.path IN (%s) ORDER BY f.path, p.key, p.idx" % [",".join(qk), ",".join(qp)], params):
		var d: Dictionary = out.get(str(r.path), {})
		if d.has(r.key):
			if typeof(d[r.key]) != TYPE_ARRAY:
				d[r.key] = [d[r.key]]
			d[r.key].append(r.value)
		else:
			d[r.key] = r.value
		out[str(r.path)] = d
	return out


func path_of_name(name: String) -> String:
	var v: Variant = _scalar("SELECT path FROM files WHERE name_key = ? LIMIT 1", [TextNorm.name_key(name)])
	return "" if v == null else str(v)


func backlinks(name: String, limit := 100) -> Array:
	return rows("SELECT DISTINCT f.path, f.name, f.type FROM links l JOIN files f ON f.fid = l.fid WHERE l.target_key = ? ORDER BY f.name_key LIMIT ?",
		[TextNorm.name_key(name), limit])


static func words_of(q: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for ch in TextNorm.fold(q):
		if ch.to_upper() != ch.to_lower() or "0123456789".contains(ch):
			cur += ch
		else:
			if cur != "":
				out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	return out


## Recherche dans les noms, alias, propriétés et textes. Renvoie [{path, name, type, extrait}].
func search(q: String, limit := 50, type_filter := "") -> Array:
	var words := words_of(q)
	if words.is_empty():
		return []
	var tf := ""
	var params := []
	var qf := TextNorm.fold(q.strip_edges())
	var qprefix := qf.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
	if fts:
		var parts := PackedStringArray()
		for w in words:
			parts.append("\"" + w.replace("\"", "\"\"") + "\"*")
		params.append(" ".join(parts))
		if type_filter != "":
			tf = " AND f.type = ?"
			params.append(type_filter)
		# le nom exact, puis les noms qui commencent par la recherche, puis la pertinence
		params.append(qf)
		params.append(qprefix)
		params.append(limit)
		return rows("SELECT f.path, f.name, f.type, snippet(search_fts, 1, '«', '»', '…', 10) AS extrait FROM search_fts JOIN files f ON f.fid = search_fts.rowid WHERE search_fts MATCH ?" + tf + " ORDER BY (f.name_fold = ?) DESC, (f.name_fold LIKE ? ESCAPE '\\') DESC, bm25(search_fts, 10.0, 1.0) LIMIT ?", params)
	var conds := PackedStringArray()
	var first := ""
	for w in words:
		var pat := "%" + w.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
		if first == "":
			first = pat
		conds.append("(s.title_fold LIKE ? ESCAPE '\\' OR s.body_fold LIKE ? ESCAPE '\\')")
		params.append(pat)
		params.append(pat)
	if type_filter != "":
		tf = " AND f.type = ?"
		params.append(type_filter)
	# rang : nom exact, nom qui commence par la recherche, nom ou alias qui la contient, texte
	params.push_front(first)
	params.push_front(qprefix)
	params.push_front(qf)
	params.append(limit)
	return rows("SELECT f.path, f.name, f.type, '' AS extrait, CASE WHEN f.name_fold = ? THEN 0 WHEN f.name_fold LIKE ? ESCAPE '\\' THEN 1 WHEN s.title_fold LIKE ? ESCAPE '\\' THEN 2 ELSE 3 END AS r FROM search_plain s JOIN files f ON f.fid = s.fid WHERE " + " AND ".join(conds) + tf + " ORDER BY r, f.name_key LIMIT ?", params)


# ------------------------------------------------------------------ requêtes de l'interface

static func _like(q: String) -> String:
	return "%" + TextNorm.fold(q.strip_edges()).replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


static func _type_filter(types: Array, params: Array) -> String:
	if types.is_empty():
		return ""
	var marks := PackedStringArray()
	for t in types:
		marks.append("?")
		params.append(str(t))
	return " AND f.type IN (%s)" % ",".join(marks)


static func _nature_filter(natures: Array, params: Array) -> String:
	if natures.is_empty():
		return ""
	var marks := PackedStringArray()
	for n in natures:
		marks.append("?")
		params.append(str(n))
	# Une note sans propriété « nature » reste proposée (notes faites à la main).
	return " AND (NOT EXISTS (SELECT 1 FROM props WHERE fid = f.fid AND key = 'nature' AND value != '') OR EXISTS (SELECT 1 FROM props WHERE fid = f.fid AND key = 'nature' AND value IN (%s)))" % ",".join(marks)


## Notes dont le nom ou un alias contient `q` (sans accents ni majuscules).
## Sans texte : les notes les plus récemment modifiées. Renvoie [{path, name, type}].
## `natures` : restreint aux notes de ces natures (ex. clan, lignee).
func find_notes(q: String, types: Array = [], limit := 40, natures: Array = []) -> Array:
	var params := []
	if q.strip_edges() == "":
		var tf := _type_filter(types, params) + _nature_filter(natures, params)
		params.append(limit)
		var order := " ORDER BY f.name_key" if not natures.is_empty() else " ORDER BY f.mtime DESC, f.name_key"
		return rows("SELECT f.path, f.name, f.type FROM files f WHERE 1=1" + tf + order + " LIMIT ?", params)
	var pat := _like(q)
	var start := pat.substr(1)
	params.append_array([start, pat, pat])
	var tf2 := _type_filter(types, params) + _nature_filter(natures, params)
	params.append(limit)
	return rows("SELECT f.path, f.name, f.type, CASE WHEN f.name_fold LIKE ? ESCAPE '\\' THEN 0 ELSE 1 END AS r FROM files f WHERE (f.name_fold LIKE ? ESCAPE '\\' OR f.fid IN (SELECT fid FROM aliases WHERE alias_fold LIKE ? ESCAPE '\\'))" + tf2 + " ORDER BY r, f.name_key LIMIT ?", params)


## Éléments dont l'énoncé contient `q`. Renvoie [{path, name, block, text, nature, cred}].
func find_elements(q: String, limit := 40) -> Array:
	if q.strip_edges() == "":
		return rows("SELECT f.path, f.name, e.block, e.text, e.nature, e.cred FROM elements e JOIN files f ON f.fid = e.fid WHERE e.kind = 'el' AND e.block != '' ORDER BY f.mtime DESC, e.line LIMIT ?", [limit])
	return rows("SELECT f.path, f.name, e.block, e.text, e.nature, e.cred FROM elements e JOIN files f ON f.fid = e.fid WHERE e.kind = 'el' AND e.block != '' AND e.text_fold LIKE ? ESCAPE '\\' ORDER BY f.mtime DESC, e.line LIMIT ?", [_like(q), limit])


## Notes d'un type avec certaines propriétés : [{path, name, type, mtime, props: {clé: texte ou [textes]}}].
func notes_with_props(type_name: String, keys: Array) -> Array:
	var params := [type_name]
	var marks := PackedStringArray()
	for k in keys:
		marks.append("?")
		params.append(str(k))
	var q := "SELECT f.fid, f.path, f.name, f.type, f.mtime, p.key, p.idx, p.value FROM files f LEFT JOIN props p ON p.fid = f.fid AND p.key IN (%s) WHERE f.type = ? ORDER BY f.name_key, p.key, p.idx" % ",".join(marks)
	params.push_back(params.pop_front())
	var out := []
	var by_fid := {}
	for r in rows(q, params):
		var fid := int(r.fid)
		if not by_fid.has(fid):
			by_fid[fid] = {"path": r.path, "name": r.name, "type": r.type, "mtime": r.mtime, "props": {}}
			out.append(by_fid[fid])
		if r.key == null:
			continue
		var pr: Dictionary = by_fid[fid].props
		if pr.has(r.key):
			if typeof(pr[r.key]) != TYPE_ARRAY:
				pr[r.key] = [pr[r.key]]
			pr[r.key].append(r.value)
		else:
			pr[r.key] = r.value
	return out


## Propriétés d'une note (valeurs texte ; listes pour les clés à plusieurs valeurs).
func props_of(rel: String) -> Dictionary:
	var out := {}
	for r in rows("SELECT p.key, p.idx, p.value FROM props p JOIN files f ON f.fid = p.fid WHERE f.path = ? ORDER BY p.key, p.idx", [rel]):
		if out.has(r.key):
			if typeof(out[r.key]) != TYPE_ARRAY:
				out[r.key] = [out[r.key]]
			out[r.key].append(r.value)
		else:
			out[r.key] = r.value
	return out


## Nombre de notes rapides encore à traiter (statut absent ou différent de « traitee »).
func quick_notes_todo_count() -> int:
	return int(_scalar("SELECT count(*) FROM files f WHERE f.type = 'en_cours' AND NOT EXISTS (SELECT 1 FROM props p WHERE p.fid = f.fid AND p.key = 'statut' AND p.value = 'traitee')"))


func quick_notes_todo(limit := 100) -> Array:
	return rows("SELECT f.path, f.name, f.type FROM files f WHERE f.type = 'en_cours' AND NOT EXISTS (SELECT 1 FROM props p WHERE p.fid = f.fid AND p.key = 'statut' AND p.value = 'traitee') ORDER BY f.name_key DESC LIMIT ?", [limit])


func recent_notes(limit := 10) -> Array:
	return rows("SELECT path, name, type, mtime FROM files ORDER BY mtime DESC, name_key LIMIT ?", [limit])


## Valeurs déjà utilisées pour une propriété texte (suggestions des formulaires).
func distinct_values(key: String, type_name := "", limit := 60) -> Array:
	var out := []
	var q := "SELECT DISTINCT p.value AS v FROM props p JOIN files f ON f.fid = p.fid WHERE p.key = ? AND p.value != ''"
	var params := [key]
	if type_name != "":
		q += " AND f.type = ?"
		params.append(type_name)
	params.append(limit)
	for r in rows(q + " ORDER BY p.value LIMIT ?", params):
		out.append(str(r.v))
	return out


## Notes qui pointent vers `name` depuis certaines propriétés : [{path, name, type, origin}].
func linked_from(name: String, prop_keys: Array) -> Array:
	var origins := PackedStringArray()
	var params := [TextNorm.name_key(name)]
	for k in prop_keys:
		origins.append("?")
		params.append("propriété " + str(k))
	return rows("SELECT DISTINCT f.path, f.name, f.type, l.origin FROM links l JOIN files f ON f.fid = l.fid WHERE l.target_key = ? AND l.origin IN (%s) ORDER BY f.name_key" % ",".join(origins), params)


## Éléments décrivant une relation où `name` est d'un côté ou de l'autre.
func relations_of(name: String, limit := 200) -> Array:
	var k := TextNorm.name_key(name)
	return rows("SELECT f.path, f.name AS note, f.type, e.block, e.text, e.relation, e.de_key, e.vers_key, e.cred, e.nature, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE e.relation != '' AND (e.de_key = ? OR e.vers_key = ?) ORDER BY f.name_key DESC LIMIT ?", [k, k, limit])


## Éléments « était présent à » qui visent `name` (une soirée, un lieu…), où qu'ils soient notés.
func presences_reported(name: String, limit := 2000) -> Array:
	return rows("SELECT f.path, f.name AS note, f.type, e.block, e.text, e.cred, e.nature, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE e.relation = 'present_a' AND e.vers_key = ? ORDER BY f.name_key LIMIT ?", [TextNorm.name_key(name), limit])


## Éléments qui citent `name` dans leur énoncé (via les liens du corps).
func elements_mentioning(name: String, limit := 200) -> Array:
	return rows("SELECT DISTINCT f.path, f.name AS note, f.type, e.block, e.text, e.nature, e.cred, e.fields FROM links l JOIN elements e ON e.fid = l.fid AND e.line = l.line JOIN files f ON f.fid = l.fid WHERE l.target_key = ? AND e.kind = 'el' ORDER BY f.name_key DESC LIMIT ?", [TextNorm.name_key(name), limit])


## Éléments d'une note, dans l'ordre des lignes : [{block, line, text, nature, cred, fields}].
func elements_of(rel: String) -> Array:
	return rows("SELECT e.block, e.line, e.text, e.nature, e.cred, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE f.path = ? AND e.kind = 'el' ORDER BY e.line", [rel])


## Pour chaque fiche citée : nombre de notes qui la citent (rétroliens, sans
## elle-même) et nombre d'éléments qui la citent. {name_key: [rétroliens, éléments]}.
func mention_counts() -> Dictionary:
	var out := {}
	for r in rows("SELECT l.target_key AS k, COUNT(DISTINCT l.fid) AS n FROM links l JOIN files f ON f.fid = l.fid WHERE f.name_key != l.target_key GROUP BY l.target_key"):
		out[str(r.k)] = [int(r.n), 0]
	for r in rows("SELECT l.target_key AS k, COUNT(DISTINCT e.fid || ':' || e.line) AS n FROM links l JOIN elements e ON e.fid = l.fid AND e.line = l.line AND e.kind = 'el' GROUP BY l.target_key"):
		var k := str(r.k)
		if not out.has(k):
			out[k] = [0, 0]
		out[k][1] = int(r.n)
	return out


## Disciplines constatées dans des éléments, par fiche citée : [{k, fields}].
func discipline_mentions() -> Array:
	return rows("SELECT DISTINCT l.target_key AS k, e.fields FROM links l JOIN elements e ON e.fid = l.fid AND e.line = l.line WHERE e.kind = 'el' AND e.fields LIKE '%\"discipline\"%'")


## Tous les éléments, avec leur note : [{fid, path, note, type, block, text, nature, cred, fields}].
func all_elements() -> Array:
	return rows("SELECT e.fid, f.path, f.name AS note, f.type, e.block, e.text, e.nature, e.cred, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE e.kind = 'el'")


## Quelques propriétés de toutes les notes qui en ont : {fid: {clé: valeur}} (première valeur).
func props_by_fid(keys: Array) -> Dictionary:
	var out := {}
	var marks := PackedStringArray()
	for k in keys:
		marks.append("?")
	for r in rows("SELECT fid, key, value FROM props WHERE key IN (%s) AND idx = 0" % ",".join(marks), keys):
		var d: Dictionary = out.get(int(r.fid), {})
		d[str(r.key)] = r.value
		out[int(r.fid)] = d
	return out


## Liens d'une note vers des éléments ([[Note#^el-…]]), dans l'ordre des lignes :
## [{target, sub, line, origin}].
func element_links_of(rel: String) -> Array:
	return rows("SELECT l.target, l.sub, l.line, l.origin FROM links l JOIN files f ON f.fid = l.fid WHERE f.path = ? AND l.sub LIKE '%el-%' ORDER BY l.line", [rel])


## Élément visé par [[Note#^bloc]] : {path, note, type, block, line, text, nature, cred, fields} ou {}.
func element_by_ref(note_name: String, block: String) -> Dictionary:
	var r := rows("SELECT f.path, f.name AS note, f.type, e.block, e.line, e.text, e.nature, e.cred, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE f.name_key = ? AND e.block = ? LIMIT 1", [TextNorm.name_key(note_name), block])
	return r[0] if not r.is_empty() else {}


## Toutes les notes : name_key -> {name, type, path} (pour le graphe).
func all_names() -> Dictionary:
	var out := {}
	for r in rows("SELECT name, name_key, type, path FROM files"):
		out[str(r.name_key)] = {"name": str(r.name), "type": str(r.type), "path": str(r.path)}
	return out


## Tous les éléments qui décrivent une relation.
## Noms partagés entre deux fiches de personnage : l'alias de l'une est le nom ou
## l'alias de l'autre. [{a_name, a_path, b_name, b_path, alias}].
func alias_collisions(limit := 2000) -> Array:
	return rows("SELECT f1.name AS a_name, f1.path AS a_path, f2.name AS b_name, f2.path AS b_path, al.alias AS alias FROM aliases al JOIN files f1 ON f1.fid = al.fid JOIN files f2 ON f2.name_key = al.alias_key AND f2.fid != f1.fid WHERE f1.type = 'personnage' AND f2.type = 'personnage' UNION SELECT f1.name, f1.path, f2.name, f2.path, a1.alias FROM aliases a1 JOIN aliases a2 ON a1.alias_key = a2.alias_key AND a1.fid < a2.fid JOIN files f1 ON f1.fid = a1.fid JOIN files f2 ON f2.fid = a2.fid WHERE f1.type = 'personnage' AND f2.type = 'personnage' LIMIT ?", [limit])


func all_relations(limit := 20000) -> Array:
	return rows("SELECT f.path, f.name AS note, f.type, e.block, e.text, e.relation, e.de_key, e.vers_key, e.cred, e.nature, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE e.relation != '' AND e.de_key != '' AND e.vers_key != '' LIMIT ?", [limit])


## Éléments d'une relation donnée (« sire_de »…), où qu'ils soient notés.
func relations_by_code(code: String, limit := 20000) -> Array:
	return rows("SELECT f.path, f.name AS note, f.type, e.block, e.text, e.relation, e.de_key, e.vers_key, e.cred, e.nature, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE e.relation = ? AND e.de_key != '' AND e.vers_key != '' ORDER BY f.name_key LIMIT ?", [code, limit])


## Présences notées dans les soirées : [{soiree, path, date, domaine, target_key, target, origin}].
func all_presences(limit := 50000) -> Array:
	return rows("SELECT f.name AS soiree, f.path, (SELECT value FROM props WHERE fid = f.fid AND key = 'date' LIMIT 1) AS date, (SELECT value FROM props WHERE fid = f.fid AND key = 'domaine' LIMIT 1) AS domaine, l.target_key, l.target, l.origin FROM links l JOIN files f ON f.fid = l.fid WHERE f.type = 'soiree' AND l.origin IN ('propriété presents', 'propriété presents_incertains') LIMIT ?", [limit])


## Éléments où une discipline a été constatée ([discipline:: [[…]]]).
func elements_with_discipline(limit := 2000) -> Array:
	return rows("SELECT f.path, f.name AS note, f.type, e.block, e.text, e.nature, e.cred, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE e.kind = 'el' AND e.fields LIKE '%\"discipline\"%' ORDER BY f.name_key DESC LIMIT ?", [limit])


## Tous les éléments ayant une date des faits (pour la chronologie).
func elements_with_dates(limit := 5000) -> Array:
	return rows("SELECT f.path, f.name AS note, f.type, e.block, e.text, e.nature, e.cred, e.fields, (SELECT value FROM props WHERE fid = f.fid AND key = 'domaine' LIMIT 1) AS domaine FROM elements e JOIN files f ON f.fid = e.fid WHERE e.kind = 'el' AND e.fields LIKE '%date_faits%' LIMIT ?", [limit])


## Notes datées (date ou date_floue), avec leur domaine : [{path, name, type, date, date_floue, domaine}].
func dated_notes(limit := 5000) -> Array:
	return rows("SELECT f.path, f.name, f.type, (SELECT value FROM props WHERE fid = f.fid AND key = 'date' LIMIT 1) AS date, (SELECT value FROM props WHERE fid = f.fid AND key = 'date_floue' LIMIT 1) AS date_floue, (SELECT value FROM props WHERE fid = f.fid AND key = 'domaine' LIMIT 1) AS domaine FROM files f WHERE f.type != '' AND EXISTS (SELECT 1 FROM props WHERE fid = f.fid AND key IN ('date', 'date_floue') AND value != '') LIMIT ?", [limit])


## Tâches ouvertes avec le domaine de leur note : [{path, name, type, line, text, domaine}].
func open_tasks(limit := 500) -> Array:
	return rows("SELECT f.path, f.name, f.type, t.line, t.text, (SELECT value FROM props WHERE fid = f.fid AND key = 'domaine' LIMIT 1) AS domaine FROM tasks t JOIN files f ON f.fid = t.fid WHERE t.done = 0 ORDER BY f.name_key, t.line LIMIT ?", [limit])


## Empreinte du contenu de l'index, pour vérifier qu'une reconstruction donne
## exactement le même résultat (dates de fichier et numéros internes exclus).
func fingerprint() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for chunk in _fingerprint_chunks():
		ctx.update(chunk.to_utf8_buffer())
	return ctx.finish().hex_encode()


## Contenu lisible utilisé par fingerprint() (pour comparer deux index).
func dump_text() -> String:
	return "".join(_fingerprint_chunks())


func _fingerprint_chunks() -> PackedStringArray:
	var out := PackedStringArray()
	var queries := [
		"SELECT path, size, hash, name, name_key, type, id, state, nb_err, nb_warn FROM files ORDER BY path",
		"SELECT f.path, p.key, p.idx, p.value FROM props p JOIN files f USING(fid) ORDER BY f.path, p.key, p.idx",
		"SELECT f.path, a.alias FROM aliases a JOIN files f USING(fid) ORDER BY f.path, a.alias",
		"SELECT f.path, l.line, l.target_key, l.sub, l.origin FROM links l JOIN files f USING(fid) ORDER BY f.path, l.line, l.target_key, l.sub, l.origin",
		"SELECT f.path, e.block, e.line, e.kind, e.nature, e.cred, e.relation, e.de_key, e.vers_key, e.text, e.fields FROM elements e JOIN files f USING(fid) ORDER BY f.path, e.line",
		"SELECT f.path, t.line, t.done, t.text FROM tasks t JOIN files f USING(fid) ORDER BY f.path, t.line",
		"SELECT f.path, p.line, p.level, p.message, p.origin FROM problems p JOIN files f USING(fid) ORDER BY f.path, p.line, p.level, p.message",
		"SELECT path, name_key FROM attachments ORDER BY path",
	]
	for q in queries:
		var buf := PackedStringArray()
		for r in rows(q):
			buf.append(JSON.stringify(r.values()))
		out.append("\n".join(buf) + "\n#\n")
	# Texte de recherche : lu par pages et résumé par une empreinte par note
	# (évite de charger tout le texte du coffre en mémoire d'un coup).
	var sq := "SELECT f.path AS p, s.title AS a, s.body AS b FROM search_fts s JOIN files f ON f.fid = s.rowid" if fts \
		else "SELECT f.path AS p, s.title_fold AS a, s.body_fold AS b FROM search_plain s JOIN files f ON f.fid = s.fid"
	var sbuf := PackedStringArray()
	var last := ""
	while true:
		var page := rows(sq + " WHERE f.path > ? ORDER BY f.path LIMIT 500", [last])
		if page.is_empty():
			break
		for r in page:
			sbuf.append("%s\t%s" % [r.p, (str(r.a) + "\n" + str(r.b)).sha256_text()])
		last = str(page[-1].p)
	out.append("\n".join(sbuf) + "\n#\n")
	return out
