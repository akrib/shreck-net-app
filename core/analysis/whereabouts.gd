extends RefCounted
## Alibis et chronologie (A-FAIRE §2) : où était chacun, et qui était là à
## chaque incident. Tout est calculé à partir des notes ; rien n'est écrit.
##
## Une présence vient :
##  - d'une soirée : présents (constatés), présents incertains, absences remarquées ;
##  - d'un événement : ses participants (sauf s'il est réfuté) ;
##  - d'un élément « était présent à » (relation present_a) ;
##  - d'un indice de même relation (sauf s'il est réfuté).
## Sa date : la date des faits de l'élément, sinon celle de la soirée ou de
## l'événement visé, sinon celle de la soirée où l'élément est noté.
## Une soirée datée du 14 couvre la nuit du 14 au 15 : « telle nuit » est une date au jour près.
##
## Force d'une présence (pour classer et pour les alibis) : 3 sûre, 2 probable,
## 1 douteuse, 0 pour une absence. Seules les présences de force 2 ou plus
## fournissent un alibi.
##
## Deux présences sont « ailleurs » l'une par rapport à l'autre quand leurs lieux
## sont connus et différents, ou, à défaut de lieux, quand leurs domaines sont
## connus et différents. Sinon, on ne sait pas : ni alibi, ni contradiction.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Dates := preload("res://core/model/dates.gd")

const HOW := {"present": "présent (constaté)", "incertain": "présence incertaine", "absent": "absence remarquée",
	"participant": "participant", "rapporte": "présent selon une source", "indice": "présent selon un indice"}
const KIND := {"sur_place": "sur place", "alibi": "vu ailleurs", "absent": "absence remarquée",
	"compatible": "au même lieu, date compatible", "parages": "dans le domaine ce soir-là", "": "—"}


static func _list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v
	return [] if str(v) == "" else [v]


static func _first(v: Variant) -> String:
	var l := _list(v)
	return str(l[0]) if not l.is_empty() else ""


## Lieux de rendez-vous connus : clé de nom -> {name, type, path, date, lieu, domaine, statut}.
## Soirées, événements et lieux ; une soirée ou un événement est « au » lieu de sa propriété `lieu`.
static func places(index: RefCounted) -> Dictionary:
	var out := {}
	for t in ["soiree", "evenement", "lieu"]:
		for n in index.notes_with_props(t, ["date", "date_floue", "domaine", "lieu", "statut"]):
			var pr: Dictionary = n.props
			var date := _first(pr.get("date"))
			if date == "":
				date = _first(pr.get("date_floue"))
			var lieu := str(n.name) if t == "lieu" else Schema.link_name(_first(pr.get("lieu")))
			out[TextNorm.name_key(str(n.name))] = {"name": str(n.name), "type": t, "path": str(n.path),
				"date": "" if t == "lieu" else date, "lieu": lieu, "domaine": Schema.link_name(_first(pr.get("domaine"))),
				"statut": _first(pr.get("statut"))}
	return out


static func _place_of(pl: Dictionary, names: Dictionary, target: String) -> Dictionary:
	var k := TextNorm.name_key(target)
	if pl.has(k):
		return pl[k]
	var inf: Dictionary = names.get(k, {})
	return {"name": str(inf.get("name", target)), "type": str(inf.get("type", "")), "path": str(inf.get("path", "")),
		"date": "", "lieu": "", "domaine": "", "statut": ""}


static func _fact(names: Dictionary, who: String, place: Dictionary, date: String, how: String, force: int,
		note: String, path: String, block := "", text := "", cred: Variant = null) -> Dictionary:
	var wk := TextNorm.name_key(who)
	var inf: Dictionary = names.get(wk, {})
	var sp := Dates.span(date)
	return {"who": str(inf.get("name", who)), "who_key": wk, "who_path": str(inf.get("path", "")),
		"who_type": str(inf.get("type", "")),
		"where": str(place.name), "where_key": TextNorm.name_key(str(place.name)), "where_path": str(place.path),
		"where_type": str(place.type),
		"lieu": str(place.lieu), "lieu_key": TextNorm.name_key(str(place.lieu)) if str(place.lieu) != "" else "",
		"domaine": str(place.domaine), "domaine_key": TextNorm.name_key(str(place.domaine)) if str(place.domaine) != "" else "",
		"date": date, "first": sp[0], "last": sp[1], "exact": Dates.is_day(date),
		"how": how, "force": force, "note": note, "path": path, "block": block, "text": text, "cred": cred}


