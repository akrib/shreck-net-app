extends RefCounted
## Rapport de soirée (format 1.3, A-FAIRE §2.2), calculé depuis l'index :
##  - les présents, rangés par clan (ordre de préséance du domaine), puis par
##    statut d'âge (du plus vieux au plus jeune), puis par points de statut
##    (postes, reconnaissances et tances en cours à la date de la soirée) ;
##  - les présences rapportées : éléments « était présent à » (present_a) qui
##    visent la soirée, notés dans les comptes rendus, pour les personnes qui ne
##    sont pas déjà dans vos présents (sinon ils corroborent la présence) ;
##  - les informations : éléments de la soirée, éléments des sources rattachées
##    à la soirée (propriété `soiree`), et ce que la propriété `rapport` de la
##    soirée cite ; dans l'ordre de `rapport`, puis dans l'ordre naturel.
## Rien n'est écrit ici : les modifications passent par AppService.
##
## Ordre suivi : statut d'âge, puis statut de fonction, puis reconnaissances.
## Le barème des points vient de la configuration du coffre (section
## « statut »), avec un barème simple par défaut : 1 point par poste,
## +1 par reconnaissance, −1 par tance.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Dates := preload("res://core/model/dates.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")

const RANGS := ["venerable", "ancien", "ancilla", "nouveau_ne", "infant"]
## Une reconnaissance ou une tance compte si sa crédibilité est au moins « possiblement vraie ».
const CRED_MAX := 3


## Barème effectif : {postes: {poste replié: points}, poste_defaut, reconnaissance, tance}.
static func bareme(config: Dictionary) -> Dictionary:
	var out := {"postes": {}, "poste_defaut": 1.0, "reconnaissance": 1.0, "tance": -1.0, "configure": false}
	var st: Variant = config.get("statut", {})
	if typeof(st) != TYPE_DICTIONARY:
		return out
	for k in ["poste_defaut", "reconnaissance", "tance"]:
		if st.has(k) and (typeof(st[k]) == TYPE_INT or typeof(st[k]) == TYPE_FLOAT):
			out[k] = float(st[k])
			out.configure = true
	var p: Variant = st.get("postes", {})
	if typeof(p) == TYPE_DICTIONARY:
		for k in p:
			if typeof(p[k]) == TYPE_INT or typeof(p[k]) == TYPE_FLOAT:
				out.postes[TextNorm.fold(str(k)).strip_edges()] = float(p[k])
				out.configure = true
	return out


## Ordre de préséance des clans pour un domaine : propriété `preseance` de la
## fiche du domaine, sinon liste `preseance` de la configuration. Clés de noms.
static func preseance(index: RefCounted, domaine: String, config: Dictionary) -> Array:
	var out := []
	var path: String = index.path_of_name(domaine) if domaine != "" else ""
	if path != "":
		var v: Variant = index.props_of(path).get("preseance", [])
		for x in (v if typeof(v) == TYPE_ARRAY else ([] if v == null or str(v) == "" else [v])):
			out.append(TextNorm.name_key(Schema.link_name(x)))
	if out.is_empty():
		var c: Variant = config.get("preseance", [])
		if typeof(c) == TYPE_ARRAY:
			for x in c:
				out.append(TextNorm.name_key(Schema.link_name(x)))
	return out


## Sépare « Prévôt de Lyon » en {poste: "Prévôt", lieu: "Lyon"} d'après la liste des postes.
static func split_titre(titre: String) -> Dictionary:
	var t := Schema.display_text(titre).strip_edges()
	var ft := TextNorm.fold(t)
	var best := ""
	for secte in Schema.POSTES:
		for p in Schema.POSTES[secte]:
			var fp := TextNorm.fold(p)
			if ft.begins_with(fp) and fp.length() > best.length():
				best = p
	if best == "":
		return {"poste": t, "lieu": "", "connu": false}
	var rest := t.substr(best.length()).strip_edges()
	var lieu := ""
	for prep in ["de ", "d'", "d’", "du ", "des "]:
		if rest.to_lower().begins_with(prep):
			lieu = rest.substr(prep.length()).strip_edges()
			break
	return {"poste": best, "lieu": lieu, "connu": true}


