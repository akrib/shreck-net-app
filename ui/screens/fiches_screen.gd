extends VBoxContainer
## Écran « Fiches » : recherche globale (noms, alias, propriétés, texte) et
## liste par type, choisi d'un appui (avec le nombre de notes de chaque type).
## La liste est un tableau : une colonne par propriété utile du type (clan,
## âge, secte, domaine, statut pour un personnage ; niveau, débiteur, créancier
## pour une faveur…). Un appui sur un titre de colonne trie la liste ; les types
## datés (soirées, sources, faveurs…) viennent du plus récent. Un appui sur une
## ligne ouvre la note.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")

const TYPES := ["", "personnage", "soiree", "source", "faveur", "evenement", "indice", "groupe",
	"lieu", "domaine", "objet", "dossier", "concept", "en_cours"]
## Types nommés par leur date : le plus récent d'abord.
const DATED := ["soiree", "source", "faveur", "evenement", "en_cours"]
const PAGE := 3000
const SEARCH_MAX := 1000
## Colonnes de chaque type, après le nom : [propriété, titre].
const COLUMNS := {
	"personnage": [["clan", "Clan"], ["rang", "Âge"], ["secte", "Secte"], ["domaine", "Domaine"], ["statut", "Statut"]],
	"soiree": [["domaine", "Domaine"], ["nature", "Nature"]],
	"source": [["nature", "Nature"], ["auteur", "Auteur"], ["fiabilite", "Fiabilité"]],
	"faveur": [["niveau", "Niveau"], ["debiteur", "Débiteur"], ["creancier", "Créancier"], ["statut", "Statut"]],
	"evenement": [["statut", "Statut"], ["domaine", "Domaine"]],
	"indice": [["statut", "Statut"]],
	"groupe": [["nature", "Nature"], ["clan", "Clan"], ["secte", "Secte"], ["domaine", "Domaine"]],
	"lieu": [["nature", "Nature"], ["domaine", "Domaine"]],
	"domaine": [["region", "Région"]],
	"objet": [["nature", "Nature"], ["detenteur", "Détenteur"]],
	"dossier": [["statut", "Statut"], ["priorite", "Priorité"]],
	"concept": [["nature", "Nature"], ["secte", "Secte"]],
	"en_cours": [["statut", "Statut"], ["domaine", "Domaine"]],
}
## Valeur par défaut qu'on ne répète pas dans le tableau (seules les exceptions ressortent).
const QUIET := {"personnage.statut": "actif", "soiree.nature": "assemblee", "faveur.statut": "active"}
const MUTED := Color("a59cb3")
const ALERT := Color("ffb38a")
const ZEBRA := Color(1, 1, 1, 0.025)

var app: Node
var main: Control
var _search: LineEdit
var _types: HFlowContainer
var _group := ButtonGroup.new()
var _type := ""
var _limit := PAGE
var _table: Tree
var _info: Label
var _more: Button
var _timer: Timer
## Lignes chargées : [{path, name, type, cells: {clé: texte}, keys: {clé: clé de tri}, extrait}].
var _rows: Array = []
var _cols: Array = []
var _sort_key := ""
var _sort_desc := false
var _base_info := ""
var _base_order := ""
## Options des champs à liste, lues une fois par affichage.
static var _opts := {}


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_search = UiKit.line_edit("Rechercher : nom, alias, texte… (sans accents possible) — Entrée ouvre le premier, ↓ parcourt la liste")
	_search.text_changed.connect(func(_t): _timer.start())
	_search.text_submitted.connect(func(_t): submit())
	_search.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_DOWN:
			_focus_table()
			_search.accept_event())
	add_child(UiKit.hbox([_search, UiKit.button("+ Nouvelle", func(): main.new_note(), "Créer une note (Ctrl+N)")]))
	_types = UiKit.flow(6)
	add_child(_types)
	_info = UiKit.muted("")
	add_child(_info)
	_table = Tree.new()
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.hide_root = true
	_table.select_mode = Tree.SELECT_ROW
	_table.column_titles_visible = true
	_table.item_mouse_selected.connect(func(_pos, btn):
		if btn == MOUSE_BUTTON_LEFT:
			_open_selected())
	_table.item_activated.connect(_open_selected)
	_table.column_title_clicked.connect(func(c, _btn): _sort_by(c))
	# ↑ sur la première ligne, ou Échap : retour au champ de recherche
	_table.gui_input.connect(func(ev: InputEvent):
		if not (ev is InputEventKey and ev.pressed):
			return
		var first := _table.get_root().get_first_child() if _table.get_root() != null else null
		if ev.keycode == KEY_ESCAPE or (ev.keycode == KEY_UP and _table.get_selected() == first):
			_search.grab_focus()
			_table.accept_event())
	add_child(_table)
	_more = UiKit.button("Afficher plus", func():
		_limit += PAGE
		_refresh(), "Charger la suite de la liste")
	_more.visible = false
	add_child(UiKit.hbox([_more]))
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.25
	_timer.timeout.connect(func():
		_limit = PAGE
		_refresh())
	add_child(_timer)


