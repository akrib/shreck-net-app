extends Node
## Façade unique entre l'interface et le cœur. L'interface n'appelle que ce
## service ; elle ne lit ni n'écrit jamais de fichier elle-même.

signal repo_checked(check: Dictionary)
signal job_started(job: String)
signal job_progress(text: String)
signal job_finished(job: String, result: Dictionary)
signal log_line(text: String)
signal notes_changed   ## une note a été créée ou enregistrée depuis l'application

const RepoAccess := preload("res://core/storage/repo_access.gd")
const SafeWriter := preload("res://core/storage/safe_writer.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const NoteDocument := preload("res://core/format/note_document.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const Synthetic := preload("res://core/app/synthetic.gd")
const Benchmark := preload("res://core/app/benchmark.gd")
const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Ids := preload("res://core/format/ids.gd")
const Exporter := preload("res://core/exchange/exporter.gd")
const LotImporter := preload("res://core/exchange/lot_importer.gd")
const Fusion := preload("res://core/app/fusion.gd")
const Alerts := preload("res://core/analysis/alerts.gd")
const Contradictions := preload("res://core/analysis/contradictions.gd")
const Hypotheses := preload("res://core/analysis/hypotheses.gd")
const Trash := preload("res://core/storage/trash.gd")

## Fichier des réglages. Les outils de test le redirigent avant de créer
## l'application, pour ne jamais toucher aux réglages réels.
static var settings_file := "user://reglages.cfg"
const VERSION := "0.16 (statistiques)"

var settings := ConfigFile.new()
var repo: RefCounted = null          ## RepoAccess, ou null si non configuré
var index: RefCounted = null         ## IndexStore pour les lectures (fil principal)
var last_check := {}
var last_report := {}
var index_needs_repair := false
var journal := PackedStringArray()

var _thread: Thread = null
var _job := ""
var _sync_again := false
## Faux dans les tests : les synchronisations se font tout de suite, sans fil de fond.
var background_jobs := true


func _ready() -> void:
	settings.load(settings_file)
	_log("Nosferatu Intelligence — %s — Godot %s — %s" % [VERSION,
		Engine.get_version_info().string, OS.get_name()])
	if not IndexStore.sqlite_available():
		_log("ERREUR : module SQLite indisponible sur cette plateforme.")


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
	if index != null:
		index.close()


func save_settings() -> void:
	settings.save(settings_file)


func _log(t: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), t]
	journal.append(line)
	if journal.size() > 400:
		journal = journal.slice(journal.size() - 400)
	print(line)
	log_line.emit(line)


# ------------------------------------------------------------------ réglages

func repo_path() -> String:
	return str(settings.get_value("coffre", "chemin", ""))


func bench_path() -> String:
	var def := OS.get_user_data_dir() + "/banc"
	return str(settings.get_value("banc", "chemin", def))


func set_bench_path(p: String) -> void:
	settings.set_value("banc", "chemin", p.strip_edges())
	save_settings()


## Enregistre le chemin du coffre, le vérifie et lance une synchronisation.
## Ne crée, ne déplace et ne supprime aucune note.
func set_repo_path(p: String) -> Dictionary:
	settings.set_value("coffre", "chemin", p.strip_edges())
	save_settings()
	return open_repo()


func open_repo() -> Dictionary:
	var p := repo_path()
	if index != null:
		index.close()
		index = null
	repo = null
	if p == "":
		last_check = {"error": "aucun dossier configuré"}
		repo_checked.emit(last_check)
		return last_check
	var r = RepoAccess.new(p)
	last_check = r.check()
	if last_check.readable:
		repo = r
		Schema.load_vocab(r.config)
		if last_check.writable:
			for note in SafeWriter.new(repo).recover():
				_log("Reprise après interruption : " + note)
		_open_read_index()
		_log("Coffre : %s" % p)
	else:
		_log("Coffre inaccessible : %s" % last_check.error)
	repo_checked.emit(last_check)
	return last_check


func db_path() -> String:
	return "user://index/%s.sqlite" % repo_path().sha256_text().substr(0, 16)


func _open_read_index() -> void:
	if index != null:
		index.close()
	index = IndexStore.new()
	if not index.open(db_path()):
		_log("ERREUR index : " + index.last_error)
		index = null


func add_tmp_to_gitignore() -> void:
	if repo != null:
		var err: Error = repo.add_tmp_to_gitignore()
		_log("Ajout de .nosferatu/tmp/ au .gitignore : " + error_string(err))
		open_repo()


