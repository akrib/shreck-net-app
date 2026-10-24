extends RefCounted
## Contradictions (A-FAIRE §2, piste 1) : ce que vos notes disent de
## contradictoire, à trancher par vous. Calculé depuis l'index ; rien n'est écrit.
##
## Genres, du plus grave au plus léger :
##  - deux_endroits : une personne notée à deux endroits la même nuit (cf. alibis) ;
##  - sire : deux sires différents pour un même infant (éléments `sire_de`, propriété `sire`) ;
##  - relation : deux personnes dites à la fois alliées et ennemies ;
##  - poste : un poste qu'une seule personne tient à la fois (Prince, Sénéchal,
##    Shérif, Fléau, Maître des Harpies, Harpie majeure) écrit sur deux fiches en vie ;
##  - faveur : une faveur en cours dont une partie est morte ou disparue ;
##  - identite : deux fiches qui portent le même nom ou alias, ou marquées
##    « peut-être la même personne ».
## Les éléments de crédibilité 5 (réfutés) ne comptent pas.
## Chaque entrée : {kind, label, title, detail (lignes d'explication), paths (notes en
## cause), who (noms), key, items (facultatif : les notes listées une à une)}.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Where := preload("res://core/analysis/whereabouts.gd")

const KIND_ORDER := {"deux_endroits": 0, "sire": 1, "relation": 2, "poste": 3, "faveur": 4, "identite": 5}
const KIND_LABEL := {"deux_endroits": "Vu à deux endroits", "sire": "Deux sires", "relation": "Allié et ennemi",
	"poste": "Poste tenu deux fois", "faveur": "Faveur et mort", "identite": "Même personne ?"}
const UNIQUE_POSTES := ["prince", "senechal", "sherif", "fleau", "maitre des harpies", "harpie majeure"]
const GONE := ["mort_finale", "disparu"]


static func _list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v
	return [] if str(v) == "" else [v]


static func _fields(r: Dictionary) -> Dictionary:
	var f: Variant = JSON.parse_string(str(r.get("fields", "")))
	return f if typeof(f) == TYPE_DICTIONARY else {}


static func _source(r: Dictionary) -> String:
	var c := str(r.get("cred", ""))
	return "%s%s" % [str(r.note), (" (crédibilité %s)" % c) if c != "" and c != "6" and c != "<null>" else ""]


## Toutes les contradictions, les plus graves d'abord. `all_facts` : présences
## déjà calculées (Where.facts), pour ne pas les recalculer.
static func build(index: RefCounted, all_facts := []) -> Array:
	var out := []
	# fiches des personnages : nom, chemin, statut
	var people := {}
	for p in index.notes_with_props("personnage", ["statut", "titres", "sire", "peut_etre"]):
		people[TextNorm.name_key(str(p.name))] = p
	var name_of := func(key: String, fallback: String) -> String:
		return str(people[key].name) if people.has(key) else fallback
	var path_of := func(key: String) -> String:
		return str(people[key].path) if people.has(key) else ""
	var rels: Array = index.all_relations().filter(func(r): return str(r.cred) != "5")
	_two_places(index, all_facts, out)
	_sires(rels, people, name_of, path_of, out)
	_allies_enemies(rels, name_of, path_of, out)
	_postes(people, out)
	_faveurs(index, people, out)
	_identities(index, people, out)
	out.sort_custom(func(a, b):
		if a.kind != b.kind:
			return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
		return TextNorm.fold(str(a.title)) < TextNorm.fold(str(b.title)))
	return out


static func _add(out: Array, kind: String, title: String, detail: Array, paths: Array, who: Array) -> void:
	var clean := []
	for p in paths:
		if str(p) != "" and not clean.has(str(p)):
			clean.append(str(p))
	out.append({"kind": kind, "label": KIND_LABEL[kind], "title": title, "detail": detail, "paths": clean, "who": who,
		"key": kind + ":" + ",".join(PackedStringArray(who.map(func(w): return TextNorm.name_key(str(w)))))})


# ------------------------------------------------------------------ deux endroits

