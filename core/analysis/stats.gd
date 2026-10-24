extends RefCounted
## Statistiques des personnages et des informations (calculées depuis l'index ;
## rien n'est écrit).
##
## Personnages : statut, statut d'âge, ville (domaine), clan, secte, disciplines
## (celles de la fiche et celles constatées dans des éléments qui la citent),
## nombre d'informations (éléments qui la citent) et de rétroliens (notes qui la citent).
##
## Informations (éléments) : cote de l'Amirauté (fiabilité de la note A–F ×
## crédibilité de l'élément 1–6), nature, type de note, année, domaine, voix.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")

## Répartitions proposées pour les personnages : [clé, libellé].
const PEOPLE_DIMS := [["statut", "Statut"], ["rang", "Âge"], ["domaine", "Ville"], ["clan", "Clan"],
	["secte", "Secte"], ["discipline", "Discipline"]]
## Répartitions proposées pour les informations.
const INFO_DIMS := [["fiab", "Fiabilité de la source (A–F)"], ["cred", "Crédibilité de l'information (1–6)"],
	["cote", "Cote complète (ex. B2)"], ["nature", "Nature (observé, rapporté…)"],
	["kind", "Type de note"], ["year", "Année"], ["domaine", "Domaine"], ["voice", "Voix (qui affirme)"]]
const NONE := {"statut": "Non renseigné", "rang": "Non renseigné", "domaine": "Sans ville", "clan": "Clan inconnu",
	"secte": "Secte inconnue", "discipline": "Aucune connue"}
const SOLID_FIAB := ["A", "B"]
const SOLID_CRED := ["1", "2"]
static var DATE_RE := RegEx.create_from_string("\\d{4}(-\\d{2}){0,2}")


static func _list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v
	return [] if str(v) == "" else [v]


# ------------------------------------------------------------------ personnages

## Une ligne par fiche de personnage : {name, path, key, statut, rang, domaine,
## clan, secte, disciplines (noms), infos, backlinks}. Les codes sont gardés ;
## `label()` donne le texte affiché.
static func people(index: RefCounted) -> Array:
	var counts: Dictionary = index.mention_counts()
	var obs := {}
	for r in index.discipline_mentions():
		var f: Variant = JSON.parse_string(str(r.fields))
		if typeof(f) == TYPE_DICTIONARY:
			var d := Schema.link_name(f.get("discipline", ""))
			if d != "":
				if not obs.has(str(r.k)):
					obs[str(r.k)] = {}
				obs[str(r.k)][d] = true
	var out := []
	for p in index.notes_with_props("personnage", ["statut", "rang", "domaine", "clan", "secte", "disciplines"]):
		var pr: Dictionary = p.props
		var k := TextNorm.name_key(str(p.name))
		var disc := {}
		for x in _list(pr.get("disciplines")):
			var n := Schema.link_name(x)
			if n != "":
				disc[n] = true
		for n in obs.get(k, {}):
			disc[n] = true
		var c: Array = counts.get(k, [0, 0])
		out.append({"name": str(p.name), "path": str(p.path), "key": k, "statut": str(pr.get("statut", "") if pr.get("statut") != null else ""),
			"rang": str(pr.get("rang", "") if pr.get("rang") != null else ""), "domaine": Schema.link_name(_first(pr.get("domaine"))),
			"clan": Schema.link_name(_first(pr.get("clan"))), "secte": Schema.link_name(_first(pr.get("secte"))),
			"disciplines": disc.keys(), "backlinks": int(c[0]), "infos": int(c[1])})
	return out


static func _first(v: Variant) -> Variant:
	var l := _list(v)
	return l[0] if not l.is_empty() else ""


## Filtre : `statuts` (codes, "" = non renseigné ; vide = tous), `min_infos`, `min_backlinks`.
static func filter_people(list: Array, f: Dictionary) -> Array:
	var st: Array = f.get("statuts", [])
	var mi := int(f.get("min_infos", 0))
	var mb := int(f.get("min_backlinks", 0))
	return list.filter(func(p): return (st.is_empty() or st.has(p.statut)) and int(p.infos) >= mi and int(p.backlinks) >= mb)


## Valeurs d'une personne pour une répartition (plusieurs pour les disciplines).
static func values_of(p: Dictionary, dim: String) -> Array:
	if dim == "discipline":
		return p.disciplines if not (p.disciplines as Array).is_empty() else [""]
	return [str(p.get(dim, ""))]


## Texte affiché d'une valeur.
static func label(dim: String, v: String) -> String:
	if v == "":
		return NONE.get(dim, "Non renseigné")
	match dim:
		"statut":
			return Schema.option_label("personnage", "statut", v)
		"rang":
			return Schema.option_label("personnage", "rang", v)
	return v


## Répartition : [[valeur, libellé, nombre]], les plus nombreux d'abord (le
## « non renseigné » en dernier). Une personne aux trois disciplines compte trois fois.
static func breakdown(list: Array, dim: String) -> Array:
	var c := {}
	for p in list:
		for v in values_of(p, dim):
			c[v] = int(c.get(v, 0)) + 1
	var out := []
	for v in c:
		out.append([v, label(dim, v), c[v]])
	out.sort_custom(func(a, b):
		if (a[0] == "") != (b[0] == ""):
			return b[0] == ""
		return a[2] > b[2] if a[2] != b[2] else TextNorm.fold(a[1]) < TextNorm.fold(b[1]))
	return out


