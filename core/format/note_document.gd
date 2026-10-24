extends RefCounted
## Une note Markdown : frontmatter + corps.
##
## Règle : une note non modifiée se réécrit à l'octet près (BOM, fins de ligne
## CRLF, absence de saut de ligne final). Seules les propriétés modifiées sont
## réécrites (FlatYaml.patch) ; le corps n'est touché que s'il a été édité.

const FlatYaml := preload("res://core/format/flat_yaml.gd")

var raw_text := ""
var has_bom := false
var eol := "\n"
var utf8_ok := true

var has_frontmatter := false
var unclosed := false            ## frontmatter ouvert mais jamais fermé
var fm_lines := PackedStringArray()
var fm: Dictionary = {}          ## résultat de FlatYaml.parse
var closing_has_eol := true
var body := ""                   ## texte exact après la ligne « --- » de fermeture
var body_first_line := 1         ## numéro (1-based) de la première ligne du corps

var _dirty := false


## Pour créer une note depuis un fil de travail : NoteDocument.new() puis load_bytes().
static func from_bytes(bytes: PackedByteArray) -> RefCounted:
	var doc = load("res://core/format/note_document.gd").new()
	doc.load_bytes(bytes)
	return doc


static func from_text(text: String) -> RefCounted:
	var doc = load("res://core/format/note_document.gd").new()
	if text.begins_with(String.chr(0xFEFF)):
		doc.has_bom = true
		text = text.substr(1)
	doc._load_text(text)
	return doc


func load_bytes(bytes: PackedByteArray) -> void:
	var b := bytes
	if b.size() >= 3 and b[0] == 0xEF and b[1] == 0xBB and b[2] == 0xBF:
		has_bom = true
		b = b.slice(3)
	var text := b.get_string_from_utf8()
	if text.to_utf8_buffer() != b:
		utf8_ok = false
	_load_text(text)


func _load_text(text: String) -> void:
	raw_text = text
	var crlf := text.count("\r\n")
	var lf := text.count("\n")
	eol = "\r\n" if crlf > 0 and crlf * 2 >= lf else "\n"
	var lines := text.split("\n")
	if lines.size() > 0 and lines[0].trim_suffix("\r") == "---":
		var close := -1
		for k in range(1, lines.size()):
			if lines[k].trim_suffix("\r").strip_edges(false, true) == "---":
				close = k
				break
		if close == -1:
			unclosed = true
			body = text
			body_first_line = 1
			fm = FlatYaml.parse(PackedStringArray())
			return
		has_frontmatter = true
		for k in range(1, close):
			fm_lines.append(lines[k].trim_suffix("\r"))
		closing_has_eol = close < lines.size() - 1
		body = "\n".join(lines.slice(close + 1)) if closing_has_eol else ""
		body_first_line = close + 2
	else:
		body = text
		body_first_line = 1
	fm = FlatYaml.parse(fm_lines)


func properties() -> Dictionary:
	return fm.get("data", {})


func type_name() -> String:
	var t: Variant = properties().get("type")
	return t if typeof(t) == TYPE_STRING else ""


func note_id() -> String:
	var i: Variant = properties().get("id")
	return i if typeof(i) == TYPE_STRING else ""


## Peut-on réécrire les propriétés sans risque ?
func can_edit_properties() -> bool:
	return utf8_ok and not unclosed and fm.get("ok", false)


## Applique des changements de propriétés. Renvoie "" si OK, sinon un message.
func set_properties(changes: Dictionary, hints := {}) -> String:
	if not can_edit_properties():
		return "propriétés illisibles : la note doit être corrigée à la main"
	if changes.is_empty():
		return ""
	fm_lines = FlatYaml.patch(fm_lines, fm, changes, hints)
	fm = FlatYaml.parse(fm_lines)
	if not fm.ok:
		return "les nouvelles propriétés ne sont pas valides : " + str(fm.errors[0].msg)
	has_frontmatter = true
	_dirty = true
	return ""


## Remplace le corps. `new_body` utilise "\n" (comme TextEdit).
func set_body(new_body: String) -> void:
	var b := new_body.replace("\r\n", "\n")
	if eol == "\r\n":
		b = b.replace("\n", "\r\n")
	if b == body:
		return
	body = b
	_dirty = true


## Corps avec des fins de ligne "\n" (pour l'affichage).
func body_for_edit() -> String:
	return body.replace("\r\n", "\n")


func is_dirty() -> bool:
	return _dirty


func to_text() -> String:
	if not _dirty:
		return raw_text
	if not has_frontmatter:
		return body
	var s := "---" + eol
	for l in fm_lines:
		s += l + eol
	s += "---"
	if closing_has_eol or body != "":
		s += eol
	return s + body


func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	if has_bom:
		out.append_array(PackedByteArray([0xEF, 0xBB, 0xBF]))
	out.append_array(to_text().to_utf8_buffer())
	return out