## La date d'un élément est-elle antérieure (ou égale) à la soirée, et son échéance
## pas encore passée ? Renvoie "ok", "futur" ou "expire".
static func validity(fields: Dictionary, note_date: String, soiree_date: String) -> String:
	if soiree_date == "":
		return "ok"
	var start := Dates.sort_key(str(fields.get("date_faits", note_date)))
	if start != "" and start.replace("-00", "") > soiree_date:
		return "futur"
	var j := str(fields.get("jusqu_au", "")).strip_edges()
	if j != "" and j != "inconnue":
		var end := j
		if j.contains("/") and not j.ends_with("/.."):
			end = j.split("/")[1]
		var ek := Dates.sort_key(end)
		# une échéance au mois (« 2026-11 ») court jusqu'à la fin du mois
		ek = ek.replace("-00", "-99")
		if ek != "" and ek < soiree_date:
			return "expire"
	return "ok"


## Statut d'un personnage à la date de la soirée.
static func person(index: RefCounted, name: String, soiree_date: String, domaine: String, bar: Dictionary,
		domaines: Dictionary, note_dates: Dictionary) -> Dictionary:
	var key := TextNorm.name_key(name)
	var path: String = index.path_of_name(name)
	var pr: Dictionary = index.props_of(path) if path != "" else {}
	var out := {"name": name, "key": key, "path": path, "missing": path == "",
		"clan": Schema.link_name(pr.get("clan", "")), "secte": Schema.link_name(pr.get("secte", "")),
		"rang": str(pr.get("rang", "")), "rang_label": Schema.option_label("personnage", "rang", pr.get("rang", "")),
		"statut": str(pr.get("statut", "")), "sanctions": _list(pr.get("sanctions")),
		"postes": [], "recos": [], "tances": [], "points": 0.0}
	var rang_i := RANGS.find(out.rang)
	out["rang_index"] = rang_i if rang_i >= 0 else RANGS.size()
	var seen_postes := {}
	# domaine de la soirée, sous son nom canonique (les alias d'un domaine y mènent)
	var dom_fold: String = str(domaines.get(TextNorm.fold(domaine), TextNorm.fold(domaine)))
	for t in _list(pr.get("titres")):
		var sp := split_titre(str(t))
		var lf := TextNorm.fold(Schema.link_name(sp.lieu))
		var hors: bool = sp.lieu != "" and domaines.has(lf) and str(domaines[lf]) != dom_fold
		var pts := 0.0 if hors else float(bar.postes.get(TextNorm.fold(sp.poste), bar.poste_defaut))
		out.postes.append({"titre": Schema.display_text(str(t)), "poste": sp.poste, "points": pts, "hors_domaine": hors, "source": ""})
		seen_postes[TextNorm.fold(Schema.display_text(str(t)))] = true
	if path != "" or key != "":
		for r in index.relations_of(name):
			if str(r.vers_key) != key:
				continue
			var code := str(r.relation)
			if not code in ["reconnait", "sobriquet", "nomme"]:
				continue
			var f: Variant = JSON.parse_string(str(r.fields))
			if typeof(f) != TYPE_DICTIONARY:
				f = {}
			var v := validity(f, str(note_dates.get(str(r.path), "")), soiree_date)
			if v == "futur":
				continue
			var cred: int = int(r.cred) if r.cred != null else 6
			var qual := Schema.display_text(str(f.get("qualificatif", ""))).strip_edges()
			var de := Schema.link_name(f.get("de", ""))
			if code == "nomme":
				if qual == "" or seen_postes.has(TextNorm.fold(qual)) or v != "ok" or cred > CRED_MAX:
					continue
				seen_postes[TextNorm.fold(qual)] = true
				var sp2 := split_titre(qual)
				var lf2 := TextNorm.fold(Schema.link_name(sp2.lieu))
				var hors2: bool = sp2.lieu != "" and domaines.has(lf2) and str(domaines[lf2]) != dom_fold
				out.postes.append({"titre": qual, "poste": sp2.poste, "hors_domaine": hors2, "source": str(r.note),
					"points": 0.0 if hors2 else float(bar.postes.get(TextNorm.fold(sp2.poste), bar.poste_defaut))})
				continue
			var list: Array = out.recos if code == "reconnait" else out.tances
			var dk := TextNorm.name_key(de) + "|" + TextNorm.fold(qual)
			var found := false
			for x in list:
				if x.dk == dk:
					found = true
					x.sources += 1
					if cred < int(x.cred):
						x.cred = cred
						x.source = str(r.note)
						x.path = str(r.path)
					if v == "ok":
						x.etat = "ok"
			if not found:
				list.append({"dk": dk, "qualificatif": qual, "de": de, "cred": cred, "etat": v,
					"jusqu_au": str(f.get("jusqu_au", "")), "source": str(r.note), "path": str(r.path), "sources": 1})
	var pp := 0.0
	for p in out.postes:
		pp += float(p.points)
	var pr_pts := 0.0
	for x in out.recos:
		x["compte"] = x.etat == "ok" and int(x.cred) <= CRED_MAX
		if x.compte:
			pr_pts += float(bar.reconnaissance)
	for x in out.tances:
		x["compte"] = x.etat == "ok" and int(x.cred) <= CRED_MAX
		if x.compte:
			pr_pts += float(bar.tance)
	out["points_postes"] = pp
	out["points_recos"] = pr_pts
	out.points = pp + pr_pts
	return out