## Toutes les présences connues (voir l'en-tête).
static func facts(index: RefCounted) -> Array:
	var names: Dictionary = index.all_names()
	var pl := places(index)
	var out := []
	# 1. soirées
	for s in index.notes_with_props("soiree", ["presents", "presents_incertains", "absents"]):
		var place: Dictionary = pl.get(TextNorm.name_key(str(s.name)), {})
		if place.is_empty():
			continue
		for spec in [["presents", "present", 3], ["presents_incertains", "incertain", 1], ["absents", "absent", 0]]:
			for who in _list(s.props.get(spec[0])):
				var nm := Schema.link_name(who)
				if nm != "":
					out.append(_fact(names, nm, place, str(place.date), spec[1], spec[2], str(s.name), str(s.path)))
	# 2. événements
	for ev in index.notes_with_props("evenement", ["participants"]):
		var place: Dictionary = pl.get(TextNorm.name_key(str(ev.name)), {})
		if place.is_empty() or str(place.statut) == "refute":
			continue
		for who in _list(ev.props.get("participants")):
			var nm := Schema.link_name(who)
			if nm != "":
				out.append(_fact(names, nm, place, str(place.date), "participant", 3 if str(place.statut) == "corrobore" else 2,
					str(ev.name), str(ev.path)))
	# 3. éléments « était présent à »
	for r in index.all_relations():
		if str(r.relation) != "present_a":
			continue
		var f: Variant = JSON.parse_string(str(r.fields))
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var who := Schema.link_name(f.get("de", ""))
		var target := Schema.link_name(f.get("vers", ""))
		if who == "" or target == "":
			continue
		var place := _place_of(pl, names, target)
		var date := str(f.get("date_faits", "")).strip_edges()
		if date == "":
			date = str(place.date)
		if date == "" and str(r.type) == "soiree":
			date = str(pl.get(TextNorm.name_key(str(r.note)), {}).get("date", ""))
		var cred: int = int(r.cred) if r.cred != null else 6
		var force := 3 if cred <= 2 else (2 if cred == 3 or cred == 6 else 1)
		if str(r.nature) in ["deduction", "hypothese"]:
			force = mini(force, 1)
		out.append(_fact(names, who, place, date, "rapporte", force, str(r.note), str(r.path), str(r.block if r.block != null else ""),
			str(r.text), cred))
	# 4. indices « était présent à »
	for n in index.notes_with_props("indice", ["relation", "de", "vers", "statut", "credibilite", "date_floue"]):
		var pr: Dictionary = n.props
		if _first(pr.get("relation")) != "present_a" or _first(pr.get("statut")) == "refute":
			continue
		var who := Schema.link_name(_first(pr.get("de")))
		var target := Schema.link_name(_first(pr.get("vers")))
		if who == "" or target == "":
			continue
		var place := _place_of(pl, names, target)
		var date := _first(pr.get("date_floue"))
		if date == "":
			date = str(place.date)
		var cred := _first(pr.get("credibilite")).to_int()
		var force := 3 if _first(pr.get("statut")) == "corrobore" else (2 if cred in [2, 3] else 1)
		out.append(_fact(names, who, place, date, "indice", force, str(n.name), str(n.path), "", "", cred))
	return out


## Les deux présences sont-elles à des endroits différents ? (voir l'en-tête)
static func elsewhere(a: Dictionary, b: Dictionary) -> bool:
	if str(a.where_key) == str(b.where_key):
		return false
	if str(a.lieu_key) != "" and str(b.lieu_key) != "":
		return str(a.lieu_key) != str(b.lieu_key)
	if str(a.domaine_key) != "" and str(b.domaine_key) != "":
		return str(a.domaine_key) != str(b.domaine_key)
	return false


## Libellé d'une présence : « présent (constaté) », « présent selon Rapport de Lise »…
static func how_label(f: Dictionary) -> String:
	if str(f.how) == "rapporte" and str(f.note) != "":
		return "présent selon %s" % f.note
	return str(HOW.get(str(f.how), f.how))


## Jours (« AAAA-MM-JJ ») où les présences données placent quelqu'un à deux
## endroits différents, ou présent et absent au même endroit : jour -> [présences].
static func conflicts(list: Array) -> Dictionary:
	var by_day := {}
	for f in list:
		if f.exact and (int(f.force) >= 2 or str(f.how) == "absent"):
			var d := str(f.first)
			if not by_day.has(d):
				by_day[d] = []
			by_day[d].append(f)
	var out := {}
	for d in by_day:
		var l: Array = by_day[d]
		var bad := false
		for i in l.size():
			for j in range(i + 1, l.size()):
				var a: Dictionary = l[i]
				var b: Dictionary = l[j]
				var abs_a: bool = str(a.how) == "absent"
				var abs_b: bool = str(b.how) == "absent"
				if abs_a != abs_b and str(a.where_key) == str(b.where_key):
					bad = true
				elif not abs_a and not abs_b and elsewhere(a, b):
					bad = true
		if bad:
			out[d] = l
	return out


