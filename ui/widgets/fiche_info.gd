extends RefCounted
## Renseignements calculés pour la note ouverte, à partir de l'index :
## présences, relations, faveurs, indices, ce qui se dit sur la personne…
## Rien de tout cela n'est écrit dans la note (FORMAT §16) : c'est recalculé
## à chaque ouverture, depuis les sources.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Dates := preload("res://core/model/dates.gd")
const Where := preload("res://core/analysis/whereabouts.gd")
const AlibiView := preload("res://ui/widgets/alibi_view.gd")
const Members := preload("res://core/analysis/members.gd")
const Lineage := preload("res://core/analysis/lineage.gd")

const ACTIVE_FAVEURS := ["active", "reclamee", "suspendue"]


## `wide` : affiché dans la colonne principale (frise de temps pleine largeur).
static func build(app: Node, main: Control, rel: String, name: String, type_name: String, wide := false) -> Control:
	var col := UiKit.vbox([], 8)
	match type_name:
		"personnage":
			_statut(app, main, col, name, rel)
			_disciplines(app, main, col, name, rel)
			_presences(app, main, col, name, wide)
			_lignees(app, main, col, name)
			_relations(app, main, col, name)
			_faveurs(app, main, col, name)
			_indices(app, main, col, name)
			_mentions(app, main, col, name, wide)
		"groupe":
			_chef(app, main, col, name, rel)
			_members(app, main, col, name)
			_relations(app, main, col, name)
			_indices(app, main, col, name)
			_mentions(app, main, col, name)
		"domaine":
			_attached(app, main, col, name, "soiree", "Soirées de ce domaine")
			_attached(app, main, col, name, "personnage", "Personnages rattachés")
			_attached(app, main, col, name, "lieu", "Lieux")
			_attached(app, main, col, name, "faveur", "Faveurs enregistrées ici")
		"concept":
			_concept_usage(app, main, col, name, rel)
			_relations(app, main, col, name)
			_mentions(app, main, col, name)
		"lieu", "objet":
			_relations(app, main, col, name)
			_mentions(app, main, col, name)
		"soiree":
			_alibi_links(app, main, col, rel)
			_reported_presences(app, main, col, name)
		"evenement":
			_alibi_links(app, main, col, rel)
			_faisceau(app, main, col, rel)
		"indice":
			_faisceau(app, main, col, rel)
		"dossier":
			_dossier(app, main, col, rel)
	if col.get_child_count() == 0:
		col.free()
		return null
	col.add_child(UiKit.muted("Ces renseignements sont calculés depuis vos sources ; ils ne sont pas écrits dans la note."))
	return col


static func _section(col: VBoxContainer, title: String, n: int) -> VBoxContainer:
	var fold := FoldableContainer.new()
	fold.title = "%s (%d)" % [title, n]
	fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # titre long : jamais plus large que l'écran
	fold.folded = n == 0 or n > 15
	var inner := UiKit.vbox([], 6)
	fold.add_child(inner)
	col.add_child(fold)
	return inner


## Bouton « + » dans la barre de titre d'une section : ouvre la fenêtre d'ajout
## (ui/widgets/add_info.gd) depuis l'écran de la note, qui relit ensuite la fiche.
static func _plus(main: Control, inner: VBoxContainer, text: String, tip: String, spec: Dictionary) -> void:
	var fold := inner.get_parent() as FoldableContainer
	if fold == null or not main.screens.has("note"):
		return
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", Color("9be3a8"))
	b.pressed.connect(func(): main.screens.note.open_add(spec))
	fold.add_title_bar_control(b)


## Bouton « + » qui ouvre le formulaire d'une nouvelle note préremplie (faveur, indice, soirée…).
static func _plus_new(main: Control, inner: VBoxContainer, text: String, tip: String, type_name: String, preset: Dictionary) -> void:
	var fold := inner.get_parent() as FoldableContainer
	if fold == null or not main.screens.has("note"):
		return
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", Color("9be3a8"))
	b.pressed.connect(func(): main.screens.note.open_new(type_name, preset))
	fold.add_title_bar_control(b)


