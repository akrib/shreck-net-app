extends RefCounted
## Chemins les plus probables entre deux fiches (format 1.3, A-FAIRE §2.1).
##
## Chaque lien entre deux fiches est attesté par un ou plusieurs éléments,
## indices, faveurs… Une attestation vaut une probabilité tirée de l'échelle de
## l'Amirauté : p(fiabilité de la source) × p(crédibilité de l'information).
## Plusieurs attestations d'un même lien le renforcent (« ou » probabiliste),
## sauf si elles viennent de la même note ou de la même personne : dans ce cas
## seule la meilleure compte. Le chemin le plus probable est celui dont le
## produit des probabilités est le plus grand (Dijkstra sur −ln p), et les
## suivants sont trouvés par l'algorithme de Yen.
## Rien n'est écrit dans les notes.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Dates := preload("res://core/model/dates.gd")

## Table par défaut ; le coffre peut la remplacer (config.json, section « amiraute »).
const P_FIAB := {"A": 0.95, "B": 0.8, "C": 0.6, "D": 0.4, "E": 0.2, "F": 0.5}
const P_CRED := {"1": 0.95, "2": 0.8, "3": 0.6, "4": 0.4, "5": 0.2, "6": 0.5}
## Fiches qui relient « tout le monde » : exclues comme étapes intermédiaires
## tant que l'option « clan, secte, domaine » n'est pas cochée.
const HUB_TYPES := ["domaine", "concept"]
const HUB_NATURES := ["clan", "lignee", "secte"]
const P_STRUCTURE := 0.8
const P_COPRESENCE := 0.2
const P_MAX := 0.99


## Table de conversion effective (défauts complétés par le coffre).
static func table(config: Dictionary) -> Dictionary:
	var fi := P_FIAB.duplicate()
	var cr := P_CRED.duplicate()
	var am: Variant = config.get("amiraute", {})
	if typeof(am) == TYPE_DICTIONARY:
		for pair in [[fi, "fiabilite"], [cr, "credibilite"]]:
			var src: Variant = am.get(pair[1], {})
			if typeof(src) != TYPE_DICTIONARY:
				continue
			for k in src:
				var v := float(str(src[k])) if str(src[k]).is_valid_float() else -1.0
				if pair[0].has(str(k)) and v > 0.0 and v <= 1.0:
					pair[0][str(k)] = v
	return {"fiabilite": fi, "credibilite": cr}


static func p_of(tab: Dictionary, fiab: String, cred: Variant) -> float:
	var pf: float = tab.fiabilite.get(fiab if fiab != "" else "F", tab.fiabilite.F)
	var pc: float = tab.credibilite.get(str(cred) if cred != null and str(cred) != "" else "6", tab.credibilite["6"])
	return pf * pc


## Fin de la période couverte par une date (clé triable) : un intervalle ouvert
## (« depuis ») court toujours.
static func _end_key(edtf: String) -> String:
	var s := edtf.strip_edges()
	if s == "" or s == "inconnue":
		return ""
	if s.ends_with("/.."):
		return "9999-99-99"
	if s.contains("/") and not s.begins_with("../"):
		return Dates.sort_key(s.split("/")[1])
	return Dates.sort_key(s)