func on_show() -> void:
	_build_types()
	_refresh()


func on_job_finished(_job: String, _result: Dictionary) -> void:
	if is_inside_tree():
		_build_types()
		_refresh()


func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


## Entrée dans la recherche : résultats à jour, puis ouverture du premier.
func submit() -> void:
	_timer.stop()
	_limit = PAGE
	_refresh()
	if _table.get_root() != null and _table.get_root().get_first_child() != null:
		var first := _table.get_root().get_first_child()
		first.select(0)
		main.open_note(str(first.get_metadata(0)))


## ↓ depuis la recherche : la première ligne du tableau est choisie, Entrée l'ouvre.
func _focus_table() -> void:
	if _timer.time_left > 0.0:
		_timer.stop()
		_limit = PAGE
		_refresh()
	var root := _table.get_root()
	if root == null or root.get_first_child() == null:
		return
	var first := root.get_first_child()
	_table.grab_focus()
	first.select(0)
	_table.scroll_to_item(first)


## Sélectionne un type (clé de Schema, "" = tous) ; utile aussi depuis d'autres écrans.
func select_type(t: String) -> void:
	_type = t
	_limit = PAGE
	_sort_key = ""
	for b in _types.get_children():
		if b is Button:
			b.set_pressed_no_signal(str(b.get_meta("type", "")) == t)
	_refresh()


## Nombre de lignes affichées (pour les tests).
func row_count() -> int:
	return _rows.size()


func _build_types() -> void:
	for c in _types.get_children():
		c.queue_free()
	if app.index == null:
		return
	var counts: Dictionary = app.index.stats().types
	var total := 0
	for k in counts:
		total += int(counts[k])
	for t in TYPES:
		var n: int = total if t == "" else int(counts.get(t, 0))
		if t != "" and n == 0:
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.custom_minimum_size.y = UiKit.TOUCH
		b.text = "%s  %d" % ["Tout" if t == "" else Schema.type_label(t), n]
		b.set_meta("type", t)
		b.set_meta("count", n)
		b.button_pressed = t == _type
		var tt: String = t
		b.pressed.connect(func(): select_type(tt))
		_types.add_child(b)


