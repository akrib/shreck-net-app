extends RefCounted
## Lecture et écriture du profil YAML « plat » d'Obsidian (FORMAT.md §6.1).
##
## Autorisé : `clé: valeur` au premier niveau ; valeurs texte (sur une ligne,
## simple ou entre guillemets), nombre, booléen, vide, liste de valeurs simples
## (en bloc `  - x` ou en ligne `[a, b]`).
## Refusé, avec un message explicite : objets imbriqués, listes de listes,
## texte sur plusieurs lignes, ancres/alias/étiquettes, clés en double.
##
## Ce n'est pas un parseur YAML complet : il REFUSE tout ce qui sort du profil
## au lieu de deviner. Les cas ambigus entre YAML 1.1 (PyYAML) et YAML 1.2
## (Obsidian) sont lus comme du texte et signalés.
##
## Les dates restent du texte : `2026-10-10` est lu "2026-10-10".

const REMOVE := "__nosferatu_supprimer_cette_propriete__"
const MSG_LIEN := "lien non entre guillemets : écrire \"[[Nom]]\""

static var _rx := {}
static var R_KEY: RegEx = _mk("^([^\\s#'\"\\-?:,\\[\\]{}&*!|>%@`][^:]*?):(?:[ ]+(.*))?$")
static var R_INT: RegEx = _mk("^[-+]?[0-9]+$")
static var R_FLOAT: RegEx = _mk("^[-+]?([0-9]+\\.[0-9]*|\\.[0-9]+)$")
static var R_AMBIG: RegEx = _mk("^[-+]?(0x[0-9a-fA-F]+|0o[0-7]+|0b[01]+|[0-9.]+[eE][-+]?[0-9]+|\\.(inf|Inf|INF|nan|NaN|NAN)|[0-9][0-9_]*(:[0-5]?[0-9])+(\\.[0-9_]*)?|[0-9][0-9_]*_[0-9_]*)$")
static var R_YEAR: RegEx = _mk("^[0-9]{4}")
static var R_DATE: RegEx = _mk("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")


static func _mk(pattern: String) -> RegEx:
	var r := RegEx.new()
	r.compile(pattern)
	return r


static func _re(pattern: String) -> RegEx:
	if not _rx.has(pattern):
		var r := RegEx.new()
		r.compile(pattern)
		_rx[pattern] = r
	return _rx[pattern]


static func _err(res: Dictionary, line: int, msg: String) -> void:
	res.errors.append({"line": line, "msg": msg})


static func _warn(res: Dictionary, line: int, msg: String) -> void:
	res.warnings.append({"line": line, "msg": msg})


static func _indent(line: String) -> int:
	var k := 0
	while k < line.length() and line[k] == " ":
		k += 1
	return k


# ---------------------------------------------------------------- lecture

## Analyse les lignes du frontmatter (sans les délimiteurs ---).
## Les numéros de ligne renvoyés sont des index dans `lines` (à partir de 0).
static func parse(lines: PackedStringArray) -> Dictionary:
	var res := {
		"ok": true, "data": {}, "order": [], "ranges": {},
		"errors": [], "warnings": [], "has_comments": false,
	}
	var n := lines.size()
	var i := 0
	while i < n:
		var line: String = lines[i]
		var stripped := line.strip_edges()
		if stripped == "":
			i += 1
			continue
		if line.begins_with("\t") or line.strip_edges(true, false) != line and \
				line.substr(0, _indent(line) + 1).ends_with("\t"):
			_err(res, i, "tabulation interdite dans l'indentation")
			i += 1
			continue
		if stripped.begins_with("#"):
			res.has_comments = true
			i += 1
			continue
		if line.begins_with(" "):
			_err(res, i, "ligne indentée inattendue (objet imbriqué ou texte sur plusieurs lignes)")
			i += 1
			continue
		if line.begins_with("- ") or line == "-":
			_err(res, i, "élément de liste sans propriété")
			i += 1
			continue
		var m := R_KEY.search(line)
		if m == null:
			_err(res, i, "ligne non reconnue (attendu « clé: valeur »)")
			i += 1
			continue
		var key := m.get_string(1).strip_edges()
		var v := m.get_string(2).strip_edges()
		var start := i
		var end := i + 1
		var value: Variant = null
		if v == "" or v.begins_with("#"):
			if v.begins_with("#"):
				res.has_comments = true
			var seq := _parse_block_seq(lines, i + 1, res)
			value = seq.value
			end = seq.end
		else:
			value = _parse_inline(v, i, res, false)
		if res.data.has(key):
			_err(res, i, "clé en double : « %s »" % key)
		else:
			res.data[key] = value
			res.order.append(key)
			res.ranges[key] = [start, end]
		i = end
	res.ok = res.errors.is_empty()
	return res