## Toutes les attestations de liens du coffre, filtrées.
## opts : {relations, indices, faveurs, structure, copresence: bool,
##         sans_inevaluable: bool (ignore F et 6), depuis: "AAAA-MM-JJ" ou "",
##         max_cred: 1..6, exclure: [codes de relation], config: Dictionary}
## Renvoie [{a, b, kind, code, label, de, vers, p, fiab, cred, origin, par, path, note, text, date}].
static func attestations(index: RefCounted, opts: Dictionary) -> Array:
	var tab := table(opts.get("config", {}))
	var out := []
	var depuis := str(opts.get("depuis", ""))
	var skip_f := bool(opts.get("sans_inevaluable", false))
	var max_cred := int(opts.get("max_cred", 6))
	var exclude := {}
	for c in opts.get("exclure", []):
		exclude[str(c)] = true
	var rel_labels := {}
	for o in Schema.options("", "relation"):
		rel_labels[o[0]] = o[1]
	# fiabilité et date de chaque note qui en porte une
	var info := {}
	for r in index.rows("SELECT f.path, f.name_key, f.type, (SELECT value FROM props WHERE fid = f.fid AND key = 'fiabilite' LIMIT 1) AS fiab, (SELECT value FROM props WHERE fid = f.fid AND key = 'date' LIMIT 1) AS date, (SELECT value FROM props WHERE fid = f.fid AND key = 'date_floue' LIMIT 1) AS date_floue FROM files f WHERE f.type != ''"):
		info[str(r.path)] = {"fiab": str(r.fiab if r.fiab != null else ""), "type": str(r.type),
			"date": str(r.date if r.date != null else (r.date_floue if r.date_floue != null else "")), "key": str(r.name_key)}
	var person_fiab := {}
	for p in info:
		if info[p].type == "personnage" and info[p].fiab != "":
			person_fiab[info[p].key] = info[p].fiab
	if opts.get("relations", true):
		for r in index.all_relations():
			var code := str(r.relation)
			if code == "present_a" or exclude.has(code):
				continue
			if r.cred != null and int(r.cred) > max_cred:
				continue
			var f: Variant = JSON.parse_string(str(r.fields))
			if typeof(f) != TYPE_DICTIONARY:
				f = {}
			var ni: Dictionary = info.get(str(r.path), {})
			var par := TextNorm.name_key(Schema.link_name(f.get("par", "")))
			# fiabilité : celle de la personne qui l'a dit si elle est évaluée, sinon celle de la note
			# (la fiabilité d'une fiche personnage est celle du personnage, pas de la note)
			var fiab := str(person_fiab.get(par, "")) if par != "" else ""
			if (fiab == "" or fiab == "F") and str(ni.get("type", "")) in ["source", "soiree"] and str(ni.get("fiab", "")) != "":
				fiab = str(ni.fiab)
			if fiab == "":
				fiab = "F"
			var cred: Variant = r.cred
			if skip_f and (fiab == "F" or cred == null or int(cred) == 6):
				continue
			var date := str(f.get("date_faits", ni.get("date", "")))
			if depuis != "":
				var ek := _end_key(date)
				if ek != "" and ek < depuis:
					continue
				var jusqu := _end_key(str(f.get("jusqu_au", "")))
				if jusqu != "" and jusqu < depuis:
					continue
			out.append({"a": str(r.de_key), "b": str(r.vers_key), "kind": "relation", "code": code,
				"label": str(rel_labels.get(code, code)),
				"de": Schema.link_name(f.get("de", "")), "vers": Schema.link_name(f.get("vers", "")),
				"p": p_of(tab, fiab, cred), "fiab": fiab, "cred": cred if cred != null else 6,
				"origin": "note:" + str(r.path), "par": par, "path": str(r.path), "note": str(r.note),
				"text": str(r.text), "date": date})
	if opts.get("indices", true):
		for n in index.notes_with_props("indice", ["relation", "de", "vers", "statut", "credibilite", "date_floue", "pour"]):
			var pr: Dictionary = n.props
			var code := str(pr.get("relation", ""))
			var st := str(pr.get("statut", ""))
			if code == "" or st in ["refute", "obsolete"] or exclude.has(code):
				continue
			var c := str(pr.get("credibilite", "6"))
			if c.is_valid_int() and int(c) > max_cred:
				continue
			if skip_f and c == "6":
				continue
			var de := Schema.link_name(pr.get("de", ""))
			var vers := Schema.link_name(pr.get("vers", ""))
			# l'indice s'appuie sur ses éléments « pour » : ce n'est pas une origine indépendante d'eux
			var joins := []
			var pour: Variant = pr.get("pour", [])
			for ref in (pour if typeof(pour) == TYPE_ARRAY else ([] if pour == null else [pour])):
				var p: String = index.path_of_name(Schema.link_name(ref))
				if p != "":
					joins.append("note:" + p)
			out.append({"joins": joins, "a": TextNorm.name_key(de), "b": TextNorm.name_key(vers), "kind": "indice", "code": code,
				"label": str(rel_labels.get(code, code)), "statut": Schema.option_label("indice", "statut", st).to_lower(),
				"de": de, "vers": vers, "p": float(tab.credibilite.get(c, tab.credibilite["6"])), "fiab": "",
				"cred": int(c) if c.is_valid_int() else 6, "origin": "note:" + str(n.path), "par": "",
				"path": str(n.path), "note": str(n.name), "text": str(n.name), "date": str(pr.get("date_floue", ""))})
	if opts.get("faveurs", false):
		for n in index.notes_with_props("faveur", ["debiteur", "creancier", "niveau", "statut", "credibilite", "date"]):
			var pr: Dictionary = n.props
			if not str(pr.get("statut", "")) in ["active", "reclamee", "suspendue"]:
				continue
			var c := str(pr.get("credibilite", "2"))
			var de := Schema.link_name(pr.get("debiteur", ""))
			var vers := Schema.link_name(pr.get("creancier", ""))
			out.append({"a": TextNorm.name_key(de), "b": TextNorm.name_key(vers), "kind": "faveur",
				"code": str(pr.get("niveau", "")),
				"label": "doit une faveur %s à" % Schema.option_label("faveur", "niveau", pr.get("niveau", "")).to_lower(),
				"de": de, "vers": vers, "p": float(tab.credibilite.get(c, tab.credibilite["2"])), "fiab": "",
				"cred": int(c) if c.is_valid_int() else 2, "origin": "note:" + str(n.path), "par": "",
				"path": str(n.path), "note": str(n.name), "text": str(n.name), "date": str(pr.get("date", ""))})
	if opts.get("structure", false):
		for n in index.notes_with_props("personnage", ["clan", "secte", "sire"]):
			var pr: Dictionary = n.props
			var me := str(n.name)
			for k in ["clan", "secte", "sire"]:
				var t := Schema.link_name(pr.get(k, ""))
				if t == "":
					continue
				var de := t if k == "sire" else me
				var vers := me if k == "sire" else t
				out.append({"a": TextNorm.name_key(de), "b": TextNorm.name_key(vers), "kind": "structure", "code": k,
					"label": {"clan": "est du clan", "secte": "est de la secte", "sire": "est le sire de"}[k],
					"de": de, "vers": vers, "p": P_STRUCTURE, "fiab": "", "cred": 2,
					"origin": "note:" + str(n.path), "par": "", "path": str(n.path), "note": me, "text": "", "date": ""})
	if opts.get("copresence", false):
		var by_soiree := {}
		var names := {}
		for pr in index.all_presences():
			var key := str(pr.path)
			if depuis != "" and str(pr.date if pr.date != null else "") != "" and Dates.sort_key(str(pr.date)) < depuis:
				continue
			if not by_soiree.has(key):
				by_soiree[key] = {"name": str(pr.soiree), "date": str(pr.date if pr.date != null else ""), "people": {}}
			by_soiree[key].people[str(pr.target_key)] = true
			names[str(pr.target_key)] = str(pr.target)
		for key in by_soiree:
			var people: Array = by_soiree[key].people.keys()
			people.sort()
			if people.size() > 40:
				continue  # grand rassemblement : la coprésence n'y apprend rien
			for i in people.size():
				for j in range(i + 1, people.size()):
					out.append({"a": people[i], "b": people[j], "kind": "copresence", "code": "",
						"label": "vu avec", "de": names[people[i]], "vers": names[people[j]], "p": P_COPRESENCE,
						"fiab": "", "cred": 3, "origin": "note:" + key, "par": "", "path": key,
						"note": by_soiree[key].name, "text": "", "date": by_soiree[key].date})
	return out.filter(func(x): return str(x.a) != "" and str(x.b) != "" and x.a != x.b)


