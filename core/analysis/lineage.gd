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


# ------------------------------------------------------------------ lignées

## Relations qui disent l'appartenance à une lignée : « est de la lignée de » (1.6),
## et « est membre de » quand la cible est une lignée.
const LIG_CODES := ["lignee_de", "membre_de"]
const LIG_PREFIX := "lig:"


## Les lignées : {clé « lig:… »: {name, path, clan, chef, chef_key}} — groupes de
## nature lignée (avec leur chef de lignée, format 1.7), et cibles de « est de la
## lignée de » sans fiche.
static func lignees(index: RefCounted) -> Dictionary:
	var out := {}
	for g in index.notes_with_props("groupe", ["nature", "clan", "chef"]):
		if str(g.props.get("nature", "")) == "lignee":
			var chef := Schema.link_name(g.props.get("chef", ""))
			out[LIG_PREFIX + TextNorm.name_key(str(g.name))] = {"name": str(g.name), "path": str(g.path), "clan": Schema.link_name(g.props.get("clan", "")),
				"chef": chef, "chef_key": TextNorm.name_key(chef) if chef != "" else ""}
	for r in index.relations_by_code("lignee_de"):
		var f: Variant = JSON.parse_string(str(r.fields))
		if typeof(f) == TYPE_DICTIONARY:
			var v := Schema.link_name(f.get("vers", ""))
			var k := LIG_PREFIX + TextNorm.name_key(v)
			if v != "" and not out.has(k) and index.path_of_name(v) == "":
				out[k] = {"name": v, "path": "", "clan": "", "chef": "", "chef_key": ""}
	return out


## Chef proposé d'après le nom d'une lignée : « Lignée de Karios » → Karios,
## « de la Dame Noire » → La Dame Noire, « du Chroniqueur » → Le Chroniqueur,
## « de l'Apothicaire » → L'Apothicaire ou Apothicaire. On cherche les fiches de
## personnage de ce nom (aux accents près), de cet alias, ou de ce nom précisé
## (« Stanislas (Paris) ») ; avec `clan`, seulement celles de ce clan ou sans clan.
## Renvoie les noms trouvés : une seule fiche, c'est une proposition sûre.
static func chef_candidates(index: RefCounted, lignee_name: String, clan := "") -> Array:
	var f := TextNorm.fold(lignee_name.strip_edges())
	var base := ""
	var names := []
	for pre in [["lignee de la ", "La "], ["lignee de l'", "L'"], ["lignee du ", "Le "], ["lignee des ", "Les "], ["lignee de ", ""], ["lignee d'", ""]]:
		if f.begins_with(str(pre[0])):
			base = lignee_name.strip_edges().substr(str(pre[0]).length()).strip_edges()
			names.append(str(pre[1]) + base)
			if str(pre[1]) == "L'":
				names.append(base)
			break
	if base == "":
		return []
	var out := []
	for nm in names:
		var nf := TextNorm.fold(str(nm))
		var hits: Array = index.rows("SELECT name, path FROM files WHERE type = 'personnage' AND (name_fold = ? OR name_fold LIKE ?)", [nf, nf + " (%"])
		hits.append_array(index.rows("SELECT f.name AS name, f.path AS path FROM aliases a JOIN files f ON f.fid = a.fid WHERE f.type = 'personnage' AND a.alias_fold = ?", [nf]))
		for h in hits:
			if out.has(str(h.name)):
				continue
			if clan != "":
				var c := Schema.link_name(index.props_of(str(h.path)).get("clan", ""))
				if c != "" and TextNorm.name_key(c) != TextNorm.name_key(clan):
					continue
			out.append(str(h.name))
	return out


## « Chef de la lignée de Karios » (plusieurs : « … et de la lignée de … »).
static func chef_mention(lignee_names: Array) -> String:
	var parts := PackedStringArray()
	for n in lignee_names:
		var s := str(n)
		var f := TextNorm.fold(s)
		parts.append(("l" + s.substr(1)) if f.begins_with("lignee ") or f.begins_with("lignee d'") else "lignée " + s)
	return "Chef de la " + " et de la ".join(parts)


