extends VBoxContainer
## Écran « Statistiques » (core/analysis/stats.gd), deux onglets :
##  - Personnages : filtres sur le statut et sur le nombre d'informations ou de
##    rétroliens ; camembert de la répartition choisie (statut, âge, ville, clan,
##    secte, discipline) ; une part choisie liste ses personnages.
##  - Informations : chiffres clés, camembert (fiabilité, crédibilité, cote de
##    l'Amirauté, nature, type de note, année, domaine, voix), grille de
##    l'Amirauté ; une part ou une case choisie liste ses éléments.
## Rien n'est écrit.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const Stats := preload("res://core/analysis/stats.gd")
const PieChart := preload("res://ui/widgets/pie_chart.gd")
const SortTable := preload("res://ui/widgets/sort_table.gd")

const STATUTS := [["actif", "Actif"], ["torpeur", "Torpeur"], ["disparu", "Disparu"], ["mort_finale", "Mort finale"],
	["inconnu", "Inconnu"], ["", "Non renseigné"]]
const PIE_SIZE := 400.0

var app: Node
var main: Control
var tab := "personnages"
var _tab_buttons := {}
var _body: VBoxContainer
var _people: Array = []
var _infos: Array = []
var _loaded := false
# personnages
var _p_dim := "statut"
var _p_statuts := {}
var _p_min_infos := 0
var _p_min_back := 0
var _p_rows: Array = []
var _p_filtered: Array = []
# informations
var _i_dim := "fiab"
var _i_domaine := ""
var _i_rows: Array = []
var _i_filtered: Array = []
var _i_cell := ""
## Répartitions dont la part « non renseigné » est masquée ("p:discipline", "i:voice"…).
var _hide_empty := {"p:discipline": true, "i:voice": true}
# widgets courants
var _pie: Control
var _legend: VBoxContainer
var _table: Tree
var _info: Label
var _grid: GridContainer
var _holder: HBoxContainer


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var bar := UiKit.flow(6)
	for t in [["personnages", "Personnages"], ["informations", "Informations"]]:
		var key: String = t[0]
		var b := UiKit.button(t[1], func(): show_tab(key))
		b.toggle_mode = true
		_tab_buttons[key] = b
		bar.add_child(b)
	bar.add_child(UiKit.button("Recalculer", func():
		_loaded = false
		_refresh(), "Relire l'index (après une synchronisation)"))
	add_child(bar)
	_body = UiKit.vbox([], 8)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)


func on_show() -> void:
	_refresh()


func on_job_finished(_job: String, _result: Dictionary) -> void:
	_loaded = false
	if is_inside_tree():
		_refresh()


func show_tab(key: String) -> void:
	tab = key
	_refresh()


func _load() -> void:
	if _loaded or app.index == null:
		return
	_people = Stats.people(app.index)
	_infos = Stats.infos(app.index)
	_loaded = true


func _refresh() -> void:
	for k in _tab_buttons:
		_tab_buttons[k].set_pressed_no_signal(k == tab)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if app.index == null:
		_body.add_child(UiKit.label("Aucun coffre ouvert."))
		return
	_load()
	if tab == "informations":
		_build_infos()
	else:
		_build_people()


# ------------------------------------------------------------------ éléments communs

func _dim_picker(dims: Array, current: String, cb: Callable) -> OptionButton:
	var o := UiKit.option_button(dims.map(func(d): return d[1]), maxi(0, dims.map(func(d): return d[0]).find(current)))
	o.size_flags_horizontal = Control.SIZE_FILL
	o.custom_minimum_size.x = 330
	o.item_selected.connect(func(i): cb.call(str(dims[i][0])))
	return o


