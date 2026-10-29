extends VBoxContainer
## Écran « Filiations » (core/analysis/lineage.gd), deux onglets :
##  - Lignages : à partir d'un point de départ (une personne ou une lignée), ses
##    ascendants et toute sa descendance — sires, infants, lignées. Gris : sire →
##    infant (plein : sûr ; pointillés : incertain) ; violet : lignée (plein :
##    déclarée ; pointillés : déduite d'un infant) ; rouge : second sire, ou
##    lignées qui ne s'accordent pas. Une lignée qui a un chef (format 1.7) n'a pas
##    de case à elle : c'est la case de son chef, « Chef de la lignée de… », cadre
##    violet. « Tout afficher » montre tous les lignages.
##    « Exporter » copie le lignage affiché en Markdown dans le presse-papiers.
##  - Clans et lignées : chaque clan, ses lignées et leurs membres connus.
## Lecture seule, sauf les ajouts faits par la fenêtre « + » (add_info.gd).

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Lineage := preload("res://core/analysis/lineage.gd")
const Members := preload("res://core/analysis/members.gd")
const TreeView := preload("res://ui/widgets/tree_view.gd")
const AddInfo := preload("res://ui/widgets/add_info.gd")
const Picker := preload("res://ui/widgets/picker.gd")

const PALETTE := [Color("8fd3ff"), Color("c8b6ff"), Color("9be3a8"), Color("f5e08a"), Color("ff8aa8"),
	Color("ffb38a"), Color("7fd59b"), Color("d7a6ff"), Color("e0b04a"), Color("5d8fb8")]
const LIG_COLOR := Color("b79cff")
const MAX_LEAVES := 12
const LEGEND := "Gris : sire → infant (plein : sûr ; pointillés : incertain). Violet : lignée (plein : déclarée ; pointillés : déduite d'un infant). Cadre violet : chef de lignée, sa case montre la lignée. Rouge : second sire, ou lignées qui ne s'accordent pas. Double appui : ouvrir la fiche."

var app: Node
var main: Control
var tab := "sires"
var focus_name := ""
var start_key := ""      ## point de départ (clé de personne ou « lig:… »), "" = aucun
var show_all := false
var _tab_buttons := {}
var _search: LineEdit
var _start_btn: Button
var _info: Label
var tree: Control
var _side: VBoxContainer
var _fams: Array = []
var _clans: Array = []
var _loaded := false
var _family_of := {}    ## clé de nœud -> indice de famille
var _group_rows := {}   ## clé de nœud (clans) -> {kind, name, path}
var _shown: Array = []  ## [[famille, sous-ensemble ou null]] : ce que l'arbre affiche


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	# une note écrite ailleurs (un « + » d'une fiche, un chef de lignée…) : à recalculer
	app.notes_changed.connect(func(): _loaded = false)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var bar := UiKit.flow(6)
	bar.add_child(UiKit.button("← Enquête", func(): main.show_screen("enquete")))
	for t in [["sires", "Lignages"], ["lignees", "Clans et lignées"]]:
		var key: String = t[0]
		var b := UiKit.button(t[1], func(): show_tab(key))
		b.toggle_mode = true
		_tab_buttons[key] = b
		bar.add_child(b)
	_start_btn = UiKit.button("Point de départ…", _pick_start, "Une personne ou une lignée : ses ascendants et sa descendance")
	bar.add_child(_start_btn)
	_search = UiKit.line_edit("Trouver une personne, une lignée, un clan…")
	_search.custom_minimum_size.x = 300
	_search.size_flags_horizontal = Control.SIZE_FILL
	_search.text_submitted.connect(func(t): find(t))
	bar.add_child(_search)
	bar.add_child(UiKit.button("Tout afficher", func():
		show_all = true
		start_key = ""
		_refresh(), "Tous les lignages à l'écran"))
	bar.add_child(UiKit.button("Recadrer", func(): tree.fit_view(), "Tout ce qui est affiché à l'écran"))
	bar.add_child(UiKit.button("Exporter (Markdown)", export_to_clipboard, "Copier le lignage affiché dans le presse-papiers, en Markdown"))
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


## Ouvre un onglet, centré sur une personne, une lignée ou un clan ("" = rien de choisi).
func open(p_tab: String, p_focus := "") -> void:
	tab = p_tab
	focus_name = p_focus
	show_all = false
	start_key = ""


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
	_start_btn.visible = tab == "sires"
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


