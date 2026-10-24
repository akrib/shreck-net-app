extends RefCounted
## Filiations et lignées, calculées depuis l'index (FORMAT §16) ; rien n'est écrit.
##  - liens sire → infant : la propriété `sire` d'une fiche, les éléments
##    « est le sire de » (`sire_de` : de = sire, vers = infant ; crédibilité 5
##    écartée) et les indices de même relation (sauf réfutés ou obsolètes) ;
##  - familles (lignages) : les personnes reliées par ces liens, génération par
##    génération ; un infant qui a deux sires est signalé ;
##  - clans et lignées : les lignées rattachées à leur clan (`clan` de la lignée),
##    avec le nombre de membres connus.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Members := preload("res://core/analysis/members.gd")


static func _cred(v: Variant) -> int:
	var s := str(v if v != null else "")
	return int(s) if s.is_valid_int() else 6


## Un lien par couple sire → infant : [{sire, infant, sk, ik, sources: [{origin
## ("fiche", "element", "indice"), label, path, cred}], cred (la meilleure), sure}].
static func sire_links(index: RefCounted) -> Array:
	var by := {}
	var order := []
	var add := func(sire: String, infant: String, origin: String, label: String, path: String, cred: int) -> void:
		if sire == "" or infant == "":
			return
		var sk := TextNorm.name_key(sire)
		var ik := TextNorm.name_key(infant)
		if sk == ik:
			return
		var k := sk + ">" + ik
		if not by.has(k):
			by[k] = {"sire": sire, "infant": infant, "sk": sk, "ik": ik, "sources": []}
			order.append(k)
		by[k].sources.append({"origin": origin, "label": label, "path": path, "cred": cred})
	for p in index.notes_with_props("personnage", ["sire"]):
		var s: Variant = p.props.get("sire", "")
		for x in (s if typeof(s) == TYPE_ARRAY else [s]):
			add.call(Schema.link_name(x), str(p.name), "fiche", "fiche de " + str(p.name), str(p.path), 1)
	for r in index.relations_by_code("sire_de"):
		var c := _cred(r.cred)
		if c == 5:
			continue
		var f: Variant = JSON.parse_string(str(r.fields))
		if typeof(f) != TYPE_DICTIONARY:
			continue
		add.call(Schema.link_name(f.get("de", "")), Schema.link_name(f.get("vers", "")), "element", str(r.note), str(r.path), c)
	for n in index.notes_with_props("indice", ["relation", "de", "vers", "statut", "credibilite"]):
		var pr: Dictionary = n.props
		if str(pr.get("relation", "")) != "sire_de" or str(pr.get("statut", "")) in ["refute", "obsolete"]:
			continue
		add.call(Schema.link_name(pr.get("de", "")), Schema.link_name(pr.get("vers", "")), "indice", "indice « %s »" % n.name, str(n.path), _cred(pr.get("credibilite")))
	var out := []
	for k in order:
		var l: Dictionary = by[k]
		var best := 6
		for s in l.sources:
			best = mini(best, int(s.cred))
		l["cred"] = best
		l["sure"] = best <= 3
		out.append(l)
	return out


## Familles reliées par les liens sire → infant, les plus grandes d'abord :
## [{label, root, size, depth, nodes: {clé: {name, path, clan, statut, rang, level,
## sires: [clés], infants: [clés]}}, links, parent: {clé infant: clé du sire retenu
## pour la disposition}, conflicts: {clé infant: true}, roots: [clés]}].
static func families(index: RefCounted, links: Variant = null) -> Array:
	var ls: Array = links if links != null else sire_links(index)
	var adj := {}
	var names := {}
	for l in ls:
		names[l.sk] = l.sire
		names[l.ik] = l.infant
		for pair in [[l.sk, l.ik], [l.ik, l.sk]]:
			if not adj.has(pair[0]):
				adj[pair[0]] = []
			adj[pair[0]].append(pair[1])
	# fiches : chemin, clan, statut, âge
	var info := {}
	for p in index.notes_with_props("personnage", ["clan", "statut", "rang"]):
		var k := TextNorm.name_key(str(p.name))
		if adj.has(k):
			info[k] = {"name": str(p.name), "path": str(p.path), "clan": Schema.link_name(p.props.get("clan", "")),
				"statut": str(p.props.get("statut", "") if p.props.get("statut") != null else ""),
				"rang": str(p.props.get("rang", "") if p.props.get("rang") != null else "")}
	var seen := {}
	var out := []
	for start in adj:
		if seen.has(start):
			continue
		var comp := [start]
		seen[start] = true
		var i := 0
		while i < comp.size():
			for nb in adj[comp[i]]:
				if not seen.has(nb):
					seen[nb] = true
					comp.append(nb)
			i += 1
		out.append(_family(comp, ls, names, info))
	out.sort_custom(func(a, b): return a.size > b.size if a.size != b.size else TextNorm.fold(a.label) < TextNorm.fold(b.label))
	return out