func _refresh() -> void:
	_rows = []
	_more.visible = false
	if app.index == null:
		_fill()
		_info.text = "Aucun index : configurez le dossier du coffre (Réglages)."
		return
	var q := _search.text.strip_edges()
	var t0 := Time.get_ticks_msec()
	var found: Array = app.index.search(q, SEARCH_MAX, _type) if q != "" else app.index.list_by_type(_type, _limit, _type in DATED)
	var ms := Time.get_ticks_msec() - t0
	var keys := {}
	for t in COLUMNS:
		for c in COLUMNS[t]:
			keys[c[0]] = true
	var props: Dictionary = app.index.props_for(found.map(func(r): return str(r.path)), keys.keys())
	_opts.clear()
	for r in found:
		var ty := str(r.type)
		var p: Dictionary = props.get(str(r.path), {})
		var row := {"path": str(r.path), "name": str(r.name), "type": ty, "cells": {}, "props": p,
			"extrait": str(r.get("extrait", "")).replace("\n", " ").strip_edges().left(160)}
		if _type == "":
			row.cells["detail"] = detail(ty, p)
		else:
			for c in COLUMNS.get(ty, []):
				row.cells[c[0]] = cell(ty, c[0], p)
		row.cells["type"] = Schema.type_label(ty)
		_rows.append(row)
	_fill()
	if q == "":
		var total := 0
		for b in _types.get_children():
			if b is Button and str(b.get_meta("type", "")) == _type:
				total = int(b.get_meta("count", 0))
		var order := "du plus récent au plus ancien" if _type in DATED else "ordre alphabétique"
		var shown := ("%d sur %d" % [_rows.size(), total]) if total > _rows.size() else str(_rows.size())
		_base_info = shown
		_base_order = order
		_more.visible = _rows.size() >= _limit and total > _rows.size()
	else:
		var mode := "plein texte" if app.index.fts else "recherche simple"
		_base_info = "%d résultat(s) en %d ms (%s)" % [_rows.size(), ms, mode]
		if _rows.size() >= SEARCH_MAX:
			_base_info = "les %d premiers résultats en %d ms (%s) : précisez la recherche" % [_rows.size(), ms, mode]
		_base_order = "les plus pertinents d'abord"
	_show_info()


## Colonnes affichées : nom, puis celles du type (ou type et détail pour « Tout »),
## puis l'extrait trouvé lors d'une recherche.
func _columns() -> Array:
	var cols := [["name", "Nom", 3.0]]
	if _type == "":
		cols.append(["type", "Type", 1.0])
		cols.append(["detail", "Détail", 4.0])
	else:
		for c in COLUMNS.get(_type, []):
			var ratio := 1.0
			if c[0] in ["debiteur", "creancier", "auteur", "detenteur"]:
				ratio = 1.6
			elif c[0] == "fiabilite":
				ratio = 0.5
			cols.append([c[0], c[1], ratio])
	if _rows.any(func(r): return str(r.extrait) != ""):
		cols.append(["extrait", "Extrait", 4.0])
	return cols


func _fill() -> void:
	_table.clear()
	_cols = _columns()
	_table.columns = _cols.size()
	for i in _cols.size():
		var c: Array = _cols[i]
		var arrow := ""
		if c[0] == _sort_key:
			arrow = "  ▼" if _sort_desc else "  ▲"
		_table.set_column_title(i, c[1] + arrow)
		_table.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		_table.set_column_expand(i, true)
		_table.set_column_expand_ratio(i, c[2])
		_table.set_column_clip_content(i, true)
	_show_info()
	var rows := _sorted()
	var root := _table.create_item()
	var n := 0
	for r in rows:
		var it := _table.create_item(root)
		it.set_metadata(0, r.path)
		for i in _cols.size():
			var key: String = _cols[i][0]
			var text := str(r.name) if key == "name" else str(r.extrait if key == "extrait" else r.cells.get(key, ""))
			it.set_text(i, text)
			it.set_tooltip_text(i, r.path if key == "name" else text)
			if key == "type":
				it.set_custom_color(i, Color(str(Schema.TYPES.get(r.type, {}).get("color", "a59cb3"))))
			elif key == "statut" and r.type == "personnage" and text != "":
				it.set_custom_color(i, ALERT)
			elif key != "name":
				it.set_custom_color(i, MUTED)
			if n % 2 == 1:
				it.set_custom_bg_color(i, ZEBRA)
		n += 1


func _show_info() -> void:
	var how := _base_order + " · un appui sur un titre de colonne trie la liste"
	for c in _cols:
		if c[0] == _sort_key:
			how = "trié par %s (%s)" % [str(c[1]).to_lower(), "décroissant" if _sort_desc else "croissant"]
	_info.text = _base_info + " · " + how


