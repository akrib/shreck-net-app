extends RefCounted
## Préparation de séance pour un domaine (FORMAT §12 et §16) : qui sera
## probablement là, les faveurs en cours entre ces personnes, les questions
## ouvertes, les tâches, ce qui s'est passé depuis la dernière soirée et les
## alertes (Chasse au Sang, parjure, paria…). Tout est calculé ; rien n'est écrit.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")

const ALERTES := ["chasse_au_sang", "parjure", "liste_ecarlate", "paria", "banni"]
const MAX_GAPS := 12   ## au plus tant de personnes dont la fiche a des trous, les plus vues d'abord


static func _list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v
	return [] if str(v) == "" else [v]


## `today` (AAAA-MM-JJ, défaut : aujourd'hui) : les morts et disparus ne sont
## signalés que s'ils ont été vus dans le domaine depuis moins d'un an ; ils ne
## comptent pas parmi les personnes probables (liste `gone`).
## `contradictions` : les points à trancher (Contradictions.build, sans ceux
## écartés) ; ceux qui touchent une personne probable deviennent des questions.
static func build(index: RefCounted, domaine: String, today := "", contradictions := []) -> Dictionary:
	var dk := TextNorm.name_key(domaine)
	if today == "":
		today = Time.get_date_string_from_system()
	var year_ago := "%04d%s" % [int(today.substr(0, 4)) - 1, today.substr(4)]
	var out := {"domaine": domaine, "people": [], "faveurs": [], "questions": [], "tasks": [],
		"since": [], "alerts": [], "last_soiree": {}, "soirees": 0, "gone": [], "others": []}
	# 1. soirées du domaine et présences
	var soirees := []
	for s in index.notes_with_props("soiree", ["date", "domaine"]):
		if TextNorm.name_key(Schema.link_name(s.props.get("domaine", ""))) == dk:
			soirees.append(s)
	soirees.sort_custom(func(a, b): return str(a.props.get("date", "")) > str(b.props.get("date", "")))
	out.soirees = soirees.size()
	var soiree_dates := {}
	for s in soirees:
		soiree_dates[TextNorm.name_key(str(s.name))] = str(s.props.get("date", ""))
	if not soirees.is_empty():
		out.last_soiree = {"name": str(soirees[0].name), "path": str(soirees[0].path), "date": str(soirees[0].props.get("date", ""))}
	var people := {}
	var touch := func(key: String, name: String) -> Dictionary:
		if not people.has(key):
			people[key] = {"key": key, "name": name, "count": 0, "last": "", "rattache": false, "sure": false, "reported": 0}
		return people[key]
	for p in index.all_presences():
		var sk := TextNorm.name_key(str(p.soiree))
		if not soiree_dates.has(sk):
			continue
		var e: Dictionary = touch.call(str(p.target_key), str(p.target))
		e.count += 1
		if str(p.date) > str(e.last):
			e.last = str(p.date)
		if str(p.origin) == "propriété presents":
			e.sure = true
	for r in index.all_relations():
		if str(r.relation) != "present_a" or not soiree_dates.has(str(r.vers_key)):
			continue
		var f: Variant = JSON.parse_string(str(r.fields))
		var nm := Schema.link_name(f.get("de", "")) if typeof(f) == TYPE_DICTIONARY else str(r.de_key)
		var e: Dictionary = touch.call(str(r.de_key), nm)
		e.count += 1
		e.reported += 1
		var d: String = soiree_dates[str(r.vers_key)]
		if d > str(e.last):
			e.last = d
	for r in index.linked_from(domaine, ["domaine"]):
		if str(r.type) == "personnage":
			var e: Dictionary = touch.call(TextNorm.name_key(str(r.name)), str(r.name))
			e.rattache = true
	# fiches des personnes
	var fiches := {}
	for p in index.notes_with_props("personnage", ["clan", "titres", "sanctions", "rang", "secte", "statut", "identite"]):
		fiches[TextNorm.name_key(str(p.name))] = p
	for k in people:
		var e: Dictionary = people[k]
		var fi: Variant = fiches.get(k)
		e["path"] = str(fi.path) if fi != null else ""
		if fi != null:
			e.name = str(fi.name)
			var pr: Dictionary = fi.props
			e["clan"] = Schema.link_name(pr.get("clan", ""))
			e["titres"] = _list(pr.get("titres"))
			e["rang"] = Schema.option_label("personnage", "rang", pr.get("rang", ""))
			e["statut"] = str(pr.get("statut", ""))
			e["identite"] = str(pr.get("identite", ""))
			var al := []
			for x in _list(pr.get("sanctions")):
				if ALERTES.has(str(x)):
					al.append(Schema.option_label("personnage", "sanctions", x))
			e["alerts"] = al
			var gone := str(pr.get("statut", "")) in ["disparu", "mort_finale", "torpeur"]
			e["gone"] = gone
			if gone:
				# un mort ou un disparu n'est pas attendu ; on le rappelle s'il a été vu depuis moins d'un an
				if str(e.last) >= year_ago:
					out.alerts.append({"text": "%s : %s (vu(e) le %s)" % [e.name, Schema.option_label("personnage", "statut", pr.statut).to_lower(), e.last], "path": e.path})
			elif not al.is_empty():
				out.alerts.append({"text": "%s : %s" % [e.name, ", ".join(PackedStringArray(al))], "path": e.path})
	var plist: Array = people.values().filter(func(e): return not e.get("gone", false))
	out.gone = people.values().filter(func(e): return e.get("gone", false))
	plist.sort_custom(func(a, b): return str(a.last) > str(b.last) if str(a.last) != str(b.last) else int(a.count) > int(b.count))
	# probables : vues dans le domaine depuis moins d'un an ; les autres (vues avant,
	# ou seulement rattachées au domaine) à part
	out.people = plist.filter(func(e): return str(e.last) >= year_ago)
	out.others = plist.filter(func(e): return str(e.last) < year_ago)
	# 2. faveurs en cours dont une partie est une personne probable
	var recent := {}
	for e in out.people:
		recent[str(e.key)] = true
	for n in index.notes_with_props("faveur", ["debiteur", "creancier", "niveau", "statut", "domaine", "date"]):
		var pr: Dictionary = n.props
		var st := str(pr.get("statut", ""))
		if not st in ["active", "reclamee", "suspendue"]:
			continue
		var deb := TextNorm.name_key(Schema.link_name(pr.get("debiteur", "")))
		var cre := TextNorm.name_key(Schema.link_name(pr.get("creancier", "")))
		if not (recent.has(deb) or recent.has(cre)):
			continue
		out.faveurs.append({"text": "%s doit à %s — %s, %s" % [Schema.link_name(pr.get("debiteur", "")), Schema.link_name(pr.get("creancier", "")),
			Schema.option_label("faveur", "niveau", pr.get("niveau", "")).to_lower(), Schema.option_label("faveur", "statut", st).to_lower()],
			"path": str(n.path), "order": 0 if st == "reclamee" else 1, "date": str(pr.get("date", ""))})
	out.faveurs.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.date > b.date)
	# 3. questions pour la soirée : d'abord les contradictions qui touchent une
	#    personne probable, puis les dossiers et indices, puis les trous des fiches
	for c in contradictions:
		if (c.who as Array).any(func(w): return recent.has(TextNorm.name_key(str(w)))):
			out.questions.append({"text": "À trancher : " + str(c.title), "path": str((c.paths as Array)[0]) if not (c.paths as Array).is_empty() else "", "kind": "trancher"})
	for n in index.notes_with_props("dossier", ["statut", "question", "sujets", "priorite"]):
		var pr: Dictionary = n.props
		if not str(pr.get("statut", "ouvert")) in ["ouvert", "en_pause", ""]:
			continue
		if _concerns(pr.get("sujets"), people, dk):
			out.questions.append({"text": "Dossier : %s (priorité %s)" % [str(pr.get("question", n.name)), str(pr.get("priorite", "moyenne"))], "path": str(n.path), "kind": "dossier"})
	for n in index.notes_with_props("indice", ["statut", "sujets", "de", "vers", "credibilite"]):
		var pr: Dictionary = n.props
		var st := str(pr.get("statut", ""))
		if not st in ["non_verifie", "conteste"]:
			continue
		var subj: Array = _list(pr.get("sujets")) + _list(pr.get("de")) + _list(pr.get("vers"))
		if _concerns(subj, people, dk):
			out.questions.append({"text": "À vérifier : %s (%s)" % [n.name, Schema.option_label("indice", "statut", st).to_lower()], "path": str(n.path), "kind": "indice"})
	# trous des fiches des personnes vues au moins deux fois : ce qu'on peut leur demander
	var gaps := 0
	var by_count: Array = out.people.duplicate()
	by_count.sort_custom(func(a, b): return int(a.count) > int(b.count))
	for e in by_count:
		if gaps >= MAX_GAPS or int(e.count) < 2:
			continue
		var miss := PackedStringArray()
		if str(e.get("path", "")) == "":
			miss.append("pas encore de fiche")
		else:
			if str(e.get("clan", "")) == "":
				miss.append("clan")
			if str(e.get("rang", "")) == "":
				miss.append("statut d'âge")
			if str(e.get("identite", "")) in ["incertaine", "inconnue"]:
				miss.append("identité " + str(e.identite))
		if miss.is_empty():
			continue
		gaps += 1
		out.questions.append({"text": "Sur %s (vu(e) %d fois) : %s ?" % [e.name, e.count, ", ".join(miss)], "path": str(e.get("path", "")), "kind": "fiche"})

	# 4. tâches ouvertes : notes du domaine, ou qui citent une de ces personnes
	for t in index.open_tasks(2000):
		var here := TextNorm.name_key(Schema.link_name(t.domaine)) == dk
		var cites := false
		for l in _links(str(t.text)):
			if people.has(l):
				cites = true
		if here or cites:
			out.tasks.append({"text": "%s — %s" % [Schema.display_line(str(t.text)), t.name], "path": str(t.path), "line": int(t.line), "raw": str(t.text)})
	# 5. depuis la dernière soirée : sources et notes rapides datées après elle
	var since: String = str(out.last_soiree.get("date", ""))
	for n in index.dated_notes():
		if not str(n.type) in ["source", "en_cours", "evenement"]:
			continue
		var d := str(n.date if n.date != null and str(n.date) != "" else n.date_floue)
		var ndk := TextNorm.name_key(Schema.link_name(n.domaine))
		if since != "" and d < since:
			continue
		if ndk != dk and ndk != "":
			continue
		out.since.append({"text": "%s · %s · %s" % [d, Schema.type_label(str(n.type)), n.name], "path": str(n.path), "d": d})
	out.since.sort_custom(func(a, b): return a.d > b.d)
	return out