## Une ligne de section : un appui ouvre la note ; `rm` (facultatif) ajoute une croix
## qui supprime seulement cette ligne ou ce lien, après confirmation (note_screen.confirm_remove).
static func _row(main: Control, inner: VBoxContainer, text: String, path: String, rm := {}) -> void:
	var b := UiKit.button(text, func():
		if path != "":
			main.open_note(path))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if rm.is_empty() or not main.screens.has("note"):
		inner.add_child(b)
		return
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x := Button.new()
	x.text = "×"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.tooltip_text = "Supprimer seulement ceci (après confirmation)"
	x.custom_minimum_size = Vector2(UiKit.TOUCH, UiKit.TOUCH)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.add_theme_color_override("font_color", Color("ff9b8a"))
	x.add_theme_font_size_override("font_size", 20)
	x.pressed.connect(func(): main.screens.note.confirm_remove(rm))
	inner.add_child(UiKit.hbox([b, x], 4))


static func _rm_el(r: Dictionary) -> Dictionary:
	return {"kind": "element", "rel": str(r.path), "block": str(r.get("block", "") if r.get("block") != null else ""), "text": str(r.get("text", ""))}


static func _fields(r: Dictionary) -> Dictionary:
	var f: Variant = JSON.parse_string(str(r.get("fields", "{}")))
	return f if typeof(f) == TYPE_DICTIONARY else {}


static func _cred(c: Variant) -> String:
	return "crédibilité %s" % str(c) if c != null and str(c) != "" else "crédibilité ?"


# ------------------------------------------------------------------ personnages

## Statut (Règles FCF p. 765-796) : reconnaissances et sobriquets reçus et donnés,
## nominations ; un signal discret quand la règle du Paria pourrait s'appliquer.
static func _statut(app: Node, main: Control, col: VBoxContainer, name: String, rel: String) -> void:
	var k := TextNorm.name_key(name)
	var recus := []
	var donnes := []
	var n_reco := 0
	var n_sobr := 0
	for r in app.index.relations_of(name):
		var code := str(r.relation)
		if not code in ["reconnait", "sobriquet", "nomme"]:
			continue
		var f := _fields(r)
		var qual := str(f.get("qualificatif", "")).strip_edges()
		var de := Schema.link_name(f.get("de", ""))
		var vers := Schema.link_name(f.get("vers", ""))
		var what: String = {"reconnait": "reconnaissance", "sobriquet": "sobriquet", "nomme": "nomination"}[code]
		if str(r.vers_key) == k:
			if code == "reconnait":
				n_reco += 1
			elif code == "sobriquet":
				n_sobr += 1
			recus.append(["%s%s — par %s (%s, %s)" % [what.capitalize(), (" « %s »" % qual) if qual != "" else "", de, r.note, _cred(r.cred)], r.path, _rm_el(r)])
		elif str(r.de_key) == k:
			donnes.append(["A donné %s%s à %s (%s)" % [("le sobriquet" if code == "sobriquet" else ("une reconnaissance" if code == "reconnait" else "un poste")),
				(" « %s »" % qual) if qual != "" else "", vers, r.note], r.path, _rm_el(r)])
	var inner := _section(col, "Statut : reconnaissances, sobriquets, postes", recus.size() + donnes.size())
	_plus(main, inner, "+ Statut", "Une reconnaissance, un sobriquet ou une nomination reçus, notés comme information dans la source de votre choix", {"kind": "statut"})
	var pr: Dictionary = app.index.props_of(rel)
	var rang := Schema.option_label("personnage", "rang", pr.get("rang", ""))
	var secte := Schema.link_name(pr.get("secte", ""))
	var titres: Variant = pr.get("titres", [])
	var t_list: Array = titres if typeof(titres) == TYPE_ARRAY else ([] if titres == null or str(titres) == "" else [titres])
	var resume := PackedStringArray()
	if rang != "":
		resume.append("Statut d'âge : " + rang)
	if secte != "":
		resume.append("Secte : " + secte)
	if not t_list.is_empty():
		resume.append("Postes : " + ", ".join(PackedStringArray(t_list)))
	resume.append("%d reconnaissance(s), %d sobriquet(s) connus" % [n_reco, n_sobr])
	inner.add_child(UiKit.label(" · ".join(resume)))
	if n_sobr >= 2 and n_reco == 0 and t_list.is_empty() and str(pr.get("rang", "")) in ["nouveau_ne", "infant"]:
		inner.add_child(UiKit.warn("Deux sobriquets sans reconnaissance ni poste : selon les règles (p. 796), un Nouveau-né dans ce cas peut être déclaré Paria si son clan le décide. Simple rappel, à vous d'en juger."))
	for x in recus:
		_row(main, inner, x[0], x[1], x[2])
	for x in donnes:
		_row(main, inner, x[0], x[1], x[2])