## Regroupe les attestations par paire de fiches et calcule la probabilité de
## chaque lien. Renvoie {adj: {clé: {voisin: index du lien}}, links: [{a, b, p, att: [...]}]}.
static func combine(atts: Array) -> Dictionary:
	var by_pair := {}
	for x in atts:
		var a: String = x.a
		var b: String = x.b
		var pk := (a + "\t" + b) if a < b else (b + "\t" + a)
		if not by_pair.has(pk):
			by_pair[pk] = []
		by_pair[pk].append(x)
	var links := []
	var adj := {}
	for pk in by_pair:
		var list: Array = by_pair[pk]
		list.sort_custom(func(x, y): return x.p > y.p)
		var ab: PackedStringArray = str(pk).split("\t")
		var l := {"a": ab[0], "b": ab[1], "p": _noisy_or(list), "att": list}
		var li := links.size()
		links.append(l)
		for pair in [[ab[0], ab[1]], [ab[1], ab[0]]]:
			if not adj.has(pair[0]):
				adj[pair[0]] = {}
			adj[pair[0]][pair[1]] = li
	return {"adj": adj, "links": links}


## « Ou » probabiliste entre origines indépendantes. Deux attestations de la
## même note ou de la même personne (par::) forment une seule origine, qui vaut
## sa meilleure attestation ; un indice ne fait qu'un avec les notes de ses
## éléments « pour ».
static func _noisy_or(list: Array) -> float:
	var parent := {}
	var find := func(k: String) -> String:
		var r := k
		while parent.get(r, r) != r:
			r = parent[r]
		return r
	var groups_of := []
	for x in list:
		var keys := [str(x.origin)]
		if str(x.par) != "":
			keys.append("par:" + str(x.par))
		for j in x.get("joins", []):
			keys.append(str(j))
		groups_of.append(keys)
		for k in keys:
			if not parent.has(k):
				parent[k] = k
		var r0: String = find.call(keys[0])
		for k in keys.slice(1):
			var rk: String = find.call(k)
			if rk != r0:
				parent[rk] = r0
	var best := {}
	for i in list.size():
		var g: String = find.call(groups_of[i][0])
		best[g] = maxf(float(best.get(g, 0.0)), float(list[i].p))
	var q := 1.0
	for g in best:
		q *= 1.0 - float(best[g])
	return minf(1.0 - q, P_MAX)


