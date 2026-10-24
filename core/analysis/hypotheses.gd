extends RefCounted
## Tableau des hypothèses concurrentes d'un dossier (A-FAIRE §2, piste 2).
##
## Méthode des hypothèses concurrentes : on ne retient pas l'hypothèse qui a le
## plus de confirmations, mais celle qui est le moins contredite par les
## éléments ; un élément qui va dans le sens de toutes les hypothèses ne
## départage rien.
##
##  - Hypothèses : les indices du dossier (propriété `indices`). Un indice est une
##    affirmation à évaluer ; ses `pour` et `contre` sont les éléments cohérents
##    et incohérents avec elle.
##  - Éléments (lignes) : ceux que les hypothèses citent, et ceux que le dossier
##    cite dans son texte (`[[Note#^el-…]]`), même s'ils ne sont pas encore jugés.
##  - Case : "pour" (cohérent), "contre" (incohérent), "" (neutre ou pas jugé).
##  - Poids d'un élément : fiabilité de sa note × crédibilité (table de l'Amirauté).
##  - Classement : la somme des poids des éléments incohérents, la plus faible
##    d'abord ; à égalité, la plus soutenue.
## Rien n'est écrit ici ; AppService.set_hypothesis_cell écrit un jugement.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Paths := preload("res://core/analysis/paths.gd")


static func _list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v
	return [] if str(v) == "" else [v]


## « [[Note#^el-abc]] » -> ["Note", "el-abc"] ; ["", ""] si ce n'est pas un lien d'élément.
static func parse_ref(v: Variant) -> Array:
	var s := str(v).strip_edges()
	if s.begins_with("[[") and s.ends_with("]]"):
		s = s.substr(2, s.length() - 4)
	s = s.split("|")[0]
	var i := s.find("#")
	if i < 0:
		return ["", ""]
	var block := s.substr(i + 1).trim_prefix("^").strip_edges()
	if not block.begins_with("el-"):
		return ["", ""]
	return [s.substr(0, i).strip_edges(), block]


static func ref_of(note: String, block: String) -> String:
	return "[[%s#^%s]]" % [note, block]


static func build(index: RefCounted, dossier_rel: String, config := {}) -> Dictionary:
	var tab := Paths.table(config)
	var dp: Dictionary = index.props_of(dossier_rel)
	var out := {"dossier": dossier_rel.get_file().get_basename(), "path": dossier_rel,
		"question": str(dp.get("question", "")), "hypotheses": [], "rows": [], "ranking": []}
	var rows := {}
	var order := []
	var row_of := func(note: String, block: String) -> Dictionary:
		var k := TextNorm.name_key(note) + "#" + block
		if not rows.has(k):
			rows[k] = {"key": k, "note": note, "block": block, "ref": ref_of(note, block), "cells": {}, "examined": false}
			order.append(k)
		return rows[k]
	# hypothèses : les indices du dossier
	for link in _list(dp.get("indices")):
		var name := Schema.link_name(link)
		var path: String = index.path_of_name(name)
		var hp: Dictionary = index.props_of(path) if path != "" else {}
		var h := {"name": name, "path": path, "missing": path == "", "statut": str(hp.get("statut", "")),
			"credibilite": str(hp.get("credibilite", "")), "n_pour": 0, "n_contre": 0, "w_pour": 0.0, "w_contre": 0.0}
		var hi: int = out.hypotheses.size()
		out.hypotheses.append(h)
		for side in ["pour", "contre"]:
			for ref in _list(hp.get(side)):
				var nb := parse_ref(ref)
				if nb[0] == "":
					continue
				var r: Dictionary = row_of.call(nb[0], nb[1])
				# un élément à la fois pour et contre la même hypothèse : « contre » l'emporte
				if side == "contre" or not r.cells.has(hi):
					r.cells[hi] = side
	# éléments cités dans le texte du dossier, même pas encore jugés
	for l in index.element_links_of(dossier_rel):
		if str(l.origin) == "propriété indices":
			continue
		var nb := parse_ref("[[%s#%s]]" % [str(l.target), str(l.sub)])
		if nb[0] != "":
			row_of.call(nb[0], nb[1]).examined = true
	# détail et poids de chaque élément
	var fiab_cache := {}
	for k in order:
		var r: Dictionary = rows[k]
		var e: Dictionary = index.element_by_ref(r.note, r.block)
		r["missing"] = e.is_empty()
		r["text"] = Schema.display_text(str(e.get("text", ""))).strip_edges() if not e.is_empty() else "(élément introuvable : %s)" % r.ref
		r["path"] = str(e.get("path", ""))
		r["cred"] = str(e.get("cred", "")) if e.get("cred") != null else ""
		r["nature"] = str(e.get("nature", ""))
		if not fiab_cache.has(r.path):
			fiab_cache[r.path] = str(index.props_of(r.path).get("fiabilite", "")) if r.path != "" else ""
		r["fiab"] = fiab_cache[r.path]
		r["weight"] = 0.0 if r.missing else Paths.p_of(tab, r.fiab, r.cred)
		# un élément qui départage : ses jugements ne sont pas tous les mêmes
		var seen := {}
		for hi in out.hypotheses.size():
			seen[str(r.cells.get(hi, ""))] = true
		r["diagnostic"] = seen.size() > 1
		for hi in r.cells:
			var h: Dictionary = out.hypotheses[hi]
			if r.cells[hi] == "pour":
				h.n_pour += 1
				h.w_pour += r.weight
			else:
				h.n_contre += 1
				h.w_contre += r.weight
		out.rows.append(r)
	# les éléments qui départagent d'abord, puis les plus solides
	out.rows.sort_custom(func(a, b):
		if a.diagnostic != b.diagnostic:
			return a.diagnostic
		return a.weight > b.weight)
	var rank := range(out.hypotheses.size())
	rank.sort_custom(func(a, b):
		var ha: Dictionary = out.hypotheses[a]
		var hb: Dictionary = out.hypotheses[b]
		if not is_equal_approx(ha.w_contre, hb.w_contre):
			return ha.w_contre < hb.w_contre
		return ha.w_pour > hb.w_pour)
	out.ranking = rank
	return out


## Valeur suivante d'une case, à chaque appui : neutre → cohérent → incohérent → neutre.
static func next_cell(v: String) -> String:
	match v:
		"":
			return "pour"
		"pour":
			return "contre"
	return ""
