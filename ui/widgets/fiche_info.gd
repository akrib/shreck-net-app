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

const ACTIVE_FAVEURS := ["active", "reclamee", "suspendue"]


## `wide` : affiché dans la colonne principale (frise de temps pleine largeur).
static func build(app: Node, main: Control, rel: String, name: String, type_name: String, wide := false) -> Control:
	var col := UiKit.vbox([], 8)
	match type_name:
		"personnage":
			_statut(app, main, col, name, rel)
			_disciplines(app, main, col, name, rel)
			_presences(app, main, col, name, wide)
			_relations(app, main, col, name)
			_faveurs(app, main, col, name)
			_indices(app, main, col, name)
			_mentions(app, main, col, name, wide)
		"groupe":
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


static func _row(main: Control, inner: VBoxContainer, text: String, path: String) -> void:
	var b := UiKit.button(text, func(): main.open_note(path))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(b)


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
			recus.append(["%s%s — par %s (%s, %s)" % [what.capitalize(), (" « %s »" % qual) if qual != "" else "", de, r.note, _cred(r.cred)], r.path])
		elif str(r.de_key) == k:
			donnes.append(["A donné %s%s à %s (%s)" % [("le sobriquet" if code == "sobriquet" else ("une reconnaissance" if code == "reconnait" else "un poste")),
				(" « %s »" % qual) if qual != "" else "", vers, r.note], r.path])
	var inner := _section(col, "Statut : reconnaissances, sobriquets, postes", recus.size() + donnes.size())
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
		_row(main, inner, x[0], x[1])
	for x in donnes:
		_row(main, inner, x[0], x[1])


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
			known[TextNorm.fold(n)] = [n, "fiche", ""]
	var seen_paths := {}
	for r in app.index.elements_mentioning(name, 400):
		var f := _fields(r)
		var n := Schema.link_name(f.get("discipline", ""))
		if n == "" or seen_paths.has(str(r.path) + str(r.block)):
			continue
		seen_paths[str(r.path) + str(r.block)] = true
		if not known.has(TextNorm.fold(n)) or known[TextNorm.fold(n)][1] == "fiche":
			known[TextNorm.fold(n)] = [n, "constatée : " + Schema.display_text(str(r.text)).left(120) + " — " + str(r.note), str(r.path)]
	var communes := {}
	for c in Schema.DISCIPLINES_COMMUNES:
		communes[TextNorm.fold(c)] = true
	var inner := _section(col, "Disciplines et clans compatibles", known.size())
	if known.is_empty():
		inner.add_child(UiKit.muted("Aucune discipline connue. Notez un pouvoir constaté dans une soirée (« Plus de détails » → discipline) ou dans la fiche."))
		return
	for k in known:
		var info: Array = known[k]
		var label := "%s%s — %s" % [info[0], "" if communes.has(k) else " (rare)", info[1]]
		if str(info[2]) != "":
			_row(main, inner, label, info[2])
		else:
			inner.add_child(UiKit.label(label))
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


## Groupe : membres (clan, secte), lignées rattachées à un clan.
static func _members(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var rows := []
	for r in app.index.linked_from(name, ["clan", "secte"]):
		if str(r.type) == "personnage":
			rows.append(["%s — %s" % [r.name, "clan" if str(r.origin) == "propriété clan" else "secte"], r.path])
	var lignees := []
	for r in app.index.linked_from(name, ["clan"]):
		if str(r.type) == "groupe":
			lignees.append([str(r.name), r.path])
	var inner := _section(col, "Membres connus", rows.size())
	for x in rows:
		_row(main, inner, x[0], x[1])
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
	if list.is_empty():
		return
	inner.add_child(UiKit.hbox([UiKit.button("Voir dans Enquête → Alibis", func(): main.show_alibis("personne", name), "Ligne de temps complète, nuits contradictoires")]))
	inner.add_child(AlibiView.timeline(main, list, conf, not wide, 40))
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
			Schema.option_label("element", "nature", r.nature).split(" (")[0].to_lower(), _cred(r.cred), r.note], r.path])
	for n in app.index.notes_with_props("indice", ["relation", "de", "vers", "statut", "credibilite"]):
		var pr: Dictionary = n.props
		if str(pr.get("relation", "")) == "":
			continue
		var de := Schema.link_name(pr.get("de", ""))
		var vers := Schema.link_name(pr.get("vers", ""))
		if de.to_lower() != name.to_lower() and vers.to_lower() != name.to_lower():
			continue
		rows.append(["%s %s %s — indice %s, %s" % [de, Schema.option_label("", "relation", pr.relation), vers,
			Schema.option_label("indice", "statut", pr.get("statut", "")).to_lower(), _cred(pr.get("credibilite"))], n.path])
	var inner := _section(col, "Relations connues", rows.size())
	for x in rows:
		_row(main, inner, x[0], x[1])


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
		rows.append([0 if ACTIVE_FAVEURS.has(st) else 1, "%s — %s" % [txt, Schema.option_label("faveur", "statut", st).to_lower()], n.path])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	var inner := _section(col, "Faveurs", rows.size())
	for x in rows:
		_row(main, inner, x[1], x[2])