static func _family(comp: Array, ls: Array, names: Dictionary, info: Dictionary) -> Dictionary:
	var inside := {}
	for k in comp:
		inside[k] = true
	var nodes := {}
	for k in comp:
		var base: Dictionary = info.get(k, {"name": str(names.get(k, k)), "path": "", "clan": "", "statut": "", "rang": ""})
		var n := base.duplicate()
		n["sires"] = []
		n["infants"] = []
		n["level"] = 0
		nodes[k] = n
	var links := []
	var best_sire := {}   # infant -> [cred, sire]
	for l in ls:
		if not inside.has(l.sk):
			continue
		links.append(l)
		nodes[l.sk].infants.append(l.ik)
		nodes[l.ik].sires.append(l.sk)
		var cur: Array = best_sire.get(l.ik, [99, ""])
		if int(l.cred) < int(cur[0]):
			best_sire[l.ik] = [int(l.cred), l.sk]
	var conflicts := {}
	var parent := {}
	for k in nodes:
		if (nodes[k].sires as Array).size() > 1:
			conflicts[k] = true
		if best_sire.has(k):
			parent[k] = best_sire[k][1]
	# générations : la plus longue lignée de sires au-dessus (bornée : une boucle dans les notes ne bloque rien)
	for _pass in comp.size():
		var changed := false
		for l in links:
			var lv: int = int(nodes[l.sk].level) + 1
			if lv > int(nodes[l.ik].level) and lv <= comp.size():
				nodes[l.ik].level = lv
				changed = true
		if not changed:
			break
	var roots := []
	for k in comp:
		if (nodes[k].sires as Array).is_empty():
			roots.append(k)
	if roots.is_empty():   # boucle sire → infant → … : on part du premier
		roots.append(comp[0])
		parent.erase(comp[0])
	# le plus ancien : la racine qui a le plus de descendants
	var best_root: String = roots[0]
	var best_n := -1
	for r in roots:
		var n := _descendants(r, nodes).size()
		if n > best_n:
			best_n = n
			best_root = r
	var depth := 0
	for k in nodes:
		depth = maxi(depth, int(nodes[k].level))
	return {"label": "Lignage de " + str(nodes[best_root].name), "root": best_root, "size": comp.size(), "depth": depth + 1,
		"nodes": nodes, "links": links, "parent": parent, "conflicts": conflicts, "roots": roots}


static func _descendants(k: String, nodes: Dictionary) -> Dictionary:
	var out := {}
	var todo := [k]
	while not todo.is_empty():
		var x: String = todo.pop_back()
		for c in nodes[x].infants:
			if not out.has(c):
				out[c] = true
				todo.append(c)
	return out


## Indice de la famille qui contient `name` (-1 si aucune).
static func family_index(fams: Array, name: String) -> int:
	var k := TextNorm.name_key(name)
	for i in fams.size():
		if (fams[i].nodes as Dictionary).has(k):
			return i
	return -1


## Clans et lignées : [{name, path, members, lignees: [{name, path, members}]}], les
## clans par ordre alphabétique ; les lignées sans clan connu sous « Clan inconnu » (path "").
static func clans_tree(index: RefCounted) -> Array:
	var count := {}
	for p in index.notes_with_props("personnage", ["clan"]):
		var c := TextNorm.name_key(Schema.link_name(p.props.get("clan", "")))
		if c != "":
			count[c] = int(count.get(c, 0)) + 1
	var clans := {}
	var orphans := []
	var lignees := []
	for g in index.notes_with_props("groupe", ["nature", "clan"]):
		var nat := str(g.props.get("nature", ""))
		if nat == "clan":
			clans[TextNorm.name_key(str(g.name))] = {"name": str(g.name), "path": str(g.path),
				"members": int(count.get(TextNorm.name_key(str(g.name)), 0)), "lignees": []}
		elif nat == "lignee":
			lignees.append(g)
	for g in lignees:
		var row := {"name": str(g.name), "path": str(g.path), "members": Members.of_group(index, str(g.name)).size()}
		var ck := TextNorm.name_key(Schema.link_name(g.props.get("clan", "")))
		if clans.has(ck):
			clans[ck].lignees.append(row)
		else:
			orphans.append(row)
	var out: Array = clans.values()
	out.sort_custom(func(a, b): return TextNorm.fold(a.name) < TextNorm.fold(b.name))
	for c in out:
		(c.lignees as Array).sort_custom(func(a, b): return TextNorm.fold(a.name) < TextNorm.fold(b.name))
	if not orphans.is_empty():
		orphans.sort_custom(func(a, b): return TextNorm.fold(a.name) < TextNorm.fold(b.name))
		out.append({"name": "Clan inconnu", "path": "", "members": 0, "lignees": orphans})
	return out