## Ce que disent les notes : {decl: {clé personne: {clé lignée: [sources]}},
## parents: {clé lignée: {clé lignée parente: [sources]}}, names: {clé personne: nom},
## chefs: {clé lignée: clé de son chef}}.
## Sources : éléments et indices « est de la lignée de » ou « est membre de » une
## lignée (crédibilité 5, indices réfutés ou obsolètes écartés) ; fiche dont le
## `clan` est une lignée (anciennes notes) ; chef de lignée (fiche de la lignée,
## origine « chef »).
static func lineage_claims(index: RefCounted, ligs: Dictionary) -> Dictionary:
	var decl := {}
	var parents := {}
	var names := {}
	var add := func(de: String, vers: String, origin: String, label: String, path: String, cred: int) -> void:
		var lk := LIG_PREFIX + TextNorm.name_key(vers)
		if de == "" or not ligs.has(lk):
			return
		var dk := LIG_PREFIX + TextNorm.name_key(de)
		var src := {"origin": origin, "label": label, "path": path, "cred": cred}
		if ligs.has(dk):
			if dk == lk:
				return
			if not parents.has(dk):
				parents[dk] = {}
			if not parents[dk].has(lk):
				parents[dk][lk] = []
			parents[dk][lk].append(src)
		else:
			var pk := TextNorm.name_key(de)
			names[pk] = de
			if not decl.has(pk):
				decl[pk] = {}
			if not decl[pk].has(lk):
				decl[pk][lk] = []
			decl[pk][lk].append(src)
	for code in LIG_CODES:
		for r in index.relations_by_code(code):
			var c := _cred(r.cred)
			if c == 5:
				continue
			var f: Variant = JSON.parse_string(str(r.fields))
			if typeof(f) == TYPE_DICTIONARY:
				add.call(Schema.link_name(f.get("de", "")), Schema.link_name(f.get("vers", "")), "element", str(r.note), str(r.path), c)
	for n in index.notes_with_props("indice", ["relation", "de", "vers", "statut", "credibilite"]):
		var pr: Dictionary = n.props
		if not str(pr.get("relation", "")) in LIG_CODES or str(pr.get("statut", "")) in ["refute", "obsolete"]:
			continue
		add.call(Schema.link_name(pr.get("de", "")), Schema.link_name(pr.get("vers", "")), "indice", "indice « %s »" % n.name, str(n.path), _cred(pr.get("credibilite")))
	for p in index.notes_with_props("personnage", ["clan"]):
		var c := Schema.link_name(p.props.get("clan", ""))
		if c != "" and ligs.has(LIG_PREFIX + TextNorm.name_key(c)):
			add.call(str(p.name), c, "fiche", "fiche de %s (clan)" % p.name, str(p.path), 1)
	# le chef de lignée en est (fiche de la lignée)
	var chefs := {}
	for lk in ligs:
		var chef := str(ligs[lk].get("chef", ""))
		if chef != "" and not ligs.has(LIG_PREFIX + TextNorm.name_key(chef)):
			chefs[lk] = TextNorm.name_key(chef)
			add.call(chef, str(ligs[lk].name), "chef", "chef de lignée, selon la fiche de %s" % ligs[lk].name, str(ligs[lk].path), 1)
	return {"decl": decl, "parents": parents, "names": names, "chefs": chefs}


## Lignées entre elles déduites du chef de lignée (rien n'est écrit) : une lignée
## descend des autres lignées déclarées de son chef, et de la lignée dont le sire
## de son chef est le chef. Jamais en boucle. `sires_of` : clé -> [clés des sires].
static func add_chef_parents(claims: Dictionary, sires_of: Callable, ligs: Dictionary) -> void:
	var chefs: Dictionary = claims.get("chefs", {})
	if chefs.is_empty():
		return
	var led := {}
	for lk in chefs:
		if not led.has(chefs[lk]):
			led[chefs[lk]] = []
		led[chefs[lk]].append(lk)
	var parents: Dictionary = claims.parents
	var names: Dictionary = claims.names
	var add := func(child: String, par: String, src: Dictionary) -> void:
		if child == par or ancestors_of(par, parents).has(child):
			return
		if not parents.has(child):
			parents[child] = {}
		if not (parents[child] as Dictionary).has(par):
			parents[child][par] = [src]
	for lk in chefs:
		var ck: String = chefs[lk]
		var chef_name := str(names.get(ck, ck))
		var path := str(ligs[lk].path) if ligs.has(lk) else ""
		for m in (claims.decl.get(ck, {}) as Dictionary):
			if m == lk:
				continue
			var best := 7
			for s in claims.decl[ck][m]:
				if str(s.origin) != "chef":
					best = mini(best, int(s.cred))
			if best == 7:
				continue  # chef de deux lignées : cela ne dit pas laquelle descend de l'autre
			add.call(lk, m, {"origin": "chef", "deduced": true, "path": path, "cred": maxi(best, 3),
				"label": "déduit : son chef, %s, est de %s" % [chef_name, ligs[m].name if ligs.has(m) else m]})
		for s in sires_of.call(ck):
			for p in led.get(s, []):
				add.call(lk, p, {"origin": "chef", "deduced": true, "path": path, "cred": 3,
					"label": "déduit : son chef, %s, est l'infant de %s, chef de %s" % [chef_name, names.get(s, s), ligs[p].name if ligs.has(p) else p]})


