extends RefCounted
## Données du graphe des relations, calculées depuis l'index (FORMAT §16) :
##  - relations des éléments (avec leur source et leur crédibilité) ;
##  - indices relationnels (avec leur statut) ;
##  - faveurs, affichées à part (débiteur → créancier) ;
##  - structure : clan, secte, sire, lignée → clan ;
##  - coprésence aux soirées (facultatif : vite très dense).
## Rien n'est écrit dans les notes.

const Schema := preload("res://core/model/schema.gd")
const Lineage := preload("res://core/analysis/lineage.gd")
const TextNorm := preload("res://core/format/text_norm.gd")

static var _lig_key := ""
static var _lig_cache := {}

const HOSTILE := ["ennemi", "rival", "chantage", "sobriquet"]
const FRIENDLY := ["allie", "protege", "sert", "membre_de", "mentor_de", "contact_de", "lien_de_sang", "reconnait", "nomme"]
const NODE_TYPES := ["personnage", "groupe", "domaine", "lieu", "objet"]


## options : {center: nom ou "", depth: 1|2, relations, indices, faveurs, structure,
##            copresence: bool, max_cred: 1..6, all_faveurs: bool, max_nodes: int,
##            hide_codes: [codes de relation à cacher], lignees: bool (lignées déduites),
##            chefs: bool (une lignée qui a un chef est montrée par lui, 1.7)}
## Renvoie {nodes: {clé: {name, type, path, missing, heads: [{name, path}]}}, edges: [{a, b, kind, code, label, directed, cred, weight, path, active}]}
static func build(index: RefCounted, opts: Dictionary) -> Dictionary:
	var names: Dictionary = index.all_names()
	var disp := {}   # clé -> nom tel qu'écrit, pour les fiches qui n'existent pas encore
	var edges := []
	var max_cred := int(opts.get("max_cred", 6))
	var rel_labels := {}
	for o in Schema.options("", "relation"):
		rel_labels[o[0]] = o[1]
	var hidden: Array = opts.get("hide_codes", [])
	if opts.get("relations", true):
		for r in index.all_relations():
			var code := str(r.relation)
			if code == "present_a" or hidden.has(code):
				continue
			var c: int = int(r.cred) if r.cred != null else 6
			if c > max_cred:
				continue
			var f: Variant = JSON.parse_string(str(r.fields))
			if typeof(f) == TYPE_DICTIONARY:
				disp[str(r.de_key)] = Schema.link_name(f.get("de", ""))
				disp[str(r.vers_key)] = Schema.link_name(f.get("vers", ""))
			edges.append({"a": str(r.de_key), "b": str(r.vers_key), "kind": "relation", "code": code,
				"label": str(rel_labels.get(code, code)), "directed": true, "cred": c, "weight": 1,
				"path": str(r.path), "source": str(r.note), "active": true, "text": str(r.text)})
	if opts.get("indices", true):
		for n in index.notes_with_props("indice", ["relation", "de", "vers", "statut", "credibilite"]):
			var pr: Dictionary = n.props
			var code := str(pr.get("relation", ""))
			if code == "" or hidden.has(code):
				continue
			var c := int(str(pr.get("credibilite", "6"))) if str(pr.get("credibilite", "")).is_valid_int() else 6
			if c > max_cred:
				continue
			var st := str(pr.get("statut", ""))
			edges.append({"a": TextNorm.name_key(Schema.link_name(pr.get("de", ""))), "b": TextNorm.name_key(Schema.link_name(pr.get("vers", ""))),
				"kind": "indice", "code": code, "label": str(rel_labels.get(code, code)),
				"suffix": " (indice %s)" % Schema.option_label("indice", "statut", st).to_lower(),
				"directed": true, "cred": c, "weight": 1, "path": str(n.path), "source": str(n.name),
				"active": not st in ["refute", "obsolete"], "text": str(n.name)})
	if opts.get("faveurs", true):
		for n in index.notes_with_props("faveur", ["debiteur", "creancier", "niveau", "statut"]):
			var pr: Dictionary = n.props
			var st := str(pr.get("statut", ""))
			var active := st in ["active", "reclamee", "suspendue"]
			if not active and not opts.get("all_faveurs", false):
				continue
			edges.append({"a": TextNorm.name_key(Schema.link_name(pr.get("debiteur", ""))), "b": TextNorm.name_key(Schema.link_name(pr.get("creancier", ""))),
				"kind": "faveur", "code": str(pr.get("niveau", "")),
				"label": "doit une faveur %s (%s)" % [Schema.option_label("faveur", "niveau", pr.get("niveau", "")).to_lower(), Schema.option_label("faveur", "statut", st).to_lower()],
				"directed": true, "cred": 1, "weight": 1, "path": str(n.path), "source": str(n.name), "active": active, "text": str(n.name),
				"niv": Schema.option_label("faveur", "niveau", pr.get("niveau", "")).to_lower(),
				"st": Schema.option_label("faveur", "statut", st).to_lower()})
	if opts.get("structure", true):
		for n in index.notes_with_props("personnage", ["clan", "secte", "sire"]):
			var pr: Dictionary = n.props
			var me := TextNorm.name_key(str(n.name))
			for k in ["clan", "secte"]:
				var t := Schema.link_name(pr.get(k, ""))
				if t != "":
					edges.append({"a": me, "b": TextNorm.name_key(t), "kind": "structure", "code": k,
						"label": "clan" if k == "clan" else "secte", "directed": true, "cred": 1, "weight": 1,
						"path": str(n.path), "source": str(n.name), "active": true, "text": ""})
			var sire := Schema.link_name(pr.get("sire", ""))
			if sire != "":
				edges.append({"a": TextNorm.name_key(sire), "b": me, "kind": "structure", "code": "sire",
					"label": "sire de", "directed": true, "cred": 1, "weight": 1, "path": str(n.path),
					"source": str(n.name), "active": true, "text": ""})
		for n in index.notes_with_props("groupe", ["clan", "secte"]):
			var pr: Dictionary = n.props
			for k in ["clan", "secte"]:
				var t := Schema.link_name(pr.get(k, ""))
				if t != "":
					edges.append({"a": TextNorm.name_key(str(n.name)), "b": TextNorm.name_key(t), "kind": "structure",
						"code": k, "label": "lignée de" if k == "clan" else "secte", "directed": true, "cred": 1,
						"weight": 1, "path": str(n.path), "source": str(n.name), "active": true, "text": ""})
	# lignées déduites : la lignée d'un infant remonte à son sire (core/analysis/lineage.gd) ;
	# les lignées déclarées sont déjà des relations.
	if opts.get("lignees", true) and not hidden.has("lignee_de"):
		# calcul gardé tant que l'index ne change pas (il ne dépend pas des filtres)
		var ck: String = index.content_key() if index.has_method("content_key") else ""
		if ck == "" or ck != _lig_key:
			var ls: Array = Lineage.sire_links(index)
			var ligs0: Dictionary = Lineage.lignees(index)
			var claims0: Dictionary = Lineage.claims_with_chefs(index, ligs0, ls)
			var nm0 := {}
			for l in ls:
				nm0[l.sk] = l.sire
				nm0[l.ik] = l.infant
			_lig_cache = {"ligs": ligs0, "claims": claims0, "mem": Lineage.memberships(ls, claims0), "nm": nm0}
			_lig_key = ck
		var ligs: Dictionary = _lig_cache.ligs
		var claims: Dictionary = _lig_cache.claims
		var mem: Dictionary = _lig_cache.mem
		var nm: Dictionary = _lig_cache.nm
		for pk in mem:
			var bad: Array = Lineage.incoherent(mem[pk], claims.parents)
			for lk in mem[pk]:
				var m: Dictionary = mem[pk][lk]
				if m.declared and not bad.has(lk):
					continue
				var lname := str(ligs[lk].name)
				var via := ", ".join(PackedStringArray((m.via as Array).map(func(v): return str(nm.get(v, v)))))
				var b_key := TextNorm.name_key(lname)
				disp[b_key] = lname
				if not m.declared:
					edges.append({"a": pk, "b": b_key, "kind": "lignee", "code": "lignee_de",
						"label": "est de la lignée de (déduit de son infant %s)" % via + (" — incohérent" if bad.has(lk) else ""),
						"directed": true, "cred": 6, "weight": 1, "path": str(ligs[lk].path), "source": "déduction", "active": true,
						"text": "", "bad": bad.has(lk)})
				else:
					# déclarée mais incohérente avec une autre de ses lignées : signalée en rouge
					edges.append({"a": pk, "b": b_key, "kind": "lignee", "code": "lignee_de",
						"label": "lignées qui ne s'accordent pas (%s)" % ", ".join(PackedStringArray(bad.map(func(x): return str(ligs[x].name) if ligs.has(x) else str(x)))),
						"directed": true, "cred": 6, "weight": 1, "path": str(ligs[lk].path), "source": "cohérence", "active": true,
						"text": "", "bad": true})
	if opts.get("copresence", false):
		var by_soiree := {}
		for p in index.all_presences():
			var key := str(p.path)
			if not by_soiree.has(key):
				by_soiree[key] = {}
			by_soiree[key][str(p.target_key)] = true
		var pairs := {}
		for key in by_soiree:
			var people: Array = by_soiree[key].keys()
			people.sort()
			for i in people.size():
				for j in range(i + 1, people.size()):
					var pk := "%s|%s" % [people[i], people[j]]
					pairs[pk] = int(pairs.get(pk, 0)) + 1
		for pk in pairs:
			var ab: PackedStringArray = str(pk).split("|")
			edges.append({"a": ab[0], "b": ab[1], "kind": "copresence", "code": "", "label": "vus ensemble à %d soirée(s)" % pairs[pk],
				"directed": false, "cred": 1, "weight": pairs[pk], "path": "", "source": "", "active": true, "text": ""})
	# ne garder que les arêtes complètes
	edges = edges.filter(func(e): return str(e.a) != "" and str(e.b) != "" and e.a != e.b)
	# un chef de lignée représente sa lignée, comme dans les lignages : les liens
	# de la lignée passent à son chef, qui porte la mention « Chef de la lignée de… »
	var heads := {}
	var chef_of := {}
	if opts.get("chefs", true):
		var ligs2: Dictionary = Lineage.lignees(index)
		for lk in ligs2:
			var ck := str(ligs2[lk].get("chef_key", ""))
			if ck == "":
				continue
			chef_of[TextNorm.name_key(str(ligs2[lk].name))] = ck
			disp[ck] = str(ligs2[lk].chef)
			if not heads.has(ck):
				heads[ck] = []
			heads[ck].append({"name": str(ligs2[lk].name), "path": str(ligs2[lk].path)})
		if not chef_of.is_empty():
			var merged := []
			for e in edges:
				var a := str(chef_of.get(e.a, e.a))
				var b := str(chef_of.get(e.b, e.b))
				if a == e.a and b == e.b:
					merged.append(e)
					continue
				if a == b or (e.kind == "structure" and chef_of.has(e.a)):
					continue  # le chef a déjà son clan et sa secte
				var e2: Dictionary = e.duplicate()
				e2.a = a
				e2.b = b
				if str(e.code) in ["membre_de", "lignee_de"]:
					e2.label = "est de la lignée de"
				else:
					e2["suffix"] = " (%s)" % disp.get(e.b if chef_of.has(e.b) else e.a, "lignée")
				merged.append(e2)
			edges = merged
	# sélection des sommets
	var keep := {}
	var center := TextNorm.name_key(str(opts.get("center", "")))
	center = str(chef_of.get(center, center))
	if center != "":
		keep[center] = 0
		var frontier := [center]
		for d in int(opts.get("depth", 1)):
			var nxt := []
			for e in edges:
				for pair in [[e.a, e.b], [e.b, e.a]]:
					if frontier.has(pair[0]) and not keep.has(pair[1]):
						if e.kind == "copresence" and d > 0:
							continue  # la coprésence n'étend pas le graphe au-delà du premier cercle
						keep[pair[1]] = d + 1
						nxt.append(pair[1])
			frontier = nxt
	else:
		var degree := {}
		for e in edges:
			if e.kind == "copresence":
				continue
			degree[e.a] = int(degree.get(e.a, 0)) + 1
			degree[e.b] = int(degree.get(e.b, 0)) + 1
		var ks: Array = degree.keys()
		ks.sort_custom(func(x, y): return degree[x] > degree[y])
		for k in ks.slice(0, int(opts.get("max_nodes", 120))):
			keep[k] = 1
	var nodes := {}
	for k in keep:
		var info: Dictionary = names.get(k, {})
		nodes[k] = {"name": str(info.get("name", disp.get(k, k))), "type": str(info.get("type", "")),
			"path": str(info.get("path", "")), "missing": info.is_empty(), "ring": keep[k], "heads": heads.get(k, [])}
	var out_edges := []
	for e in edges:
		if nodes.has(e.a) and nodes.has(e.b):
			out_edges.append(e)
	return {"nodes": nodes, "edges": out_edges, "center": center}


## Couleur d'une arête selon sa nature (utilisée par la vue et la légende).
static func edge_color(e: Dictionary) -> Color:
	match str(e.kind):
		"faveur":
			return Color("e0b04a") if e.active else Color("6d5a2c")
		"structure":
			return Color("9c86c9")
		"copresence":
			return Color("5d8fb8")
		"lignee":
			return Color("ff7a6b") if e.get("bad", false) else Color("b79cff")
	var code := str(e.code)
	var base := Color("b9b2c4")
	if HOSTILE.has(code):
		base = Color("ff7a6b")
	elif FRIENDLY.has(code):
		base = Color("7fd59b")
	if not e.active:
		base = base.darkened(0.5)
	return base


static func node_color(n: Dictionary) -> Color:
	if n.missing:
		return Color("6b6475")
	match str(n.type):
		"personnage":
			return Color("8fd3ff")
		"groupe":
			return Color("c8b6ff")
		"domaine", "lieu":
			return Color("9be3a8")
	return Color("f5e08a")
