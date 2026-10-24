extends RefCounted
## Import des lots préparés par Claude (FORMAT §15) : `_Import/<lot>/` reproduit
## l'arborescence du coffre et contient `_lot.md` (le rapport).
##  - chaque note du lot est contrôlée (propriétés lisibles, type, identifiant
##    neuf et bien formé, nom et chemin libres dans le coffre, champs
##    obligatoires, liens) ;
##  - vous cochez ce que vous acceptez ; seules les notes sans erreur peuvent
##    l'être ;
##  - l'intégration copie chaque note acceptée à sa place, par écriture sûre,
##    sans jamais écraser un fichier existant ;
##  - le lot n'est ni modifié ni supprimé : un journal `_import.journal.md` y
##    garde la trace de ce qui a été intégré.

const NoteDocument := preload("res://core/format/note_document.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Ids := preload("res://core/format/ids.gd")
const SafeWriter := preload("res://core/storage/safe_writer.gd")

## Propriétés obligatoires (★ de FORMAT §9), comme le validateur.
const REQUIRED := {"soiree": ["date", "domaine"], "source": ["nature", "fiabilite"],
	"indice": ["statut", "credibilite", "pour"], "evenement": ["statut", "credibilite"],
	"faveur": ["niveau", "debiteur", "creancier", "statut", "credibilite"], "dossier": ["statut", "question"]}
const DATE_REQUIRED := ["source", "evenement", "faveur"]

const LOTS_DIR := "_Import"
const JOURNAL := "_import.journal.md"


## Lots présents : [{name, rel, notes, files, report, journal}]
static func list_lots(repo: RefCounted) -> Array:
	var out := []
	var base: String = repo.abs_path(LOTS_DIR)
	if not DirAccess.dir_exists_absolute(base):
		return out
	var names := Array(DirAccess.get_directories_at(base))
	names.sort()
	names.reverse()
	for n in names:
		if str(n).begins_with("."):
			continue
		var files := []
		_walk(base + "/" + n, "", files)
		var md := files.filter(func(f): return str(f).to_lower().ends_with(".md") and f != "_lot.md" and f != JOURNAL)
		out.append({"name": n, "rel": LOTS_DIR + "/" + n, "notes": md.size(), "files": files.size(),
			"report": files.has("_lot.md"), "journal": files.has(JOURNAL)})
	return out


static func _walk(abs_dir: String, prefix: String, out: Array) -> void:
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		if not f.begins_with("."):
			out.append(prefix + f)
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_walk(abs_dir + "/" + sub, prefix + sub + "/", out)


## Contrôle d'un lot. Renvoie {items: [...], report: texte de _lot.md, counts}.
## item = {lot_rel, target_rel, name, type, id, level: ok|avert|erreur, messages, text, is_note}
static func analyse(repo: RefCounted, index: RefCounted, lot_rel: String) -> Dictionary:
	var files := []
	_walk(repo.abs_path(lot_rel), "", files)
	files.sort()
	var report := ""
	if files.has("_lot.md"):
		report = FileAccess.get_file_as_string(repo.abs_path(lot_rel + "/_lot.md"))
	var items := []
	var lot_names := {}
	var lot_ids := {}
	var docs := {}
	for f in files:
		if f == "_lot.md" or f == JOURNAL:
			continue
		var it := {"lot_rel": lot_rel + "/" + f, "target_rel": f, "name": str(f).get_file().get_basename(),
			"type": "", "id": "", "level": "ok", "messages": [], "text": "", "is_note": str(f).to_lower().ends_with(".md")}
		if it.is_note:
			var bytes := FileAccess.get_file_as_bytes(repo.abs_path(it.lot_rel))
			var doc = NoteDocument.from_bytes(bytes)
			docs[f] = doc
			it.text = doc.raw_text
			it.type = doc.type_name()
			it.id = doc.note_id()
			var key := TextNorm.name_key(it.name)
			if lot_names.has(key):
				_msg(it, "erreur", "nom en double dans le lot : " + str(lot_names[key]))
			lot_names[key] = f
			if it.id != "":
				if lot_ids.has(it.id):
					_msg(it, "erreur", "identifiant %s en double dans le lot" % it.id)
				lot_ids[it.id] = f
		items.append(it)
	for it in items:
		_check(it, docs.get(it.target_rel), repo, index, lot_names)
	var counts := {"ok": 0, "avert": 0, "erreur": 0}
	for it in items:
		counts[it.level] += 1
	return {"items": items, "report": report, "counts": counts}


static func _msg(it: Dictionary, level: String, text: String) -> void:
	it.messages.append(text)
	var order := {"ok": 0, "avert": 1, "erreur": 2}
	if order[level] > order[it.level]:
		it.level = level


static func _check(it: Dictionary, doc: Variant, repo: RefCounted, index: RefCounted, lot_names: Dictionary) -> void:
	# destination libre ?
	if repo.exists(it.target_rel):
		_msg(it, "erreur", "un fichier existe déjà à cet endroit du coffre : il ne sera pas écrasé")
	if not it.is_note:
		return
	if index != null and index.path_of_name(it.name) != "":
		_msg(it, "erreur", "une note de ce nom existe déjà dans le coffre (%s)" % index.path_of_name(it.name))
	elif index != null:
		# même nom aux accents ou aux majuscules près (« Toreador » / « Toréador »)
		var near: Array = index.rows("SELECT path FROM files WHERE name_fold = ? LIMIT 1", [TextNorm.fold(it.name)])
		if not near.is_empty():
			_msg(it, "avert", "une fiche au nom presque identique existe déjà (%s) : accents ou majuscules ; gardez-en une seule" % near[0].path)
	if doc == null:
		return
	if not doc.utf8_ok:
		_msg(it, "erreur", "fichier non UTF-8")
		return
	if doc.unclosed or (doc.has_frontmatter and not doc.fm.ok):
		var why: String = "frontmatter non fermé" if doc.unclosed else str(doc.fm.errors[0].msg)
		_msg(it, "erreur", "propriétés illisibles : " + why)
		return
	if index != null:
		var al: Variant = doc.properties().get("aliases")
		for a in (Array(al) if (al is Array or al is PackedStringArray) else ([] if al == null else [al])):
			var other: String = index.path_of_name(str(a))
			if str(a).strip_edges() != "" and other != "":
				_msg(it, "avert", "l'alias « %s » est déjà le nom d'une fiche du coffre (%s) : deux fiches répondraient à ce nom dans les recherches" % [a, other])
	var t: String = it.type
	if t == "":
		_msg(it, "avert", "note sans type : elle sera une note libre")
	elif not Schema.TYPES.has(t):
		_msg(it, "avert", "type « %s » inconnu de l'application" % t)
	else:
		var id: String = it.id
		var prefix: String = Schema.TYPES[t].prefix
		if id == "":
			_msg(it, "erreur", "identifiant manquant (un lot doit être complet)")
		elif not Ids.is_valid(id) or Ids.prefix_of(id) != prefix:
			_msg(it, "erreur", "identifiant « %s » mal formé (attendu %s-xxxxxxxx)" % [id, prefix])
		elif index != null and not index.rows("SELECT path FROM files WHERE id = ?", [id]).is_empty():
			_msg(it, "erreur", "identifiant %s déjà utilisé dans le coffre" % id)
		var props: Dictionary = doc.properties()
		for key in REQUIRED.get(t, []):
			var v: Variant = props.get(key)
			if v == null or str(v).strip_edges() == "" or (typeof(v) == TYPE_ARRAY and v.is_empty()):
				_msg(it, "erreur", "propriété obligatoire manquante : " + key)
		if DATE_REQUIRED.has(t) and str(props.get("date", "")) == "" and str(props.get("date_floue", "")) == "":
			_msg(it, "erreur", "date ou date_floue obligatoire")
		for f in ["statut", "nature", "niveau", "rang", "identite", "priorite"]:
			var v: Variant = props.get(f)
			var opts := Schema.options(t, f)
			if v != null and str(v) != "" and not opts.is_empty():
				var known := false
				for o in opts:
					if str(o[0]) == str(v):
						known = true
				if not known:
					_msg(it, "avert" if f == "nature" and t == "soiree" else "erreur", "%s « %s » hors liste" % [f, v])
	# lignes structurées
	var parsed := StructuredLines.parse_body(doc.body, doc.body_first_line)
	for p in parsed.problems:
		_msg(it, "erreur" if p.level == "ERREUR" else "avert", "ligne %d : %s" % [p.line, p.msg])
	# liens
	var missing := {}
	var targets := []
	for l in parsed.links:
		targets.append(l.target)
	for key in doc.fm.get("order", []):
		var v: Variant = doc.properties().get(key)
		for x in (v if typeof(v) == TYPE_ARRAY else [v]):
			for l in StructuredLines.links_in("" if x == null else str(x)):
				targets.append(l.target)
	for tg in targets:
		var k := TextNorm.name_key(str(tg))
		if k == "" or lot_names.has(k) or missing.has(k):
			continue
		if index != null and (index.path_of_name(str(tg)) != "" or not index.rows("SELECT 1 FROM attachments WHERE name_key = ? LIMIT 1", [k]).is_empty()):
			continue
		missing[k] = str(tg)
	if not missing.is_empty():
		_msg(it, "avert", "lien(s) vers des fiches absentes : " + ", ".join(PackedStringArray(missing.values().slice(0, 6))) + ("…" if missing.size() > 6 else ""))


## Intègre les éléments acceptés. Renvoie {done: [chemins], failed: [[chemin, raison]]}.
static func import_items(repo: RefCounted, lot_rel: String, items: Array) -> Dictionary:
	var done := []
	var failed := []
	for it in items:
		if it.level == "erreur":
			failed.append([it.target_rel, "erreurs non corrigées"])
			continue
		var bytes := FileAccess.get_file_as_bytes(repo.abs_path(it.lot_rel))
		var w: Dictionary = SafeWriter.new(repo).write(it.target_rel, bytes, "")
		if w.ok:
			done.append(it.target_rel)
		else:
			failed.append([it.target_rel, str(w.error)])
	# journal dans le dossier du lot (le lot lui-même n'est pas modifié)
	if not done.is_empty() or not failed.is_empty():
		var jrel: String = lot_rel + "/" + JOURNAL
		var old := FileAccess.get_file_as_string(repo.abs_path(jrel)) if repo.exists(jrel) else "# Journal d'intégration\n"
		var t := PackedStringArray([old.strip_edges(), "", "## " + Time.get_datetime_string_from_system().replace("T", " ")])
		for p in done:
			t.append("- intégrée : " + str(p))
		for f in failed:
			t.append("- non intégrée : %s (%s)" % [f[0], f[1]])
		var expected := ""
		if repo.exists(jrel):
			expected = preload("res://core/storage/repo_access.gd").hash_bytes(FileAccess.get_file_as_bytes(repo.abs_path(jrel)))
		SafeWriter.new(repo).write(jrel, ("\n".join(t) + "\n").to_utf8_buffer(), expected)
	return {"done": done, "failed": failed}