## Sires de chaque infant, d'après les liens : clé -> [clés].
static func sires_by_infant(links: Array) -> Dictionary:
	var sires := {}
	for l in links:
		if not sires.has(l.ik):
			sires[l.ik] = []
		sires[l.ik].append(l.sk)
	return sires


## Ce que disent les notes, avec les liens entre lignées déduits des chefs.
static func claims_with_chefs(index: RefCounted, ligs: Dictionary, links: Array) -> Dictionary:
	var claims := lineage_claims(index, ligs)
	var sires := sires_by_infant(links)
	add_chef_parents(claims, func(k: String) -> Array: return sires.get(k, []), ligs)
	return claims


## Lignées ancêtres d'une lignée (par « est de la lignée de » entre lignées), sans elle.
static func ancestors_of(lk: String, parents: Dictionary) -> Dictionary:
	var out := {}
	var todo: Array = (parents.get(lk, {}) as Dictionary).keys()
	while not todo.is_empty():
		var x: String = todo.pop_back()
		if out.has(x) or x == lk:
			continue
		out[x] = true
		todo.append_array((parents.get(x, {}) as Dictionary).keys())
	return out


## Lignées de chaque personne, déclarées ou déduites : une lignée passe du
## infant à son sire, de sire en sire, sauf vers un sire déclaré d'une lignée plus
## ancienne (le sire du fondateur), et jamais au-dessus du chef de la lignée.
## {clé: {clé lignée: {declared, sources, via: [clés]}}}.
static func memberships(links: Array, claims: Dictionary) -> Dictionary:
	var sires := sires_by_infant(links)
	var chefs: Dictionary = claims.get("chefs", {})
	var parents: Dictionary = claims.parents
	var out := {}
	for pk in claims.decl:
		out[pk] = {}
		for lk in claims.decl[pk]:
			out[pk][lk] = {"declared": true, "sources": claims.decl[pk][lk], "via": []}
	for pk in claims.decl:
		for lk in claims.decl[pk]:
			var anc := ancestors_of(lk, parents)
			var head := str(chefs.get(lk, ""))
			var seen := {pk: true}
			var todo := [pk]
			while not todo.is_empty():
				var c: String = todo.pop_back()
				if c == head:
					continue  # le chef est en tête de sa lignée : on ne remonte pas au-dessus
				for s in sires.get(c, []):
					if seen.has(s):
						continue
					seen[s] = true
					# le sire déclaré d'une lignée plus ancienne : c'est au-dessus de cette lignée
					var above := false
					for m in (claims.decl.get(s, {}) as Dictionary):
						if anc.has(m):
							above = true
					if above:
						continue
					if not out.has(s):
						out[s] = {}
					if not out[s].has(lk):
						out[s][lk] = {"declared": false, "sources": [], "via": []}
					if not (out[s][lk].via as Array).has(c):
						out[s][lk].via.append(c)
					todo.append(s)
	return out


## Lignées d'une personne qui ne s'accordent pas : deux lignées dont aucune ne
## descend de l'autre. Renvoie les clés de lignée en cause (vide = cohérent).
static func incoherent(lset: Dictionary, parents: Dictionary) -> Array:
	var keys := lset.keys()
	var bad := {}
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: String = keys[i]
			var b: String = keys[j]
			if not ancestors_of(a, parents).has(b) and not ancestors_of(b, parents).has(a):
				bad[a] = true
				bad[b] = true
	return bad.keys()