## Disciplines connues ou constatées, et clans dont les disciplines de clan
## les expliquent. Les disciplines communes s'apprennent hors clan (p. 346) :
## seules les autres départagent vraiment. Simple indication, jamais une conclusion.
static func _disciplines(app: Node, main: Control, col: VBoxContainer, name: String, rel: String) -> void:
	var known := {}   # nom replié -> [nom affiché, origine, chemin]
	var pr: Dictionary = app.index.props_of(rel)
	var d: Variant = pr.get("disciplines", [])
	for x in (d if typeof(d) == TYPE_ARRAY else ([] if d == null or str(d) == "" else [d])):
		var n := Schema.link_name(x)
		if n != "":
			known[TextNorm.fold(n)] = [n, "fiche", "", {"kind": "prop", "rel": rel, "key": "disciplines", "target": n}]
	var seen_paths := {}
	for r in app.index.elements_mentioning(name, 400):
		var f := _fields(r)
		var n := Schema.link_name(f.get("discipline", ""))
		if n == "" or seen_paths.has(str(r.path) + str(r.block)):
			continue
		seen_paths[str(r.path) + str(r.block)] = true
		if not known.has(TextNorm.fold(n)) or known[TextNorm.fold(n)][1] == "fiche":
			known[TextNorm.fold(n)] = [n, "constatée : " + Schema.display_text(str(r.text)).left(120) + " — " + str(r.note), str(r.path), _rm_el(r)]
	var communes := {}
	for c in Schema.DISCIPLINES_COMMUNES:
		communes[TextNorm.fold(c)] = true
	var inner := _section(col, "Disciplines et clans compatibles", known.size())
	_plus(main, inner, "+ Discipline", "Un pouvoir constaté, noté comme information dans la source de votre choix", {"kind": "discipline"})
	if known.is_empty():
		inner.add_child(UiKit.muted("Aucune discipline connue. « + Discipline » note un pouvoir constaté."))
		return
	for k in known:
		var info: Array = known[k]
		var label := "%s%s — %s" % [info[0], "" if communes.has(k) else " (rare)", info[1]]
		_row(main, inner, label, str(info[2]), info[3])
	# clans et lignées candidats
	var cands := []
	var have_clans := false
	for g in app.index.notes_with_props("groupe", ["nature", "disciplines"]):
		var nat := str(g.props.get("nature", ""))
		if not nat in ["clan", "lignee"]:
			continue
		var gd: Variant = g.props.get("disciplines", [])
		var glist := {}
		for x in (gd if typeof(gd) == TYPE_ARRAY else ([] if gd == null or str(gd) == "" else [gd])):
			glist[TextNorm.fold(Schema.link_name(x))] = true
		if glist.is_empty():
			continue
		have_clans = true
		var ok := true
		var common := 0
		for k in known:
			if glist.has(k):
				common += 1
			elif not communes.has(k):
				ok = false
		if ok and common > 0:
			cands.append([common, str(g.name), g.path, nat])
	if not have_clans:
		inner.add_child(UiKit.muted("Importez les fiches de clans (lot des règles) pour voir les clans compatibles."))
		return
	cands.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	inner.add_child(UiKit.muted("Clans et lignées dont les disciplines de clan expliquent ces pouvoirs (une discipline commune peut aussi s'apprendre hors clan, règles p. 346) :"))
	if cands.is_empty():
		inner.add_child(UiKit.warn("Aucun clan connu n'a toutes ces disciplines rares en discipline de clan."))
	for c in cands.slice(0, 12):
		_row(main, inner, "%s (%s) — %d discipline(s) en commun" % [c[1], "lignée" if c[3] == "lignee" else "clan", c[0]], c[2])