# ------------------------------------------------------------------ tâches de fond

func busy() -> bool:
	return _thread != null


func _start(job: String, fn: Callable) -> bool:
	if _thread != null:
		_log("Une tâche est déjà en cours (%s)." % _job)
		return false
	_job = job
	_thread = Thread.new()
	job_started.emit(job)
	_thread.start(func(): _finish.call_deferred(fn.call()))
	return true


func _finish(result: Dictionary) -> void:
	_thread.wait_to_finish()
	_thread = null
	var job := _job
	_job = ""
	if job in ["synchronisation", "reconstruction"]:
		last_report = result
		index_needs_repair = false
		_open_read_index()
	job_finished.emit(job, result)
	if _sync_again and repo != null:
		_sync_again = false
		start_sync()


func _progress_cb() -> Callable:
	return func(done: int, total: int, phase: String):
		var t := "%s %d/%d" % [phase, done, total] if total > 0 else phase
		job_progress.emit.call_deferred(t)


func start_sync() -> bool:
	if repo == null:
		return false
	var root: String = repo.root
	var dbp := db_path()
	var cb := _progress_cb()
	return _start("synchronisation", func() -> Dictionary:
		var r = RepoAccess.new(root)
		var idx = IndexStore.new()
		if not idx.open(dbp):
			return {"error": idx.last_error}
		var sc = Scanner.new(r, idx)
		sc.progress = cb
		var rep: Dictionary = sc.scan()
		idx.close()
		return rep)


## Supprime l'index et le reconstruit entièrement depuis les notes.
func start_rebuild() -> bool:
	if repo == null or busy():
		return false
	if index != null:
		index.close()
		index = null
	IndexStore.delete_files(db_path())
	_log("Index supprimé : reconstruction complète depuis les notes.")
	return start_sync()


## Vérifie que les fichiers correspondent à l'index, puis qu'une reconstruction
## dans une base séparée donne exactement le même contenu.
func start_verify() -> bool:
	if repo == null:
		return false
	var root: String = repo.root
	var dbp := db_path()
	var cb := _progress_cb()
	return _start("vérification", func() -> Dictionary:
		var r = RepoAccess.new(root)
		var idx = IndexStore.new()
		if not idx.open(dbp):
			return {"error": idx.last_error}
		var sc = Scanner.new(r, idx)
		sc.progress = cb
		sc.scan()
		var t0 := Time.get_ticks_msec()
		var v: Dictionary = sc.verify()
		var fp1: String = idx.fingerprint()
		idx.close()
		var tmp_db := "user://index/verification.sqlite"
		IndexStore.delete_files(tmp_db)
		var idx2 = IndexStore.new()
		idx2.open(tmp_db)
		var sc2 = Scanner.new(r, idx2)
		sc2.scan()
		var fp2: String = idx2.fingerprint()
		idx2.close()
		IndexStore.delete_files(tmp_db)
		v["fingerprint_current"] = fp1
		v["fingerprint_rebuilt"] = fp2
		v["rebuild_identical"] = fp1 == fp2
		v["ms"] = Time.get_ticks_msec() - t0
		return v)


func start_bench_generate(path: String, scale: float) -> bool:
	var problem := Synthetic.check_target(path, repo_path())
	if problem != "":
		_log("Banc : " + problem)
		return false
	set_bench_path(path)
	var cb := _progress_cb()
	return _start("génération du banc", func() -> Dictionary:
		var g = Synthetic.new()
		return g.generate(path, scale, 42, cb))


func start_bench_run(path: String) -> bool:
	var problem := Synthetic.check_target(path, repo_path())
	if problem != "":
		_log("Banc : " + problem)
		return false
	if not FileAccess.file_exists(path.trim_suffix("/") + "/" + Synthetic.MARKER):
		_log("Banc : générez d'abord le jeu de données dans ce dossier.")
		return false
	var cb := _progress_cb()
	return _start("mesures", func() -> Dictionary:
		return Benchmark.run(path, "user://index/banc.sqlite", cb))


# ------------------------------------------------------------------ notes

## Lit une note. Renvoie {ok, doc, hash, parsed, error}.
func read_note(rel: String) -> Dictionary:
	if repo == null:
		return {"ok": false, "error": "coffre non configuré"}
	var rb: Dictionary = repo.read_bytes(rel)
	if rb.error != OK:
		return {"ok": false, "error": error_string(rb.error)}
	var doc = NoteDocument.from_bytes(rb.bytes)
	return {"ok": true, "doc": doc, "hash": RepoAccess.hash_bytes(rb.bytes),
		"parsed": StructuredLines.parse_body(doc.body, doc.body_first_line)}