## Les plus précises des lignées d'une personne (celles dont aucune autre ne descend).
static func most_specific(lset: Dictionary, parents: Dictionary) -> Array:
	var out := []
	for a in lset:
		var general := false
		for b in lset:
			if a != b and ancestors_of(b, parents).has(a):
				general = true
		if not general:
			out.append(a)
	out.sort()
	return out


## Lignées d'une seule personne, pour sa fiche, sans tout recalculer : sa
## descendance connue suffit (une lignée remonte de l'infant au sire).
## {lignees: {clé: {name, path, declared, sources, via: [noms]}}, bad: [clés], specific: [clés],
## heads: [{key, name, path}] (lignées dont elle est le chef)}.
static func person_lignees(index: RefCounted, name: String) -> Dictionary:
	var ligs := lignees(index)
	var pk := TextNorm.name_key(name)
	var names := {pk: name}
	var links := []
	var todo := [name]
	var seen := {pk: true}
	while not todo.is_empty():
		var x: String = todo.pop_back()
		var xk := TextNorm.name_key(x)
		var infants := []
		for r in index.relations_of(x):
			if str(r.relation) == "sire_de" and str(r.de_key) == xk and _cred(r.cred) != 5:
				var f: Variant = JSON.parse_string(str(r.fields))
				if typeof(f) == TYPE_DICTIONARY:
					infants.append(Schema.link_name(f.get("vers", "")))
		for r in index.linked_from(x, ["sire"]):
			if str(r.type) == "personnage":
				infants.append(str(r.name))
		for r in index.linked_from(x, ["de"]):
			if str(r.type) == "indice":
				var pr: Dictionary = index.props_of(str(r.path))
				if str(pr.get("relation", "")) == "sire_de" and not str(pr.get("statut", "")) in ["refute", "obsolete"]:
					infants.append(Schema.link_name(pr.get("vers", "")))
		for i in infants:
			var ik := TextNorm.name_key(i)
			if i == "" or ik == xk:
				continue
			links.append({"sk": xk, "ik": ik})
			if not seen.has(ik):
				seen[ik] = true
				names[ik] = i
				todo.append(i)
	# ce que disent les notes sur ces personnes, et la parenté des lignées en cause
	var decl := {}
	var parents := {}
	var lig_todo := []
	var add := func(de_k: String, vers: String, src: Dictionary, target: Dictionary) -> void:
		var lk := LIG_PREFIX + TextNorm.name_key(vers)
		if not ligs.has(lk):
			return
		if not target.has(de_k):
			target[de_k] = {}
		if not target[de_k].has(lk):
			target[de_k][lk] = []
			lig_todo.append(lk)
		target[de_k][lk].append(src)
	var claims_of := func(who: String, who_k: String, target: Dictionary) -> void:
		for r in index.relations_of(who):
			if str(r.relation) in LIG_CODES and str(r.de_key) == TextNorm.name_key(who) and _cred(r.cred) != 5:
				var f: Variant = JSON.parse_string(str(r.fields))
				if typeof(f) == TYPE_DICTIONARY:
					add.call(who_k, Schema.link_name(f.get("vers", "")), {"origin": "element", "label": str(r.note), "path": str(r.path), "cred": _cred(r.cred),
						"block": str(r.block if r.block != null else ""), "text": str(r.text)}, target)
		for r in index.linked_from(who, ["de"]):
			if str(r.type) != "indice":
				continue
			var pr: Dictionary = index.props_of(str(r.path))
			if str(pr.get("relation", "")) in LIG_CODES and not str(pr.get("statut", "")) in ["refute", "obsolete"]:
				add.call(who_k, Schema.link_name(pr.get("vers", "")), {"origin": "indice", "label": "indice « %s »" % r.name, "path": str(r.path), "cred": _cred(pr.get("credibilite"))}, target)
	for k in names:
		claims_of.call(names[k], k, decl)
		var pp: String = index.path_of_name(names[k])
		if pp != "":
			var c := Schema.link_name(index.props_of(pp).get("clan", ""))
			if c != "" and ligs.has(LIG_PREFIX + TextNorm.name_key(c)):
				add.call(k, c, {"origin": "fiche", "label": "fiche de %s (clan)" % names[k], "path": pp, "cred": 1}, decl)
	# chefs de lignée : celui qui dirige une lignée en est
	var chefs := {}
	for lk in ligs:
		if str(ligs[lk].get("chef_key", "")) != "" and not ligs.has(LIG_PREFIX + str(ligs[lk].chef_key)):
			chefs[lk] = str(ligs[lk].chef_key)
			if names.has(chefs[lk]):
				add.call(chefs[lk], str(ligs[lk].name), {"origin": "chef", "label": "chef de lignée, selon la fiche de %s" % ligs[lk].name,
					"path": str(ligs[lk].path), "cred": 1}, decl)
	# parenté des lignées en cause, y compris celle que leurs chefs font déduire
	var all_names := names.duplicate()
	var chef_seen := {}
	var sire_cache := {}
	var sires_of := func(k: String) -> Array:
		if not sire_cache.has(k):
			sire_cache[k] = _sires_in_index(index, str(all_names.get(k, k)))
		return sire_cache[k]
	var done := {}
	for _round in 20:
		while not lig_todo.is_empty():
			var lk: String = lig_todo.pop_back()
			if done.has(lk):
				continue
			done[lk] = true
			claims_of.call(str(ligs[lk].name), lk, parents)
		var more := false
		for lk in done.keys():
			var ck := str(chefs.get(lk, ""))
			if ck == "" or chef_seen.has(ck):
				continue
			chef_seen[ck] = true
			all_names[ck] = str(ligs[lk].chef)
			if not names.has(ck):
				claims_of.call(str(ligs[lk].chef), ck, decl)
			more = true
		add_chef_parents({"decl": decl, "parents": parents, "names": all_names, "chefs": chefs}, sires_of, ligs)
		for dk in parents:
			for p in parents[dk]:
				if not done.has(p) and not lig_todo.has(p):
					lig_todo.append(p)
					more = true
		if not more and lig_todo.is_empty():
			break
	var mem := memberships(links, {"decl": decl, "parents": parents, "names": names, "chefs": chefs})
	var mine: Dictionary = mem.get(pk, {})
	var out := {}
	for lk in mine:
		var via := []
		for v in mine[lk].via:
			via.append(str(names.get(v, v)))
		out[lk] = {"name": str(ligs[lk].name), "path": str(ligs[lk].path), "declared": mine[lk].declared, "sources": mine[lk].sources, "via": via}
	var led := []
	for lk in chefs:
		if chefs[lk] == pk:
			led.append({"key": lk, "name": str(ligs[lk].name), "path": str(ligs[lk].path)})
	return {"lignees": out, "bad": incoherent(mine, parents), "specific": most_specific(mine, parents), "heads": led}


