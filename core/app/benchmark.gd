extends RefCounted
## Mesures de performance sur un dossier de banc (jamais sur le coffre).
## Les durées affichées sont MESURÉES sur l'appareil qui exécute le banc.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const SafeWriter := preload("res://core/storage/safe_writer.gd")
const NoteDocument := preload("res://core/format/note_document.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const Ids := preload("res://core/format/ids.gd")
const Parallel := preload("res://core/app/parallel.gd")


static func run(bench_root: String, db_path: String, progress := Callable()) -> Dictionary:
	var out := {"lines": PackedStringArray(), "ok": false}
	var lines: PackedStringArray = out.lines
	var mem0 := OS.get_static_memory_usage()
	lines.append("Banc Nosferatu — %s — %s %s" % [Time.get_datetime_string_from_system(),
		OS.get_name(), OS.get_model_name()])
	var repo = RepoAccess.new(bench_root)
	IndexStore.delete_files(db_path)
	var index = IndexStore.new()
	if not index.open(db_path):
		lines.append("ERREUR : " + index.last_error)
		return out
	lines.append("Recherche plein texte FTS5 : " + ("oui" if index.fts else "non (recherche simple)"))
	var sc = Scanner.new(repo, index)
	sc.progress = progress
	# 1. indexation complète
	var r1: Dictionary = sc.scan()
	lines.append("Fils de travail : %d" % r1.workers)
	lines.append("Indexation complète : %d fichiers, %.1f Mo lus, %d ms (listage %d ms, dates %d ms, lecture+analyse %d ms, écriture de l'index %d ms)" % [
		r1.files, r1.bytes_read / 1048576.0, r1.ms_total, r1.ms_list, r1.ms_stat, r1.ms_load, r1.ms_db])
	# 2. resynchronisation sans changement
	var r2: Dictionary = sc.scan()
	lines.append("Resynchronisation sans changement, juste après : %d ms (%d fichiers récents relus par prudence)" % [
		r2.ms_total, r2.rehashed_same])
	var r2b: Dictionary = sc.scan()
	lines.append("Resynchronisation sans changement (cas courant) : %d ms (listage %d ms, dates %d ms, %d fichiers relus)" % [
		r2b.ms_total, r2b.ms_list, r2b.ms_stat, r2b.rehashed_same])
	# 3. un enregistrement dans l'application
	var listing: Dictionary = repo.list_files()
	var target := ""
	for rel in listing.md:
		if str(rel).begins_with("Sources/"):
			target = rel
			break
	if target != "":
		var t0 := Time.get_ticks_msec()
		var rb: Dictionary = repo.read_bytes(target)
		var doc = NoteDocument.from_bytes(rb.bytes)
		var line := "- Ajout de test du banc. [nature:: observe] [credibilite:: 2] ^" + Ids.generate("el")
		doc.set_body(StructuredLines.append_to_section(doc.body_for_edit(), "Éléments", line))
		var w = SafeWriter.new(repo).write(target, doc.to_bytes(), RepoAccess.hash_bytes(rb.bytes))
		var t1 := Time.get_ticks_msec()
		sc.reindex_one(target)
		var t2 := Time.get_ticks_msec()
		lines.append("Enregistrement sûr d'une note : %d ms (%s) ; réindexation : %d ms" % [
			t1 - t0, "vérifié" if w.ok else "ÉCHEC " + str(w.error), t2 - t1])
		var r3: Dictionary = sc.scan()
		lines.append("Resynchronisation après 1 modification : %d ms" % r3.ms_total)
	# 4. recherches
	var queries := ["nuit", "elysee", "Victor", "faveur sang", "Mélisande Lescure", "zzzzzz"]
	for q in queries:
		var t0 := Time.get_ticks_msec()
		var res: Array = index.search(q, 50)
		lines.append("Recherche « %s » : %d résultats, %d ms" % [q, res.size(), Time.get_ticks_msec() - t0])
	# 5. statistiques
	var s: Dictionary = index.stats()
	lines.append("Index : %d notes, %d éléments, %d mouvements, %d liens, %d erreurs, %d avertissements" % [
		s.files, s.elements, s.movements, s.links, s.errors, s.warnings])
	var t5 := Time.get_ticks_msec()
	var broken: int = index.broken_link_count()
	lines.append("Liens cassés : %d (calcul : %d ms)" % [broken, Time.get_ticks_msec() - t5])
	# 6. détail des accès fichiers sur cet appareil (sert à choisir les réglages)
	lines.append("— Détail des accès fichiers —")
	_details(repo, index.fts, lines, progress)
	index.close()
	var db_size := FileAccess.get_size(ProjectSettings.globalize_path(db_path))
	lines.append("Taille de l'index : %.1f Mo" % (db_size / 1048576.0))
	lines.append("Mémoire statique : %.1f Mo (variation pendant le banc : %+.1f Mo)" % [
		OS.get_static_memory_usage() / 1048576.0, (OS.get_static_memory_usage() - mem0) / 1048576.0])
	out.ok = true
	return out


static func _details(repo: RefCounted, fts: bool, lines: PackedStringArray, progress: Callable) -> void:
	if progress.is_valid():
		progress.call(0, 0, "détail des accès")
	var t := Time.get_ticks_msec()
	var l_new: Dictionary = repo.list_files()
	var ms_new := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	var old_md := []
	_legacy_walk(repo, "", old_md)
	var ms_old := Time.get_ticks_msec() - t
	old_md.sort()
	lines.append("Listage : %d ms (méthode 0.4) ; ancienne méthode 0.3, sans parallélisme : %d ms ; même liste de notes : %s" % [
		ms_new, ms_old, "oui" if old_md == l_new.md else "NON (%d contre %d)" % [l_new.md.size(), old_md.size()]])
	var sample: Array = l_new.md.slice(0, 2000)
	var n := sample.size()
	var mt := func(rel: String) -> int: return repo.mtime(rel)
	t = Time.get_ticks_msec()
	Parallel.map(sample, mt, 1)
	var d1 := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	Parallel.map(sample, mt)
	var dn := Time.get_ticks_msec() - t
	lines.append("Dates de %d fichiers : %d ms sur 1 fil, %d ms sur %d fils" % [n, d1, dn, Parallel.workers()])
	var rd := func(rel: String) -> PackedByteArray: return repo.read_bytes(rel).bytes
	t = Time.get_ticks_msec()
	var blobs: Array = Parallel.map(sample, rd, 1)
	var r1 := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	Parallel.map(sample, rd)
	var rn := Time.get_ticks_msec() - t
	lines.append("Lecture de %d fichiers : %d ms sur 1 fil, %d ms sur %d fils" % [n, r1, rn, Parallel.workers()])
	var parse := func(b: PackedByteArray) -> int:
		var doc = NoteDocument.new()
		doc.load_bytes(b)
		var parsed := StructuredLines.parse_body(doc.body, doc.body_first_line)
		return IndexStore.prepare("x.md", doc, parsed, fts).props.size()
	t = Time.get_ticks_msec()
	Parallel.map(blobs, parse, 1)
	var p1 := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	Parallel.map(blobs, parse)
	var pn := Time.get_ticks_msec() - t
	lines.append("Analyse de %d notes (en mémoire) : %d ms sur 1 fil, %d ms sur %d fils" % [n, p1, pn, Parallel.workers()])


## Listage tel que fait jusqu'à la 0.3 (pour comparaison sur l'appareil).
static func _legacy_walk(repo: RefCounted, rel_dir: String, out: Array) -> void:
	var d := DirAccess.open(repo.root if rel_dir == "" else repo.abs_path(rel_dir))
	if d == null:
		return
	d.include_hidden = false
	d.include_navigational = false
	var prefix := "" if rel_dir == "" else rel_dir + "/"
	for f in d.get_files():
		if f.to_lower().ends_with(".md") and not f.begins_with("."):
			out.append(prefix + f)
	for sub in d.get_directories():
		if sub in RepoAccess.ALWAYS_IGNORED or sub.begins_with("."):
			continue
		if rel_dir == "" and sub in repo.ignored_top:
			continue
		_legacy_walk(repo, prefix + sub, out)