static func _parse_block_seq(lines: PackedStringArray, j: int, res: Dictionary) -> Dictionary:
	var items := []
	var item_indent := -1
	var last := -1
	var k := j
	while k < lines.size():
		var l: String = lines[k]
		var st := l.strip_edges()
		if st == "":
			k += 1
			continue
		if st.begins_with("#") and item_indent != -1:
			res.has_comments = true
			k += 1
			continue
		if not (st == "-" or st.begins_with("- ")):
			break
		var ind := _indent(l)
		if l.substr(0, ind + 1).ends_with("\t"):
			_err(res, k, "tabulation interdite dans l'indentation")
		if item_indent == -1:
			item_indent = ind
		elif ind != item_indent:
			_err(res, k, "liste imbriquée ou indentation incohérente")
			last = k
			k += 1
			continue
		var t := st.substr(1).strip_edges()
		if t == "":
			_warn(res, k, "élément de liste vide")
			items.append(null)
		elif t == "-" or t.begins_with("- "):
			_err(res, k, "liste de listes interdite")
		else:
			items.append(_parse_inline(t, k, res, true))
		last = k
		k += 1
	if last == -1:
		return {"value": null, "end": j}
	return {"value": items, "end": last + 1}


static func _parse_inline(v: String, line: int, res: Dictionary, in_seq: bool) -> Variant:
	var c := v[0]
	if c == "\"" or c == "'":
		var r := _scan_quoted(v, 0)
		if not r.ok:
			_err(res, line, r.msg)
			return null
		_check_tail(v.substr(r.next), line, res)
		return r.value
	if c == "[":
		if v.begins_with("[["):
			_err(res, line, MSG_LIEN)
			return null
		if in_seq:
			_err(res, line, "liste de listes interdite")
			return null
		return _parse_flow_seq(v, line, res)
	if c == "{":
		_err(res, line, "objet imbriqué interdit (non géré par Obsidian)")
		return null
	if c == "|" or c == ">":
		_err(res, line, "texte sur plusieurs lignes (| ou >) interdit dans les propriétés")
		return null
	if c == "&" or c == "*" or c == "!":
		_err(res, line, "ancre, alias ou étiquette YAML (&, *, !) interdit")
		return null
	if c == "@" or c == "`" or c == "%":
		_err(res, line, "valeur commençant par « %s » : mettre entre guillemets" % c)
		return null
	if v == "-" or v.begins_with("- "):
		_err(res, line, "liste sur la ligne de la clé : écrire les éléments dessous")
		return null
	return _plain(v, line, res)


static func _check_tail(tail: String, line: int, res: Dictionary) -> void:
	var t := tail.strip_edges()
	if t == "":
		return
	if t.begins_with("#") and (tail.begins_with(" ") or tail.begins_with("\t")):
		res.has_comments = true
		return
	_err(res, line, "texte inattendu après les guillemets : « %s »" % t)