## Sires d'une personne d'après l'index : propriété `sire`, éléments « est le sire
## de » (sauf crédibilité 5), indices de même relation (sauf réfutés ou obsolètes).
static func _sires_in_index(index: RefCounted, name: String) -> Array:
	var k := TextNorm.name_key(name)
	var out := []
	var p: String = index.path_of_name(name)
	if p != "":
		var s: Variant = index.props_of(p).get("sire", "")
		for x in (s if typeof(s) == TYPE_ARRAY else [s]):
			var sn := Schema.link_name(x)
			if sn != "":
				out.append(TextNorm.name_key(sn))
	for r in index.relations_of(name):
		if str(r.relation) == "sire_de" and str(r.vers_key) == k and _cred(r.cred) != 5 and not out.has(str(r.de_key)):
			out.append(str(r.de_key))
	for r in index.linked_from(name, ["vers"]):
		if str(r.type) != "indice":
			continue
		var pr: Dictionary = index.props_of(str(r.path))
		if str(pr.get("relation", "")) == "sire_de" and not str(pr.get("statut", "")) in ["refute", "obsolete"]:
			var sn := TextNorm.name_key(Schema.link_name(pr.get("de", "")))
			if sn != "" and not out.has(sn):
				out.append(sn)
	return out


# ------------------------------------------------------------------ lignages

