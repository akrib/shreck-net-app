extends RefCounted
## Lecture du corps d'une note (FORMAT.md §10) : liens, identifiants de bloc,
## tâches, et lignes structurées des sections « ## Éléments » et
## « ## Mouvements ». Le texte n'est jamais modifié par la lecture.

const TextNorm := preload("res://core/format/text_norm.gd")

static var _rx := {}
static var R_LINK: RegEx = _mk("!?\\[\\[([^\\[\\]]+?)\\]\\]")
static var R_LINK_ONLY: RegEx = _mk("^\\[\\[([^\\[\\]]+?)\\]\\]$")
static var R_FIELD: RegEx = _mk("\\[([a-z_]+)::\\s*")
static var R_FENCE: RegEx = _mk("^\\s*(```|~~~)")
static var R_CODE: RegEx = _mk("`[^`]*`")
static var R_HEAD: RegEx = _mk("^(#{1,6})\\s+(.*?)\\s*#*\\s*$")
static var R_BLOCK: RegEx = _mk("\\s\\^([A-Za-z0-9-]+)\\s*$")
static var R_TASK: RegEx = _mk("^\\s*[-*+]\\s+\\[[ xX]\\]\\s")
static var R_DONE: RegEx = _mk("\\[[xX]\\]")
static var R_ITEM: RegEx = _mk("^[-*+]\\s+(.*)$")
static var R_H12: RegEx = _mk("^##\\s+(.*?)\\s*#*\\s*$")
static var R_H1OR2: RegEx = _mk("^#{1,2}\\s")


static func _mk(pattern: String) -> RegEx:
	var r := RegEx.new()
	r.compile(pattern)
	return r


static func _re(pattern: String) -> RegEx:
	if not _rx.has(pattern):
		_rx[pattern] = _mk(pattern)
	return _rx[pattern]


## Découpe le contenu d'un lien : "Note#^bloc|alias" -> {target, sub}.
static func split_link(content: String) -> Dictionary:
	var cible := content.split("|", true, 1)[0]
	var sub := ""
	var h := cible.find("#")
	if h >= 0:
		sub = cible.substr(h + 1).strip_edges()
		cible = cible.substr(0, h)
	cible = cible.strip_edges()
	var slash := cible.rfind("/")
	if slash >= 0:
		cible = cible.substr(slash + 1)
	if cible.to_lower().ends_with(".md"):
		cible = cible.substr(0, cible.length() - 3)
	return {"target": cible, "sub": sub}


## Tous les liens [[…]] d'un texte.
static func links_in(text: String) -> Array:
	var out := []
	if not text.contains("[["):
		return out
	for m in R_LINK.search_all(text):
		out.append(split_link(m.get_string(1)))
	return out