## Clé d'un nœud d'après son nom : la personne, sinon la lignée (ou la case de
## son chef, quand la lignée en a un).
func key_of(name: String) -> String:
	var k := TextNorm.name_key(name)
	if _family_of.has(k):
		return k
	var lk := Lineage.LIG_PREFIX + k
	if _family_of.has(lk):
		return lk
	for f in _fams:
		var nk := Lineage.node_key(f, lk)
		if nk != "" and _family_of.has(nk):
			return nk
	return ""


func node_of(k: String) -> Dictionary:
	return _fams[_family_of[k]].nodes[k] if _family_of.has(k) else {}


# ------------------------------------------------------------------ lignages

func _build_sires() -> void:
	if focus_name != "":
		start_key = key_of(focus_name)
		if start_key != "":
			show_all = false
	var n_links := 0
	var n_conf := 0
	var n_bad := 0
	for f in _fams:
		n_links += (f.links as Array).size()
		n_conf += (f.conflicts as Dictionary).size()
		n_bad += (f.incoherent as Dictionary).size()
	var summary := "%d lignage(s), %d lien(s) sire → infant%s%s. " % [_fams.size(), n_links,
		(" · %d infant(s) à deux sires" % n_conf) if n_conf > 0 else "", (" · %d personne(s) aux lignées incohérentes" % n_bad) if n_bad > 0 else ""]
	_shown = []
	if _fams.is_empty():
		_info.text = "Aucun sire, infant ni lignée connus dans vos notes. Sur une fiche de personnage : « + Relation » (est le sire de, est de la lignée de), ou la propriété Sire."
		tree.set_forest([])
		_start_btn.text = "Point de départ…"
		if focus_name != "":
			_side_unknown(focus_name)
		else:
			_side_help()
		return
	if show_all:
		for f in _fams:
			_shown.append([f, null])
	elif start_key != "" and _family_of.has(start_key):
		var f: Dictionary = _fams[_family_of[start_key]]
		_shown.append([f, Lineage.around(f, start_key)])
	_start_btn.text = ("Point de départ : %s" % node_of(start_key).name) if start_key != "" and _family_of.has(start_key) else "Point de départ…"
	var forest := []
	for sh in _shown:
		forest.append(_tree_of(sh[0], sh[1]))
	_info.text = summary + LEGEND if not _shown.is_empty() else summary + "Choisissez un point de départ (une personne ou une lignée), ou « Tout afficher »."
	tree.set_forest(forest, start_key if _family_of.has(start_key) else "")
	if focus_name != "" and start_key == "":
		_side_unknown(focus_name)
	elif start_key != "" and _family_of.has(start_key):
		_on_select(start_key)
	else:
		_side_help()


## Arbre affichable d'une famille, limité à `subset` (null = tout).
func _tree_of(f: Dictionary, subset: Variant) -> Dictionary:
	var inside := func(k: String) -> bool: return subset == null or (subset as Dictionary).has(k)
	var nodes := {}
	for k in f.nodes:
		if not inside.call(k):
			continue
		var n: Dictionary = f.nodes[k]
		if n.kind == "lignee":
			nodes[k] = {"label": str(n.name), "sub": "lignée" + ((" · " + str(n.clan)) if str(n.clan) != "" else "") + ("" if str(n.path) != "" else " · pas de fiche"),
				"color": LIG_COLOR, "kind": "group"}
			continue
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
		var heads: Array = n.get("heads", [])
		if not heads.is_empty():
			nodes[k]["head"] = Lineage.chef_mention(heads.map(func(lk): return Lineage.lignee_name(f, lk)))
	# parent retenu : celui de la famille s'il est affiché, sinon le premier lien affiché
	var primary := {}
	for e in f.edges:
		if inside.call(e.a) and inside.call(e.b) and str(f.parent.get(e.b, "")) == e.a:
			primary[e.b] = e.a
	for e in f.edges:
		if inside.call(e.a) and inside.call(e.b) and not primary.has(e.b):
			primary[e.b] = e.a
	var children := {}
	var styles := {}
	var extra := []
	var used := {}
	for e in f.edges:
		if not (inside.call(e.a) and inside.call(e.b)):
			continue
		if str(primary.get(e.b, "")) == e.a and not used.has(e.b):
			used[e.b] = true
			if not children.has(e.a):
				children[e.a] = []
			children[e.a].append(e.b)
			styles["%s>%s" % [e.a, e.b]] = e.style
		else:
			extra.append({"a": e.a, "b": e.b, "style": "bad" if e.kind == "sire" else e.style})
	for k in children:
		(children[k] as Array).sort_custom(func(a, b):
			var ga: bool = f.nodes[a].kind == "lignee"
			var gb: bool = f.nodes[b].kind == "lignee"
			return ga if ga != gb else TextNorm.fold(str(f.nodes[a].name)) < TextNorm.fold(str(f.nodes[b].name)))
	var roots := []
	for k in nodes:
		if not primary.has(k):
			roots.append(k)
	roots.sort_custom(func(a, b): return TextNorm.fold(str(f.nodes[a].name)) < TextNorm.fold(str(f.nodes[b].name)))
	var title := ("Autour de %s · %d nœud(s)" % [f.nodes[start_key].name, nodes.size()]) if subset != null and f.nodes.has(start_key) \
		else "%s · %d nœud(s) · %d niveau(x)" % [f.label, f.size, f.depth]
	return {"title": title, "nodes": nodes, "roots": roots, "children": children, "styles": styles, "extra": extra}