static func _list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v
	return [] if str(v).strip_edges() == "" else [v]


## Clé de tri des présents : préséance du clan, statut d'âge, postes, reconnaissances, nom.
static func sort_people(people: Array, order: Array, clan_parent: Dictionary) -> void:
	var rank := func(p: Dictionary) -> int:
		var k := TextNorm.name_key(str(p.clan))
		if k == "":
			return 100000
		var i := order.find(k)
		if i < 0 and clan_parent.has(k):
			i = order.find(clan_parent[k])  # une lignée suit son clan d'origine
		return i if i >= 0 else 1000
	people.sort_custom(func(a, b):
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		if ra != rb:
			return ra < rb
		if ra >= 1000 and str(a.clan) != str(b.clan):
			return TextNorm.fold(str(a.clan)) < TextNorm.fold(str(b.clan))
		if int(a.rang_index) != int(b.rang_index):
			return int(a.rang_index) < int(b.rang_index)
		# statut de fonction, puis reconnaissances
		if not is_equal_approx(float(a.points_postes), float(b.points_postes)):
			return float(a.points_postes) > float(b.points_postes)
		if not is_equal_approx(float(a.points_recos), float(b.points_recos)):
			return float(a.points_recos) > float(b.points_recos)
		return TextNorm.fold(str(a.name)) < TextNorm.fold(str(b.name)))


## Regroupe des présents déjà triés : [{clan, people}].
static func group_by_clan(people: Array) -> Array:
	var groups := []
	var cur := "\u0001"
	for p in people:
		if str(p.clan) != cur:
			cur = str(p.clan)
			groups.append({"clan": cur, "people": []})
		groups[groups.size() - 1].people.append(p)
	return groups


