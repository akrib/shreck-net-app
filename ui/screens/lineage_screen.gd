extends VBoxContainer
## Écran « Filiations » (core/analysis/lineage.gd), deux onglets :
##  - Sires et infants : les lignages en arbres, génération par génération.
##    Trait plein : lien sûr (fiche, crédibilité 1 à 3) ; pointillés : incertain ;
##    rouge : un second sire pour le même infant. Une personne choisie montre
##    d'où vient chaque lien, et « + Sire », « + Infant ».
##  - Clans et lignées : chaque clan, ses lignées et leurs membres connus.
## Lecture seule, sauf les ajouts faits par la fenêtre « + » (add_info.gd).

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Lineage := preload("res://core/analysis/lineage.gd")
const Members := preload("res://core/analysis/members.gd")
const TreeView := preload("res://ui/widgets/tree_view.gd")
const AddInfo := preload("res://ui/widgets/add_info.gd")

const PALETTE := [Color("8fd3ff"), Color("c8b6ff"), Color("9be3a8"), Color("f5e08a"), Color("ff8aa8"),
	Color("ffb38a"), Color("7fd59b"), Color("d7a6ff"), Color("e0b04a"), Color("5d8fb8")]
const MAX_LEAVES := 12

var app: Node
var main: Control
var tab := "sires"
var focus_name := ""
var _tab_buttons := {}
var _search: LineEdit
var _info: Label
var tree: Control
var _side: VBoxContainer
var _fams: Array = []
var _clans: Array = []
var _loaded := false
var _family_of := {}    ## clé de personne -> indice de famille
var _group_rows := {}   ## clé de nœud (clans) -> {kind, name, path}


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var bar := UiKit.flow(6)
	for t in [["sires", "Sires et infants"], ["lignees", "Clans et lignées"]]:
		var key: String = t[0]
		var b := UiKit.button(t[1], func(): show_tab(key))
		b.toggle_mode = true
		_tab_buttons[key] = b
		bar.add_child(b)
	_search = UiKit.line_edit("Trouver une personne, un clan, une lignée…")
	_search.custom_minimum_size.x = 340
	_search.size_flags_horizontal = Control.SIZE_FILL
	_search.text_submitted.connect(func(t): find(t))
	bar.add_child(_search)
	bar.add_child(UiKit.button("Voir tout", func(): tree.fit_view(), "Tous les arbres à l'écran"))
	bar.add_child(UiKit.button("Recalculer", func():
		_loaded = false
		_refresh(), "Relire l'index (après une synchronisation)"))
	add_child(bar)
	_info = UiKit.muted("")
	add_child(_info)
	var body := UiKit.hbox([], 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree = TreeView.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.node_selected.connect(_on_select)
	tree.node_activated.connect(_on_activate)
	body.add_child(tree)
	_side = UiKit.vbox([], 8)
	var side_scroll := UiKit.scroll(_side)
	side_scroll.custom_minimum_size.x = 400
	side_scroll.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(side_scroll)
	add_child(body)


func on_show() -> void:
	_refresh()


func on_job_finished(_job: String, _result: Dictionary) -> void:
	_loaded = false
	if is_inside_tree():
		_refresh()


## Ouvre un onglet, centré sur une personne ou un groupe ("" = tout).
func open(p_tab: String, p_focus := "") -> void:
	tab = p_tab
	focus_name = p_focus


func show_tab(key: String) -> void:
	tab = key
	focus_name = ""
	_refresh()


func _load() -> void:
	if _loaded or app.index == null:
		return
	_fams = Lineage.families(app.index)
	_clans = Lineage.clans_tree(app.index)
	_family_of.clear()
	for i in _fams.size():
		for k in _fams[i].nodes:
			_family_of[k] = i
	_loaded = true


func _refresh() -> void:
	for k in _tab_buttons:
		_tab_buttons[k].set_pressed_no_signal(k == tab)
	if app.index == null:
		_info.text = "Aucun coffre ouvert."
		tree.set_forest([])
		return
	_load()
	if tab == "lignees":
		_build_clans()
	else:
		_build_sires()


static func color_of(name: String) -> Color:
	if name == "":
		return Color("8a7fa0")
	return PALETTE[absi(hash(TextNorm.fold(name))) % PALETTE.size()]


# ------------------------------------------------------------------ sires et infants

func _build_sires() -> void:
	var forest := []
	var n_links := 0
	var n_conf := 0
	for f in _fams:
		forest.append(_family_tree(f))
		n_links += (f.links as Array).size()
		n_conf += (f.conflicts as Dictionary).size()
	var fk := TextNorm.name_key(focus_name)
	_info.text = ("%d lignage(s), %d lien(s) sire → infant%s. Trait plein : lien sûr (fiche, crédibilité 1 à 3) ; pointillés : incertain ; rouge : un second sire pour le même infant. Double appui : ouvrir la fiche." % [
		_fams.size(), n_links, (" · %d infant(s) à deux sires" % n_conf) if n_conf > 0 else ""]) if not _fams.is_empty() \
		else "Aucun sire ni infant connu dans vos notes. Sur une fiche de personnage : « + Relation » (est le sire de), ou la propriété Sire."
	tree.set_forest(forest, fk if _family_of.has(fk) else "")
	if focus_name != "" and not _family_of.has(fk):
		_side_person_unknown(focus_name)
	elif _family_of.has(fk):
		_on_select(fk)
	else:
		_side_help()


func _family_tree(f: Dictionary) -> Dictionary:
	var nodes := {}
	var children := {}
	var styles := {}
	var extra := []
	for k in f.nodes:
		var n: Dictionary = f.nodes[k]
		var sub := PackedStringArray()
		if str(n.clan) != "":
			sub.append(str(n.clan))
		if str(n.rang) != "":
			sub.append(Schema.option_label("personnage", "rang", n.rang))
		if str(n.statut) not in ["", "actif"]:
			sub.append(Schema.option_label("personnage", "statut", n.statut).to_lower())
		if str(n.path) == "":
			sub.append("pas de fiche")
		nodes[k] = {"label": ("† " if str(n.statut) == "mort_finale" else "") + str(n.name), "sub": " · ".join(sub),
			"color": color_of(str(n.clan)), "faded": str(n.statut) in ["mort_finale", "disparu"]}
	for l in f.links:
		if str(f.parent.get(l.ik, "")) == l.sk:
			if not children.has(l.sk):
				children[l.sk] = []
			children[l.sk].append(l.ik)
			styles["%s>%s" % [l.sk, l.ik]] = "solid" if l.sure else "dashed"
		else:
			extra.append({"a": l.sk, "b": l.ik})
	for k in children:
		(children[k] as Array).sort_custom(func(a, b): return TextNorm.fold(str(f.nodes[a].name)) < TextNorm.fold(str(f.nodes[b].name)))
	return {"title": "%s · %d pers. · %d gén." % [f.label, f.size, f.depth], "nodes": nodes, "roots": f.roots,
		"children": children, "styles": styles, "extra": extra}


func _side_clear() -> void:
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()


func _side_help() -> void:
	_side_clear()
	_side.add_child(UiKit.heading("Lignages"))
	_side.add_child(UiKit.muted("Choisissez une personne dans un arbre : ses sires et ses infants s'affichent ici, avec la note d'où vient chaque lien."))
	for i in mini(_fams.size(), 40):
		var f: Dictionary = _fams[i]
		var root: String = f.root
		_side.add_child(UiKit.list_row(str(f.label), "%d · %d gén." % [f.size, f.depth], func():
			tree.select(root)
			tree.focus_on(root)))


func _side_person_unknown(name: String) -> void:
	_side_clear()
	_side.add_child(UiKit.heading(name))
	_side.add_child(UiKit.muted("Aucun sire ni infant connu pour cette personne."))
	_person_actions(name, TextNorm.name_key(name))


func _on_select(k: String) -> void:
	if tab == "lignees":
		_select_group(k)
		return
	if k == "" or not _family_of.has(k):
		_side_help()
		return
	var f: Dictionary = _fams[_family_of[k]]
	var n: Dictionary = f.nodes[k]
	_side_clear()
	_side.add_child(UiKit.heading(str(n.name)))
	var bits := PackedStringArray()
	for x in [n.clan, Schema.option_label("personnage", "rang", n.rang) if str(n.rang) != "" else "",
			Schema.option_label("personnage", "statut", n.statut) if str(n.statut) != "" else ""]:
		if str(x) != "":
			bits.append(str(x))
	if not bits.is_empty():
		_side.add_child(UiKit.muted(" · ".join(bits)))
	if f.conflicts.has(k):
		_side.add_child(UiKit.warn("Deux sires différents dans vos notes : à trancher (Enquête → À trancher)."))
	_links_block("Sire", k, f, true)
	_links_block("Infants", k, f, false)
	_person_actions(str(n.name), k)


func _links_block(title: String, k: String, f: Dictionary, sires: bool) -> void:
	var rows := (f.links as Array).filter(func(l): return (l.ik == k) if sires else (l.sk == k))
	_side.add_child(UiKit.label("%s (%d)" % [title, rows.size()], false, 16))
	if rows.is_empty():
		_side.add_child(UiKit.muted("Aucun connu."))
	for l in rows:
		var other: String = l.sire if sires else l.infant
		var ok_key: String = l.sk if sires else l.ik
		_side.add_child(UiKit.list_row(other, "", func():
			tree.select(ok_key)))
		for s in l.sources:
			var p: String = s.path
			var lbl := ("selon sa fiche" if s.origin == "fiche" else "crédibilité %d — %s" % [int(s.cred), s.label])
			var b := UiKit.button("   " + lbl, func(): main.open_note(p))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.flat = true
			b.add_theme_color_override("font_color", Color("a59cb3"))
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_side.add_child(b)


func _person_actions(name: String, k: String) -> void:
	var row := UiKit.flow(6)
	var p: String = app.index.path_of_name(name)
	if p != "":
		row.add_child(UiKit.button("Ouvrir la fiche", func(): main.open_note(p)))
		row.add_child(UiKit.button("+ Sire", func(): _add(name, 1), "Noter qui est son sire, avec la source"))
		row.add_child(UiKit.button("+ Infant", func(): _add(name, 0), "Noter un infant, avec la source"))
	_side.add_child(row)


## Fenêtre d'ajout : un élément « est le sire de », dans la source choisie.
func _add(name: String, dir: int) -> void:
	AddInfo.open_in(main, app, {"kind": "relation", "subject": name, "subject_type": "personnage", "relation": "sire_de", "dir": dir,
		"title": ("Sire de « %s »" if dir == 1 else "Infant de « %s »") % name}, func(msg: String):
			_loaded = false
			focus_name = name
			_refresh()
			main._set_status(msg))


func _on_activate(k: String) -> void:
	var name := ""
	if tab == "lignees":
		var g: Dictionary = _group_rows.get(k, {})
		var p := str(g.get("path", ""))
		if p != "":
			main.open_note(p)
		return
	if _family_of.has(k):
		name = str(_fams[_family_of[k]].nodes[k].name)
	var p: String = app.index.path_of_name(name) if name != "" else ""
	if p != "":
		main.open_note(p)


## Recherche : une personne (onglet sires) ou un clan, une lignée, un membre (onglet clans).
func find(q: String) -> void:
	var t := q.strip_edges()
	if t == "":
		tree.fit_view()
		return
	var fq := TextNorm.fold(t)
	if tab == "lignees":
		for k in _group_rows:
			if TextNorm.fold(str(_group_rows[k].name)).contains(fq):
				tree.select(k)
				tree.focus_on(k)
				return
		_info.text = "Rien trouvé pour « %s »." % t
		return
	for k in _family_of:
		if TextNorm.fold(str(_fams[_family_of[k]].nodes[k].name)).contains(fq):
			tree.select(k)
			tree.focus_on(k)
			return
	focus_name = t
	_side_person_unknown(t)


# ------------------------------------------------------------------ clans et lignées

func _build_clans() -> void:
	_group_rows.clear()
	var forest := []
	var n_lig := 0
	var fk := ""
	for c in _clans:
		var ck := "clan:" + str(c.name)
		_group_rows[ck] = {"kind": "clan", "name": str(c.name), "path": str(c.path), "members": int(c.members)}
		var nodes := {ck: {"label": str(c.name), "sub": ("clan · %d membre(s)" % int(c.members)) if str(c.path) != "" else "lignées sans clan connu",
			"color": color_of(str(c.name) if str(c.path) != "" else "")}}
		var children := {ck: []}
		for l in c.lignees:
			n_lig += 1
			var lk := "lig:" + str(l.name)
			_group_rows[lk] = {"kind": "lignee", "name": str(l.name), "path": str(l.path), "members": int(l.members)}
			nodes[lk] = {"label": str(l.name), "sub": "lignée · %d membre(s)" % int(l.members), "color": color_of(str(c.name)) if str(c.path) != "" else Color("8a7fa0")}
			children[ck].append(lk)
			# les membres connus de la lignée, en feuilles (les premiers seulement)
			if int(l.members) > 0:
				var ms: Array = Members.of_group(app.index, str(l.name))
				children[lk] = []
				for m in ms.slice(0, MAX_LEAVES):
					var mk := "mem:%s:%s" % [l.name, m.name]
					_group_rows[mk] = {"kind": "membre", "name": str(m.name), "path": str(m.path)}
					nodes[mk] = {"label": str(m.name), "sub": ", ".join(PackedStringArray(m.roles)), "color": color_of(str(c.name))}
					children[lk].append(mk)
				if ms.size() > MAX_LEAVES:
					var more := "more:" + str(l.name)
					_group_rows[more] = {"kind": "lignee", "name": str(l.name), "path": str(l.path)}
					nodes[more] = {"label": "… et %d autres" % (ms.size() - MAX_LEAVES), "sub": "voir la fiche de la lignée", "color": Color("8a7fa0"), "faded": true}
					children[lk].append(more)
		if focus_name != "" and fk == "":
			for k in nodes:
				if TextNorm.fold(str(nodes[k].label)) == TextNorm.fold(focus_name):
					fk = k
		forest.append({"title": "", "nodes": nodes, "roots": [ck], "children": children})
	_info.text = ("%d clan(s), %d lignée(s). Une lignée se rattache à son clan par sa propriété Clan. Double appui : ouvrir la fiche." % [
		_clans.filter(func(c): return str(c.path) != "").size(), n_lig]) if not _clans.is_empty() else "Aucun clan dans vos notes."
	tree.set_forest(forest, fk)
	if fk != "":
		_select_group(fk)
	else:
		_side_clear()
		_side.add_child(UiKit.heading("Clans et lignées"))
		_side.add_child(UiKit.muted("Choisissez un clan ou une lignée : ses membres connus s'affichent ici."))


func _select_group(k: String) -> void:
	_side_clear()
	var g: Dictionary = _group_rows.get(k, {})
	if g.is_empty():
		_side.add_child(UiKit.muted("Choisissez un clan ou une lignée."))
		return
	var name := str(g.name)
	var p := str(g.path)
	_side.add_child(UiKit.heading(name))
	var row := UiKit.flow(6)
	if p != "":
		row.add_child(UiKit.button("Ouvrir la fiche", func(): main.open_note(p)))
	if g.kind == "lignee" and p != "":
		row.add_child(UiKit.button("+ Membre", func():
			AddInfo.open_in(main, app, {"kind": "membre", "subject": name, "subject_type": "groupe", "group_nature": "lignee"}, func(msg: String):
				_loaded = false
				focus_name = name
				_refresh()
				main._set_status(msg)), "Noter qu'un personnage est de cette lignée, avec la source"))
	if g.kind == "membre" and p != "":
		row.add_child(UiKit.button("Sires et infants", func():
			open("sires", name)
			_refresh()))
	_side.add_child(row)
	match str(g.kind):
		"clan":
			_side.add_child(UiKit.muted("%d personnage(s) portent ce clan sur leur fiche. Les statistiques (Enquête → Statistiques, répartition par clan) les listent." % int(g.get("members", 0))))
		"lignee":
			var ms: Array = Members.of_group(app.index, name)
			_side.add_child(UiKit.label("Membres connus (%d)" % ms.size(), false, 16))
			if ms.is_empty():
				_side.add_child(UiKit.muted("Aucun membre connu. « + Membre » en ajoute un."))
			for m in ms:
				var mp: String = m.path
				_side.add_child(UiKit.list_row(Members.describe(m), "", func():
					if mp != "":
						main.open_note(mp)))
