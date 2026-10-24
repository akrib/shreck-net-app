extends Tree
## Tableau triable : un appui sur un titre de colonne trie la liste, un second
## inverse l'ordre ; un appui sur une ligne l'ouvre (signal `row_opened`).
## Les colonnes : [{key, title, ratio (largeur relative), min (largeur minimale, pixels),
## numeric (tri par nombre)}].
## Les lignes : [{path, cells: {clé: texte}, keys: {clé: valeur de tri} (facultatif),
## colors: {clé: Color} (facultatif)}]. Les cases vides vont toujours en bas.

signal row_opened(path: String)

const TextNorm := preload("res://core/format/text_norm.gd")
const MUTED := Color("a59cb3")
const ZEBRA := Color(1, 1, 1, 0.025)

var _cols: Array = []
var _rows: Array = []
var sort_key := ""
var sort_desc := false
## Colonnes écrites en clair (les autres sont grisées).
var bright := ["name"]


func setup(cols: Array) -> void:
	_cols = cols
	hide_root = true
	select_mode = Tree.SELECT_ROW
	column_titles_visible = true
	columns = cols.size()
	for i in cols.size():
		set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		set_column_expand(i, true)
		set_column_expand_ratio(i, float(cols[i].get("ratio", 1.0)))
		if cols[i].has("min"):
			set_column_custom_minimum_width(i, int(cols[i].min))
		set_column_clip_content(i, true)
	column_title_clicked.connect(func(c, _b): sort_by(c))
	item_mouse_selected.connect(func(_p, b):
		if b == MOUSE_BUTTON_LEFT:
			_open())
	item_activated.connect(_open)


func set_rows(rows: Array) -> void:
	_rows = rows
	_fill()


func row_count() -> int:
	return _rows.size()


func sort_by(c: int) -> void:
	if c < 0 or c >= _cols.size():
		return
	var k := str(_cols[c].key)
	if k == sort_key:
		sort_desc = not sort_desc
	else:
		sort_key = k
		sort_desc = bool(_cols[c].get("numeric", false))  # un nombre : le plus grand d'abord
	_fill()


func _open() -> void:
	var it := get_selected()
	if it != null and str(it.get_metadata(0)) != "":
		row_opened.emit(str(it.get_metadata(0)))


func _key(r: Dictionary, k: String, numeric: bool) -> Variant:
	var v: Variant = r.get("keys", {}).get(k, r.cells.get(k, ""))
	if numeric:
		return float(v) if str(v) != "" else null
	return TextNorm.fold(str(v))


func _sorted() -> Array:
	if sort_key == "":
		return _rows
	var numeric := false
	for c in _cols:
		if str(c.key) == sort_key:
			numeric = bool(c.get("numeric", false))
	var k := sort_key
	var out := _rows.duplicate()
	for r in out:
		r["_sk"] = _key(r, k, numeric)
		r["_sn"] = TextNorm.fold(str(r.cells.get("name", "")))
	out.sort_custom(func(a, b):
		var ka: Variant = a._sk
		var kb: Variant = b._sk
		var ea := ka == null or str(ka) == ""
		var eb := kb == null or str(kb) == ""
		if ea != eb:
			return eb  # les cases vides toujours en bas
		if ea or ka == kb:
			return a._sn < b._sn
		return (ka > kb) if sort_desc else (ka < kb))
	return out


func _fill() -> void:
	clear()
	for i in _cols.size():
		var t := str(_cols[i].title)
		if str(_cols[i].key) == sort_key:
			t += "  ▼" if sort_desc else "  ▲"
		set_column_title(i, t)
	var root := create_item()
	var n := 0
	for r in _sorted():
		var it := create_item(root)
		it.set_metadata(0, str(r.get("path", "")))
		var colors: Dictionary = r.get("colors", {})
		for i in _cols.size():
			var k := str(_cols[i].key)
			var text := str(r.cells.get(k, ""))
			it.set_text(i, text)
			it.set_tooltip_text(i, text)
			if colors.has(k):
				it.set_custom_color(i, colors[k])
			elif not bright.has(k):
				it.set_custom_color(i, MUTED)
			if n % 2 == 1:
				it.set_custom_bg_color(i, ZEBRA)
		n += 1