## Personnage : ses lignées, déclarées (« est de la lignée de », « est membre de »
## une lignée) ou déduites (la lignée d'un infant remonte à son sire).
static func _lignees(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var pl: Dictionary = Lineage.person_lignees(app.index, name)
	var ls: Dictionary = pl.lignees
	var inner := _section(col, "Lignées", ls.size())
	_plus(main, inner, "+ Lignée", "Noter de quelle lignée est cette personne, avec la source",
		{"kind": "relation", "relation": "lignee_de", "dir": 0, "title": "Lignée de « %s »" % name})
	if not (pl.bad as Array).is_empty():
		inner.add_child(UiKit.warn("Lignées qui ne s'accordent pas : %s. Aucune ne descend de l'autre." % ", ".join(PackedStringArray(
			(pl.bad as Array).map(func(k): return str(ls[k].name) if ls.has(k) else str(k))))))
	var heads: Array = pl.get("heads", [])
	if not heads.is_empty():
		var hl := UiKit.label(Lineage.chef_mention(heads.map(func(h): return str(h.name))), false, 16)
		hl.add_theme_color_override("font_color", Color("b79cff"))
		inner.add_child(hl)
	if ls.is_empty():
		inner.add_child(UiKit.muted("Aucune lignée connue. « + Lignée » en note une ; celle d'un infant remonte d'elle-même à son sire."))
	for lk in ls:
		var m: Dictionary = ls[lk]
		var how := "déclarée" if m.declared else "déduite de son infant " + ", ".join(PackedStringArray(m.via))
		if m.declared and not (m.sources as Array).is_empty() and str(m.sources[0].origin) == "chef":
			how = "chef de la lignée (fiche de la lignée)"
		elif m.declared and not (m.sources as Array).is_empty():
			var s: Dictionary = m.sources[0]
			how += " ; selon %s%s" % ["sa fiche" if s.origin == "fiche" else s.label, "" if s.origin == "fiche" else " (%s)" % _cred(s.cred)]
		var p: String = m.path if str(m.path) != "" else (str(m.sources[0].path) if not (m.sources as Array).is_empty() else "")
		# une lignée déclarée par une seule note : la croix la retire ; déduite, elle disparaît d'elle-même avec sa cause
		var rm := {}
		if m.declared and (m.sources as Array).size() == 1:
			var s0: Dictionary = m.sources[0]
			match str(s0.origin):
				"element":
					rm = {"kind": "element", "rel": str(s0.path), "block": str(s0.get("block", "")), "text": str(s0.get("text", ""))}
				"indice":
					rm = {"kind": "note", "rel": str(s0.path)}
				"fiche":
					rm = {"kind": "prop", "rel": str(s0.path), "key": "clan", "target": str(m.name)}
				"chef":
					rm = {"kind": "prop", "rel": str(s0.path), "key": "chef", "target": name}
		_row(main, inner, "%s — %s" % [m.name, how], p, rm)
	if not ls.is_empty():
		var nm := name
		inner.add_child(UiKit.hbox([UiKit.button("Voir le lignage", func(): main.show_lineage("sires", nm), "Enquête → Filiations, à partir de cette personne")]))


## Lignée : son chef (propriété `chef`, format 1.7), facultatif mais recommandé.
## Sans chef : la proposition tirée du nom (« Lignée de Karios » : Karios), et le choix.
static func _chef(app: Node, main: Control, col: VBoxContainer, name: String, rel: String) -> void:
	var props: Dictionary = app.index.props_of(rel)
	if str(props.get("nature", "")) != "lignee":
		return
	var chef := Schema.link_name(props.get("chef", ""))
	var inner := _section(col, "Chef de lignée", 1 if chef != "" else 0)
	var fold := inner.get_parent() as FoldableContainer
	if fold != null:
		fold.folded = false  # recommandé : la proposition reste en vue
		if chef == "":
			fold.title = "Chef de lignée — à renseigner (recommandé)"
	var has_note: bool = main.screens.has("note")
	if chef != "":
		_row(main, inner, "%s — chef de la lignée" % chef, app.index.path_of_name(chef), {"kind": "prop", "rel": rel, "key": "chef", "target": chef})
		inner.add_child(UiKit.muted("Dans les lignages et le graphe, la lignée est montrée par la case de son chef : « %s »." % Lineage.chef_mention([name])))
	else:
		inner.add_child(UiKit.muted("Non renseigné. C'est recommandé : la lignée est alors montrée par son chef dans les lignages et le graphe, et ses lignées d'origine se déduisent de celles du chef."))
	if not has_note:
		return
	var row := UiKit.flow(6)
	if chef == "":
		for c in Lineage.chef_candidates(app.index, name, Schema.link_name(props.get("clan", ""))).slice(0, 1):
			var cand := str(c)
			var b := UiKit.button("Chef : %s (d'après le nom)" % cand, func(): main.screens.note.set_link_property("chef", cand),
				"Écrire « chef: [[%s]] » dans cette fiche" % cand)
			b.add_theme_color_override("font_color", Color("9be3a8"))
			row.add_child(b)
	row.add_child(UiKit.button("Changer de chef…" if chef != "" else "Choisir le chef…", func():
		main.screens.note.pick_link_property("chef", ["personnage"], "Chef de « %s »" % name), "Un personnage, écrit dans cette fiche"))
	inner.add_child(row)


## Groupe : membres (clan ou secte de leur fiche, éléments et indices « est
## membre de » ou « dirige »), lignées rattachées à un clan.
static func _members(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var rows: Array = Members.of_group(app.index, name)
	var lignees := []
	for r in app.index.linked_from(name, ["clan"]):
		if str(r.type) == "groupe":
			lignees.append([str(r.name), r.path])
	var inner := _section(col, "Membres connus", rows.size())
	var nat := str(app.index.props_of(app.index.path_of_name(name)).get("nature", ""))
	_plus(main, inner, "+ Membre", "Clan ou secte : écrit dans la fiche du personnage. Lignée, faction, coterie… : noté comme information dans la source de votre choix.",
		{"kind": "membre"})
	if rows.is_empty():
		inner.add_child(UiKit.muted("Aucun membre connu. « + Membre » en ajoute un." if nat in ["clan", "secte"]
			else "Aucun membre connu. « + Membre » note qu'un personnage en est membre, ou le dirige, avec la source de l'information."))
	for x in rows:
		var p: String = x.path if str(x.path) != "" else (str(x.sources[0].path) if not x.sources.is_empty() else "")
		# ce qu'une croix peut retirer : le clan ou la secte de sa fiche, ou chaque information
		var targets := []
		if (x.roles as Array).has("chef"):
			targets.append(["chef de lignée (fiche de la lignée)", app.index.path_of_name(name),
				{"kind": "prop", "rel": app.index.path_of_name(name), "key": "chef", "target": str(x.name)}])
		if x.from_fiche and str(x.path) != "":
			for role in x.roles:
				if role in ["clan", "lignee", "secte"]:
					targets.append(["%s (fiche)" % {"clan": "clan", "lignee": "lignée", "secte": "secte"}[role], str(x.path),
						{"kind": "prop", "rel": str(x.path), "key": "secte" if role == "secte" else "clan", "target": name}])
		for src in x.sources:
			var sp: Dictionary = {"kind": "note", "rel": str(src.path)} if str(src.get("origin", "")) == "indice" else \
				{"kind": "element", "rel": str(src.path), "block": str(src.get("block", "")), "text": str(src.get("text", ""))}
			targets.append(["selon %s (%s)" % [src.label, _cred(src.cred)], str(src.path), sp])
		if targets.size() == 1:
			_row(main, inner, Members.describe(x), p, targets[0][2])
		else:
			_row(main, inner, Members.describe(x), p)
			for t in targets:
				_row(main, inner, "   · %s — %s" % [x.name, t[0]], t[1], t[2])
	if not lignees.is_empty():
		var inner2 := _section(col, "Lignées", lignees.size())
		for x in lignees:
			_row(main, inner2, x[0], x[1])


## Concept : clans qui ont cette discipline, personnes chez qui elle a été constatée,
## titulaires connus d'un poste.
static func _concept_usage(app: Node, main: Control, col: VBoxContainer, name: String, rel: String) -> void:
	var pr: Dictionary = app.index.props_of(rel)
	var nat := str(pr.get("nature", ""))
	if nat == "discipline" or nat == "":
		var clans := []
		var persos := []
		for r in app.index.linked_from(name, ["disciplines"]):
			(clans if str(r.type) == "groupe" else persos).append([str(r.name), r.path])
		if not clans.is_empty() or nat == "discipline":
			var inner := _section(col, "Clans et lignées qui la possèdent", clans.size())
			for x in clans:
				_row(main, inner, x[0], x[1])
			var inner2 := _section(col, "Constatée chez", persos.size())
			for x in persos:
				_row(main, inner2, x[0], x[1])
	if nat == "discipline":
		var uses := []
		var k := TextNorm.fold(name)
		for r in app.index.elements_with_discipline():
			if TextNorm.fold(Schema.link_name(_fields(r).get("discipline", ""))) == k:
				uses.append(["%s\n— %s (%s)" % [Schema.display_text(str(r.text)).left(200), r.note, _cred(r.cred)], r.path])
		var inner4 := _section(col, "Utilisations constatées", uses.size())
		for x in uses:
			_row(main, inner4, x[0], x[1])
	if nat == "poste":
		var rows := []
		var low := name.to_lower()
		for p in app.index.notes_with_props("personnage", ["titres"]):
			var t: Variant = p.props.get("titres", [])
			for x in (t if typeof(t) == TYPE_ARRAY else [t]):
				if str(x).to_lower().begins_with(low):
					rows.append(["%s — %s" % [p.name, x], p.path])
		var inner3 := _section(col, "Titulaires connus", rows.size())
		for x in rows:
			_row(main, inner3, x[0], x[1])


## Où était-il ? Présences aux soirées, participations aux événements, éléments
## « était présent à » : sur une ligne de temps, les nuits contradictoires en rouge.
static func _presences(app: Node, main: Control, col: VBoxContainer, name: String, wide := false) -> void:
	var list: Array = Where.of_person(app.index, name)
	var conf: Dictionary = Where.conflicts(list)
	var inner := _section(col, "Où était-il ?" + ((" — %d nuit%s à deux endroits" % [conf.size(), "s" if conf.size() > 1 else ""]) if not conf.is_empty() else " Présences"), list.size())
	_plus(main, inner, "+ Présence", "Vu à une soirée : écrit dans les présents de la soirée. Rapporté : noté comme information dans une source.", {"kind": "presence"})
	if list.is_empty():
		return
	inner.add_child(UiKit.hbox([UiKit.button("Voir dans Enquête → Alibis", func(): main.show_alibis("personne", name), "Ligne de temps complète, nuits contradictoires")]))
	inner.add_child(AlibiView.timeline(main, list, conf, not wide, 40, func(spec): main.screens.note.confirm_remove(spec)))
	if list.size() > 40:
		inner.add_child(UiKit.muted("… et %d autres (voir Enquête → Alibis)." % (list.size() - 40)))


## Soirée ou événement : qui était où cette nuit-là, et qui était là à cet incident et à d'autres.
static func _alibi_links(app: Node, main: Control, col: VBoxContainer, rel: String) -> void:
	var pr: Dictionary = app.index.props_of(rel)
	var d := str(pr.get("date", ""))
	if d == "":
		d = str(pr.get("date_floue", ""))
	var row := UiKit.flow(6)
	if Dates.is_day(d):
		row.add_child(UiKit.button("Qui était où cette nuit-là", func(): main.show_alibis("nuit", d), "Enquête → Alibis, nuit du " + Dates.label(d)))
	row.add_child(UiKit.button("Comparer à d'autres incidents", func(): main.show_alibis("incidents", rel), "Qui était sur place, qui a un alibi"))
	col.add_child(row)


static func _relations(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var rows := []
	for r in app.index.relations_of(name):
		if str(r.relation) == "present_a":
			continue
		var f := _fields(r)
		var lib := Schema.option_label("", "relation", r.relation)
		rows.append(["%s %s %s — %s, %s, %s" % [Schema.link_name(f.get("de", "")), lib, Schema.link_name(f.get("vers", "")),
			Schema.option_label("element", "nature", r.nature).split(" (")[0].to_lower(), _cred(r.cred), r.note], r.path, _rm_el(r)])
	for n in app.index.notes_with_props("indice", ["relation", "de", "vers", "statut", "credibilite"]):
		var pr: Dictionary = n.props
		if str(pr.get("relation", "")) == "":
			continue
		var de := Schema.link_name(pr.get("de", ""))
		var vers := Schema.link_name(pr.get("vers", ""))
		if de.to_lower() != name.to_lower() and vers.to_lower() != name.to_lower():
			continue
		rows.append(["%s %s %s — indice %s, %s" % [de, Schema.option_label("", "relation", pr.relation), vers,
			Schema.option_label("indice", "statut", pr.get("statut", "")).to_lower(), _cred(pr.get("credibilite"))], n.path, {"kind": "note", "rel": str(n.path)}])
	var inner := _section(col, "Relations connues", rows.size())
	_plus(main, inner, "+ Relation", "Allié, ennemi, membre, sire, mentor, contact… noté comme information dans la source de votre choix", {"kind": "relation"})
	for x in rows:
		_row(main, inner, x[0], x[1], x[2])


static func _faveurs(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var rows := []
	var lk := name.to_lower()
	for n in app.index.notes_with_props("faveur", ["debiteur", "creancier", "niveau", "statut", "date"]):
		var pr: Dictionary = n.props
		var deb := Schema.link_name(pr.get("debiteur", ""))
		var cre := Schema.link_name(pr.get("creancier", ""))
		if deb.to_lower() != lk and cre.to_lower() != lk:
			continue
		var st := str(pr.get("statut", ""))
		var niv := Schema.option_label("faveur", "niveau", pr.get("niveau", "")).to_lower()
		var txt := ("Doit une faveur %s à %s" % [niv, cre]) if deb.to_lower() == lk else ("%s lui doit une faveur %s" % [deb, niv])
		rows.append([0 if ACTIVE_FAVEURS.has(st) else 1, "%s — %s" % [txt, Schema.option_label("faveur", "statut", st).to_lower()], n.path, {"kind": "note", "rel": str(n.path)}])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	var inner := _section(col, "Faveurs", rows.size())
	_plus_new(main, inner, "+ Faveur", "Nouvelle note de faveur, « %s » en débiteur (à inverser dans le formulaire s'il est créancier)" % name, "faveur", {"debiteur": "[[%s]]" % name})
	for x in rows:
		_row(main, inner, x[1], x[2], x[3])


static func _indices(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var rows := []
	var seen := {}
	for r in app.index.linked_from(name, ["sujets", "de", "vers", "participants"]):
		if not str(r.type) in ["indice", "evenement", "dossier"] or seen.has(r.path):
			continue
		seen[r.path] = true
		var pr: Dictionary = app.index.props_of(r.path)
		# la croix retire cette fiche des sujets ou des participants ; pour un indice dont c'est
		# la relation (de, vers), c'est l'indice entier qui part à la corbeille
		var key := str(r.origin).trim_prefix("propriété ")
		var rm: Dictionary = {"kind": "prop", "rel": str(r.path), "key": key, "target": name} if key in ["sujets", "participants"] else {"kind": "note", "rel": str(r.path)}
		rows.append(["%s — %s, %s" % [r.name, Schema.type_label(str(r.type)).to_lower(),
			Schema.option_label(str(r.type), "statut", pr.get("statut", "")).to_lower()], r.path, rm])
	var inner := _section(col, "Indices, événements et dossiers", rows.size())
	_plus_new(main, inner, "+ Indice", "Nouvel indice (une affirmation à évaluer) dont « %s » est le sujet" % name, "indice", {"sujets": ["[[%s]]" % name]})
	for x in rows:
		_row(main, inner, x[0], x[1], x[2])


static func _mentions(app: Node, main: Control, col: VBoxContainer, name: String, wide := false) -> void:
	var rows: Array = app.index.elements_mentioning(name, 200)
	var inner := _section(col, "Ce que disent les sources", rows.size())
	_plus(main, inner, "+ Information", "Ce que vous avez vu ou appris, écrit dans la source de votre choix (Mes notes du jour par défaut)", {"kind": "mention"})
	if wide and not rows.is_empty():
		(inner.get_parent() as FoldableContainer).folded = false  # c'est le cœur de la fiche
	for r in rows.slice(0, 40):
		_row(main, inner, "%s\n— %s · %s · %s" % [Schema.display_text(str(r.text)).left(200), r.note,
			Schema.option_label("element", "nature", r.nature).split(" (")[0].to_lower(), _cred(r.cred)], r.path, _rm_el(r))
	if rows.size() > 40:
		inner.add_child(UiKit.muted("… et %d autres (voir les rétroliens)." % (rows.size() - 40)))


static func _attached(app: Node, main: Control, col: VBoxContainer, name: String, ty: String, title: String) -> void:
	var rows := []
	for r in app.index.linked_from(name, ["domaine"]):
		if str(r.type) == ty:
			rows.append([str(r.name), r.path, {"kind": "prop", "rel": str(r.path), "key": "domaine", "target": name} if ty == "personnage" else {}])
	rows.sort_custom(func(a, b): return a[0] > b[0] if ty == "soiree" else a[0] < b[0])
	var inner := _section(col, title, rows.size())
	match ty:
		"personnage":
			_plus(main, inner, "+ Personnage", "Rattacher un personnage à ce domaine : écrit dans sa fiche (domaine)", {"kind": "rattache"})
		"soiree":
			_plus_new(main, inner, "+ Soirée", "Nouvelle soirée dans ce domaine", "soiree", {"domaine": "[[%s]]" % name})
		"lieu":
			_plus_new(main, inner, "+ Lieu", "Nouveau lieu dans ce domaine", "lieu", {"domaine": "[[%s]]" % name})
		"faveur":
			_plus_new(main, inner, "+ Faveur", "Nouvelle faveur enregistrée dans ce domaine", "faveur", {"domaine": "[[%s]]" % name})
	for x in rows:
		_row(main, inner, x[0], x[1], x[2])


# ------------------------------------------------------------------ soirées, faisceaux, dossiers

static func _reported_presences(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var rows := []
	var k := TextNorm.name_key(name)
	for r in app.index.relations_of(name):
		if str(r.relation) == "present_a" and str(r.vers_key) == k:
			var f := _fields(r)
			rows.append(["%s — selon %s (%s)" % [Schema.link_name(f.get("de", "")), r.note, _cred(r.cred)], r.path, _rm_el(r)])
	var inner := _section(col, "Présences rapportées par d'autres sources", rows.size())
	for x in rows:
		_row(main, inner, x[0], x[1], x[2])


## Pour un indice ou un événement : d'où viennent les éléments pour et contre.
static func _faisceau(app: Node, main: Control, col: VBoxContainer, rel: String) -> void:
	var pr: Dictionary = app.index.props_of(rel)
	var sources := {}
	for side in ["pour", "contre"]:
		var lst: Variant = pr.get(side, [])
		for x in (lst if typeof(lst) == TYPE_ARRAY else [lst]):
			var n := Schema.link_name(x)
			if n != "":
				sources[side + "|" + n] = true
	var n_pour := 0
	var n_contre := 0
	var notes_pour := {}
	for key in sources:
		var parts: PackedStringArray = str(key).split("|")
		if parts[0] == "pour":
			n_pour += 1
			notes_pour[parts[1]] = true
		else:
			n_contre += 1
	var inner := _section(col, "Faisceau", n_pour + n_contre)
	inner.add_child(UiKit.label("%d élément(s) pour, venant de %d note(s) différente(s) ; %d contre." % [
		_count(pr.get("pour", [])), notes_pour.size(), _count(pr.get("contre", []))]))
	var st := str(pr.get("statut", ""))
	if st == "corrobore" and notes_pour.size() < 2:
		inner.add_child(UiKit.warn("Statut « corroboré », mais les éléments pour viennent d'une seule note : sont-ils vraiment indépendants ?"))
	if _count(pr.get("contre", [])) > 0 and st in ["non_verifie", "corrobore"]:
		inner.add_child(UiKit.warn("Il existe des éléments contraires : le statut « contesté » serait peut-être plus juste."))
	for n in notes_pour:
		var p: String = app.index.path_of_name(n)
		if p != "":
			_row(main, inner, "Pour : " + n, p)


static func _count(v: Variant) -> int:
	if typeof(v) == TYPE_ARRAY:
		return v.size()
	return 0 if v == null or str(v) == "" else 1


static func _dossier(app: Node, main: Control, col: VBoxContainer, rel: String) -> void:
	var pr: Dictionary = app.index.props_of(rel)
	var lst: Variant = pr.get("indices", [])
	var rows := []
	for x in (lst if typeof(lst) == TYPE_ARRAY else [lst]):
		var n := Schema.link_name(x)
		if n == "":
			continue
		var p: String = app.index.path_of_name(n)
		var rm := {"kind": "prop", "rel": rel, "key": "indices", "target": n}
		if p == "":
			rows.append(["%s — introuvable" % n, "", rm])
			continue
		var ip: Dictionary = app.index.props_of(p)
		rows.append(["%s — %s, %s" % [n, Schema.option_label("indice", "statut", ip.get("statut", "")).to_lower(), _cred(ip.get("credibilite"))], p, rm])
	var inner := _section(col, "Indices du dossier", rows.size())
	for x in rows:
		if x[1] == "":
			inner.add_child(UiKit.warn(x[0]))
		else:
			_row(main, inner, x[0], x[1], x[2])