## Lit une chaîne entre guillemets à partir de `pos`. Renvoie {ok, value, next, msg}.
static func _scan_quoted(s: String, pos: int) -> Dictionary:
	var q := s[pos]
	var out := ""
	var k := pos + 1
	while k < s.length():
		var ch := s[k]
		if q == "'":
			if ch == "'":
				if k + 1 < s.length() and s[k + 1] == "'":
					out += "'"
					k += 2
					continue
				return {"ok": true, "value": out, "next": k + 1, "msg": ""}
			out += ch
			k += 1
			continue
		if ch == "\"":
			return {"ok": true, "value": out, "next": k + 1, "msg": ""}
		if ch == "\\":
			if k + 1 >= s.length():
				break
			var e := s[k + 1]
			var simple := {"\\": "\\", "\"": "\"", "/": "/", "n": "\n", "t": "\t", "r": "\r",
				"a": "\u0007", "b": "\u0008", "e": "\u001b", "f": "\u000c",
				"v": "\u000b", " ": " ", "N": "\u0085", "_": " ", "L": " ", "P": " "}
			if simple.has(e):
				out += simple[e]
				k += 2
				continue
			var lens := {"x": 2, "u": 4, "U": 8}
			if lens.has(e):
				var hexs := s.substr(k + 2, lens[e])
				if hexs.length() != lens[e] or not hexs.is_valid_hex_number(false):
					return {"ok": false, "value": null, "next": k, "msg": "échappement \\%s invalide" % e}
				out += String.chr(hexs.hex_to_int())
				k += 2 + lens[e]
				continue
			return {"ok": false, "value": null, "next": k, "msg": "échappement « \\%s » inconnu" % e}
		out += ch
		k += 1
	return {"ok": false, "value": null, "next": k,
		"msg": "guillemet non fermé (le texte sur plusieurs lignes est interdit)"}


static func _parse_flow_seq(v: String, line: int, res: Dictionary) -> Variant:
	var items := []
	var k := 1
	var n := v.length()
	var expect_item := true
	while true:
		while k < n and v[k] == " ":
			k += 1
		if k >= n:
			_err(res, line, "liste entre crochets non fermée (« ] » manquant)")
			return null
		var ch := v[k]
		if ch == "]":
			k += 1
			break
		if not expect_item:
			if ch == ",":
				k += 1
				expect_item = true
				continue
			_err(res, line, "liste entre crochets mal formée")
			return null
		if ch == "," :
			_err(res, line, "élément vide dans une liste entre crochets")
			return null
		if ch == "\"" or ch == "'":
			var r := _scan_quoted(v, k)
			if not r.ok:
				_err(res, line, r.msg)
				return null
			items.append(r.value)
			k = r.next
		elif ch == "[":
			_err(res, line, MSG_LIEN if v.substr(k).begins_with("[[") else "liste de listes interdite")
			return null
		elif ch == "{":
			_err(res, line, "objet dans une liste interdit")
			return null
		else:
			var start := k
			while k < n and v[k] != "," and v[k] != "]":
				k += 1
			var raw := v.substr(start, k - start).strip_edges()
			if raw.contains(": "):
				_err(res, line, "objet dans une liste interdit")
				return null
			items.append(_resolve(raw, line, res))
		expect_item = false
	_check_tail(v.substr(k), line, res)
	return items


static func _plain(v: String, line: int, res: Dictionary) -> Variant:
	var s := v
	var h := s.find(" #")
	if h >= 0:
		res.has_comments = true
		s = s.substr(0, h)
	s = s.strip_edges()
	if s.contains(": ") or s.ends_with(":"):
		_err(res, line, "« : » dans une valeur sans guillemets : mettre la valeur entre guillemets")
		return null
	return _resolve(s, line, res)


## Résout un scalaire simple selon YAML 1.2 (cœur), en signalant les cas que
## PyYAML (YAML 1.1) lirait autrement. Les cas ambigus restent du texte.
static func _resolve(s: String, line: int, res: Dictionary) -> Variant:
	match s:
		"", "~", "null", "Null", "NULL":
			return null
		"true", "True", "TRUE":
			return true
		"false", "False", "FALSE":
			return false
	var c0 := s.unicode_at(0)
	var numeric_start := (c0 >= 48 and c0 <= 57) or c0 == 43 or c0 == 45 or c0 == 46  # 0-9 + - .
	if not numeric_start:
		if s.length() <= 3 and s.to_lower() in ["yes", "no", "on", "off"]:
			_warn(res, line, "« %s » est ambigu (oui/non pour certains outils) : lu comme texte, "
					% s + "mettre entre guillemets")
		return s
	if R_INT.search(s):
		var digits := s.trim_prefix("-").trim_prefix("+")
		if digits.length() > 1 and digits.begins_with("0"):
			_warn(res, line, "« %s » : nombre avec zéro initial ambigu, lu comme texte" % s)
			return s
		if digits.length() > 18:
			return s
		return s.to_int()
	if R_FLOAT.search(s):
		return s.to_float()
	if R_AMBIG.search(s):
		_warn(res, line, "« %s » : valeur numérique ambiguë, lue comme texte" % s)
		return s
	return s