## Les fiches qui ne peuvent pas servir d'étape (clans, sectes, domaines…).
static func hubs(index: RefCounted) -> Dictionary:
	var out := {}
	for r in index.rows("SELECT f.name_key, f.type, (SELECT value FROM props WHERE fid = f.fid AND key = 'nature' LIMIT 1) AS nature FROM files f WHERE f.type IN ('domaine', 'concept', 'groupe')"):
		if str(r.type) in HUB_TYPES or str(r.nature if r.nature != null else "") in HUB_NATURES:
			out[str(r.name_key)] = true
	return out


## Les k chemins les plus probables de `from` à `to` (noms de fiches).
## opts : ceux d'attestations(), plus k (5), max_etapes (8), garder_hubs (bool).
## Renvoie {ok, error, from, to, paths: [{p, nodes: [clés], links: [index]}], links, names}.
static func find(index: RefCounted, from: String, to: String, opts: Dictionary) -> Dictionary:
	var a := TextNorm.name_key(Schema.link_name(from))
	var b := TextNorm.name_key(Schema.link_name(to))
	var res := {"ok": false, "error": "", "from": a, "to": b, "paths": [], "links": [], "names": {}}
	if a == "" or b == "":
		res.error = "choisissez les deux fiches"
		return res
	if a == b:
		res.error = "les deux fiches sont identiques"
		return res
	var g := combine(attestations(index, opts))
	res.links = g.links
	var blocked := {}
	if not opts.get("structure", false):
		blocked = hubs(index)
		blocked.erase(a)
		blocked.erase(b)
	var k := int(opts.get("k", 5))
	var max_hops := int(opts.get("max_etapes", 8))
	res.paths = yen(g, a, b, k, blocked, max_hops)
	var names: Dictionary = index.all_names()
	var shown := {}
	for x in g.links:
		for at in x.att:
			shown[str(at.a)] = str(at.de)
			shown[str(at.b)] = str(at.vers)
	for p in res.paths:
		for n in p.nodes:
			var inf: Dictionary = names.get(n, {})
			res.names[n] = {"name": str(inf.get("name", shown.get(n, n))), "type": str(inf.get("type", "")),
				"path": str(inf.get("path", "")), "missing": inf.is_empty()}
	for n in [a, b]:
		if not res.names.has(n):
			var inf: Dictionary = names.get(n, {})
			res.names[n] = {"name": str(inf.get("name", Schema.link_name(from) if n == a else Schema.link_name(to))),
				"type": str(inf.get("type", "")), "path": str(inf.get("path", "")), "missing": inf.is_empty()}
	res.ok = true
	if res.paths.is_empty():
		res.error = "aucun chemin avec ces filtres" if g.adj.has(a) and g.adj.has(b) else \
			"%s n'a aucun lien connu avec ces filtres" % (res.names[a].name if not g.adj.has(a) else res.names[b].name)
	return res