## Enregistre une note : écriture sûre d'abord, index ensuite.
## Renvoie {ok, conflict, error, hash, index_ok}.
func save_note(rel: String, doc: RefCounted, expected_hash: String) -> Dictionary:
	if not doc.utf8_ok:
		return {"ok": false, "conflict": false, "error": "fichier non UTF-8 : lecture seule"}
	var w: Dictionary = SafeWriter.new(repo).write(rel, doc.to_bytes(), expected_hash)
	if not w.ok:
		_log("Enregistrement refusé (%s) : %s" % [rel, w.error])
		return w
	_log("Enregistré et vérifié : " + rel)
	w["index_ok"] = true
	if busy():
		_sync_again = true
		_log("Index mis à jour à la fin de la tâche en cours.")
	elif index != null:
		var err: String = Scanner.new(repo, index).reindex_one(rel)
		if err != "":
			index_needs_repair = true
			w.index_ok = false
			_log("Markdown enregistré, mais index à réparer : " + err)
	clear_draft(rel)
	notes_changed.emit()
	return w


# ------------------------------------------------------------------ création de notes

## Contexte des valeurs préremplies (dernier domaine, dernière nature de source…).
func schema_ctx() -> Dictionary:
	return {"last_domaine": str(settings.get_value("saisie", "domaine", settings.get_value("soiree", "domaine", ""))),
		"last_source_nature": str(settings.get_value("saisie", "source_nature", "note")),
		"now": Time.get_datetime_dict_from_system()}


func _remember(type_name: String, v: Dictionary) -> void:
	var dom := Schema.link_name(v.get("domaine", ""))
	if dom != "":
		settings.set_value("saisie", "domaine", dom)
	if type_name == "source" and str(v.get("nature", "")) != "":
		settings.set_value("saisie", "source_nature", str(v.nature))
	save_settings()


## Nom libre dans tout le coffre (les noms de notes y sont uniques) : « (2) », « (3) »… si besoin.
func _unique_name(name: String, folder: String) -> String:
	var n := name
	var k := 2
	while (index != null and index.path_of_name(n) != "") or repo.exists(folder + "/" + n + ".md"):
		n = "%s (%d)" % [name, k]
		k += 1
	return n


func _reindex(rels: Array) -> void:
	if index != null and not busy():
		var sc = Scanner.new(repo, index)
		for r in rels:
			if sc.reindex_one(r) != "":
				index_needs_repair = true
	else:
		# Une synchronisation tourne déjà : on en relance une juste après elle.
		_sync_again = true


## Crée une note à partir d'un formulaire (champs de Schema.FIELDS).
## `text` : texte repris (d'une note rapide), placé dans la section principale.
## `from_quick` : chemin de la note rapide d'origine, marquée « traitée » ensuite.
## N'écrase jamais rien. Renvoie {ok, rel, name, error}.
func create_note(type_name: String, values: Dictionary, text := "", from_quick := "") -> Dictionary:
	if repo == null:
		return {"ok": false, "error": "coffre non configuré"}
	if not Schema.TYPES.has(type_name):
		return {"ok": false, "error": "type inconnu : " + type_name}
	var v := values.duplicate()
	var df := str(v.get("date_floue", "")).strip_edges()
	if RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(df) and str(v.get("date", "")) == "":
		v["date"] = df  # une date exacte va dans « date » (FORMAT §7)
		v.erase("date_floue")
	var problems := Schema.check(type_name, v)
	if not problems.is_empty():
		return {"ok": false, "error": " ; ".join(problems)}
	var now := Time.get_datetime_dict_from_system()
	var name := Schema.build_name(type_name, v, now)
	if name == "":
		return {"ok": false, "error": "le nom de la note est vide"}
	var folder := Schema.folder(type_name, v, now)
	name = _unique_name(name, folder)
	var rel := folder + "/" + name + ".md"
	var fm := Schema.build_frontmatter(type_name, v, Ids.generate(Schema.TYPES[type_name].prefix))
	var body_text := text.strip_edges()
	if from_quick != "" and body_text != "":
		body_text += "\n\n*Repris de la note rapide [[%s]].*" % from_quick.get_file().get_basename()
	var content := "---\n" + "\n".join(fm) + "\n---\n" + Schema.build_body(type_name, name, v, body_text, now)
	var w: Dictionary = SafeWriter.new(repo).write(rel, content.to_utf8_buffer(), "")
	if not w.ok:
		_log("Création refusée (%s) : %s" % [rel, w.error])
		return {"ok": false, "error": w.error}
	_log("Note créée : " + rel)
	_remember(type_name, v)
	_reindex([rel])
	notes_changed.emit()
	var out := {"ok": true, "rel": rel, "name": name}
	if from_quick != "":
		var m := mark_quick_done(from_quick, name)
		if not m.ok:
			out["warning"] = "note créée, mais la note rapide n'a pas pu être marquée traitée : " + str(m.error)
	return out