static func _by_date_desc(a: Dictionary, b: Dictionary) -> bool:
	if str(a.first) != str(b.first):
		if str(a.first) == "" or str(b.first) == "":
			return str(b.first) == ""
		return str(a.first) > str(b.first)
	if int(a.force) != int(b.force):
		return int(a.force) > int(b.force)
	return TextNorm.fold(str(a.where)) < TextNorm.fold(str(b.where))


## Où était `name` : ses présences, des plus récentes aux plus anciennes (dates inconnues à la fin).
static func of_person(index: RefCounted, name: String, all_facts := []) -> Array:
	var src: Array = all_facts if not all_facts.is_empty() else facts(index)
	var k := TextNorm.name_key(name)
	var out := src.filter(func(f): return str(f.who_key) == k)
	out.sort_custom(_by_date_desc)
	return out


## Telle nuit (« AAAA-MM-JJ ») : présences datées de ce jour exactement.
## {day, places: [{where, where_path, where_type, lieu, domaine, facts}],
##  people: [{who, who_path, facts, conflict}], approx: [présences dont la date floue inclut ce jour]}
static func night(index: RefCounted, day: String, all_facts := []) -> Dictionary:
	var src: Array = all_facts if not all_facts.is_empty() else facts(index)
	var by_place := {}
	var by_who := {}
	var approx := []
	for f in src:
		if str(f.first) == "":
			continue
		if f.exact and str(f.first) == day:
			var pk := str(f.where_key)
			if not by_place.has(pk):
				by_place[pk] = {"where": f.where, "where_path": f.where_path, "where_type": f.where_type,
					"lieu": f.lieu, "domaine": f.domaine, "facts": []}
			by_place[pk].facts.append(f)
			if not by_who.has(f.who_key):
				by_who[f.who_key] = {"who": f.who, "who_path": f.who_path, "facts": [], "conflict": false}
			by_who[f.who_key].facts.append(f)
		elif not f.exact and str(f.first) <= day and day <= str(f.last) and str(f.how) != "absent" \
				and Dates.days_between(str(f.first), str(f.last)) <= 31:
			approx.append(f)
	for k in by_who:
		by_who[k].conflict = not conflicts(by_who[k].facts).is_empty()
	var pls: Array = by_place.values()
	for p in pls:
		p.facts.sort_custom(func(a, b): return int(a.force) > int(b.force) if int(a.force) != int(b.force) \
			else TextNorm.fold(str(a.who)) < TextNorm.fold(str(b.who)))
	pls.sort_custom(func(a, b): return a.facts.size() > b.facts.size() if a.facts.size() != b.facts.size() \
		else TextNorm.fold(str(a.where)) < TextNorm.fold(str(b.where)))
	var ppl: Array = by_who.values()
	ppl.sort_custom(func(a, b): return a.conflict if a.conflict != b.conflict else TextNorm.fold(str(a.who)) < TextNorm.fold(str(b.who)))
	approx.sort_custom(func(a, b): return TextNorm.fold(str(a.who)) < TextNorm.fold(str(b.who)))
	return {"day": day, "places": pls, "people": ppl, "approx": approx}


## Nuits où au moins une présence est datée au jour près, des plus récentes aux plus anciennes : [{day, count}].
static func nights(index: RefCounted, all_facts := []) -> Array:
	var src: Array = all_facts if not all_facts.is_empty() else facts(index)
	var n := {}
	for f in src:
		if f.exact:
			n[f.first] = int(n.get(f.first, 0)) + 1
	var out := []
	for d in n:
		out.append({"day": d, "count": n[d]})
	out.sort_custom(func(a, b): return str(a.day) > str(b.day))
	return out


## Incidents proposés : événements et soirées, des plus récents aux plus anciens.
## [{name, path, type, date, lieu, domaine, statut}]
static func incidents(index: RefCounted) -> Array:
	var out := []
	for p in places(index).values():
		if str(p.type) in ["evenement", "soiree"]:
			out.append(p)
	out.sort_custom(func(a, b):
		var da := Dates.sort_key(a.date)
		var db := Dates.sort_key(b.date)
		if da != db:
			return da > db
		return TextNorm.fold(str(a.name)) < TextNorm.fold(str(b.name)))
	return out