## Rapport complet d'une soirée (chemin de la note).
static func build(index: RefCounted, soiree_rel: String, config: Dictionary) -> Dictionary:
	var pr: Dictionary = index.props_of(soiree_rel)
	var name := soiree_rel.get_file().get_basename()
	var date := str(pr.get("date", ""))
	var domaine := Schema.link_name(pr.get("domaine", ""))
	var bar := bareme(config)
	var out := {"path": soiree_rel, "name": name, "date": date, "domaine": domaine,
		"nature": Schema.option_label("soiree", "nature", pr.get("nature", "assemblee")),
		"fiabilite": str(pr.get("fiabilite", "")), "bareme": bar, "people": [], "uncertain": [], "groups": [],
		"items": [], "missing_ids": 0, "moi": str(config.get("moi", ""))}
	# notes datées (pour situer les reconnaissances) et domaines connus
	var note_dates := {}
	var domaines := {}
	var clan_parent := {}
	for r in index.rows("SELECT f.path, f.type, f.name, (SELECT value FROM props WHERE fid = f.fid AND key IN ('date', 'date_floue') LIMIT 1) AS d, (SELECT value FROM props WHERE fid = f.fid AND key = 'clan' LIMIT 1) AS clan FROM files f WHERE f.type != ''"):
		if r.d != null:
			note_dates[str(r.path)] = str(r.d)
		if str(r.type) == "domaine":
			domaines[TextNorm.fold(str(r.name))] = TextNorm.fold(str(r.name))
		if str(r.type) == "groupe" and r.clan != null:
			clan_parent[TextNorm.name_key(str(r.name))] = TextNorm.name_key(Schema.link_name(r.clan))
	# alias des domaines : « Prévôt du Très Bon Dauphiné » est un poste de Grenoble
	for r in index.rows("SELECT f.name, a.alias FROM aliases a JOIN files f ON f.fid = a.fid WHERE f.type = 'domaine'"):
		var fa := TextNorm.fold(str(r.alias))
		if not domaines.has(fa):
			domaines[fa] = TextNorm.fold(str(r.name))
	var order := preseance(index, domaine, config)
	out["preseance"] = order
	for k in [["presents", "people"], ["presents_incertains", "uncertain"]]:
		for x in _list(pr.get(k[0])):
			var nm := Schema.link_name(x)
			if nm != "":
				out[k[1]].append(person(index, nm, date, domaine, bar, domaines, note_dates))
	# présences rapportées : éléments « était présent à » des comptes rendus (GUIDE §5.1),
	# hors des présents que vous avez notés vous-même
	var listed := {}
	for p in out.people + out.uncertain:
		listed[str(p.key)] = p
	var rep_by := {}
	for r in index.presences_reported(name):
		var f: Variant = JSON.parse_string(str(r.fields))
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var who := Schema.link_name(f.get("de", ""))
		if who == "":
			continue
		var k := TextNorm.name_key(who)
		var src := {"note": str(r.note), "path": str(r.path), "block": str(r.block if r.block != null else ""),
			"cred": int(r.cred) if r.cred != null else 6, "nature": str(r.nature)}
		if listed.has(k):
			var lp: Dictionary = listed[k]
			if not lp.has("reported_by"):
				lp["reported_by"] = []
			lp.reported_by.append(src)
			continue
		if not rep_by.has(k):
			var np := person(index, who, date, domaine, bar, domaines, note_dates)
			np["reported_by"] = []
			rep_by[k] = np
		rep_by[k].reported_by.append(src)
	out["reported"] = rep_by.values()
	sort_people(out.people, order, clan_parent)
	sort_people(out.uncertain, order, clan_parent)
	sort_people(out.reported, order, clan_parent)
	out.groups = group_by_clan(out.people)
	out["reported_groups"] = group_by_clan(out.reported)
	out.items = items(index, soiree_rel, name, pr)
	for it in out.items:
		if str(it.block) == "" and it.kind == "element":
			out.missing_ids += 1
	return out