func _side_clear() -> void:
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()


func _side_help() -> void:
	_side_clear()
	_side.add_child(UiKit.heading("Lignages"))
	_side.add_child(UiKit.muted("Choisissez un point de départ : une personne ou une lignée. L'arbre montre ses ascendants et toute sa descendance, avec la note d'où vient chaque lien."))
	for i in mini(_fams.size(), 60):
		var f: Dictionary = _fams[i]
		var root: String = f.root
		_side.add_child(UiKit.list_row(str(f.label), "%d · %d niv." % [f.size, f.depth], func(): set_start(root)))


func _side_unknown(name: String) -> void:
	_side_clear()
	_side.add_child(UiKit.heading(name))
	_side.add_child(UiKit.muted("Aucun sire, infant ni lignée connus pour cette fiche."))
	_person_actions(name, TextNorm.name_key(name))


## Point de départ : une clé de nœud.
func set_start(k: String) -> void:
	start_key = k
	show_all = false
	focus_name = ""
	_refresh()


func _pick_start() -> void:
	Picker.open_in(main, app, "Point de départ du lignage", "notes", ["personnage", "groupe"], func(v):
		var nm := Schema.link_name(v)
		var k := key_of(nm)
		if k != "":
			set_start(k)
		else:
			start_key = ""
			show_all = false
			_refresh()
			_side_unknown(nm))


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
	if n.kind == "lignee":
		_side_lignee(k, f, false)
		return
	var heads: Array = n.get("heads", [])
	if not heads.is_empty():
		var hl := UiKit.label(Lineage.chef_mention(heads.map(func(lk): return Lineage.lignee_name(f, lk))), false, 16)
		hl.add_theme_color_override("font_color", LIG_COLOR)
		_side.add_child(hl)
	var bits := PackedStringArray()
	for x in [n.clan, Schema.option_label("personnage", "rang", n.rang) if str(n.rang) != "" else "",
			Schema.option_label("personnage", "statut", n.statut) if str(n.statut) != "" else ""]:
		if str(x) != "":
			bits.append(str(x))
	if not bits.is_empty():
		_side.add_child(UiKit.muted(" · ".join(bits)))
	if f.conflicts.has(k):
		_side.add_child(UiKit.warn("Deux sires différents dans vos notes : à trancher (Enquête → À trancher)."))
	if f.incoherent.has(k):
		_side.add_child(UiKit.warn("Lignées qui ne s'accordent pas : %s. Aucune ne descend de l'autre : si l'une est issue de l'autre, notez-le sur la fiche de la lignée (« est de la lignée de »)." % ", ".join(PackedStringArray(
			(f.incoherent[k] as Array).map(func(x): return Lineage.lignee_name(f, str(x)))))))
	_links_block("Sire", k, f, true)
	_links_block("Infants", k, f, false)
	_lignees_block(k, f, n)
	_person_actions(str(n.name), k)
	# les lignées qu'il dirige : leur parenté, leurs membres, leurs boutons
	for lk in heads:
		_side_lignee(str(lk), f, true)


