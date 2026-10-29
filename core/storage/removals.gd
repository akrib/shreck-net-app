extends RefCounted
## Suppressions ciblées depuis une fiche (boutons ×) : une seule ligne d'élément,
## ou un seul lien dans une propriété. Rien ne disparaît en silence :
##  - la ligne retirée (et ses sous-points) est gardée dans le journal
##    `.nosferatu/lignes-supprimees.json`, d'où on la restaure (Réglages → Corbeille) ;
##  - une note entière (faveur, indice) passe par la corbeille habituelle.
## Toute écriture passe par l'écriture sûre (empreinte vérifiée).

const RepoAccess := preload("res://core/storage/repo_access.gd")
const SafeWriter := preload("res://core/storage/safe_writer.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const TextNorm := preload("res://core/format/text_norm.gd")

const JOURNAL := ".nosferatu/lignes-supprimees.json"


## Lignes du corps à retirer pour un élément : sa ligne et ses sous-points indentés.
## `lines` : le corps ; `k` : indice de la ligne de l'élément. Renvoie [début, fin exclue].
static func element_span(lines: PackedStringArray, k: int) -> Array:
	var end := k + 1
	while end < lines.size() and lines[end] != "" and (lines[end].begins_with(" ") or lines[end].begins_with("\t")):
		end += 1
	return [k, end]


## Trouve l'élément dans le corps analysé : par identifiant, sinon par énoncé (unique).
## Renvoie l'élément ({line, block, text…}) ou {} ; `error` si plusieurs correspondent.
static func find_element(parsed: Dictionary, block: String, text: String) -> Dictionary:
	if block != "":
		for e in parsed.get("elements", []):
			if str(e.block) == block:
				return e
		return {}
	var hits := []
	for e in parsed.get("elements", []):
		if str(e.text).strip_edges() == text.strip_edges():
			hits.append(e)
	if hits.size() == 1:
		return hits[0]
	return {"error": "plusieurs lignes ont ce texte : supprimez-la dans la note"} if hits.size() > 1 else {}


## Retire `lines[a..b)` du corps ; renvoie {body, removed}.
static func cut(body: String, a: int, b: int) -> Dictionary:
	var lines := body.split("\n")
	var removed := PackedStringArray()
	var keep := PackedStringArray()
	for i in lines.size():
		if i >= a and i < b:
			removed.append(lines[i])
		else:
			keep.append(lines[i])
	return {"body": "\n".join(keep), "removed": removed}


## Retire un lien vers `target` d'une valeur de propriété (texte ou liste).
## Renvoie [nouvelle valeur (null si vide), trouvé].
static func without_link(value: Variant, target: String) -> Array:
	var tk := TextNorm.name_key(target)
	var match_link := func(x: Variant) -> bool:
		return TextNorm.name_key(StructuredLines.link_target(x)) == tk or TextNorm.name_key(str(x)) == tk
	if typeof(value) == TYPE_ARRAY:
		var out := []
		var found := false
		for x in value:
			if match_link.call(x):
				found = true
			else:
				out.append(x)
		return [out if not out.is_empty() else null, found]
	if value != null and match_link.call(value):
		return [null, true]
	return [value, false]


# ------------------------------------------------------------------ journal

static func journal(repo: RefCounted) -> Array:
	var rb: Dictionary = repo.read_bytes(JOURNAL)
	if rb.error != OK:
		return []
	var v: Variant = JSON.parse_string(rb.bytes.get_string_from_utf8())
	if typeof(v) == TYPE_DICTIONARY and typeof(v.get("lignes")) == TYPE_ARRAY:
		return v.lignes
	return []


static func save_journal(repo: RefCounted, entries: Array) -> Dictionary:
	var cur: Dictionary = repo.read_bytes(JOURNAL)
	var h := RepoAccess.hash_bytes(cur.bytes) if cur.error == OK else ""
	var text := JSON.stringify({"lignes": entries}, "\t", false) + "\n"
	return SafeWriter.new(repo).write(JOURNAL, text.to_utf8_buffer(), h)