## Informations du rapport, dans l'ordre : d'abord celui de la propriété
## `rapport`, puis les éléments de la soirée, puis ceux des sources rattachées.
static func items(index: RefCounted, soiree_rel: String, soiree_name: String, pr: Dictionary) -> Array:
	var natural := []
	var fiab_of := {}
	var sfiab := str(pr.get("fiabilite", ""))
	for e in index.elements_of(soiree_rel):
		natural.append(_item_from_row(e, soiree_rel, soiree_name, "soiree", sfiab, "soiree"))
	var linked: Array = index.linked_from(soiree_name, ["soiree"])
	linked.sort_custom(func(a, b): return str(a.name) < str(b.name))
	for l in linked:
		if str(l.path) == soiree_rel:
			continue
		var lp: Dictionary = index.props_of(str(l.path))
		fiab_of[str(l.path)] = str(lp.get("fiabilite", ""))
		for e in index.elements_of(str(l.path)):
			natural.append(_item_from_row(e, str(l.path), str(l.name), str(l.type), str(lp.get("fiabilite", "")), "source"))
	# les présences rapportées ont leur propre rubrique : pas de doublon dans les informations
	var sk := TextNorm.name_key(soiree_name)
	natural = natural.filter(func(it): return not (str(it.fields.get("relation", "")) == "present_a"
		and TextNorm.name_key(Schema.link_name(it.fields.get("vers", ""))) == sk))
	var by_key := {}
	for it in natural:
		by_key[it.key] = it
	var ordered := []
	var used := {}
	for ref in _list(pr.get("rapport")):
		var s := str(ref).strip_edges()
		if s.begins_with("[[") and s.ends_with("]]"):
			s = s.substr(2, s.length() - 4)
		var sl := StructuredLines.split_link(s)
		var target: String = sl.target if sl.target != "" else soiree_name
		var sub: String = sl.sub
		if sub.begins_with("^"):
			var bid := sub.substr(1)
			var k := TextNorm.name_key(target) + "#" + bid
			if by_key.has(k):
				if not used.has(k):
					ordered.append(by_key[k])
					used[k] = true
				continue
			var row: Dictionary = index.element_by_ref(target, bid)
			if row.is_empty():
				ordered.append({"kind": "absent", "key": k, "ref": str(ref), "text": "Élément introuvable : " + str(ref),
					"path": "", "note": target, "note_type": "", "block": bid, "line": 0, "nature": "", "cred": null,
					"fiab": "", "origin": "lien", "fields": {}})
				used[k] = true
				continue
			var lp2: Dictionary = index.props_of(str(row.path))
			var it := _item_from_row(row, str(row.path), str(row.note), str(row.type), str(lp2.get("fiabilite", "")), "lien")
			if not used.has(it.key):
				ordered.append(it)
				used[it.key] = true
		else:
			# une note entière : événement, indice (sa crédibilité), ou source (tous ses éléments)
			var path: String = index.path_of_name(target)
			var nk := TextNorm.name_key(target)
			if path == "":
				ordered.append({"kind": "absent", "key": nk, "ref": str(ref), "text": "Note introuvable : " + str(ref),
					"path": "", "note": target, "note_type": "", "block": "", "line": 0, "nature": "", "cred": null,
					"fiab": "", "origin": "lien", "fields": {}})
				continue
			var np: Dictionary = index.props_of(path)
			var t := str(np.get("type", ""))
			if t == "source" or t == "soiree":
				for e in index.elements_of(path):
					var it2 := _item_from_row(e, path, target, t, str(np.get("fiabilite", "")), "lien")
					if not used.has(it2.key):
						ordered.append(it2)
						used[it2.key] = true
				continue
			if used.has(nk):
				continue
			used[nk] = true
			var c: Variant = np.get("credibilite")
			ordered.append({"kind": "note", "key": nk, "ref": "[[%s]]" % target, "path": path, "note": target,
				"note_type": t, "block": "", "line": 0,
				"text": str(np.get("description", target)) if np.has("description") else target,
				"nature": "", "cred": int(str(c)) if c != null and str(c).is_valid_int() else null,
				"fiab": "", "origin": "lien", "fields": {}, "statut": str(np.get("statut", ""))})
	for it in natural:
		if not used.has(it.key):
			ordered.append(it)
			used[it.key] = true
	return ordered


static func _item_from_row(e: Dictionary, path: String, note: String, note_type: String, fiab: String, origin: String) -> Dictionary:
	var f: Variant = JSON.parse_string(str(e.fields))
	if typeof(f) != TYPE_DICTIONARY:
		f = {}
	var block := str(e.block if e.block != null else "")
	var key := (TextNorm.name_key(note) + "#" + block) if block != "" else (path + "@" + str(e.line))
	return {"kind": "element", "key": key, "ref": ("[[%s#^%s]]" % [note, block]) if block != "" else "",
		"path": path, "note": note, "note_type": note_type, "block": block, "line": int(e.line),
		"text": str(e.text), "nature": str(e.nature if e.nature != null else ""),
		"cred": int(e.cred) if e.cred != null else null, "fiab": fiab, "origin": origin, "fields": f,
		"par": Schema.link_name(f.get("par", ""))}