## Plus court chemin (coût −ln p) en évitant des sommets et des liens.
static func dijkstra(g: Dictionary, src: String, dst: String, banned_nodes: Dictionary, banned_links: Dictionary, blocked: Dictionary, max_hops: int) -> Dictionary:
	var dist := {src: 0.0}
	var hops := {src: 0}
	var prev := {}
	var heap := [[0.0, src]]
	var done := {}
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var u: String = top[1]
		if done.has(u):
			continue
		done[u] = true
		if u == dst:
			break
		if u != src and blocked.has(u):
			continue  # un « hub » ne sert pas d'étape
		if int(hops[u]) >= max_hops:
			continue
		for v in g.adj.get(u, {}):
			if banned_nodes.has(v) or done.has(v):
				continue
			var li: int = g.adj[u][v]
			if banned_links.has(li):
				continue
			var p: float = g.links[li].p
			if p <= 0.0:
				continue
			var nd: float = float(dist[u]) - log(p)
			if not dist.has(v) or nd < float(dist[v]) - 1e-12:
				dist[v] = nd
				hops[v] = int(hops[u]) + 1
				prev[v] = [u, li]
				_push(heap, [nd, v])
	if not dist.has(dst) or not done.has(dst):
		return {}
	var nodes := [dst]
	var lks := []
	var cur := dst
	while cur != src:
		var pv: Array = prev[cur]
		lks.push_front(pv[1])
		cur = pv[0]
		nodes.push_front(cur)
	return {"cost": float(dist[dst]), "nodes": nodes, "links": lks}


## Yen : les k chemins sans boucle les moins coûteux.
static func yen(g: Dictionary, src: String, dst: String, k: int, blocked: Dictionary, max_hops: int) -> Array:
	var first := dijkstra(g, src, dst, {}, {}, blocked, max_hops)
	if first.is_empty():
		return []
	var found := [first]
	var cands := []
	var seen := {_sig(first): true}
	while found.size() < k:
		var last: Dictionary = found[found.size() - 1]
		for i in last.nodes.size() - 1:
			var spur: String = last.nodes[i]
			var root_nodes: Array = last.nodes.slice(0, i + 1)
			var root_links: Array = last.links.slice(0, i)
			var banned_links := {}
			for pth in found:
				if pth.nodes.size() > i and pth.nodes.slice(0, i + 1) == root_nodes:
					banned_links[pth.links[i]] = true
			var banned_nodes := {}
			for n in root_nodes.slice(0, i):
				banned_nodes[n] = true
			var sp := dijkstra(g, spur, dst, banned_nodes, banned_links, blocked, max_hops - i)
			if sp.is_empty():
				continue
			var cost := 0.0
			for li in root_links:
				cost -= log(float(g.links[li].p))
			var total := {"cost": cost + float(sp.cost), "nodes": root_nodes.slice(0, i) + sp.nodes,
				"links": root_links + sp.links}
			var sg := _sig(total)
			if not seen.has(sg):
				seen[sg] = true
				cands.append(total)
		if cands.is_empty():
			break
		cands.sort_custom(func(x, y): return x.cost < y.cost)
		found.append(cands.pop_front())
	var out := []
	for pth in found:
		out.append({"p": exp(-float(pth.cost)), "nodes": pth.nodes, "links": pth.links})
	return out