## Nom visé par une valeur de propriété "[[Nom]]" (ou "" si ce n'est pas un lien seul).
static func link_target(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var m := R_LINK_ONLY.search(value.strip_edges())
	return split_link(m.get_string(1)).target if m else ""


## Extrait les champs [clé:: valeur] d'une ligne. Renvoie {fields, spans, errors}.
static func read_fields(line: String) -> Dictionary:
	var fields := {}
	var spans := []
	var errors := []
	var i := 0
	var re := R_FIELD
	while true:
		var m := re.search(line, i)
		if m == null:
			break
		if m.get_start() > 0 and line[m.get_start() - 1] == "[":
			i = m.get_end()
			continue
		var j := m.get_end()
		var closed := false
		while true:
			var close := line.find("]", j)
			if close == -1:
				break
			var open := line.find("[[", j)
			if open != -1 and open < close:
				var end_link := line.find("]]", open + 2)
				if end_link == -1:
					break
				j = end_link + 2
				continue
			j = close
			closed = true
			break
		if not closed:
			errors.append("champ « %s » non fermé (crochet ] manquant)" % m.get_string(1))
			break
		var key := m.get_string(1)
		if fields.has(key):
			errors.append("champ « %s » présent deux fois" % key)
		fields[key] = line.substr(m.get_end(), j - m.get_end()).strip_edges()
		spans.append([m.get_start(), j + 1])
		i = j + 1
	return {"fields": fields, "spans": spans, "errors": errors}


## Analyse le corps. `first_line` = numéro (1-based) de la première ligne du corps.
static func parse_body(body: String, first_line := 1) -> Dictionary:
	var res := {"links": [], "blocks": {}, "elements": [], "movements": [], "tasks": [],
		"problems": []}
	var section := ""
	var in_code := false
	var last_item = null
	var lines := body.split("\n")
	for k in lines.size():
		var num := first_line + k
		var brute: String = lines[k].trim_suffix("\r")
		if (brute.contains("```") or brute.contains("~~~")) and R_FENCE.search(brute):
			in_code = not in_code
			continue
		if in_code:
			continue
		var line := R_CODE.sub(brute, "", true) if brute.contains("`") else brute
		var mt: RegExMatch = R_HEAD.search(line) if line.begins_with("#") else null
		if mt:
			if mt.get_string(1).length() <= 2:
				section = ""
				var titre := TextNorm.fold(mt.get_string(2)).strip_edges()
				if mt.get_string(1).length() == 2 and (titre == "elements" or titre == "mouvements"):
					section = titre
			last_item = null
		if line.contains("[["):
			for l in links_in(line):
				l["line"] = num
				res.links.append(l)
		if line.contains("^"):
			var mb := R_BLOCK.search(line)
			if mb:
				var bid := mb.get_string(1)
				if res.blocks.has(bid):
					res.problems.append({"line": num, "level": "ERREUR",
						"msg": "identifiant de bloc ^%s en double dans la note" % bid})
				res.blocks[bid] = num
		var is_task := line.contains("]") and R_TASK.search(line) != null
		if section == "" or mt:
			if is_task:
				res.tasks.append({"line": num, "done": R_DONE.search(line) != null,
					"text": line.strip_edges()})
			continue
		if line.strip_edges() == "":
			continue
		if is_task:
			res.problems.append({"line": num, "level": "AVERTISSEMENT",
				"msg": "tâche dans une section structurée : la placer sous « ## À faire »"})
			continue
		var c0 := line.left(1)
		if (c0 == "-" or c0 == "*" or c0 == "+") and R_ITEM.search(line):
			last_item = _structured_line(line, num, section, res)
			continue
		if (line.begins_with(" ") or line.begins_with("\t")) and last_item != null:
			continue
		res.problems.append({"line": num, "level": "AVERTISSEMENT",
			"msg": "contenu non structuré dans la section (conservé, non interprété)"})
	return res


static func _structured_line(line: String, num: int, section: String, res: Dictionary) -> Dictionary:
	var f := read_fields(line)
	for e in f.errors:
		res.problems.append({"line": num, "level": "ERREUR", "msg": e})
	var rest := line
	var spans: Array = f.spans
	spans.reverse()
	for s in spans:
		rest = rest.substr(0, s[0]) + rest.substr(s[1])
	var block := ""
	var mb := R_BLOCK.search(rest)
	if mb:
		block = mb.get_string(1)
		rest = rest.substr(0, mb.get_start())
	var mi := R_ITEM.search(rest.strip_edges() + " ")
	var enonce := (mi.get_string(1) if mi else rest).strip_edges()
	var entry := {"line": num, "fields": f.fields, "block": block, "text": enonce}
	if section == "elements":
		res.elements.append(entry)
	else:
		res.movements.append(entry)
	for key in f.fields:
		for l in links_in(f.fields[key]):
			l["line"] = num
			l["origin"] = "champ " + key
			res.links.append(l)
	return entry


## Remplace la valeur d'un champ [clé:: valeur] d'une ligne structurée, ou
## l'ajoute (avant l'identifiant de bloc) s'il n'y est pas. Le reste de la
## ligne est conservé à l'identique.
static func set_line_field(line: String, key: String, value: String) -> String:
	var f := read_fields(line)
	for s in f.spans:
		var m := R_FIELD.search(line, s[0])
		if m and m.get_start() == s[0] and m.get_string(1) == key:
			return line.substr(0, s[0]) + "[%s:: %s]" % [key, value] + line.substr(s[1])
	var field := "[%s:: %s]" % [key, value]
	var mb := R_BLOCK.search(line)
	if mb:
		return line.substr(0, mb.get_start()).strip_edges(false, true) + " " + field + line.substr(mb.get_start())
	return line.strip_edges(false, true) + " " + field


## Ajoute un identifiant de bloc en fin de ligne (si elle n'en a pas).
static func add_block_id(line: String, bid: String) -> String:
	if R_BLOCK.search(line):
		return line
	return line.strip_edges(false, true) + " ^" + bid


## Attribue un identifiant aux éléments et mouvements qui n'en ont pas (FORMAT
## §5). `gen` : Callable(prefixe) -> identifiant. Renvoie {body, added}.
static func assign_missing_ids(body: String, gen: Callable) -> Dictionary:
	var parsed := parse_body(body, 1)
	var lines := body.split("\n")
	var added := 0
	for pair in [[parsed.elements, "el"], [parsed.movements, "mv"]]:
		for e in pair[0]:
			if str(e.block) != "":
				continue
			var k: int = int(e.line) - 1
			if k < 0 or k >= lines.size():
				continue
			lines[k] = add_block_id(lines[k], str(gen.call(pair[1])))
			added += 1
	return {"body": "\n".join(lines), "added": added}


## Ordre des champs d'une ligne d'élément écrite par l'application (§10.2).
const ELEMENT_FIELDS := ["nature", "credibilite", "par", "date_faits", "relation", "de", "vers", "discipline",
	"qualificatif", "jusqu_au"]


## Ligne d'élément, sans identifiant : « - énoncé [clé:: valeur]… ». Les champs
## vides sont omis ; les crochets sont retirés du qualificatif (texte libre).
static func element_line(text: String, fields: Dictionary) -> String:
	var line := "- " + text.strip_edges().replace("\r", " ").replace("\n", " ")
	for k in ELEMENT_FIELDS:
		var v: Variant = fields.get(k)
		if v == null or str(v).strip_edges() == "":
			continue
		var s := str(v).strip_edges()
		if k == "qualificatif":
			s = s.replace("[", "").replace("]", "")
		line += " [%s:: %s]" % [k, s]
	return line


## Ajoute une ligne à la fin de la section « ## Éléments » (créée si absente).
## `body` utilise "\n". Le reste du corps est conservé tel quel.
static func append_to_section(body: String, section_title: String, item_line: String) -> String:
	var lines := body.split("\n")
	var target := TextNorm.fold(section_title)
	var start := -1
	var in_code := false
	for k in lines.size():
		if R_FENCE.search(lines[k]):
			in_code = not in_code
			continue
		if in_code:
			continue
		var mt := R_H12.search(lines[k])
		if mt and TextNorm.fold(mt.get_string(1)).strip_edges() == target:
			start = k
			break
	if start == -1:
		var out := body
		if out != "" and not out.ends_with("\n"):
			out += "\n"
		if out != "" and not out.ends_with("\n\n"):
			out += "\n"
		return out + "## " + section_title + "\n" + item_line + "\n"
	# fin de section : prochain titre de niveau 1 ou 2
	var end := lines.size()
	in_code = false
	for k in range(start + 1, lines.size()):
		if R_FENCE.search(lines[k]):
			in_code = not in_code
			continue
		if not in_code and R_H1OR2.search(lines[k]):
			end = k
			break
	# insérer après le dernier contenu non vide de la section
	var insert_at := start + 1
	for k in range(start + 1, end):
		if lines[k].strip_edges() != "":
			insert_at = k + 1
	lines.insert(insert_at, item_line)
	return "\n".join(lines)
