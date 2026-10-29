extends RefCounted
## Membres d'un groupe (clan, faction, coterie…), d'après :
##  - les fiches de personnages dont le `clan` ou la `secte` est ce groupe ;
##  - les éléments « est membre de » ou « dirige » qui le visent (§11) ;
##  - les indices de même relation (sauf réfutés ou obsolètes) ;
##  - pour une lignée, son chef (propriété `chef` de sa fiche, format 1.7).
## Rien n'est écrit : c'est recalculé depuis les notes (§16).

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")

const ROLES := {"membre_de": "membre", "dirige": "dirige", "lignee_de": "de la lignée"}


## [{name, path (fiche du membre, "" si absente), roles: ["membre"…], sources:
## [{label, path, cred}], from_fiche (bool)}], dans l'ordre des noms.
static func of_group(index: RefCounted, group: String) -> Array:
	var k := TextNorm.name_key(group)
	var gprops: Dictionary = index.props_of(index.path_of_name(group))
	var is_lignee := str(gprops.get("nature", "")) == "lignee"
	var by := {}
	var get_row := func(person: String) -> Dictionary:
		var pk := TextNorm.name_key(person)
		if not by.has(pk):
			by[pk] = {"name": person, "path": index.path_of_name(person), "roles": [], "sources": [], "from_fiche": false}
		return by[pk]
	var chef := Schema.link_name(gprops.get("chef", "")) if is_lignee else ""
	if chef != "":
		(get_row.call(chef).roles as Array).append("chef")
	for r in index.linked_from(group, ["clan", "secte"]):
		if str(r.type) != "personnage":
			continue
		var row: Dictionary = get_row.call(str(r.name))
		row.from_fiche = true
		# une fiche qui porte la lignée dans `clan` (anciennes notes) : « lignée (fiche) »
		var what := ("lignee" if is_lignee else "clan") if str(r.origin) == "propriété clan" else "secte"
		if not row.roles.has(what):
			row.roles.append(what)
	for r in index.relations_of(group):
		var code := str(r.relation)
		if not ROLES.has(code) or str(r.vers_key) != k:
			continue
		var f: Variant = JSON.parse_string(str(r.fields))
		var person := Schema.link_name((f as Dictionary).get("de", "")) if typeof(f) == TYPE_DICTIONARY else ""
		if person == "":
			continue
		var row: Dictionary = get_row.call(person)
		if not row.roles.has(ROLES[code]):
			row.roles.append(ROLES[code])
		row.sources.append({"label": str(r.note), "path": str(r.path), "cred": r.cred, "origin": "element", "block": str(r.block if r.block != null else ""), "text": str(r.text)})
	for n in index.notes_with_props("indice", ["relation", "de", "vers", "statut", "credibilite"]):
		var pr: Dictionary = n.props
		var code := str(pr.get("relation", ""))
		if not ROLES.has(code) or TextNorm.name_key(Schema.link_name(pr.get("vers", ""))) != k:
			continue
		if str(pr.get("statut", "")) in ["refute", "obsolete"]:
			continue
		var person := Schema.link_name(pr.get("de", ""))
		if person == "":
			continue
		var row: Dictionary = get_row.call(person)
		if not row.roles.has(ROLES[code]):
			row.roles.append(ROLES[code])
		row.sources.append({"label": "indice « %s »" % str(n.name), "path": str(n.path), "cred": pr.get("credibilite"), "origin": "indice"})
	var out: Array = by.values()
	out.sort_custom(func(a, b):
		# le chef de lignée, puis qui dirige, puis par nom
		var ca: bool = a.roles.has("chef")
		var cb: bool = b.roles.has("chef")
		if ca != cb:
			return ca
		var da: bool = a.roles.has("dirige")
		var db: bool = b.roles.has("dirige")
		return da if da != db else TextNorm.fold(a.name) < TextNorm.fold(b.name))
	return out


## Texte d'une ligne : « Victor Morel — dirige ; selon 2026-10-24 … (crédibilité 2) ».
static func describe(row: Dictionary) -> String:
	var parts := PackedStringArray()
	for r in row.roles:
		parts.append({"clan": "clan (fiche)", "lignee": "lignée (fiche)", "secte": "secte (fiche)", "chef": "chef de lignée"}.get(r, r))
	var txt := "%s — %s" % [row.name, ", ".join(parts)]
	var src: Array = row.sources
	if src.size() == 1:
		txt += " ; selon %s (crédibilité %s)" % [src[0].label, str(src[0].cred) if src[0].cred != null else "?"]
	elif src.size() > 1:
		txt += " ; selon %d sources" % src.size()
	if row.path == "":
		txt += " · pas de fiche"
	return txt