## Note rapide : créée tout de suite, avec la date et le dernier domaine.
func create_quick_note() -> Dictionary:
	return create_note("en_cours", Schema.defaults("en_cours", schema_ctx()))


## Fiche minimale créée depuis un sélecteur (« Créer la fiche … »).
func create_stub(type_name: String, name: String, nature := "") -> Dictionary:
	var v := Schema.defaults(type_name, schema_ctx())
	v["nom"] = name
	if nature != "" and (Schema.TYPES[type_name].fields as Array).has("nature"):
		v["nature"] = nature
	return create_note(type_name, v)


## Marque une note rapide « traitée » et ajoute le lien vers la note créée.
func mark_quick_done(rel: String, new_name := "") -> Dictionary:
	var r := read_note(rel)
	if not r.ok:
		return {"ok": false, "error": r.error}
	var doc: RefCounted = r.doc
	if not doc.can_edit_properties():
		return {"ok": false, "error": "propriétés non modifiables"}
	var changes := {"statut": "traitee"}
	if new_name != "":
		var dev: Variant = doc.properties().get("devenue", [])
		var lst: Array = (dev if typeof(dev) == TYPE_ARRAY else ([] if dev == null or str(dev) == "" else [dev])).duplicate()
		lst.append("[[%s]]" % new_name)
		changes["devenue"] = lst
	var err: String = doc.set_properties(changes)
	if err != "":
		return {"ok": false, "error": err}
	return save_note(rel, doc, r.hash)


## Soirée du jour déjà créée pour ce domaine ("" sinon ; domaine vide = n'importe lequel).
func today_soiree(domaine := "") -> String:
	if index == null:
		return ""
	var d := Time.get_date_dict_from_system()
	var today := "%04d-%02d-%02d" % [d.year, d.month, d.day]
	for n in index.notes_with_props("soiree", ["date", "domaine"]):
		if str(n.props.get("date", "")) == today and (domaine == "" or
				Schema.link_name(n.props.get("domaine", "")).to_lower() == domaine.to_lower()):
			return n.path
	return ""


## Coche ou décoche une tâche « - [ ] » (ligne du fichier, 1 = première). Vérifie
## que la ligne est bien celle attendue avant d'écrire.
func set_task_done(rel: String, line: int, expected_text: String, done: bool) -> Dictionary:
	var r := read_note(rel)
	if not r.ok:
		return {"ok": false, "error": r.error}
	var doc: RefCounted = r.doc
	var lines: PackedStringArray = doc.body_for_edit().split("\n")
	var k: int = line - doc.body_first_line
	if k < 0 or k >= lines.size() or lines[k].strip_edges() != expected_text.strip_edges():
		return {"ok": false, "error": "la note a changé : resynchronisez puis réessayez"}
	var l: String = lines[k]
	var m := RegEx.create_from_string("^(\\s*[-*+]\\s+)\\[[ xX]\\]").search(l)
	if m == null:
		return {"ok": false, "error": "cette ligne n'est pas une tâche"}
	lines[k] = m.get_string(1) + ("[x]" if done else "[ ]") + l.substr(m.get_end())
	doc.set_body("\n".join(lines))
	return save_note(rel, doc, r.hash)


# ------------------------------------------------------------------ modifications ciblées

## Change des propriétés d'une note (relue juste avant). Renvoie le résultat de save_note.
func set_note_properties(rel: String, changes: Dictionary) -> Dictionary:
	var r := read_note(rel)
	if not r.ok:
		return {"ok": false, "error": r.error}
	var doc: RefCounted = r.doc
	var err: String = doc.set_properties(changes, {"date": "date"} if changes.has("date") else {})
	if err != "":
		return {"ok": false, "error": err}
	return save_note(rel, doc, r.hash)


