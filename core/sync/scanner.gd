extends RefCounted
## Synchronisation incrémentale coffre -> index (architecture §5 « Détection »).
##  - date inchangée (et assez ancienne) : fichier ignoré ;
##  - sinon lecture + empreinte SHA-256 : si identique, seule la date est mise à jour ;
##  - sinon nouvelle analyse et réindexation de ce seul fichier ;
##  - chemin disparu + nouveau chemin avec le même id : renommage ;
##  - chemin disparu seul : retiré de l'index (le disque n'est jamais modifié).
## Le listage est séquentiel (sous Android, Godot sérialise ces accès) ; les
## dates, les lectures, les analyses et la préparation des lignes d'index se
## font en parallèle ; l'écriture dans SQLite est séquentielle, groupée par
## lots, dans une seule transaction : une interruption laisse l'index précédent intact.

const NoteDocument := preload("res://core/format/note_document.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const RepoAccess := preload("res://core/storage/repo_access.gd")
const Parallel := preload("res://core/app/parallel.gd")
const IndexStore := preload("res://core/index/index_store.gd")

## Marge pour les dates de fichier à la seconde (même règle que Git).
const RACY_SECONDS := 2
const BATCH := 160

var repo: RefCounted
var index: RefCounted
var progress := Callable()   ## progress.call(fait, total, phase)
var _fts := false


func _init(p_repo: RefCounted, p_index: RefCounted) -> void:
	repo = p_repo
	index = p_index


func _progress(done: int, total: int, phase: String) -> void:
	if progress.is_valid():
		progress.call(done, total, phase)


## Lecture + empreinte + analyse + préparation des lignes d'index d'un fichier.
## Exécutée dans un fil de travail : ne touche ni à SQLite ni à l'interface.
func _load(item: Array) -> Dictionary:
	var rel: String = item[0]
	var rb: Dictionary = repo.read_bytes(rel)
	var r := {"rel": rel, "mtime": item[1], "error": rb.error, "size": rb.bytes.size(), "hash": "",
		"prep": null}
	if rb.error != OK:
		return r
	r.hash = RepoAccess.hash_bytes(rb.bytes)
	if r.hash == item[2]:
		return r  # contenu identique : pas besoin d'analyser
	var doc = NoteDocument.new()
	doc.load_bytes(rb.bytes)
	var parsed := StructuredLines.parse_body(doc.body, doc.body_first_line)
	r.prep = IndexStore.prepare(rel, doc, parsed, _fts)
	return r


func _read_error(r: Dictionary) -> String:
	if DirAccess.dir_exists_absolute(repo.abs_path(r.rel)):
		return "%s : c'est un dossier dont le nom finit par .md ; renommez-le pour que son contenu soit indexé" % r.rel
	return "%s : %s" % [r.rel, error_string(r.error)]


func scan() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	_fts = index.fts
	var report := {"files": 0, "new": 0, "modified": 0, "deleted": 0, "renamed": [],
		"unchanged": 0, "rehashed_same": 0, "read_errors": [], "list_errors": [],
		"ms_list": 0, "ms_stat": 0, "ms_load": 0, "ms_db": 0, "ms_index": 0, "ms_total": 0, "bytes_read": 0,
		"workers": Parallel.workers()}
	_progress(0, 0, "liste des fichiers")
	var listing: Dictionary = repo.list_files()
	report.list_errors = listing.errors
	var paths: Array = listing.md
	report.files = paths.size()
	report.ms_list = Time.get_ticks_msec() - t0
	var manifest: Dictionary = index.manifest()
	var last_scan := int(index.meta_get("last_scan", "0"))
	var scan_start := int(Time.get_unix_time_from_system())
	# 1. dates de modification, en parallèle (sur Android, cet appel n'est pas
	#    sérialisé par Godot, contrairement au listage et à la lecture)
	_progress(0, paths.size(), "dates")
	var t1 := Time.get_ticks_msec()
	var mtimes := Parallel.map(paths, func(rel: String) -> int: return repo.mtime(rel))
	report.ms_stat = Time.get_ticks_msec() - t1
	var to_read := []
	for i in paths.size():
		var rel: String = paths[i]
		var mt: int = mtimes[i]
		var m: Variant = manifest.get(rel)
		if m != null and int(m.mtime) == mt and mt < last_scan - RACY_SECONDS:
			report.unchanged += 1
			continue
		to_read.append([rel, mt, "" if m == null else str(m.hash)])
	# 2. lecture, analyse et préparation en parallèle, par lots ;
	#    écriture SQLite séquentielle, groupée par lot
	index.meta_set("dirty", "1")
	index.begin()
	var new_items := []  # [rel, id]
	var done := 0
	for b in range(0, to_read.size(), BATCH):
		var batch := to_read.slice(b, b + BATCH)
		var tl := Time.get_ticks_usec()
		var results := Parallel.map(batch, _load)
		var td := Time.get_ticks_usec()
		report.ms_load += (td - tl) / 1000.0
		var writes := []
		for r in results:
			done += 1
			if r.error != OK:
				report.read_errors.append(_read_error(r))
				continue
			report.bytes_read += r.size
			var m: Variant = manifest.get(r.rel)
			if r.prep == null:
				index.update_stat(r.rel, r.size, r.mtime)
				report.unchanged += 1
				report.rehashed_same += 1
				continue
			writes.append(r)
			if m != null:
				report.modified += 1
			else:
				new_items.append([r.rel, str(r.prep.id)])
		index.write_notes(writes)
		report.ms_db += (Time.get_ticks_usec() - td) / 1000.0
		_progress(done, to_read.size(), "analyse")
	# 3. suppressions et renommages
	var seen := {}
	for rel in paths:
		seen[rel] = true
	var gone := []
	for rel in manifest:
		if not seen.has(rel):
			gone.append(rel)
	var gone_by_id := {}
	for rel in gone:
		var gid: String = manifest[rel].id
		if gid != "":
			gone_by_id[gid] = rel
	for it in new_items:
		var nid: String = it[1]
		if nid != "" and gone_by_id.has(nid):
			report.renamed.append([gone_by_id[nid], it[0]])
			gone_by_id.erase(nid)
		else:
			report.new += 1
	if not gone.is_empty():
		var gone_fids: Dictionary = index.fids_of(gone)
		index.delete_fids(gone_fids.values())
	report.deleted = gone.size() - report.renamed.size()
	_progress(0, 0, "contrôles")
	# Rien n'a changé ? On évite les contrôles globaux (coûteux sur téléphone).
	var att_sig := ("\n".join(PackedStringArray(listing.other))).sha256_text()
	var changed: bool = report.modified + report.deleted + new_items.size() > 0
	if att_sig != index.meta_get("attachments_sig", ""):
		index.replace_attachments(listing.other)
		index.meta_set("attachments_sig", att_sig)
		changed = true
	if changed or index.meta_get("global_ok", "") != "1":
		index.recompute_global_problems()
		index.meta_set("global_ok", "1")
	index.meta_set("last_scan", str(scan_start))
	index.meta_set("dirty", "0")
	index.commit()
	report.ms_total = Time.get_ticks_msec() - t0
	report.ms_index = report.ms_total - report.ms_list - report.ms_stat
	return report


## Réindexe un seul fichier (après un enregistrement dans l'application).
func reindex_one(rel: String) -> String:
	_fts = index.fts
	if not repo.exists(rel):
		index.begin()
		index.remove_path(rel)
		index.recompute_global_problems()
		index.commit()
		return ""
	var r := _load([rel, repo.mtime(rel), ""])
	if r.error != OK:
		return error_string(r.error)
	index.begin()
	index.write_notes([r])
	index.recompute_global_problems()
	index.commit()
	return ""


## Vérification complète : chaque fichier relu (en parallèle) et comparé à l'index.
func verify() -> Dictionary:
	var r := {"checked": 0, "hash_mismatch": [], "missing_in_index": [], "missing_on_disk": []}
	var listing: Dictionary = repo.list_files()
	var manifest: Dictionary = index.manifest()
	var hashes := Parallel.map(listing.md, func(rel: String) -> String:
		var rb: Dictionary = repo.read_bytes(rel)
		return RepoAccess.hash_bytes(rb.bytes) if rb.error == OK else "")
	for i in listing.md.size():
		var rel: String = listing.md[i]
		r.checked += 1
		if not manifest.has(rel):
			r.missing_in_index.append(rel)
		elif hashes[i] != manifest[rel].hash:
			r.hash_mismatch.append(rel)
	var on_disk := {}
	for rel in listing.md:
		on_disk[rel] = true
	for rel in manifest:
		if not on_disk.has(rel):
			r.missing_on_disk.append(rel)
	return r