func _source_button(s: Dictionary) -> Button:
	var p: String = s.path
	var lbl := ("selon sa fiche" if s.origin == "fiche" else "crédibilité %d — %s" % [int(s.cred), s.label])
	var b := UiKit.button("   " + lbl, func(): main.open_note(p))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.add_theme_color_override("font_color", Color("a59cb3"))
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


func _links_block(title: String, k: String, f: Dictionary, sires: bool) -> void:
	var rows := (f.links as Array).filter(func(l): return (l.ik == k) if sires else (l.sk == k))
	_side.add_child(UiKit.label("%s (%d)" % [title, rows.size()], false, 16))
	if rows.is_empty():
		_side.add_child(UiKit.muted("Aucun connu."))
	for l in rows:
		var other: String = l.sire if sires else l.infant
		var ok_key: String = l.sk if sires else l.ik
		_side.add_child(UiKit.list_row(other, "", func(): tree.select(ok_key)))
		for s in l.sources:
			_side.add_child(_source_button(s))


func _lignees_block(k: String, f: Dictionary, n: Dictionary) -> void:
	var ls: Dictionary = n.get("lignees", {})
	_side.add_child(UiKit.label("Lignées (%d)" % ls.size(), false, 16))
	if ls.is_empty():
		_side.add_child(UiKit.muted("Aucune connue."))
	for lk in ls:
		var m: Dictionary = ls[lk]
		var lname := Lineage.lignee_name(f, lk)
		var how := "déclarée" if m.declared else "déduite de son infant %s" % ", ".join(PackedStringArray((m.via as Array).map(func(x): return str(f.nodes[x].name) if f.nodes.has(x) else str(x))))
		if m.declared and (m.sources as Array).all(func(s): return str(s.origin) == "chef"):
			how = "chef de la lignée"
		var bad: bool = f.incoherent.has(k) and (f.incoherent[k] as Array).has(lk)
		var target := Lineage.node_key(f, lk)
		var row := UiKit.list_row(lname, how, func():
			if target != "" and target != k:
				tree.select(target))
		if bad:
			row.add_theme_color_override("font_color", Color("ff9b8a"))
		_side.add_child(row)
		for s in m.sources:
			_side.add_child(_source_button(s))