# ------------------------------------------------------------------ informations

## Un élément par ligne : {path, note, text, cred, fiab, cote, nature, kind, year,
## domaine, voice}.
static func infos(index: RefCounted) -> Array:
	var np: Dictionary = index.props_by_fid(["fiabilite", "nature", "date", "date_floue", "domaine", "auteur"])
	var out := []
	for e in index.all_elements():
		var p: Dictionary = np.get(int(e.fid), {})
		var f: Variant = JSON.parse_string(str(e.fields))
		var fields: Dictionary = f if typeof(f) == TYPE_DICTIONARY else {}
		var fiab := str(p.get("fiabilite", "")).strip_edges().to_upper()
		if not fiab in ["A", "B", "C", "D", "E", "F"]:
			fiab = ""
		var cred := str(e.cred) if e.cred != null and str(e.cred) in ["1", "2", "3", "4", "5", "6"] else ""
		var ty := str(e.type)
		var kind := Schema.type_label(ty) if ty != "" else "Note libre"
		if ty == "source" and str(p.get("nature", "")) != "":
			kind += " · " + Schema.option_label("source", "nature", p.nature)
		var date := str(fields.get("date_faits", ""))
		if date == "":
			date = str(p.get("date", p.get("date_floue", "")))
		# « 2026~ », « ../2026-08-26 », « 2025-03/2025-04 » : la première date écrite
		var m := DATE_RE.search(date)
		var voice := Schema.link_name(fields.get("par", ""))
		if voice == "":
			voice = Schema.link_name(p.get("auteur", ""))
		out.append({"path": str(e.path), "note": str(e.note), "block": str(e.block), "text": Schema.display_text(str(e.text)).strip_edges(),
			"fiab": fiab, "cred": cred, "cote": (fiab if fiab != "" else "?") + (cred if cred != "" else "?"),
			"nature": str(e.nature), "kind": kind, "year": m.get_string().left(4) if m else "",
			"domaine": Schema.link_name(p.get("domaine", "")), "voice": voice, "date": m.get_string() if m else ""})
	# les plus récentes d'abord (date des faits, sinon de la note)
	out.sort_custom(func(a, b): return a.date > b.date if a.date != b.date else a.note < b.note)
	return out


static func info_label(dim: String, v: String) -> String:
	if v == "" or v == "??":
		return {"fiab": "Fiabilité non notée", "cred": "Crédibilité non notée", "nature": "Nature non notée", "year": "Sans date",
			"domaine": "Sans domaine", "voice": "Voix inconnue", "cote": "Non cotée"}.get(dim, "Non renseigné")
	match dim:
		"fiab":
			for o in Schema.FIABILITE:
				if str(o[0]) == v:
					return str(o[1])
		"cred":
			for o in Schema.CREDIBILITE:
				if str(o[0]) == v:
					return str(o[1])
		"nature":
			return Schema.option_label("element", "nature", v)
	return v


static func info_breakdown(list: Array, dim: String) -> Array:
	var c := {}
	for x in list:
		var v := str(x.get(dim, ""))
		c[v] = int(c.get(v, 0)) + 1
	var out := []
	for v in c:
		out.append([v, info_label(dim, v), c[v]])
	var ordered := dim in ["fiab", "cred", "cote", "year"]
	out.sort_custom(func(a, b):
		var ea: bool = a[0] == "" or a[0] == "??"
		var eb: bool = b[0] == "" or b[0] == "??"
		if ea != eb:
			return eb
		if ordered:
			# l'échelle dans son ordre (A avant B, 1 avant 2) ; les années, la plus récente d'abord
			return a[0] > b[0] if dim == "year" else a[0] < b[0]
		return a[2] > b[2] if a[2] != b[2] else TextNorm.fold(a[1]) < TextNorm.fold(b[1]))
	return out


## Grille de l'Amirauté : {"A1": n, …} et les totaux.
static func admiralty_grid(list: Array) -> Dictionary:
	var g := {}
	for x in list:
		var k: String = str(x.cote)
		g[k] = int(g.get(k, 0)) + 1
	return g


## Chiffres clés des informations.
static func info_summary(list: Array) -> Dictionary:
	var n := list.size()
	var solid := 0
	var weak := 0
	var unrated := 0
	var refuted := 0
	var rumors := 0
	var sources := {}
	for x in list:
		sources[x.path] = true
		if x.fiab in SOLID_FIAB and x.cred in SOLID_CRED:
			solid += 1
		if x.fiab in ["D", "E"] or x.cred in ["4", "5"]:
			weak += 1
		if x.fiab in ["", "F"] and x.cred in ["", "6"]:
			unrated += 1
		if x.cred == "5":
			refuted += 1
		if x.nature == "rumeur":
			rumors += 1
	return {"total": n, "notes": sources.size(), "solid": solid, "weak": weak, "unrated": unrated, "refuted": refuted, "rumors": rumors}