static func _indices(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var rows := []
	var seen := {}
	for r in app.index.linked_from(name, ["sujets", "de", "vers", "participants"]):
		if not str(r.type) in ["indice", "evenement", "dossier"] or seen.has(r.path):
			continue
		seen[r.path] = true
		var pr: Dictionary = app.index.props_of(r.path)
		rows.append(["%s — %s, %s" % [r.name, Schema.type_label(str(r.type)).to_lower(),
			Schema.option_label(str(r.type), "statut", pr.get("statut", "")).to_lower()], r.path])
	var inner := _section(col, "Indices, événements et dossiers", rows.size())
	for x in rows:
		_row(main, inner, x[0], x[1])


static func _mentions(app: Node, main: Control, col: VBoxContainer, name: String, wide := false) -> void:
	var rows: Array = app.index.elements_mentioning(name, 200)
	var inner := _section(col, "Ce que disent les sources", rows.size())
	if wide and not rows.is_empty():
		(inner.get_parent() as FoldableContainer).folded = false  # c'est le cœur de la fiche
	for r in rows.slice(0, 40):
		_row(main, inner, "%s\n— %s · %s · %s" % [Schema.display_text(str(r.text)).left(200), r.note,
			Schema.option_label("element", "nature", r.nature).split(" (")[0].to_lower(), _cred(r.cred)], r.path)
	if rows.size() > 40:
		inner.add_child(UiKit.muted("… et %d autres (voir les rétroliens)." % (rows.size() - 40)))


static func _attached(app: Node, main: Control, col: VBoxContainer, name: String, ty: String, title: String) -> void:
	var rows := []
	for r in app.index.linked_from(name, ["domaine"]):
		if str(r.type) == ty:
			rows.append([str(r.name), r.path])
	rows.sort_custom(func(a, b): return a[0] > b[0] if ty == "soiree" else a[0] < b[0])
	var inner := _section(col, title, rows.size())
	for x in rows:
		_row(main, inner, x[0], x[1])


# ------------------------------------------------------------------ soirées, faisceaux, dossiers

static func _reported_presences(app: Node, main: Control, col: VBoxContainer, name: String) -> void:
	var rows := []
	var k := TextNorm.name_key(name)
	for r in app.index.relations_of(name):
		if str(r.relation) == "present_a" and str(r.vers_key) == k:
			var f := _fields(r)
			rows.append(["%s — selon %s (%s)" % [Schema.link_name(f.get("de", "")), r.note, _cred(r.cred)], r.path])
	var inner := _section(col, "Présences rapportées par d'autres sources", rows.size())
	for x in rows:
		_row(main, inner, x[0], x[1])


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
		if p == "":
			rows.append(["%s — introuvable" % n, ""])
			continue
		var ip: Dictionary = app.index.props_of(p)
		rows.append(["%s — %s, %s" % [n, Schema.option_label("indice", "statut", ip.get("statut", "")).to_lower(), _cred(ip.get("credibilite"))], p])
	var inner := _section(col, "Indices du dossier", rows.size())
	for x in rows:
		if x[1] == "":
			inner.add_child(UiKit.warn(x[0]))
		else:
			_row(main, inner, x[0], x[1])