## Lignages : personnes et lignées reliées par les liens sire → infant, les
## lignées et leurs membres, les lignées entre elles ; les plus grands d'abord.
## Une lignée qui a un chef est représentée par lui : sa case est celle du chef
## (`heads`), et ses liens partent de lui.
## [{label, root, size, depth, nodes: {clé: {kind ("personne"|"lignee"), name, path,
## clan, statut, rang, level, sires, infants, lignees: {clé: {declared, sources, via}},
## heads: [clés des lignées qu'il dirige]}}, edges: [{a, b, kind ("sire"|"lignee"|
## "hierarchie"), style, sources, cred, sure, inferred, bad}], links (sire → infant),
## parent: {clé: clé du parent retenu pour la disposition}, conflicts: {clé infant: true},
## incoherent: {clé: [clés de lignée]}, roots, lignees: {clé de lignée: {name, path,
## clan, chef, chef_key, node (sa case), parents: {clé: [sources]}, children: [clés]}}}].
## Style : "solid", "dashed" (incertain), "lig", "lig_dashed" (lignée déduite), "bad" (incohérent).
static func families(index: RefCounted, links: Variant = null) -> Array:
	var ls: Array = links if links != null else sire_links(index)
	var ligs := lignees(index)
	var claims := claims_with_chefs(index, ligs, ls)
	var mem := memberships(ls, claims)
	var parents: Dictionary = claims.parents
	var names: Dictionary = claims.names.duplicate()
	var edges := []
	for l in ls:
		names[l.sk] = l.sire
		names[l.ik] = l.infant
		edges.append({"a": l.sk, "b": l.ik, "kind": "sire", "style": "solid" if l.sure else "dashed", "sources": l.sources,
			"cred": l.cred, "sure": l.sure, "inferred": false, "bad": false, "link": l})
	var sires := {}
	for l in ls:
		if not sires.has(l.ik):
			sires[l.ik] = []
		sires[l.ik].append(l.sk)
	var incoh := {}
	for pk in mem:
		var bad := incoherent(mem[pk], parents)
		if not bad.is_empty():
			incoh[pk] = bad
		for lk in most_specific(mem[pk], parents):
			# la lignée arrive par un sire qui l'a déjà : pas de second trait
			var through_sire := false
			for s in sires.get(pk, []):
				var sset: Dictionary = mem.get(s, {})
				if sset.has(lk):
					through_sire = true
				for m in sset:
					if ancestors_of(m, parents).has(lk):
						through_sire = true
			if through_sire and not bad.has(lk):
				continue
			var m: Dictionary = mem[pk][lk]
			var best := 6
			for src in m.sources:
				best = mini(best, int(src.cred))
			var st := "bad" if bad.has(lk) else ("lig" if m.declared else "lig_dashed")
			edges.append({"a": lk, "b": pk, "kind": "lignee", "style": st, "sources": m.sources, "cred": best if m.declared else 6,
				"sure": m.declared, "inferred": not m.declared, "bad": bad.has(lk), "via": m.via})
	for dk in parents:
		for lk in parents[dk]:
			var best := 6
			var deduced := true
			for src in parents[dk][lk]:
				best = mini(best, int(src.cred))
				if not src.get("deduced", false):
					deduced = false
			edges.append({"a": lk, "b": dk, "kind": "hierarchie", "style": "lig" if best <= 3 and not deduced else "lig_dashed", "sources": parents[dk][lk],
				"cred": best, "sure": best <= 3 and not deduced, "inferred": deduced, "bad": false})
	# un chef de lignée représente sa lignée : les liens de la lignée partent de lui
	var chefs: Dictionary = claims.get("chefs", {})
	if not chefs.is_empty():
		edges = _merge_chefs(edges, chefs)
		for lk in chefs:
			if not names.has(chefs[lk]):
				names[chefs[lk]] = str(ligs[lk].chef)
	# composantes
	var adj := {}
	for e in edges:
		for pair in [[e.a, e.b], [e.b, e.a]]:
			if not adj.has(pair[0]):
				adj[pair[0]] = []
			adj[pair[0]].append(pair[1])
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
		out.append(_family(comp, edges, ls, names, info, ligs, mem, incoh, chefs, parents))
	out.sort_custom(func(a, b): return a.size > b.size if a.size != b.size else TextNorm.fold(a.label) < TextNorm.fold(b.label))
	return out