# ---------------------------------------------------------------- écriture

static func needs_quotes(s: String) -> bool:
	if s == "" or s != s.strip_edges():
		return true
	if "-?:,[]{}#&*!|>'\"%@`".contains(s[0]):
		return true
	if s.contains(": ") or s.contains(" #") or s.ends_with(":") or s.contains("[["):
		return true
	for k in s.length():
		if s.unicode_at(k) < 32:
			return true
	var tmp := {"errors": [], "warnings": [], "has_comments": false}
	var r: Variant = _resolve(s, 0, tmp)
	if typeof(r) != TYPE_STRING or not tmp.warnings.is_empty():
		return true
	if R_YEAR.search(s):
		return true
	return false


static func quote(s: String) -> String:
	var out := "\""
	for k in s.length():
		var ch := s[k]
		var code := s.unicode_at(k)
		if ch == "\\":
			out += "\\\\"
		elif ch == "\"":
			out += "\\\""
		elif ch == "\n":
			out += "\\n"
		elif ch == "\t":
			out += "\\t"
		elif ch == "\r":
			out += "\\r"
		elif code < 32:
			out += "\\x%02x" % code
		else:
			out += ch
	return out + "\""


## `hint` = "date" pour une propriété de type Date (écrite sans guillemets).
static func dump_scalar(v: Variant, hint := "") -> String:
	match typeof(v):
		TYPE_NIL:
			return ""
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			var f := str(v)
			return f if f.contains(".") or f.contains("e") else f + ".0"
		_:
			var s := str(v)
			if hint == "date" and R_DATE.search(s):
				return s
			return quote(s) if needs_quotes(s) else s


static func dump_entry(key: String, v: Variant, hint := "") -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_PACKED_STRING_ARRAY:
		if v.is_empty():
			out.append(key + ": []")
		else:
			out.append(key + ":")
			for x in v:
				out.append("  - " + dump_scalar(x))
	elif v == null:
		out.append(key + ":")
	else:
		out.append(key + ": " + dump_scalar(v, hint))
	return out


static func dump(data: Dictionary, order: Array = [], hints := {}) -> PackedStringArray:
	var keys := order.duplicate()
	for k in data:
		if not keys.has(k):
			keys.append(k)
	var out := PackedStringArray()
	for k in keys:
		if data.has(k):
			out.append_array(dump_entry(k, data[k], hints.get(k, "")))
	return out


## Réécrit seulement les propriétés modifiées. Les autres lignes (y compris les
## commentaires et la mise en forme d'Obsidian) restent identiques à l'octet près.
## `changes` : clé -> nouvelle valeur, ou REMOVE pour supprimer la propriété.
static func patch(lines: PackedStringArray, parsed: Dictionary, changes: Dictionary,
		hints := {}) -> PackedStringArray:
	var starts := {}
	for k in parsed.order:
		starts[parsed.ranges[k][0]] = k
	var out := PackedStringArray()
	var i := 0
	while i < lines.size():
		if starts.has(i):
			var key: String = starts[i]
			var rng: Array = parsed.ranges[key]
			if changes.has(key):
				var nv: Variant = changes[key]
				if not (typeof(nv) == TYPE_STRING and nv == REMOVE):
					out.append_array(dump_entry(key, nv, hints.get(key, "")))
			else:
				for j in range(rng[0], rng[1]):
					out.append(lines[j])
			i = rng[1]
			continue
		out.append(lines[i])
		i += 1
	for key in changes:
		if not parsed.data.has(key):
			var nv: Variant = changes[key]
			if not (typeof(nv) == TYPE_STRING and nv == REMOVE):
				out.append_array(dump_entry(key, nv, hints.get(key, "")))
	return out