static func _two_places(index: RefCounted, all_facts: Array, out: Array) -> void:
	var facts: Array = all_facts if not all_facts.is_empty() else Where.facts(index)
	var by_who := {}
	for f in facts:
		var k := str(f.who_key)
		if not by_who.has(k):
			by_who[k] = []
		by_who[k].append(f)
	for k in by_who:
		var conf: Dictionary = Where.conflicts(by_who[k])
		for day in conf:
			var lst: Array = conf[day]
			var who := str(lst[0].who)
			var lines := []
			var paths := [str(lst[0].who_path)]
			for f in lst:
				lines.append("%s — %s" % [Where.how_label(f), str(f.where)])
				paths.append(str(f.path))
			_add(out, "deux_endroits", "%s, nuit du %s : à deux endroits" % [who, day], lines, paths, [who, day])


# ------------------------------------------------------------------ sires

static func _sires(rels: Array, people: Dictionary, name_of: Callable, path_of: Callable, out: Array) -> void:
	var sires := {}   # infant -> {sire_key: [sources]}
	var add := func(infant: String, sire: String, src: String, path: String) -> void:
		if not sires.has(infant):
			sires[infant] = {}
		if not sires[infant].has(sire):
			sires[infant][sire] = []
		sires[infant][sire].append([src, path])
	for r in rels:
		if str(r.relation) == "sire_de":
			add.call(str(r.vers_key), str(r.de_key), _source(r), str(r.path))
	for k in people:
		var s := Schema.link_name(people[k].props.get("sire", ""))
		if s != "":
			add.call(k, TextNorm.name_key(s), "fiche de %s" % people[k].name, str(people[k].path))
	for infant in sires:
		var by: Dictionary = sires[infant]
		if by.size() < 2:
			continue
		var lines := []
		var paths := [path_of.call(infant)]
		var who := [name_of.call(infant, infant)]
		for s in by:
			var nm: String = name_of.call(s, s)
			who.append(nm)
			paths.append(path_of.call(s))
			for x in by[s]:
				lines.append("%s, selon %s" % [nm, x[0]])
				paths.append(x[1])
		_add(out, "sire", "%s : %d sires différents (%s)" % [who[0], by.size(), ", ".join(PackedStringArray(who.slice(1)))], lines, paths, who)


# ------------------------------------------------------------------ allié et ennemi

static func _allies_enemies(rels: Array, name_of: Callable, path_of: Callable, out: Array) -> void:
	var pairs := {}
	for r in rels:
		var code := str(r.relation)
		if code != "allie" and code != "ennemi":
			continue
		var a := str(r.de_key)
		var b := str(r.vers_key)
		var k := a + "|" + b if a < b else b + "|" + a
		if not pairs.has(k):
			pairs[k] = {"allie": [], "ennemi": [], "names": {}}
		pairs[k][code].append(r)
		var f := _fields(r)
		pairs[k].names[a] = Schema.link_name(f.get("de", a))
		pairs[k].names[b] = Schema.link_name(f.get("vers", b))
	for k in pairs:
		var pr: Dictionary = pairs[k]
		if pr.allie.is_empty() or pr.ennemi.is_empty():
			continue
		var ks: PackedStringArray = k.split("|")
		var na: String = name_of.call(ks[0], pr.names.get(ks[0], ks[0]))
		var nb: String = name_of.call(ks[1], pr.names.get(ks[1], ks[1]))
		var lines := []
		var paths := [path_of.call(ks[0]), path_of.call(ks[1])]
		for code in ["allie", "ennemi"]:
			for r in pr[code]:
				lines.append("%s, selon %s" % ["alliés" if code == "allie" else "ennemis", _source(r)])
				paths.append(str(r.path))
		_add(out, "relation", "%s et %s : alliés et ennemis (ont-ils changé ?)" % [na, nb], lines, paths, [na, nb])


# ------------------------------------------------------------------ postes uniques