## Liens vus sur les chefs : une lignée qui a un chef est remplacée par lui. Plus de
## lien d'un chef vers lui-même ; pas de second trait quand le lien sire → infant
## dit déjà la même chose (sauf incohérence, qui reste visible).
static func _merge_chefs(edges: Array, chefs: Dictionary) -> Array:
	var sire_pair := {}
	for e in edges:
		if e.kind == "sire":
			sire_pair["%s>%s" % [e.a, e.b]] = true
	var out := []
	var at := {}
	for e in edges:
		if e.kind == "sire":
			out.append(e)
			continue
		var a := str(chefs.get(e.a, e.a))
		var b := str(chefs.get(e.b, e.b))
		if a == b or (not e.bad and sire_pair.has("%s>%s" % [a, b])):
			continue
		var e2: Dictionary = e
		if a != e.a or b != e.b:
			e2 = e.duplicate()
			e2.a = a
			e2.b = b
			e2["lig_a"] = e.a
			e2["lig_b"] = e.b
		var pk := "%s>%s" % [a, b]
		if at.has(pk):
			if e2.bad and not out[at[pk]].bad:
				out[at[pk]] = e2
			continue
		at[pk] = out.size()
		out.append(e2)
	return out


static func _family(comp: Array, all_edges: Array, ls: Array, names: Dictionary, info: Dictionary, ligs: Dictionary,
		mem: Dictionary, incoh: Dictionary, chefs := {}, parents := {}) -> Dictionary:
	var inside := {}
	for k in comp:
		inside[k] = true
	var heads := {}
	for lk in chefs:
		if inside.has(chefs[lk]):
			if not heads.has(chefs[lk]):
				heads[chefs[lk]] = []
			heads[chefs[lk]].append(lk)
	var nodes := {}
	for k in comp:
		var n: Dictionary
		if ligs.has(k):
			n = {"kind": "lignee", "name": str(ligs[k].name), "path": str(ligs[k].path), "clan": str(ligs[k].clan), "statut": "", "rang": ""}
		else:
			n = (info.get(k, {"name": str(names.get(k, k)), "path": "", "clan": "", "statut": "", "rang": ""}) as Dictionary).duplicate()
			n["kind"] = "personne"
		n["sires"] = []
		n["infants"] = []
		n["level"] = 0
		n["lignees"] = mem.get(k, {})
		n["heads"] = heads.get(k, [])
		nodes[k] = n
	# les lignées en cause dans ce lignage : leur nom, leur case, leur parenté
	var lig_info := {}
	var want := {}
	for k in nodes:
		if ligs.has(k):
			want[k] = true
		for lk in nodes[k].lignees:
			want[lk] = true
		for lk in nodes[k].heads:
			want[lk] = true
	for lk in want:
		if not ligs.has(lk):
			continue
		var node: String = lk if nodes.has(lk) else str(chefs.get(lk, ""))
		lig_info[lk] = {"name": str(ligs[lk].name), "path": str(ligs[lk].path), "clan": str(ligs[lk].clan),
			"chef": str(ligs[lk].get("chef", "")), "chef_key": str(chefs.get(lk, "")), "node": node if nodes.has(node) else "",
			"parents": parents.get(lk, {}), "children": []}
	for lk in lig_info:
		for p in lig_info[lk].parents:
			if lig_info.has(p):
				lig_info[p].children.append(lk)
	var edges := []
	var links := []
	for e in all_edges:
		if inside.has(e.a):
			edges.append(e)
			if e.kind == "sire":
				links.append(e.link)
				nodes[e.a].infants.append(e.b)
				nodes[e.b].sires.append(e.a)
	var conflicts := {}
	for k in nodes:
		if (nodes[k].sires as Array).size() > 1:
			conflicts[k] = true
	# parent retenu pour la disposition : le meilleur sire, sinon la lignée, sinon la lignée parente
	var parent := {}
	var best := {}
	for e in edges:
		var rank: int = int(e.cred) + (0 if e.kind == "sire" else 10)
		if e.kind == "lignee" and e.bad:
			rank += 10
		if not best.has(e.b) or rank < int(best[e.b][0]):
			best[e.b] = [rank, e.a]
	for k in best:
		parent[k] = best[k][1]
	# générations (bornées : une boucle dans les notes ne bloque rien)
	for _pass in comp.size():
		var changed := false
		for e in edges:
			var lv: int = int(nodes[e.a].level) + 1
			if lv > int(nodes[e.b].level) and lv <= comp.size():
				nodes[e.b].level = lv
				changed = true
		if not changed:
			break
	var has_parent := {}
	for e in edges:
		has_parent[e.b] = true
	var roots := []
	for k in comp:
		if not has_parent.has(k):
			roots.append(k)
	if roots.is_empty():
		roots.append(comp[0])
		parent.erase(comp[0])
	var best_root: String = roots[0]
	var best_n := -1
	for r in roots:
		var nd := _below(r, edges).size()
		if nd > best_n or (nd == best_n and nodes[r].kind == "lignee" and nodes[best_root].kind != "lignee"):
			best_n = nd
			best_root = r
	var depth := 0
	for k in nodes:
		depth = maxi(depth, int(nodes[k].level))
	var bad := {}
	for k in comp:
		if incoh.has(k):
			bad[k] = incoh[k]
	var label := ("Lignage de " + str(nodes[best_root].name)) if nodes[best_root].kind == "personne" else str(nodes[best_root].name)
	return {"label": label, "root": best_root, "size": comp.size(), "depth": depth + 1, "nodes": nodes, "edges": edges,
		"links": links, "parent": parent, "conflicts": conflicts, "incoherent": bad, "roots": roots, "lignees": lig_info}