## Où en était chacun à un incident : {kind, force, facts, contradiction, other}.
## kind, par ordre de priorité :
##   sur_place : présent à l'incident lui-même, ou à son lieu le même jour ;
##   alibi : vu ailleurs la même nuit (incident daté au jour près) ;
##   absent : absence remarquée à cette soirée ;
##   compatible : à son lieu, à une date qui recouvre celle de l'incident sans être la même ;
##   parages : dans le même domaine la même nuit ;
##   "" : rien de connu.
static func _status(inc: Dictionary, list: Array) -> Dictionary:
	var ik := TextNorm.name_key(str(inc.name))
	var ilieu := TextNorm.name_key(str(inc.lieu)) if str(inc.lieu) != "" else ""
	var idom := TextNorm.name_key(str(inc.domaine)) if str(inc.domaine) != "" else ""
	var isp := Dates.span(inc.date)
	var iday: bool = Dates.is_day(inc.date)
	var ref := {"where_key": ik, "lieu_key": ilieu, "domaine_key": idom}
	var here := []
	var away := []
	var absent := []
	var compat := []
	var near := []
	var force := 0
	for f in list:
		if str(f.where_key) == ik:
			if str(f.how) == "absent":
				absent.append(f)
			else:
				here.append(f)
				force = maxi(force, int(f.force))
			continue
		if str(f.how) == "absent":
			continue
		var same_day: bool = iday and f.exact and str(f.first) == str(isp[0])
		if ilieu != "" and str(f.lieu_key) == ilieu and Dates.overlap(isp, [f.first, f.last]):
			if same_day:
				here.append(f)
				force = maxi(force, int(f.force))
			else:
				compat.append(f)
			continue
		if not same_day or int(f.force) < 2:
			continue
		if elsewhere(f, ref):
			away.append(f)
		elif idom != "" and str(f.domaine_key) == idom:
			near.append(f)
	var kind := ""
	if not here.is_empty():
		kind = "sur_place"
	elif not away.is_empty():
		kind = "alibi"
	elif not absent.is_empty():
		kind = "absent"
	elif not compat.is_empty():
		kind = "compatible"
	elif not near.is_empty():
		kind = "parages"
	var shown: Array = {"sur_place": here, "alibi": away, "absent": absent, "compatible": compat, "parages": near}.get(kind, [])
	return {"kind": kind, "force": force if kind == "sur_place" else 0, "facts": shown,
		"contradiction": kind == "sur_place" and (not away.is_empty() or not absent.is_empty()),
		"other": away + absent if kind == "sur_place" else []}


## Présences communes à plusieurs incidents (chemins de notes).
## {incidents: [{name, path, type, date, lieu, domaine}],
##  people: [{who, who_path, at: [statut par incident], count, near, away, force, all}]}
## count : incidents où il était sur place ; near : au même lieu à une date
## compatible, ou dans le domaine la même nuit ; away : vu ailleurs ou absent.
## Ordre : présents au plus d'incidents, puis dans les parages, puis les plus sûrs ;
## ceux qui ont un alibi passent après les autres à nombre égal.
static func common(index: RefCounted, paths: Array, all_facts := []) -> Dictionary:
	var src: Array = all_facts if not all_facts.is_empty() else facts(index)
	var pl := places(index)
	var incs := []
	for p in pl.values():
		if str(p.path) in paths:
			incs.append(p)
	incs.sort_custom(func(a, b): return Dates.sort_key(a.date) < Dates.sort_key(b.date))
	var by_who := {}
	for f in src:
		if not by_who.has(f.who_key):
			by_who[f.who_key] = []
		by_who[f.who_key].append(f)
	var people := []
	for k in by_who:
		var list: Array = by_who[k]
		var at := []
		var count := 0
		var near := 0
		var away := 0
		var force := 0
		for inc in incs:
			var st := _status(inc, list)
			at.append(st)
			match st.kind:
				"sur_place":
					count += 1
					force += int(st.force)
				"parages", "compatible":
					near += 1
				"alibi", "absent":
					away += 1
		if count + near == 0:
			continue
		people.append({"who": list[0].who, "who_path": list[0].who_path, "who_type": list[0].who_type, "at": at,
			"count": count, "near": near, "away": away, "force": force, "all": count == incs.size() and not incs.is_empty()})
	people.sort_custom(func(a, b):
		if a.count != b.count:
			return a.count > b.count
		if a.near != b.near:
			return a.near > b.near
		if a.away != b.away:
			return a.away < b.away
		if a.force != b.force:
			return a.force > b.force
		return TextNorm.fold(str(a.who)) < TextNorm.fold(str(b.who)))
	return {"incidents": incs, "people": people}