## Panneau d'une lignée : sa case à elle, ou la case de son chef (`under_chef`,
## la lignée vient alors sous la personne). Chef, lignée d'origine, lignées
## issues, membres déclarés et déduits, boutons.
func _side_lignee(lk: String, f: Dictionary, under_chef: bool) -> void:
	var li: Dictionary = (f.get("lignees", {}) as Dictionary).get(lk, {})
	var nm := Lineage.lignee_name(f, lk)
	var p := str(li.get("path", f.nodes[lk].path if f.nodes.has(lk) else ""))
	var clan := str(li.get("clan", f.nodes[lk].clan if f.nodes.has(lk) else ""))
	if under_chef:
		var h := UiKit.label(nm, true, 17)
		h.add_theme_color_override("font_color", LIG_COLOR)
		_side.add_child(h)
	_side.add_child(UiKit.muted("Lignée" + ((" · clan " + clan) if clan != "" else "") + ("" if p != "" else " · pas de fiche")))
	var chef := str(li.get("chef", ""))
	if chef != "" and not under_chef:
		var ck := str(li.get("chef_key", ""))
		_side.add_child(UiKit.list_row("Chef : " + chef, "", func():
			if f.nodes.has(ck):
				tree.select(ck)))
	elif chef == "" and p != "":
		_side.add_child(UiKit.muted("Chef de lignée : non renseigné (recommandé : la lignée est alors montrée par lui, et ses lignées se déduisent)."))
		for c in Lineage.chef_candidates(app.index, nm, clan).slice(0, 1):
			var cand := str(c)
			_side.add_child(UiKit.button("Chef : %s (d'après le nom)" % cand, func(): _set_chef(nm, p, cand), "Écrire « chef: [[%s]] » dans la fiche de la lignée" % cand))
	var up: Dictionary = li.get("parents", {})
	_side.add_child(UiKit.label("Issue de (%d)" % up.size(), false, 16))
	for par in up:
		var pk := Lineage.node_key(f, str(par))
		_side.add_child(UiKit.list_row(Lineage.lignee_name(f, str(par)), "", func():
			if pk != "":
				tree.select(pk)))
		for s in up[par]:
			_side.add_child(_source_button(s))
	var down: Array = li.get("children", [])
	if not down.is_empty():
		_side.add_child(UiKit.label("Lignées issues (%d)" % down.size(), false, 16))
		for ch in down:
			var ck2 := Lineage.node_key(f, str(ch))
			_side.add_child(UiKit.list_row(Lineage.lignee_name(f, str(ch)), "", func():
				if ck2 != "":
					tree.select(ck2)))
	var declared := []
	var deduced := []
	for pk in f.nodes:
		var ls: Dictionary = f.nodes[pk].get("lignees", {})
		if f.nodes[pk].kind == "personne" and ls.has(lk) and str(li.get("chef_key", "")) != pk:
			(declared if ls[lk].declared else deduced).append(pk)
	for pair in [["Membres déclarés", declared], ["Membres déduits (sires de membres)", deduced]]:
		_side.add_child(UiKit.label("%s (%d)" % [pair[0], (pair[1] as Array).size()], false, 16))
		for pk in pair[1]:
			var kk: String = pk
			_side.add_child(UiKit.list_row(str(f.nodes[kk].name), "", func(): tree.select(kk)))
	var row := UiKit.flow(6)
	if p != "":
		row.add_child(UiKit.button("Fiche de la lignée" if under_chef else "Ouvrir la fiche", func(): main.open_note(p)))
	if not under_chef:
		row.add_child(UiKit.button("Partir d'ici", func(): set_start(Lineage.node_key(f, lk)), "Point de départ : cette lignée"))
	if p != "":
		row.add_child(UiKit.button("+ Membre", func(): _add_info({"kind": "membre", "subject": nm, "subject_type": "groupe", "group_nature": "lignee"}, nm),
			"Noter qu'un personnage est de cette lignée, avec la source"))
		row.add_child(UiKit.button("+ Lignée d'origine", func(): _add_info({"kind": "relation", "subject": nm, "subject_type": "groupe", "relation": "lignee_de", "dir": 0,
			"title": "Lignée d'origine de « %s »" % nm}, nm), "Noter de quelle lignée celle-ci est issue"))
		row.add_child(UiKit.button("Changer de chef…" if chef != "" else "Chef de lignée…", func(): _pick_chef(nm, p),
			"Choisir le chef de cette lignée (écrit dans sa fiche)"))
	_side.add_child(row)


## Chef d'une lignée : écrit dans la fiche de la lignée (propriété `chef`), puis
## l'arbre est recalculé autour du chef.
func _pick_chef(lignee: String, path: String) -> void:
	Picker.open_in(main, app, "Chef de « %s »" % lignee, "notes", ["personnage"], func(v):
		var c := Schema.link_name(v)
		if c != "":
			_set_chef(lignee, path, c))


func _set_chef(lignee: String, path: String, chef: String) -> void:
	var r: Dictionary = app.set_note_properties(path, {"chef": "[[%s]]" % chef})
	_loaded = false
	focus_name = chef
	_refresh()
	main._set_status(("Chef de « %s » : %s ✓" % [lignee, chef]) if r.ok else "Refusé : " + str(r.get("error", "")))


func _person_actions(name: String, k: String) -> void:
	var row := UiKit.flow(6)
	var p: String = app.index.path_of_name(name)
	if p != "":
		row.add_child(UiKit.button("Ouvrir la fiche", func(): main.open_note(p)))
	if _family_of.has(k):
		row.add_child(UiKit.button("Partir d'ici", func(): set_start(k), "Point de départ : cette personne"))
	if p != "":
		row.add_child(UiKit.button("+ Sire", func(): _add(name, 1), "Noter qui est son sire, avec la source"))
		row.add_child(UiKit.button("+ Infant", func(): _add(name, 0), "Noter un infant, avec la source"))
		row.add_child(UiKit.button("+ Lignée", func(): _add_info({"kind": "relation", "subject": name, "subject_type": "personnage", "relation": "lignee_de", "dir": 0,
			"title": "Lignée de « %s »" % name}, name), "Noter de quelle lignée est cette personne, avec la source"))
	_side.add_child(row)