## Modifie des champs d'un élément ([clé:: valeur]) dans sa note. L'élément est
## retrouvé par son identifiant de bloc ou, faute d'identifiant, par son numéro
## de ligne et son énoncé (rien n'est écrit si la note a changé entre-temps).
func update_element(rel: String, block: String, line: int, expected_text: String, changes: Dictionary) -> Dictionary:
	var r := read_note(rel)
	if not r.ok:
		return {"ok": false, "error": r.error}
	var doc: RefCounted = r.doc
	var target := {}
	for e in r.parsed.elements:
		if (block != "" and str(e.block) == block) or (block == "" and int(e.line) == line and str(e.text) == expected_text):
			target = e
			break
	if target.is_empty():
		return {"ok": false, "error": "élément introuvable : la note a changé, resynchronisez puis réessayez"}
	var lines: PackedStringArray = doc.body_for_edit().split("\n")
	var k: int = int(target.line) - doc.body_first_line
	if k < 0 or k >= lines.size():
		return {"ok": false, "error": "élément introuvable"}
	var l := lines[k]
	for key in changes:
		l = StructuredLines.set_line_field(l, str(key), str(changes[key]))
	if l == lines[k]:
		return {"ok": true, "unchanged": true}
	lines[k] = l
	doc.set_body("\n".join(lines))
	return save_note(rel, doc, r.hash)


## Ajoute une ligne d'élément à la section « ## Éléments » d'une note.
func append_element(rel: String, item_line: String) -> Dictionary:
	var r := read_note(rel)
	if not r.ok:
		return {"ok": false, "error": r.error}
	var doc: RefCounted = r.doc
	doc.set_body(StructuredLines.append_to_section(doc.body_for_edit(), "Éléments", item_line))
	return save_note(rel, doc, r.hash)


# ------------------------------------------------------------------ alertes

## Alertes du jour (échéances, faveurs en retard, sanctions, personnes surveillées).
func alerts() -> Array:
	if index == null:
		return []
	var d := Time.get_date_dict_from_system()
	var seen := {}
	if settings.has_section("surveillance"):
		for k in settings.get_section_keys("surveillance"):
			var v: Variant = JSON.parse_string(str(settings.get_value("surveillance", k, "{}")))
			if typeof(v) == TYPE_DICTIONARY:
				seen[k] = v
	return Alerts.build(index, repo.config if repo != null else {}, "%04d-%02d-%02d" % [d.year, d.month, d.day], seen)


## Les éléments qui citent cette personne surveillée sont lus : seuls les
## suivants feront une alerte (réglage local, propre à cet ordinateur).
func mark_seen(name: String) -> void:
	if index == null:
		return
	var keys := Alerts.mentions(index, name).map(func(e): return str(e.key))
	settings.set_value("surveillance", name, JSON.stringify({"t": int(Time.get_unix_time_from_system()), "k": keys}))
	save_settings()


# ------------------------------------------------------------------ hypothèses concurrentes

## Jugement d'un élément `ref` ([[Note#^el-…]]) face à une hypothèse (un indice
## du dossier) : "pour" (cohérent), "contre" (incohérent), "" (pas jugé).
## Écrit dans les propriétés `pour` et `contre` de l'indice.
func set_hypothesis_cell(indice_rel: String, ref: String, value: String) -> Dictionary:
	var r := read_note(indice_rel)
	if not r.ok:
		return {"ok": false, "error": r.error}
	var props: Dictionary = r.doc.properties()
	var want := Hypotheses.parse_ref(ref)
	var same := func(x: Variant) -> bool:
		var nb := Hypotheses.parse_ref(x)
		return TextNorm.name_key(nb[0]) == TextNorm.name_key(want[0]) and nb[1] == want[1]
	var lists := {}
	for side in ["pour", "contre"]:
		var v: Variant = props.get(side, [])
		var l: Array = (v if typeof(v) == TYPE_ARRAY else ([] if v == null or str(v) == "" else [v])).duplicate()
		lists[side] = l.filter(func(x): return not same.call(x))
	if value in ["pour", "contre"]:
		lists[value].append(Hypotheses.ref_of(want[0], want[1]))
	return set_note_properties(indice_rel, lists)