static func _sig(p: Dictionary) -> String:
	return "|".join(PackedStringArray(p.nodes))


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if float(heap[parent][0]) <= float(item[0]):
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = item


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var l := 2 * i + 1
		if l >= n:
			break
		var c := l
		if l + 1 < n and float(heap[l + 1][0]) < float(heap[l][0]):
			c = l + 1
		if float(heap[c][0]) >= float(last[0]):
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top


## Données pour la vue du graphe : les fiches et les liens des chemins trouvés.
## Le meilleur chemin est marqué (rank 0) pour être dessiné plus épais.
static func to_graph(res: Dictionary) -> Dictionary:
	var nodes := {}
	var edges := []
	var rank_of := {}
	for pi in res.paths.size():
		for li in res.paths[pi].links:
			if not rank_of.has(li):
				rank_of[li] = pi
	for n in res.names:
		var on_path := false
		for p in res.paths:
			if p.nodes.has(n):
				on_path = true
		if on_path or n == res.from or n == res.to:
			var x: Dictionary = res.names[n].duplicate()
			x["ring"] = 1
			nodes[n] = x
	for li in rank_of:
		var l: Dictionary = res.links[li]
		var best: Dictionary = l.att[0]
		edges.append({"a": best.a, "b": best.b, "kind": best.kind, "code": best.code, "label": best.label,
			"directed": best.kind != "copresence", "cred": best.cred, "weight": 1, "path": best.path,
			"source": best.note, "active": true, "text": best.text, "rank": rank_of[li],
			"plabel": "%d %%" % roundi(float(l.p) * 100.0)})
	# disposition en couloirs : le départ à gauche, l'arrivée à droite, le meilleur
	# chemin au milieu, les suivants au-dessus et en dessous
	var fixed := {}
	var longest := 1
	for p in res.paths:
		longest = maxi(longest, p.nodes.size() - 1)
	var width := float(longest) * 140.0
	var lane := 0
	for pi in res.paths.size():
		var p: Dictionary = res.paths[pi]
		var fresh := false
		for i in p.nodes.size():
			if not fixed.has(p.nodes[i]):
				fresh = true
		if not fresh:
			continue
		var y := 0.0
		if pi > 0:
			lane += 1
			y = float((lane + 1) / 2) * 120.0 * (1.0 if lane % 2 == 1 else -1.0)
		var n: int = p.nodes.size() - 1
		for i in p.nodes.size():
			var k: String = p.nodes[i]
			if fixed.has(k):
				continue
			fixed[k] = Vector2(width * float(i) / float(maxi(n, 1)) - width / 2.0, y)
	if not fixed.has(res.from):
		fixed[res.from] = Vector2(-width / 2.0, 0)
	if not fixed.has(res.to):
		fixed[res.to] = Vector2(width / 2.0, 0)
	return {"nodes": nodes, "edges": edges, "center": "", "ends": [res.from, res.to], "fixed_pos": fixed}


## Texte d'une attestation : « X est allié de Y — note, B/2 (76 %) ».
static func describe(at: Dictionary) -> String:
	var who := "%s %s %s" % [at.de, at.label, at.vers]
	if at.kind == "indice":
		who += " (indice %s)" % str(at.get("statut", ""))
	if at.kind == "copresence":
		who = "%s et %s vus ensemble" % [at.de, at.vers]
	var grade := ""
	if str(at.fiab) != "":
		grade = "%s/%s" % [at.fiab, str(at.cred)]
	elif at.kind in ["indice", "faveur"]:
		grade = "crédibilité %s" % str(at.cred)
	var where := str(at.note)
	if str(at.date) != "":
		where += ", " + Dates.label(at.date)
	return "%s — %s%s (%d %%)" % [who, where, (", " + grade) if grade != "" else "", roundi(float(at.p) * 100.0)]