static func _postes(people: Dictionary, out: Array) -> void:
	var holders := {}
	for k in people:
		var p: Dictionary = people[k]
		if str(p.props.get("statut", "")) in GONE:
			continue
		for t in _list(p.props.get("titres")):
			var title := Schema.display_text(str(t)).strip_edges()
			var tf := TextNorm.fold(title)
			var unique := false
			for u in UNIQUE_POSTES:
				if tf == u or tf.begins_with(u + " "):
					unique = true
			# « Prince » seul ne dit pas de quel domaine : on ne compare que des postes situés
			if not unique or not tf.contains(" "):
				continue
			if not holders.has(tf):
				holders[tf] = {"title": title, "who": []}
			holders[tf].who.append(p)
	for tf in holders:
		var h: Dictionary = holders[tf]
		if h.who.size() < 2:
			continue
		var names: Array = h.who.map(func(p): return str(p.name))
		_add(out, "poste", "« %s » : %s" % [h.title, " et ".join(PackedStringArray(names))],
			["Écrit sur %d fiches de personnes en vie ; une seule le tient à la fois." % names.size()],
			h.who.map(func(p): return str(p.path)), names)


# ------------------------------------------------------------------ faveurs

static func _faveurs(index: RefCounted, people: Dictionary, out: Array) -> void:
	# une ligne par couple débiteur → créancier dont une partie est morte ou disparue
	var groups := {}
	for n in index.notes_with_props("faveur", ["debiteur", "creancier", "statut", "niveau"]):
		var pr: Dictionary = n.props
		if not str(pr.get("statut", "")) in ["active", "reclamee", "suspendue"]:
			continue
		var deb := Schema.link_name(pr.get("debiteur", ""))
		var cre := Schema.link_name(pr.get("creancier", ""))
		for nm in [deb, cre]:
			var k := TextNorm.name_key(nm)
			if not people.has(k) or not str(people[k].props.get("statut", "")) in GONE:
				continue
			var gk := "%s|%s|%s" % [k, TextNorm.name_key(deb), TextNorm.name_key(cre)]
			if not groups.has(gk):
				groups[gk] = {"deb": deb, "cre": cre, "gone": nm, "statut": str(people[k].props.statut), "notes": [], "paths": [str(people[k].path)]}
			groups[gk].notes.append("%s (%s, %s)" % [str(n.name), Schema.option_label("faveur", "niveau", pr.get("niveau", "")).to_lower(),
				Schema.option_label("faveur", "statut", pr.statut).to_lower()])
			groups[gk].paths.append(str(n.path))
	for gk in groups:
		var g: Dictionary = groups[gk]
		var n: int = g.notes.size()
		_add(out, "faveur", "%s envers %s : %s, mais %s est %s" % [g.deb, g.cre,
			"une faveur en cours" if n == 1 else "%d faveurs en cours" % n, g.gone,
			Schema.option_label("personnage", "statut", g.statut).to_lower()],
			["À solder, annuler ou transmettre ?"], g.paths, [g.deb, g.cre, g.gone])
		out[-1]["items"] = g.notes


# ------------------------------------------------------------------ identités

static func _identities(index: RefCounted, people: Dictionary, out: Array) -> void:
	var seen := {}
	var add_pair := func(a: Dictionary, b: Dictionary, why: String) -> void:
		var ka := TextNorm.name_key(str(a.name))
		var kb := TextNorm.name_key(str(b.name))
		if ka == kb:
			return
		var k := ka + "|" + kb if ka < kb else kb + "|" + ka
		if seen.has(k):
			seen[k].detail.append(why)
			return
		var first := a if ka < kb else b
		var second := b if ka < kb else a
		_add(out, "identite", "%s et %s : la même personne ?" % [first.name, second.name], [why], [first.path, second.path], [first.name, second.name])
		seen[k] = out[-1]
	for k in people:
		var p: Dictionary = people[k]
		for x in _list(p.props.get("peut_etre")):
			var other := TextNorm.name_key(Schema.link_name(x))
			if people.has(other):
				add_pair.call(p, people[other], "%s est marqué(e) « peut-être la même personne que » %s" % [p.name, people[other].name])
	for r in index.alias_collisions():
		var ka := TextNorm.name_key(str(r.a_name))
		var kb := TextNorm.name_key(str(r.b_name))
		if people.has(ka) and people.has(kb):
			add_pair.call(people[ka], people[kb], "« %s » désigne les deux fiches (nom ou alias)" % str(r.alias))