## Nouvelle hypothèse pour un dossier : un indice (non vérifié, crédibilité 6,
## mêmes sujets que le dossier), ajouté à la propriété `indices` du dossier.
## Renvoie {ok, error, rel}.
func add_hypothesis(dossier_rel: String, enonce: String) -> Dictionary:
	var dp: Dictionary = index.props_of(dossier_rel) if index != null else {}
	var values := {"enonce": enonce, "statut": "non_verifie", "credibilite": 6}
	var sujets: Variant = dp.get("sujets", [])
	values["sujets"] = sujets if typeof(sujets) == TYPE_ARRAY else ([] if sujets == null or str(sujets) == "" else [sujets])
	var c := create_note("indice", values)
	if not c.ok:
		return c
	var r := read_note(dossier_rel)
	if not r.ok:
		return {"ok": false, "error": "hypothèse créée (%s), mais dossier illisible : %s" % [c.rel, r.error], "rel": c.rel}
	var v: Variant = r.doc.properties().get("indices", [])
	var l: Array = (v if typeof(v) == TYPE_ARRAY else ([] if v == null or str(v) == "" else [v])).duplicate()
	l.append("[[%s]]" % str(c.rel).get_file().get_basename())
	var w := set_note_properties(dossier_rel, {"indices": l})
	if not w.ok:
		return {"ok": false, "error": "hypothèse créée (%s), mais pas ajoutée au dossier : %s" % [c.rel, w.error], "rel": c.rel}
	return {"ok": true, "error": "", "rel": c.rel}


## Un élément à examiner dans un dossier, même pas encore jugé : une ligne
## « - [[Note#^el-…]] » dans la section « Éléments examinés » du dossier.
func add_examined_element(dossier_rel: String, ref: String) -> Dictionary:
	var r := read_note(dossier_rel)
	if not r.ok:
		return {"ok": false, "error": r.error}
	var doc: RefCounted = r.doc
	doc.set_body(StructuredLines.append_to_section(doc.body_for_edit(), "Éléments examinés", "- " + ref))
	return save_note(dossier_rel, doc, r.hash)


# ------------------------------------------------------------------ contradictions

## Contradictions à trancher (rien n'est écrit), sans celles écartées sur cet ordinateur.
func contradictions(include_dismissed := false) -> Array:
	if index == null:
		return []
	var all: Array = Contradictions.build(index)
	if include_dismissed:
		return all
	var gone := dismissed_contradictions()
	return all.filter(func(c): return not gone.has(str(c.key)))


## Clés des contradictions écartées (« ce n'en est pas une ») : réglage local.
func dismissed_contradictions() -> Dictionary:
	var out := {}
	if settings.has_section("contradictions_ecartees"):
		for k in settings.get_section_keys("contradictions_ecartees"):
			out[k] = true
	return out


func dismiss_contradiction(key: String) -> void:
	settings.set_value("contradictions_ecartees", key, int(Time.get_unix_time_from_system()))
	save_settings()


func restore_contradictions() -> void:
	if settings.has_section("contradictions_ecartees"):
		settings.erase_section("contradictions_ecartees")
		save_settings()


## Prépare la fusion de la fiche `old_name` dans `keep_name` (rien n'est écrit).
func merge_plan(old_name: String, keep_name: String) -> Dictionary:
	if index == null or repo == null:
		return {"ok": false, "error": "coffre non ouvert"}
	var d := Time.get_date_dict_from_system()
	return Fusion.plan(index, read_note, old_name, keep_name, "%04d-%02d-%02d" % [d.year, d.month, d.day])


## Applique une fusion préparée par merge_plan(). Chaque note est écrite de façon
## sûre, avec contrôle de conflit ; à la première note modifiée ailleurs entre-temps,
## tout s'arrête (les notes déjà écrites sont listées). Renvoie {ok, done, error}.
func merge_notes(plan: Dictionary) -> Dictionary:
	if not plan.get("ok", false):
		return {"ok": false, "done": [], "error": str(plan.get("error", "fusion non préparée"))}
	var done := []
	var writer = SafeWriter.new(repo)
	for w in plan.writes:
		var r: Dictionary = writer.write(str(w.rel), w.bytes, str(w.hash))
		if not r.ok:
			_log("Fusion interrompue (%s) : %s" % [w.rel, r.error])
			_reindex(done)
			notes_changed.emit()
			return {"ok": false, "done": done, "error": "%s : %s" % [w.rel, r.error]}
		done.append(str(w.rel))
	_log("Fusion : « %s » reprise dans « %s » (%d note(s) écrites)" % [str(plan.old_rel).get_file().get_basename(),
		str(plan.keep_rel).get_file().get_basename(), done.size()])
	_reindex(done)
	notes_changed.emit()
	return {"ok": true, "done": done, "error": ""}