func _sorted() -> Array:
	if _sort_key == "":
		return _rows
	var k := _sort_key
	var out := _rows.duplicate()
	for r in out:  # clés de tri calculées une fois, au premier tri sur cette colonne
		if not r.has("sk"):
			r["sk"] = {"name": TextNorm.fold(str(r.name))}
		if not r.sk.has(k):
			match k:
				"name":
					pass
				"type", "detail", "extrait":
					r.sk[k] = TextNorm.fold(str(r.extrait if k == "extrait" else r.cells.get(k, "")))
				_:
					r.sk[k] = sort_key(str(r.type), k, r.props)
	out.sort_custom(func(a, b):
		var ka: String = a.sk[k]
		var kb: String = b.sk[k]
		if ka == kb:
			return a.sk.name < b.sk.name
		if ka == "":
			return false  # les cases vides toujours en bas
		if kb == "":
			return true
		return (ka > kb) if _sort_desc else (ka < kb))
	return out


func _sort_by(col: int) -> void:
	if col < 0 or col >= _cols.size():
		return
	var k: String = _cols[col][0]
	if k == _sort_key:
		_sort_desc = not _sort_desc
	else:
		_sort_key = k
		_sort_desc = false
	_fill()


## Texte d'une case : libellé d'une liste (« Ancilla »), nom d'un lien, texte nu.
## Vide pour la valeur par défaut d'un champ (personnage actif, assemblée).
static func cell(ty: String, key: String, p: Dictionary) -> String:
	var v: Variant = p.get(key)
	if v == null:
		return ""
	var vals: Array = v if typeof(v) == TYPE_ARRAY else [v]
	var out := PackedStringArray()
	for x in vals:
		var s := str(x).strip_edges()
		if s == "" or s == "<null>" or QUIET.get(ty + "." + key, "\u0001") == s:
			continue
		if key == "fiabilite":
			pass  # la lettre seule (A à F)
		elif not _options(ty, key).is_empty():
			s = Schema.option_label(ty, key, s)
		elif s.begins_with("[["):
			s = Schema.link_name(s)
		out.append(Schema.display_text(s).strip_edges())
	return ", ".join(out)


## Clé de tri d'une case : rang dans la liste pour les champs à choix
## (Nouveau-né < Ancilla < Ancien…), texte sans accents sinon.
static func sort_key(ty: String, key: String, p: Dictionary) -> String:
	var opts := _options(ty, key)
	var v: Variant = p.get(key)
	if v == null or opts.is_empty():
		return TextNorm.fold(cell(ty, key, p))
	var first := str(v[0] if typeof(v) == TYPE_ARRAY and not v.is_empty() else v)
	if QUIET.get(ty + "." + key, "\u0001") == first:
		return ""
	for i in opts.size():
		if str(opts[i][0]) == first:
			return "%03d" % i
	return "999 " + TextNorm.fold(first)


static func _options(ty: String, key: String) -> Array:
	var k := ty + "." + key
	if not _opts.has(k):
		_opts[k] = Schema.options(ty, key)
	return _opts[k]


## Résumé d'une note sur une ligne (vue « Tout ») : les cases non vides de son type.
static func detail(ty: String, p: Dictionary) -> String:
	var parts := PackedStringArray()
	if ty == "faveur":
		parts.append(cell(ty, "niveau", p))
		parts.append("%s → %s" % [cell(ty, "debiteur", p), cell(ty, "creancier", p)])
		parts.append(cell(ty, "statut", p))
		return " · ".join(Array(parts).filter(func(x): return x != ""))
	for c in COLUMNS.get(ty, []):
		var s := cell(ty, c[0], p)
		if s != "":
			parts.append(("fiabilité " + s) if c[0] == "fiabilite" else s)
	return " · ".join(parts)


func _open_selected() -> void:
	var it := _table.get_selected()
	if it != null:
		main.open_note(str(it.get_metadata(0)))