## Fenêtre d'ajout : un élément « est le sire de », dans la source choisie.
func _add(name: String, dir: int) -> void:
	_add_info({"kind": "relation", "subject": name, "subject_type": "personnage", "relation": "sire_de", "dir": dir,
		"title": ("Sire de « %s »" if dir == 1 else "Infant de « %s »") % name}, name)


func _add_info(spec: Dictionary, name: String) -> void:
	AddInfo.open_in(main, app, spec, func(msg: String):
		_loaded = false
		focus_name = name
		_refresh()
		main._set_status(msg))


func _on_activate(k: String) -> void:
	if tab == "lignees":
		var g: Dictionary = _group_rows.get(k, {})
		var p := str(g.get("path", ""))
		if p != "":
			main.open_note(p)
		return
	var n := node_of(k)
	if str(n.get("path", "")) != "":
		main.open_note(str(n.path))


## Recherche : un point de départ (onglet Lignages) ; un clan, une lignée, un membre (onglet Clans).
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
	# le nom exact d'abord, puis ce qui le contient
	var hit := ""
	for k in _family_of:
		var nm := TextNorm.fold(str(node_of(k).name))
		if nm == fq:
			hit = k
			break
		if hit == "" and nm.contains(fq):
			hit = k
	if hit != "":
		set_start(hit)
		return
	start_key = ""
	_refresh()
	_side_unknown(t)


# ------------------------------------------------------------------ export

## Le lignage affiché, en Markdown : un arbre en liste, puis les autres liens.
func export_markdown() -> String:
	var d := Time.get_date_dict_from_system()
	var today := "%04d-%02d-%02d" % [d.year, d.month, d.day]
	var lines := PackedStringArray()
	var title := ("Lignage autour de %s" % node_of(start_key).name) if start_key != "" and not show_all else "Lignages"
	lines.append("# " + title)
	lines.append("")
	lines.append("*Exporté de Nosferatu Intelligence le %s%s. Liens : sire → infant, lignée → membre, lignée → lignée issue.*" % [today,
		(" · point de départ : %s" % _link(node_of(start_key))) if start_key != "" and not show_all else ""])
	for sh in _shown:
		var f: Dictionary = sh[0]
		var t: Dictionary = _tree_of(f, sh[1])
		if _shown.size() > 1:
			lines.append("")
			lines.append("## " + str(f.label))
		lines.append("")
		var parent_edge := {}
		for e in f.edges:
			parent_edge["%s>%s" % [e.a, e.b]] = e
		var seen := {}
		for r in t.roots:
			_md_node(r, "", f, t, parent_edge, lines, seen, 0)
		var others := PackedStringArray()
		for e in t.extra:
			var ed: Dictionary = parent_edge.get("%s>%s" % [e.a, e.b], {})
			others.append("- %s → %s : %s%s" % [_link(f.nodes[e.a]), _link(f.nodes[e.b]), _edge_words(ed), _edge_sources(ed)])
		for k in t.nodes:
			if f.incoherent.has(k):
				others.append("- ⚠ %s : lignées qui ne s'accordent pas (%s)" % [_link(f.nodes[k]), ", ".join(PackedStringArray(
					(f.incoherent[k] as Array).map(func(x): return _lig_link(f, str(x)))))])
			if f.conflicts.has(k):
				others.append("- ⚠ %s : deux sires différents, à trancher" % _link(f.nodes[k]))
		if not others.is_empty():
			lines.append("")
			lines.append("### Autres liens et points à vérifier")
			lines.append("")
			lines.append_array(others)
	return "\n".join(lines) + "\n"


func _md_node(k: String, parent: String, f: Dictionary, t: Dictionary, parent_edge: Dictionary, lines: PackedStringArray, seen: Dictionary, depth: int) -> void:
	if seen.has(k) or depth > 60:
		return
	seen[k] = true
	var n: Dictionary = f.nodes[k]
	var txt := "  ".repeat(depth) + "- " + _link(n)
	if n.kind == "lignee":
		txt += " — lignée" + ((" (%s)" % n.clan) if str(n.clan) != "" else "")
	else:
		var bits := PackedStringArray()
		for x in [n.clan, Schema.option_label("personnage", "rang", n.rang) if str(n.rang) != "" else "",
				Schema.option_label("personnage", "statut", n.statut).to_lower() if str(n.statut) not in ["", "actif"] else ""]:
			if str(x) != "":
				bits.append(str(x))
		if not bits.is_empty():
			txt += " — " + ", ".join(bits)
		var heads: Array = n.get("heads", [])
		if not heads.is_empty():
			txt += " — **chef de " + ", ".join(PackedStringArray(heads.map(func(lk): return _lig_link(f, str(lk))))) + "**"
	if parent != "":
		var e: Dictionary = parent_edge.get("%s>%s" % [parent, k], {})
		txt += " · " + _edge_words(e) + _edge_sources(e)
	lines.append(txt)
	for c in t.children.get(k, []):
		_md_node(c, k, f, t, parent_edge, lines, seen, depth + 1)