## Attribue un identifiant aux éléments et mouvements qui n'en ont pas (FORMAT §5).
## Renvoie {ok, added, error}.
func assign_missing_ids(rel: String) -> Dictionary:
	var r := read_note(rel)
	if not r.ok:
		return {"ok": false, "error": r.error, "added": 0}
	var doc: RefCounted = r.doc
	var a: Dictionary = StructuredLines.assign_missing_ids(doc.body_for_edit(), func(p: String) -> String: return Ids.generate(p))
	if int(a.added) == 0:
		return {"ok": true, "added": 0}
	doc.set_body(a.body)
	var w := save_note(rel, doc, r.hash)
	w["added"] = a.added
	return w


# ------------------------------------------------------------------ échanges avec Claude

## Prépare un export (sans rien écrire). Renvoie {text, notes, annuaire, truncated, chars, paths}.
func export_preview(scope: String, subject: String, label: String) -> Dictionary:
	if index == null or repo == null:
		return {"error": "coffre non ouvert"}
	var paths: Array = Exporter.select(index, scope, subject)
	var r: Dictionary = Exporter.build(index, paths, label, func(p: String) -> String:
		return repo.read_bytes(p).bytes.get_string_from_utf8())
	r["paths"] = paths
	return r


## Range un export dans `_Export/` (fichier .txt, jamais indexé). Renvoie {ok, rel, error}.
func export_save(text: String, label: String) -> Dictionary:
	var rel := "_Export/" + Exporter.file_name(label)
	var w: Dictionary = SafeWriter.new(repo).write(rel, text.to_utf8_buffer(), "")
	_log(("Export enregistré : " + rel) if w.ok else ("Export non enregistré : " + str(w.error)))
	return {"ok": w.ok, "rel": rel, "error": w.error}


func list_lots() -> Array:
	return LotImporter.list_lots(repo) if repo != null else []


func analyse_lot(lot_rel: String) -> Dictionary:
	return LotImporter.analyse(repo, index, lot_rel)


## Intègre les notes acceptées d'un lot, puis resynchronise.
func import_lot(lot_rel: String, items: Array) -> Dictionary:
	var r: Dictionary = LotImporter.import_items(repo, lot_rel, items)
	_log("Lot %s : %d note(s) intégrée(s), %d refusée(s)" % [lot_rel, r.done.size(), r.failed.size()])
	if not r.done.is_empty():
		if not background_jobs and index != null:
			Scanner.new(repo, index).scan()
		elif busy():
			_sync_again = true
		else:
			start_sync()
		notes_changed.emit()
	return r


# ------------------------------------------------------------------ corbeille

## Ce que la suppression d'une note va toucher : {name, type, backlinks, count}.
## `backlinks` : notes qui la citent encore (leurs liens deviendront des liens cassés).
func delete_info(rel: String) -> Dictionary:
	var name := rel.get_file().get_basename()
	var out := {"name": name, "type": "", "backlinks": [], "count": 0}
	if index == null:
		return out
	out.type = str(index.props_of(rel).get("type", ""))
	for b in index.backlinks(name, 400):
		if str(b.path) != rel:
			out.backlinks.append(b)
	out.count = out.backlinks.size()
	return out


## Met une note à la corbeille du coffre (`.trash/`, comme Obsidian). Rien n'est
## effacé : la note se restaure depuis Réglages → Corbeille. Renvoie {ok, conflict, error, trash_rel}.
func trash_note(rel: String, expected_hash := "") -> Dictionary:
	if repo == null:
		return {"ok": false, "conflict": false, "error": "coffre non configuré", "trash_rel": ""}
	var info := delete_info(rel)
	var r: Dictionary = Trash.move_to_trash(repo, rel, expected_hash, info)
	if not r.ok:
		_log("Suppression refusée (%s) : %s" % [rel, r.error])
		return r
	_log("Mise à la corbeille : %s → %s" % [rel, r.trash_rel])
	clear_draft(rel)
	_reindex([rel])
	notes_changed.emit()
	return r


func trash_list() -> Array:
	return Trash.list(repo) if repo != null else []