static func _links(text: String) -> Array:
	var out := []
	var re := RegEx.create_from_string("\\[\\[([^\\[\\]|#]+)")
	for m in re.search_all(text):
		out.append(TextNorm.name_key(m.get_string(1)))
	return out


static func _concerns(v: Variant, people: Dictionary, dk: String) -> bool:
	for x in _list(v):
		var k := TextNorm.name_key(Schema.link_name(x))
		if people.has(k) or k == dk:
			return true
	return false


## Comment on sait qu'une personne vient : « vue » (dans vos présents au moins
## une fois), « rapportée » (seulement par des comptes rendus), « incertaine »
## (seulement en présence incertaine), « rattachée » (jamais vue, fiche du domaine).
static func presence_kind(e: Dictionary) -> String:
	if int(e.get("count", 0)) == 0:
		return "rattachée"
	if e.get("sure", false):
		return "vue"
	if int(e.get("reported", 0)) > 0:
		return "rapportée"
	return "incertaine"


## Version texte, à copier (pour soi ou pour Claude).
static func to_markdown(p: Dictionary, title_date: String) -> String:
	var t := PackedStringArray()
	t.append("# Préparation de séance — %s — %s" % [p.domaine, title_date])
	if not p.last_soiree.is_empty():
		t.append("Dernière soirée connue : [[%s]] (%s) · %d soirée(s) dans ce domaine" % [p.last_soiree.name, p.last_soiree.date, p.soirees])
	t.append("\n## Alertes")
	for a in p.alerts:
		t.append("- " + a.text)
	if p.alerts.is_empty():
		t.append("- aucune")
	t.append("\n## Personnes probables")
	for e in p.people:
		var bits := PackedStringArray()
		if str(e.get("clan", "")) != "":
			bits.append(e.clan)
		if not (e.get("titres", []) as Array).is_empty():
			bits.append(", ".join(PackedStringArray(e.titres)))
		bits.append(("vu %d fois, dernière %s" % [e.count, e.last]) if e.count > 0 else "rattaché au domaine")
		t.append("- [[%s]] — %s" % [e.name, " · ".join(bits)])
	if not (p.get("others", []) as Array).is_empty():
		t.append("- (et %d autre(s) personne(s) du domaine, vue(s) il y a plus d'un an ou seulement rattachée(s))" % (p.others as Array).size())
	t.append("\n## Faveurs en cours")
	for f in p.faveurs:
		t.append("- " + f.text)
	t.append("\n## Questions pour la soirée")
	for q in p.questions:
		t.append("- " + q.text)
	t.append("\n## Tâches")
	for x in p.tasks:
		t.append("- [ ] " + x.text)
	t.append("\n## Depuis la dernière soirée")
	for s in p.since:
		t.append("- " + s.text)
	return "\n".join(t) + "\n"