## Liste `rapport` à écrire pour un ordre donné (les éléments sans identifiant n'y figurent pas).
static func order_refs(list: Array) -> Array:
	var out := []
	for it in list:
		if str(it.get("ref", "")) != "" and it.kind != "absent":
			out.append(str(it.ref))
	return out


## Présentation protocolaire : « Victor Morel, Ancilla du clan Toreador, Primogène de Valombre, reconnu « Avisé » par Armand Lescure ».
static func presentation(p: Dictionary) -> String:
	var parts := PackedStringArray([str(p.name)])
	var rang := str(p.rang_label)
	var clan := str(p.clan)
	if rang != "" and clan != "":
		parts.append("%s du clan %s" % [rang, clan])
	elif rang != "":
		parts.append(rang)
	elif clan != "":
		parts.append("du clan " + clan)
	for x in p.postes:
		parts.append(str(x.titre))
	for pair in [[p.recos, "reconnaissance", "reconnaissances"], [p.tances, "tance", "tances"]]:
		var bits := PackedStringArray()
		for x in pair[0]:
			if x.compte:
				var b := ("« %s »" % x.qualificatif) if str(x.qualificatif) != "" else ""
				if str(x.de) != "":
					b = (b + " par " + str(x.de)).strip_edges()
				bits.append(b)
		if not bits.is_empty():
			parts.append(("%s %s" % [pair[1] if bits.size() == 1 else pair[2], " ; ".join(bits)]).strip_edges())
	return ", ".join(parts)


## Points de statut lisibles : « 3 pts (postes 2, reconnaissances +1) ».
static func points_label(p: Dictionary) -> String:
	var pts := float(p.points)
	var s := "%s pt%s" % [_num(pts), "s" if absf(pts) >= 2.0 else ""]
	var det := PackedStringArray()
	if not is_zero_approx(float(p.points_postes)):
		det.append("postes " + _num(float(p.points_postes)))
	if not is_zero_approx(float(p.points_recos)):
		det.append("reconnaissances et tances %s%s" % ["+" if float(p.points_recos) > 0 else "", _num(float(p.points_recos))])
	return s + ((" (" + ", ".join(det) + ")") if not det.is_empty() else "")


static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else ("%.1f" % x)


## Texte prêt à publier (forum, Discord). `cotes` : ajoute la cote B2… de chaque
## information ; `hypotheses` : garde les déductions et hypothèses (sinon retirées).
static func to_text(rep: Dictionary, cotes := false, hypotheses := false) -> String:
	var lines := PackedStringArray()
	var titre := "%s de %s" % [rep.nature, rep.domaine]
	if str(rep.date).length() == 10:
		titre += " — " + Dates.label(rep.date)
	lines.append("**%s**" % titre)
	lines.append("")
	if not rep.people.is_empty():
		lines.append("**Présents**")
		for g in rep.groups:
			lines.append("*%s*" % (g.clan if str(g.clan) != "" else "Clan inconnu"))
			for p in g.people:
				lines.append("- " + presentation(p))
		lines.append("")
	if not rep.uncertain.is_empty():
		lines.append("**Présences incertaines**")
		for p in rep.uncertain:
			lines.append("- " + presentation(p))
		lines.append("")
	var infos := PackedStringArray()
	for it in rep.items:
		if it.kind == "absent":
			continue
		if not hypotheses and str(it.nature) in ["hypothese", "deduction"]:
			continue
		var t := Schema.display_text(str(it.text)).strip_edges()
		if cotes:
			var grade := ("%s%s" % [it.fiab if str(it.fiab) != "" else "", str(it.cred) if it.cred != null else ""]).strip_edges()
			if grade != "":
				t += " (%s)" % grade
		infos.append("%d. %s" % [infos.size() + 1, t])
	if not infos.is_empty():
		lines.append("**Informations**")
		lines.append_array(infos)
		lines.append("")
	if str(rep.moi) != "":
		lines.append("— " + Schema.link_name(rep.moi))
	return "\n".join(lines).strip_edges() + "\n"