## Restaure une note de la corbeille, si aucune note du coffre ne porte déjà son nom.
## Renvoie {ok, error, rel}.
func restore_note(trash_rel: String) -> Dictionary:
	if repo == null:
		return {"ok": false, "error": "coffre non configuré", "rel": ""}
	var name := trash_rel.get_file().get_basename()
	for e in Trash.list(repo):
		if str(e.trash_rel) == trash_rel:
			name = str(e.origine).get_file().get_basename()
	if index != null and index.path_of_name(name) != "":
		return {"ok": false, "rel": "", "error": "une autre note s'appelle déjà « %s » : renommez-la d'abord" % name}
	var r: Dictionary = Trash.restore(repo, trash_rel)
	if not r.ok:
		_log("Restauration refusée (%s) : %s" % [trash_rel, r.error])
		return r
	_log("Restaurée : " + str(r.rel))
	_reindex([r.rel])
	notes_changed.emit()
	return r


## Efface définitivement des notes de la corbeille. Renvoie {ok, done, error}.
func purge_trash(trash_rels: Array) -> Dictionary:
	if repo == null:
		return {"ok": false, "done": [], "error": "coffre non configuré"}
	var r: Dictionary = Trash.purge(repo, trash_rels)
	_log("Corbeille : %d fichier(s) effacé(s) définitivement%s" % [r.done.size(), "" if r.ok else " — " + str(r.error)])
	return r


## Garde une copie de la version de l'utilisateur dans _Conflits/.
func keep_conflict_copy(rel: String, doc: RefCounted) -> Dictionary:
	var r: Dictionary = SafeWriter.new(repo).save_conflict_copy(rel, doc.to_bytes())
	_log("Copie de conflit : " + ("créée dans _Conflits/" if r.ok else r.error))
	return r


# ------------------------------------------------------------------ brouillons

func _draft_path(rel: String) -> String:
	return "user://brouillons/%s.json" % (repo_path() + "|" + rel).sha256_text().substr(0, 20)


func save_draft(rel: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://brouillons"))
	var f := FileAccess.open(_draft_path(rel), FileAccess.WRITE)
	if f != null:
		data["rel"] = rel
		data["saved_at"] = Time.get_datetime_string_from_system()
		f.store_string(JSON.stringify(data))
		f.close()


func load_draft(rel: String) -> Dictionary:
	var p := _draft_path(rel)
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func clear_draft(rel: String) -> void:
	var p := _draft_path(rel)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ------------------------------------------------------------------ rapport

func diagnostic_text() -> String:
	var t := PackedStringArray()
	t.append("== Diagnostic Nosferatu Intelligence (%s) ==" % VERSION)
	t.append("Date : %s · Plateforme : %s %s · Godot %s" % [Time.get_datetime_string_from_system(),
		OS.get_name(), OS.get_model_name(), Engine.get_version_info().string])
	t.append("Coffre : %s" % repo_path())
	for k in ["exists", "readable", "writable", "git", "config", "tmp_ignored", "error"]:
		if last_check.has(k):
			t.append("  %s : %s" % [k, last_check[k]])
	if repo != null:
		var top: Dictionary = repo.top_entries()
		t.append("  racine visible : %d dossiers %s · %d fichiers · %d éléments cachés %s" % [
			top.dirs.size(), str(top.dirs.slice(0, 12)), top.files.size(), top.hidden.size(),
			str(top.hidden.slice(0, 6))])
	t.append("  cœurs utilisés : %d" % preload("res://core/app/parallel.gd").workers())
	t.append("Index : %s" % db_path())
	if index != null:
		var s: Dictionary = index.stats()
		t.append("  FTS5 : %s" % ("oui" if s.fts else "non (recherche simple)"))
		t.append("  notes : %d %s" % [s.files, JSON.stringify(s.types)])
		t.append("  éléments : %d · mouvements : %d · liens : %d · tâches ouvertes : %d" % [
			s.elements, s.movements, s.links, s.tasks_open])
		t.append("  problèmes : %d erreurs, %d avertissements · liens cassés : %d" % [
			s.errors, s.warnings, index.broken_link_count()])
		t.append("  dernière synchro : %s · index incomplet : %s" % [
			Time.get_datetime_string_from_unix_time(int(index.meta_get("last_scan", "0"))),
			index.meta_get("dirty", "?")])
	if index_needs_repair:
		t.append("  ⚠ index à mettre à jour : relancez la synchronisation")
	if not last_report.is_empty():
		t.append("Dernière synchronisation : " + JSON.stringify(last_report))
	t.append("Journal (fin) :")
	for l in journal.slice(maxi(0, journal.size() - 30)):
		t.append("  " + l)
	return "\n".join(t)