func _spin(value: int, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = 9999
	s.value = value
	s.custom_minimum_size = Vector2(110, UiKit.TOUCH)
	s.value_changed.connect(func(v): cb.call(int(v)))
	return s


## Camembert et légende ; `on_select(keys)` reçoit les valeurs de la part choisie ([] = aucune).
func _pie_block(rows: Array, on_select: Callable) -> Control:
	_pie = PieChart.new()
	_pie.custom_minimum_size = Vector2(PIE_SIZE, PIE_SIZE)
	_legend = UiKit.vbox([], 2)
	_pie.slice_selected.connect(func(i):
		_mark_legend(i)
		on_select.call([] if i < 0 else _pie.slices[i].keys))
	_pie.set_rows(rows)
	for i in _pie.slices.size():
		var s: Dictionary = _pie.slices[i]
		var sw := ColorRect.new()
		sw.color = s.color
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var idx: int = i
		var row := UiKit.list_row(str(s.label), "%d · %s" % [s.value, _pie.pct(s.value)], func(): _pie.select(idx))
		row.custom_minimum_size.y = 32
		var h: HBoxContainer = row.get_child(0)
		h.add_child(sw)
		h.move_child(sw, 0)
		_legend.add_child(row)
	var col := UiKit.vbox([_pie, UiKit.muted("Un appui sur une part (ou sur la légende) la détaille à droite ; un second appui la retire."), _legend], 6)
	col.custom_minimum_size.x = PIE_SIZE + 20
	return UiKit.scroll(col)


## Case « masquer les non renseignés » de la répartition `key` ("p:clan", "i:voice"…).
func _hide_box(key: String, none_label: String, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = "Masquer « %s »" % none_label
	c.button_pressed = bool(_hide_empty.get(key, false))
	c.tooltip_text = "Retire du camembert et du tableau ce qui n'a pas de valeur pour cette répartition."
	c.toggled.connect(func(on: bool):
		_hide_empty[key] = on
		cb.call())
	return c


static func _without_empty(rows: Array) -> Array:
	return rows.filter(func(r): return str(r[0]) != "" and str(r[0]) != "??")


func _mark_legend(i: int) -> void:
	for j in _legend.get_child_count():
		var b: Control = _legend.get_child(j)
		b.modulate = Color(1, 1, 1, 1) if i < 0 or i == j else Color(1, 1, 1, 0.45)


# ------------------------------------------------------------------ personnages

func _build_people() -> void:
	var bar := UiKit.flow(8)
	bar.add_child(UiKit.label("Répartition par", false, 15))
	bar.add_child(_dim_picker(Stats.PEOPLE_DIMS, _p_dim, func(d):
		_p_dim = d
		_refresh()))
	bar.add_child(UiKit.label("   Statut :", false, 15))
	for s in STATUTS:
		var code: String = s[0]
		var b := Button.new()
		b.text = s[1]
		b.toggle_mode = true
		b.button_pressed = _p_statuts.has(code)
		b.custom_minimum_size.y = UiKit.TOUCH
		b.tooltip_text = "Aucun bouton enfoncé : tous les statuts"
		b.toggled.connect(func(on: bool):
			if on:
				_p_statuts[code] = true
			else:
				_p_statuts.erase(code)
			_refresh())
		bar.add_child(b)
	_body.add_child(bar)
	var bar2 := UiKit.flow(8)
	bar2.add_child(UiKit.label("Au moins", false, 15))
	bar2.add_child(_spin(_p_min_infos, func(v):
		_p_min_infos = v
		_refresh_people_data()))
	bar2.add_child(UiKit.label("information(s), et au moins", false, 15))
	bar2.add_child(_spin(_p_min_back, func(v):
		_p_min_back = v
		_refresh_people_data()))
	bar2.add_child(UiKit.label("note(s) qui en parlent (rétroliens)", false, 15))
	bar2.add_child(UiKit.label("   ", false, 15))
	bar2.add_child(_hide_box("p:" + _p_dim, Stats.label(_p_dim, ""), _refresh_people_data))
	_body.add_child(bar2)
	_info = UiKit.muted("")
	_body.add_child(_info)
	_holder = UiKit.hbox([], 16)
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_holder)
	_refresh_people_data()


func _refresh_people_data() -> void:
	var holder := _holder
	if holder == null or not is_instance_valid(holder):
		return
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	_p_filtered = Stats.filter_people(_people, {"statuts": _p_statuts.keys(), "min_infos": _p_min_infos, "min_backlinks": _p_min_back})
	_p_rows = Stats.breakdown(_p_filtered, _p_dim)
	var hidden := 0
	if _p_hide():
		for r in _p_rows:
			if str(r[0]) == "":
				hidden = int(r[2])
		_p_rows = _without_empty(_p_rows)
	var with_info := _p_filtered.filter(func(p): return int(p.infos) > 0).size()
	_info.text = "%d personnage(s) retenu(s) sur %d · %d avec au moins une information · répartition par %s%s%s" % [
		_p_filtered.size(), _people.size(), with_info, _dim_label(Stats.PEOPLE_DIMS, _p_dim).to_lower(),
		" (une personne compte une fois par discipline)" if _p_dim == "discipline" else "",
		(" · %d « %s » masqué(s)" % [hidden, Stats.label(_p_dim, "").to_lower()]) if hidden > 0 else ""]
	holder.add_child(_pie_block(_p_rows, func(keys): _fill_people_table(keys)))
	_table = SortTable.new()
	_table.setup([{"key": "name", "title": "Personnage", "ratio": 2.2}, {"key": "clan", "title": "Clan", "ratio": 1.0},
		{"key": "rang", "title": "Âge", "ratio": 0.9, "min": 110}, {"key": "domaine", "title": "Ville", "ratio": 1.0},
		{"key": "statut", "title": "Statut", "ratio": 0.9, "min": 110}, {"key": "infos", "title": "Infos", "ratio": 0.5, "min": 70, "numeric": true},
		{"key": "backlinks", "title": "Rétroliens", "ratio": 0.6, "min": 100, "numeric": true}])
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.row_opened.connect(func(p): main.open_note(p))
	holder.add_child(_table)
	_fill_people_table([])


func _fill_people_table(keys: Array) -> void:
	var list := _p_filtered
	if not keys.is_empty():
		list = list.filter(func(p): return Stats.values_of(p, _p_dim).any(func(v): return keys.has(v)))
	elif _p_hide():
		list = list.filter(func(p): return Stats.values_of(p, _p_dim).any(func(v): return str(v) != ""))
	var rows := []
	for p in list:
		rows.append({"path": str(p.path), "cells": {"name": str(p.name), "clan": str(p.clan), "rang": Stats.label("rang", p.rang) if p.rang != "" else "",
			"domaine": str(p.domaine), "statut": Stats.label("statut", p.statut) if p.statut != "" else "", "infos": str(p.infos), "backlinks": str(p.backlinks)},
			"keys": {"rang": "%d" % Schema.options("personnage", "rang").map(func(o): return o[0]).find(p.rang) if p.rang != "" else ""}})
	_table.sort_key = "infos"
	_table.sort_desc = true
	_table.set_rows(rows)


func _p_hide() -> bool:
	return bool(_hide_empty.get("p:" + _p_dim, false))


func _i_hide() -> bool:
	return bool(_hide_empty.get("i:" + _i_dim, false))


static func _dim_label(dims: Array, key: String) -> String:
	for d in dims:
		if d[0] == key:
			return str(d[1])
	return key


# ------------------------------------------------------------------ informations

func _build_infos() -> void:
	var bar := UiKit.flow(8)
	bar.add_child(UiKit.label("Répartition par", false, 15))
	bar.add_child(_dim_picker(Stats.INFO_DIMS, _i_dim, func(d):
		_i_dim = d
		_i_cell = ""
		_refresh()))
	var doms := {}
	for x in _infos:
		if str(x.domaine) != "":
			doms[str(x.domaine)] = true
	var dl: Array = doms.keys()
	dl.sort()
	var items := ["Tous les domaines"] + dl
	var o := UiKit.option_button(items, maxi(0, items.find(_i_domaine)))
	o.size_flags_horizontal = Control.SIZE_FILL
	o.custom_minimum_size.x = 240
	o.item_selected.connect(func(i):
		_i_domaine = "" if i == 0 else str(items[i])
		_i_cell = ""
		_refresh())
	bar.add_child(o)
	bar.add_child(_hide_box("i:" + _i_dim, Stats.info_label(_i_dim, ""), func():
		_i_cell = ""
		_refresh()))
	_body.add_child(bar)
	_i_filtered = _infos if _i_domaine == "" else _infos.filter(func(x): return x.domaine == _i_domaine)
	# chiffres clés
	var s: Dictionary = Stats.info_summary(_i_filtered)
	var n: int = maxi(1, s.total)
	var figs := UiKit.flow(10)
	for f in [[str(s.total), "informations", "dans %d note(s)" % s.notes, Color("c8b6ff")],
			[_p(s.solid, n), "solides", "source A ou B, crédibilité 1 ou 2", Color("7fd59b")],
			[_p(s.weak, n), "fragiles", "source D ou E, ou crédibilité 4 ou 5", Color("ff7a6b")],
			[_p(s.unrated, n), "non évaluées", "ni fiabilité ni crédibilité (F, 6)", Color("a59cb3")],
			[_p(s.rumors, n), "rumeurs", "nature « rumeur »", Color("e0b04a")],
			[str(s.refuted), "improbables", "crédibilité 5", Color("ffb38a")]]:
		figs.add_child(_figure(f[0], f[1], f[2], f[3]))
	_body.add_child(figs)
	_info = UiKit.muted("")
	_body.add_child(_info)
	var holder := UiKit.hbox([], 16)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(holder)
	_i_rows = Stats.info_breakdown(_i_filtered, _i_dim)
	if _i_hide():
		_i_rows = _without_empty(_i_rows)
	holder.add_child(_pie_block(_i_rows, func(keys): _fill_info_table(keys, "")))
	var right := UiKit.vbox([], 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(UiKit.label("Échelle de l'Amirauté : fiabilité de la source (lignes) × crédibilité de l'information (colonnes). Un appui sur une case liste ses informations.", true, 14))
	_grid = _admiralty_grid()
	right.add_child(_grid)
	_table = SortTable.new()
	_table.setup([{"key": "name", "title": "Information", "ratio": 3.2}, {"key": "cote", "title": "Cote", "ratio": 0.4, "min": 70},
		{"key": "nature", "title": "Nature", "ratio": 0.8, "min": 110}, {"key": "note", "title": "Note", "ratio": 1.6},
		{"key": "year", "title": "Année", "ratio": 0.5, "min": 80}])
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.custom_minimum_size.y = 240
	_table.row_opened.connect(func(p): main.open_note(p))
	right.add_child(_table)
	holder.add_child(right)
	_fill_info_table([], "")


static func _p(a: int, n: int) -> String:
	return ("%.0f %%" % (100.0 * float(a) / float(n)))


func _figure(big: String, what: String, hint: String, col: Color) -> Control:
	var b := UiKit.label(big, false, 26)
	b.add_theme_color_override("font_color", col)
	var w := UiKit.label(what, false, 15)
	var h := UiKit.muted(hint)
	var c := UiKit.card([b, w, h], col)
	c.custom_minimum_size.x = 200
	c.tooltip_text = hint
	return c


func _admiralty_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	var counts: Dictionary = Stats.admiralty_grid(_i_filtered)
	var mx := 1
	for k in counts:
		mx = maxi(mx, int(counts[k]))
	var head := func(t: String, tip := "") -> Label:
		var l := UiKit.label(t, false, 14)
		l.custom_minimum_size = Vector2(64, 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Color("c8b6ff"))
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		return l
	g.add_child(head.call(""))
	for c in ["1", "2", "3", "4", "5", "6", "?"]:
		g.add_child(head.call(c, Stats.info_label("cred", c) if c != "?" else "Crédibilité non notée"))
	for f in ["A", "B", "C", "D", "E", "F", "?"]:
		g.add_child(head.call(f, Stats.info_label("fiab", f) if f != "?" else "Fiabilité non notée"))
		for c in ["1", "2", "3", "4", "5", "6", "?"]:
			var k: String = f + c
			var n := int(counts.get(k, 0))
			var b := Button.new()
			b.text = str(n) if n > 0 else "·"
			b.custom_minimum_size = Vector2(64, 34)
			var t := float(n) / float(mx)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("2d2636").lerp(_cell_color(f, c), clampf(0.15 + t * 0.85, 0.0, 1.0) if n > 0 else 0.0)
			sb.set_corner_radius_all(4)
			if k == _i_cell:
				sb.border_color = Color.WHITE
				sb.set_border_width_all(2)
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, sb)
			b.add_theme_color_override("font_color", Color("16131a") if t > 0.5 else Color("eae4f2"))
			b.tooltip_text = "%s · %s : %d information(s)" % [Stats.info_label("fiab", f if f != "?" else ""), Stats.info_label("cred", c if c != "?" else ""), n]
			b.disabled = n == 0
			b.pressed.connect(func():
				_i_cell = "" if _i_cell == k else k
				_refresh_grid_selection())
			g.add_child(b)
	return g


## Couleur d'une case : vert (solide) → or → rouge (fragile) ; gris si non évaluée.
static func _cell_color(f: String, c: String) -> Color:
	var fi := "ABCDEF".find(f)
	var ci := "123456".find(c)
	if fi < 0 or ci < 0 or f == "F" or c == "6":
		return Color("8a8296")
	var t := (float(fi) / 4.0 + float(ci) / 4.0) / 2.0
	return Color("7fd59b").lerp(Color("e0b04a"), clampf(t * 2.0, 0.0, 1.0)) if t < 0.5 else Color("e0b04a").lerp(Color("ff7a6b"), clampf((t - 0.5) * 2.0, 0.0, 1.0))


func _refresh_grid_selection() -> void:
	var parent := _grid.get_parent()
	var idx := _grid.get_index()
	_grid.queue_free()
	_grid = _admiralty_grid()
	parent.add_child(_grid)
	parent.move_child(_grid, idx)
	if _pie.selected >= 0:
		_pie.selected = -1
		_pie.queue_redraw()
		_mark_legend(-1)
	_fill_info_table([], _i_cell)


func _fill_info_table(keys: Array, cell: String) -> void:
	var list := _i_filtered
	var what := "toutes les informations"
	if not keys.is_empty():
		list = list.filter(func(x): return keys.has(str(x.get(_i_dim, ""))))
		what = "la part choisie"
		if _i_cell != "":
			_i_cell = ""
			_refresh_grid_only()
	elif cell != "":
		list = list.filter(func(x): return str(x.cote) == cell)
		what = "la case " + cell
	elif _i_hide():
		list = list.filter(func(x): return str(x.get(_i_dim, "")) not in ["", "??"])
		what = "toutes, sauf « %s »" % Stats.info_label(_i_dim, "").to_lower()
	_info.text = "%d information(s) — %s%s. Les 1 000 plus récentes s'affichent ; triez par colonne." % [list.size(), what,
		(" (domaine : %s)" % _i_domaine) if _i_domaine != "" else ""]
	var rows := []
	for x in list.slice(0, 1000):
		rows.append({"path": str(x.path), "cells": {"name": str(x.text), "cote": str(x.cote), "nature": Stats.info_label("nature", str(x.nature)).split(" (")[0],
			"note": str(x.note), "year": str(x.year)}})
	_table.set_rows(rows)


func _refresh_grid_only() -> void:
	var parent := _grid.get_parent()
	var idx := _grid.get_index()
	_grid.queue_free()
	_grid = _admiralty_grid()
	parent.add_child(_grid)
	parent.move_child(_grid, idx)
