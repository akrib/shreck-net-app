extends RefCounted
## Fusion de deux fiches (0.7) : quand un inconnu est identifié, sa fiche est
## reprise dans celle de la personne. Rien n'est supprimé :
##  - la fiche gardée reçoit les propriétés qui lui manquaient, les alias de
##    l'autre et son nom en alias, son texte (dans une section « Repris de… »)
##    et ses éléments (avec leurs identifiants) ;
##  - les liens qui visaient l'ancienne fiche visent la fiche gardée, en
##    gardant le texte affiché : [[Inconnu]] devient [[Victor Morel|Inconnu]] ;
##  - l'ancienne fiche devient une note de renvoi, sans type, qui conserve son
##    contenu d'origine en entier (dans un bloc de code, que rien n'indexe).
## plan() calcule tout sans rien écrire ; AppService.merge_notes() applique.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const NoteDocument := preload("res://core/format/note_document.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const Dates := preload("res://core/model/dates.gd")

const SKIP := ["type", "id", "schema"]
const R_FENCE := "^\\s*(```|~~~)"


## Réécrit les liens [[Ancien…]] d'un texte vers `new_name`. Le texte affiché ne
## change pas : [[Ancien]] -> [[Nouveau|Ancien]], [[Ancien|x]] -> [[Nouveau|x]].
## `bare` : écrire [[Nouveau]] sans texte affiché (valeurs de propriétés).
## Les blocs de code sont laissés tels quels. Renvoie {text, count}.
static func rewrite_links(text: String, old_key: String, old_name: String, new_name: String, bare := false) -> Dictionary:
	var rx := RegEx.create_from_string("(!?)\\[\\[([^\\[\\]]+?)\\]\\]")
	var fence := RegEx.create_from_string(R_FENCE)
	var lines := text.split("\n")
	var count := 0
	var in_code := false
	for k in lines.size():
		var l: String = lines[k]
		if fence.search(l):
			in_code = not in_code
			continue
		if in_code or not l.contains("[["):
			continue
		var out := ""
		var pos := 0
		for m in rx.search_all(l):
			var inner := m.get_string(2)
			var parts := inner.split("|", true, 1)
			var sl := StructuredLines.split_link(parts[0])
			if TextNorm.name_key(sl.target) != old_key:
				continue
			var shown: String = parts[1] if parts.size() > 1 else ""
			var tgt: String = new_name + (("#" + sl.sub) if sl.sub != "" else "")
			if shown == "" and not bare:
				shown = old_name
			var rep := "%s[[%s%s]]" % [m.get_string(1), tgt, ("|" + shown) if shown != "" else ""]
			out += l.substr(pos, m.get_start() - pos) + rep
			pos = m.get_end()
			count += 1
		if pos > 0:
			lines[k] = out + l.substr(pos)
	return {"text": "\n".join(lines), "count": count}


static func _list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v.duplicate()
	return [] if str(v).strip_edges() == "" else [v]


static func _empty(v: Variant) -> bool:
	return v == null or (typeof(v) == TYPE_STRING and str(v).strip_edges() == "") or (typeof(v) == TYPE_ARRAY and v.is_empty())


static func _dedupe(list: Array) -> Array:
	var seen := {}
	var out := []
	for x in list:
		var k := TextNorm.fold(Schema.link_name(x)) if typeof(x) == TYPE_STRING else str(x)
		if seen.has(k):
			continue
		seen[k] = true
		out.append(x)
	return out


## Réécrit les liens d'une note qui citait l'ancienne fiche. Renvoie {doc, count} (doc modifié en mémoire).
static func rewrite_note(doc: RefCounted, old_key: String, old_name: String, new_name: String) -> Dictionary:
	var count := 0
	var changes := {}
	if doc.can_edit_properties():
		var props: Dictionary = doc.properties()
		for key in props:
			var v: Variant = props[key]
			if typeof(v) == TYPE_STRING:
				var r := rewrite_links(str(v), old_key, old_name, new_name, StructuredLines.link_target(str(v)) != "")
				if r.count > 0:
					changes[key] = r.text
					count += r.count
			elif typeof(v) == TYPE_ARRAY:
				var nl := []
				var n := 0
				for x in v:
					if typeof(x) == TYPE_STRING:
						var r2 := rewrite_links(str(x), old_key, old_name, new_name, StructuredLines.link_target(str(x)) != "")
						n += r2.count
						nl.append(r2.text)
					else:
						nl.append(x)
				if n > 0:
					changes[key] = _dedupe(nl)
					count += n
		# une personne constatée présente n'est plus « incertaine »
		var nk := TextNorm.name_key(new_name)
		var pres: Array = changes.get("presents", _list(props.get("presents")))
		if pres.any(func(x): return TextNorm.name_key(Schema.link_name(x)) == nk):
			var inc: Array = changes.get("presents_incertains", _list(props.get("presents_incertains")))
			var inc2 := inc.filter(func(x): return TextNorm.name_key(Schema.link_name(x)) != nk)
			if inc2.size() != inc.size():
				changes["presents_incertains"] = inc2
		if not changes.is_empty():
			var err: String = doc.set_properties(changes, {"date": "date"})
			if err != "":
				return {"doc": doc, "count": 0, "error": err}
	var rb := rewrite_links(doc.body_for_edit(), old_key, old_name, new_name)
	if rb.count > 0:
		doc.set_body(rb.text)
		count += rb.count
	return {"doc": doc, "count": count, "error": ""}