## Une lignée dans l'export : son lien si elle a une fiche.
func _lig_link(f: Dictionary, lk: String) -> String:
	var li: Dictionary = (f.get("lignees", {}) as Dictionary).get(lk, {})
	var nm := Lineage.lignee_name(f, lk)
	return ("[[%s]]" % nm) if str(li.get("path", "")) != "" or (f.nodes.has(lk) and str(f.nodes[lk].path) != "") else nm


func _link(n: Dictionary) -> String:
	if n.is_empty():
		return "?"
	return ("[[%s]]" % n.name) if str(n.get("path", "")) != "" else str(n.name)


static func _edge_words(e: Dictionary) -> String:
	match str(e.get("kind", "")):
		"sire":
			return "infant" + ("" if e.get("sure", true) else " (incertain)")
		"lignee":
			return "de la lignée" + (" (incohérente)" if e.get("bad", false) else (" (déduite)" if e.get("inferred", false) else ""))
		"hierarchie":
			return "lignée issue" + (" (déduite de son chef)" if e.get("inferred", false) else "")
	return "lien"


func _edge_sources(e: Dictionary) -> String:
	var src: Array = e.get("sources", [])
	if src.is_empty():
		return ""
	var parts := PackedStringArray()
	for s in src.slice(0, 3):
		parts.append("sa fiche" if s.origin == "fiche" else ("%s, crédibilité %d" % [("[[%s]]" % s.label) if s.origin == "element" else s.label, int(s.cred)]))
	return " (selon %s%s)" % ["; ".join(parts), " …" if src.size() > 3 else ""]


func export_to_clipboard() -> void:
	if tab != "sires" or _shown.is_empty():
		main._set_status("Choisissez d'abord un point de départ, ou « Tout afficher ».")
		return
	var md := export_markdown()
	DisplayServer.clipboard_set(md)
	main._set_status("Lignage copié dans le presse-papiers, en Markdown (%d lignes)." % md.count("\n"))


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
			_group_rows[lk] = {"kind": "lignee", "name": str(l.name), "path": str(l.path), "members": int(l.members), "chef": str(l.get("chef", "")),
				"clan": str(c.name) if str(c.path) != "" else ""}
			nodes[lk] = {"label": str(l.name), "sub": "lignée%s · %d membre(s)" % [(" · chef " + str(l.chef)) if str(l.get("chef", "")) != "" else "", int(l.members)],
				"color": color_of(str(c.name)) if str(c.path) != "" else Color("8a7fa0")}
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
			var chef := str(g.get("chef", ""))
			if chef != "":
				_side.add_child(UiKit.list_row("Chef : " + chef, "voir son lignage", func():
					open("sires", chef)
					_refresh()))
			elif p != "":
				_side.add_child(UiKit.muted("Chef de lignée : non renseigné (recommandé)."))
				for c in Lineage.chef_candidates(app.index, name, str(g.get("clan", ""))).slice(0, 1):
					var cand := str(c)
					_side.add_child(UiKit.button("Chef : %s (d'après le nom)" % cand, func(): _set_chef(name, p, cand)))
			if p != "":
				_side.add_child(UiKit.button("Changer de chef…" if chef != "" else "Chef de lignée…", func(): _pick_chef(name, p)))
			var ms: Array = Members.of_group(app.index, name)
			_side.add_child(UiKit.label("Membres connus (%d)" % ms.size(), false, 16))
			if ms.is_empty():
				_side.add_child(UiKit.muted("Aucun membre connu. « + Membre » en ajoute un."))
			for m in ms:
				var mp: String = m.path
				_side.add_child(UiKit.list_row(Members.describe(m), "", func():
					if mp != "":
						main.open_note(mp)))