## Nom d'une lignée dans un lignage (même quand sa case est celle de son chef).
static func lignee_name(fam: Dictionary, lk: String) -> String:
	if (fam.get("lignees", {}) as Dictionary).has(lk):
		return str(fam.lignees[lk].name)
	if (fam.nodes as Dictionary).has(lk):
		return str(fam.nodes[lk].name)
	return lk.trim_prefix(LIG_PREFIX)


## Case d'un nœud : la lignée qui a un chef renvoie à la case du chef.
static func node_key(fam: Dictionary, k: String) -> String:
	if (fam.nodes as Dictionary).has(k):
		return k
	var li: Dictionary = (fam.get("lignees", {}) as Dictionary).get(k, {})
	return str(li.get("node", ""))


static func _below(k: String, edges: Array) -> Dictionary:
	var down := {}
	for e in edges:
		if not down.has(e.a):
			down[e.a] = []
		down[e.a].append(e.b)
	var out := {}
	var todo := [k]
	while not todo.is_empty():
		var x: String = todo.pop_back()
		for c in down.get(x, []):
			if not out.has(c):
				out[c] = true
				todo.append(c)
	return out


## Autour d'un point de départ : ses ascendants (sires, lignées) et toute sa
## descendance (infants, membres, lignées issues). {clé: true}, le point compris.
static func around(fam: Dictionary, key: String) -> Dictionary:
	var up := {}
	var down := {}
	for e in fam.edges:
		if not down.has(e.a):
			down[e.a] = []
		down[e.a].append(e.b)
		if not up.has(e.b):
			up[e.b] = []
		up[e.b].append(e.a)
	var out := {key: true}
	for dir in [up, down]:
		var todo := [key]
		var seen := {key: true}
		while not todo.is_empty():
			var x: String = todo.pop_back()
			for y in dir.get(x, []):
				if not seen.has(y):
					seen[y] = true
					out[y] = true
					todo.append(y)
	return out


## Indice de la famille qui contient `name` (-1 si aucune).
static func family_index(fams: Array, name: String) -> int:
	var k := TextNorm.name_key(name)
	for i in fams.size():
		if (fams[i].nodes as Dictionary).has(k):
			return i
	for i in fams.size():
		if node_key(fams[i], LIG_PREFIX + k) != "":
			return i
	return -1


## Clans et lignées : [{name, path, members, lignees: [{name, path, members, chef}]}], les
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
	for g in index.notes_with_props("groupe", ["nature", "clan", "chef"]):
		var nat := str(g.props.get("nature", ""))
		if nat == "clan":
			clans[TextNorm.name_key(str(g.name))] = {"name": str(g.name), "path": str(g.path),
				"members": int(count.get(TextNorm.name_key(str(g.name)), 0)), "lignees": []}
		elif nat == "lignee":
			lignees.append(g)
	for g in lignees:
		var row := {"name": str(g.name), "path": str(g.path), "members": Members.of_group(index, str(g.name)).size(),
			"chef": Schema.link_name(g.props.get("chef", ""))}
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