## Découpe le corps de l'ancienne fiche : ses éléments (à reprendre tels quels)
## et le reste du texte, titres abaissés d'un niveau, sans le titre principal.
static func split_old_body(body: String) -> Dictionary:
	var lines := body.split("\n")
	var fence := RegEx.create_from_string(R_FENCE)
	var head := RegEx.create_from_string("^(#{1,5})\\s+(.*?)\\s*$")
	var elements := []
	var text := PackedStringArray()
	var in_code := false
	var in_el := false
	var title_dropped := false
	for l in lines:
		if fence.search(l):
			in_code = not in_code
		var m: RegExMatch = null if in_code else head.search(l)
		if m:
			var lvl := m.get_string(1).length()
			if lvl <= 2:
				in_el = lvl == 2 and TextNorm.fold(m.get_string(2)).strip_edges() == "elements"
			if in_el:
				continue
			if lvl == 1 and not title_dropped:
				title_dropped = true
				continue
			text.append("#" + l)
			continue
		if in_el:
			if l.strip_edges() != "":
				elements.append(l)
			continue
		text.append(l)
	return {"elements": elements, "text": "\n".join(text).strip_edges()}


## Calcule la fusion de `old_name` dans `keep_name`, sans rien écrire.
## `read` : Callable(rel) -> {ok, doc, hash}. Renvoie {ok, error, keep_rel, old_rel,
## writes: [{rel, hash, bytes, label}], summary: PackedStringArray, conflicts, linked}.
static func plan(index: RefCounted, read: Callable, old_name: String, keep_name: String, today: String) -> Dictionary:
	var res := {"ok": false, "error": "", "writes": [], "summary": PackedStringArray(), "conflicts": [], "linked": 0}
	var old_rel: String = index.path_of_name(old_name)
	var keep_rel: String = index.path_of_name(keep_name)
	if old_rel == "" or keep_rel == "":
		res.error = "les deux fiches doivent exister"
		return res
	if old_rel == keep_rel:
		res.error = "c'est la même fiche"
		return res
	res["old_rel"] = old_rel
	res["keep_rel"] = keep_rel
	old_name = old_rel.get_file().get_basename()
	keep_name = keep_rel.get_file().get_basename()
	var ro: Dictionary = read.call(old_rel)
	var rk: Dictionary = read.call(keep_rel)
	if not ro.ok or not rk.ok:
		res.error = "lecture impossible"
		return res
	var od: RefCounted = ro.doc
	var kd: RefCounted = rk.doc
	if not od.can_edit_properties() or not kd.can_edit_properties():
		res.error = "propriétés illisibles : corrigez d'abord la note à la main"
		return res
	var ot: String = od.type_name()
	var kt: String = kd.type_name()
	if ot != kt:
		res.error = "les deux fiches ne sont pas du même type (%s, %s)" % [Schema.type_label(ot), Schema.type_label(kt)]
		return res
	var old_key := TextNorm.name_key(old_name)
	var keep_key := TextNorm.name_key(keep_name)
	# --- 1. la fiche gardée
	var op: Dictionary = od.properties()
	var kp: Dictionary = kd.properties()
	var changes := {}
	var added := PackedStringArray()
	for key in op:
		if key in SKIP or key == "aliases":
			continue
		var ov: Variant = op[key]
		if _empty(ov):
			continue
		# liens de l'ancienne fiche vers elle-même ou vers la fiche gardée : sans objet ;
		# son identité « inconnue » ou son statut « inconnu » ne valent plus une fois identifiée
		if key == "peut_etre" or key == "identite" or (key == "statut" and str(ov) == "inconnu"):
			continue
		var kv: Variant = kp.get(key)
		if _empty(kv):
			changes[key] = ov
			added.append(key)
		elif typeof(ov) == TYPE_ARRAY or typeof(kv) == TYPE_ARRAY:
			var merged := _dedupe(_list(kv) + _list(ov))
			if merged.size() != _list(kv).size():
				changes[key] = merged
				added.append(key)
		elif str(ov).strip_edges() != str(kv).strip_edges():
			res.conflicts.append({"key": key, "keep": kv, "old": ov})
	var aliases := _dedupe(_list(kp.get("aliases")) + _list(op.get("aliases")) + [old_name])
	aliases = aliases.filter(func(a): return TextNorm.name_key(str(a)) != keep_key)
	changes["aliases"] = aliases
	var pe := _list(kp.get("peut_etre")) + _list(op.get("peut_etre"))
	pe = _dedupe(pe).filter(func(x):
		var k := TextNorm.name_key(Schema.link_name(x))
		return k != old_key and k != keep_key)
	if not _list(kp.get("peut_etre")).is_empty() or not _list(op.get("peut_etre")).is_empty():
		changes["peut_etre"] = pe
	var err: String = kd.set_properties(changes, {"date": "date"})
	if err != "":
		res.error = err
		return res
	var parts := split_old_body(od.body_for_edit())
	var nice := Dates.label(today)
	var body: String = kd.body_for_edit().strip_edges(false, true)
	var section := "\n\n## Repris de « %s » (fusion du %s)\n" % [old_name, nice]
	if res.conflicts.size() > 0:
		for c in res.conflicts:
			section += "- Sur l'ancienne fiche, %s : %s\n" % [c.key, str(c.old)]
	if str(parts.text) != "":
		section += "\n" + str(parts.text) + "\n"
	elif res.conflicts.is_empty():
		section += "\n*(L'ancienne fiche n'avait pas de texte.)*\n"
	body += section
	for el in parts.elements:
		body = StructuredLines.append_to_section(body, "Éléments", str(el))
	# liens de la fiche gardée vers l'ancienne (dans son propre texte)
	kd.set_body(body)
	rewrite_note(kd, old_key, old_name, keep_name)
	res.writes.append({"rel": keep_rel, "hash": rk.hash, "bytes": kd.to_bytes(), "label": "fiche gardée"})
	res.summary.append("« %s » est gardée : %s ; « %s » devient un alias%s." % [keep_name,
		("propriétés ajoutées : " + ", ".join(added)) if not added.is_empty() else "aucune propriété à ajouter",
		old_name, (" ; %d élément(s) repris" % parts.elements.size()) if not parts.elements.is_empty() else ""])
	for c in res.conflicts:
		res.summary.append("Valeur différente gardée pour « %s » : %s (l'ancienne, %s, est notée dans le texte)." % [c.key, str(c.keep), str(c.old)])
	# --- 2. les notes qui citaient l'ancienne fiche
	var seen := {old_rel: true, keep_rel: true}
	for b in index.backlinks(old_name, 100000):
		var p := str(b.path)
		if seen.has(p):
			continue
		seen[p] = true
		var rb: Dictionary = read.call(p)
		if not rb.ok:
			res.error = "lecture impossible : " + p
			return res
		var rw := rewrite_note(rb.doc, old_key, old_name, keep_name)
		if str(rw.error) != "":
			res.error = "%s : %s" % [p, rw.error]
			return res
		if int(rw.count) > 0:
			res.writes.append({"rel": p, "hash": rb.hash, "bytes": rb.doc.to_bytes(), "label": "%d lien(s)" % rw.count})
			res.linked += 1
	res.summary.append("%d note(s) dont les liens mènent désormais à « %s »." % [res.linked, keep_name])
	# --- 3. l'ancienne fiche devient un renvoi (contenu conservé en entier)
	var original: String = od.raw_text if od.raw_text != "" else od.to_text()
	var fence := "````"
	while original.contains(fence):
		fence += "`"
	var stub := "---\nfusionnee_dans: \"[[%s]]\"\ndate_fusion: %s\nancien_type: %s\nancien_id: %s\n---\n# %s\n\nFiche fusionnée dans [[%s]] le %s : son contenu y a été repris, et les liens qui la visaient y mènent désormais. Contenu d'origine, pour mémoire :\n\n%stext\n%s\n%s\n" % [
		keep_name, today, ot, od.note_id(), old_name, keep_name, nice, fence, original.strip_edges(false, true), fence]
	res.writes.append({"rel": old_rel, "hash": ro.hash, "bytes": stub.to_utf8_buffer(), "label": "renvoi"})
	res.summary.append("« %s » devient une note de renvoi vers « %s » : rien n'est supprimé, son contenu d'origine y reste en entier." % [old_name, keep_name])
	res.ok = true
	return res
