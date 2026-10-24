extends RefCounted
## Alertes (A-FAIRE §2, piste 1), calculées depuis l'index ; rien n'est écrit.
##  - échéances : un élément `[jusqu_au:: …]` (reconnaissance, tance, nomination,
##    probation…) qui expire bientôt ou vient d'expirer ;
##  - faveurs réclamées dont le délai est dépassé (délais de la configuration du
##    coffre, section « faveurs », sinon ceux du format §9.11) ;
##  - sanctions en cours : Chasse au Sang, parjure, liste écarlate, paria, banni ;
##    et faveurs encore actives dont une partie est chassée ou parjure ;
##  - personnes surveillées (étiquette `surveille`) : nouveaux éléments depuis
##    la dernière consultation.
## Chaque alerte : {kind, level (urgent, attention, info), title, detail, path, date, key}.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Dates := preload("res://core/model/dates.gd")

const SOON_DAYS := 30          ## une échéance dans les 30 jours est signalée
const RECENT_DAYS := 30        ## une échéance passée depuis moins de 30 jours aussi
const SANCTIONS := {"chasse_au_sang": "urgent", "parjure": "attention", "liste_ecarlate": "attention",
	"paria": "attention", "banni": "attention"}
const LEVEL_ORDER := {"urgent": 0, "attention": 1, "info": 2}
## Délais par défaut après réclamation (FORMAT §9.11) : séances, mois ; null = non précisé.
const DELAIS := {"triviale": [1, 0], "mineure": [2, 1], "majeure": [6, 3], "sang": [null, null], "vie": [null, null]}


## « de Bruno », « d'Abel » : élision devant une voyelle ou un h.
static func de_nom(name: String) -> String:
	var c := TextNorm.fold(name.left(1))
	return ("d'" if c in ["a", "e", "i", "o", "u", "y", "h"] else "de ") + name


## Nombre de jours entre deux dates « AAAA-MM-JJ » (b − a).
static func days_between(a: String, b: String) -> int:
	var ua := Time.get_unix_time_from_datetime_string(a + "T00:00:00")
	var ub := Time.get_unix_time_from_datetime_string(b + "T00:00:00")
	return int(round(float(ub - ua) / 86400.0))


## Dernier jour couvert par une date floue (« 2026-12 » -> 2026-12-31), ou "" si inconnue.
static func end_day(edtf: String) -> String:
	var s := edtf.strip_edges()
	if s == "" or s == "inconnue" or s.ends_with("/.."):
		return ""
	if s.contains("/") and not s.begins_with("../"):
		s = s.split("/")[1]
	if s.begins_with("../"):
		s = s.substr(3)
	s = s.replace("~", "").replace("?", "").replace("%", "")
	var m := RegEx.create_from_string("^(\\d{4})(?:-(\\d{2}))?(?:-(\\d{2}))?$").search(s)
	if m == null:
		return ""
	var y := m.get_string(1).to_int()
	if m.get_string(3) != "":
		return "%04d-%s-%s" % [y, m.get_string(2), m.get_string(3)]
	if m.get_string(2) != "":
		var mo := m.get_string(2).to_int()
		var nd: int = [31, 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][clampi(mo - 1, 0, 11)]
		return "%04d-%02d-%02d" % [y, mo, nd]
	return "%04d-12-31" % y


## Ajoute `months` mois à une date « AAAA-MM-JJ ».
static func add_months(d: String, months: int) -> String:
	var y := d.substr(0, 4).to_int()
	var m := d.substr(5, 2).to_int() - 1 + months
	y += m / 12
	m = m % 12
	var day := d.substr(8, 2).to_int()
	var last := end_day("%04d-%02d" % [y, m + 1]).substr(8, 2).to_int()
	return "%04d-%02d-%02d" % [y, m + 1, mini(day, last)]


## Délais par niveau : ceux de la configuration (faveurs.niveaux), sinon ceux du format.
static func delais(config: Dictionary) -> Dictionary:
	var out := DELAIS.duplicate(true)
	var fav: Variant = config.get("faveurs", {})
	if typeof(fav) == TYPE_DICTIONARY and typeof(fav.get("niveaux")) == TYPE_ARRAY:
		for n in fav.niveaux:
			if typeof(n) == TYPE_DICTIONARY and n.has("code"):
				out[str(n.code)] = [n.get("delai_seances"), n.get("delai_mois")]
	return out


## Toutes les alertes à la date `today` (« AAAA-MM-JJ »). `seen` : {nom de
## personne surveillée -> horodatage unix de la dernière consultation}.
static func build(index: RefCounted, config: Dictionary, today: String, seen := {}) -> Array:
	var out := []
	_echeances(index, today, out)
	_faveurs(index, config, today, out)
	_sanctions(index, out)
	_surveilles(index, seen, out)
	out.sort_custom(func(a, b):
		if a.level != b.level:
			return LEVEL_ORDER[a.level] < LEVEL_ORDER[b.level]
		return str(a.sort) > str(b.sort))
	return out


static func _echeances(index: RefCounted, today: String, out: Array) -> void:
	var rel_labels := {"reconnait": "Reconnaissance", "sobriquet": "Tance", "nomme": "Nomination"}
	for e in index.rows("SELECT f.path, f.name AS note, e.block, e.text, e.relation, e.fields, e.cred FROM elements e JOIN files f ON f.fid = e.fid WHERE e.kind = 'el' AND e.fields LIKE '%jusqu_au%'"):
		var f: Variant = JSON.parse_string(str(e.fields))
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var until := str(f.get("jusqu_au", ""))
		var end := end_day(until)
		if end == "":
			continue
		var days := days_between(today, end)
		if days > SOON_DAYS or days < -RECENT_DAYS:
			continue
		var code := str(e.relation if e.relation != null else "")
		var what := ""
		if rel_labels.has(code):
			var q := Schema.display_text(str(f.get("qualificatif", "")))
			what = "%s%s %s par %s" % [rel_labels[code], (" « %s »" % q) if q != "" else "",
				de_nom(Schema.link_name(f.get("vers", ""))), Schema.link_name(f.get("de", ""))]
		else:
			what = Schema.display_text(str(e.text)).left(120)
		var when := ""
		if days > 1:
			when = "expire dans %d jours (%s)" % [days, Dates.label(until)]
		elif days == 1:
			when = "expire demain (%s)" % Dates.label(until)
		elif days == 0:
			when = "expire aujourd'hui"
		else:
			when = "a expiré il y a %d jour%s (%s)" % [-days, "s" if days < -1 else "", Dates.label(until)]
		out.append({"kind": "echeance", "level": "attention" if days >= 0 else "info",
			"title": what, "detail": when + " — " + str(e.note), "path": str(e.path), "date": end,
			"sort": end, "key": "echeance|%s|%s" % [e.path, e.block]})


static func _faveurs(index: RefCounted, config: Dictionary, today: String, out: Array) -> void:
	var dl := delais(config)
	# dernière réclamation de chaque faveur
	var claims := {}
	for m in index.rows("SELECT f.path, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE e.kind = 'mv' AND f.type = 'faveur'"):
		var f: Variant = JSON.parse_string(str(m.fields))
		if typeof(f) != TYPE_DICTIONARY or str(f.get("mv", "")) != "reclamation":
			continue
		var d := Dates.sort_key(str(f.get("date", ""))).replace("-00", "-01")
		if d != "" and d > str(claims.get(str(m.path), "")):
			claims[str(m.path)] = d
	# soirées par domaine, pour compter les séances depuis la réclamation
	var soirees := []
	for s in index.notes_with_props("soiree", ["date", "domaine"]):
		soirees.append({"date": str(s.props.get("date", "")), "dom": TextNorm.name_key(Schema.link_name(s.props.get("domaine", "")))})
	for n in index.notes_with_props("faveur", ["debiteur", "creancier", "niveau", "statut", "domaine", "date"]):
		var pr: Dictionary = n.props
		if str(pr.get("statut", "")) != "reclamee":
			continue
		var niv := str(pr.get("niveau", ""))
		var deb := Schema.link_name(pr.get("debiteur", ""))
		var cre := Schema.link_name(pr.get("creancier", ""))
		var claim := str(claims.get(str(n.path), ""))
		var title := "Faveur %s de %s envers %s, réclamée" % [Schema.option_label("faveur", "niveau", niv).to_lower(), deb, cre]
		if claim == "":
			out.append({"kind": "faveur", "level": "info", "title": title,
				"detail": "date de réclamation inconnue : ajoutez le mouvement « reclamation » pour suivre le délai", "path": str(n.path),
				"date": "", "sort": "", "key": "faveur|" + str(n.path)})
			continue
		var d: Array = dl.get(niv, [null, null])
		if d[0] == null and d[1] == null:
			continue  # délai non précisé (faveurs de sang, de vie)
		var dom := TextNorm.name_key(Schema.link_name(pr.get("domaine", "")))
		var seances := 0
		for s in soirees:
			if s.date > claim and s.date <= today and (dom == "" or s.dom == dom):
				seances += 1
		var mois_ok := d[1] == null or int(d[1]) <= 0 or today >= add_months(claim, int(d[1]))
		var seances_ok := d[0] == null or seances >= int(d[0])
		if mois_ok and seances_ok:
			var bits := PackedStringArray()
			if d[1] != null and int(d[1]) > 0:
				bits.append("%d mois" % int(d[1]))
			if d[0] != null:
				bits.append("%d séance%s" % [int(d[0]), "s" if int(d[0]) > 1 else ""])
			out.append({"kind": "faveur", "level": "urgent", "title": title,
				"detail": "délai dépassé : réclamée le %s, délai %s, %d séance(s) depuis" % [Dates.label(claim), " et ".join(bits), seances],
				"path": str(n.path), "date": claim, "sort": claim, "key": "faveur|" + str(n.path)})


static func _sanctions(index: RefCounted, out: Array) -> void:
	var hunted := {}
	for p in index.notes_with_props("personnage", ["sanctions", "statut"]):
		if str(p.props.get("statut", "")) == "mort_finale":
			continue
		var sv: Variant = p.props.get("sanctions", [])
		for s in (sv if typeof(sv) == TYPE_ARRAY else ([] if sv == null or str(sv) == "" else [sv])):
			var code := str(s)
			if not SANCTIONS.has(code):
				continue
			if code in ["chasse_au_sang", "parjure"]:
				hunted[TextNorm.name_key(str(p.name))] = Schema.option_label("personnage", "sanctions", code)
			out.append({"kind": "sanction", "level": SANCTIONS[code],
				"title": "%s : %s" % [p.name, Schema.option_label("personnage", "sanctions", code)],
				"detail": "sanction en cours (fiche du personnage)", "path": str(p.path), "date": "", "sort": "",
				"key": "sanction|%s|%s" % [p.path, code]})
	# faveurs encore actives dont une partie est chassée ou parjure
	if hunted.is_empty():
		return
	for n in index.notes_with_props("faveur", ["debiteur", "creancier", "statut"]):
		var pr: Dictionary = n.props
		if not str(pr.get("statut", "")) in ["active", "reclamee"]:
			continue
		for side in ["debiteur", "creancier"]:
			var who := Schema.link_name(pr.get(side, ""))
			var k := TextNorm.name_key(who)
			if hunted.has(k):
				out.append({"kind": "faveur", "level": "attention",
					"title": "Faveur encore active alors que %s est sous le coup d'une sanction (%s)" % [who, str(hunted[k]).to_lower()],
					"detail": "%s : à suspendre ou à annuler ?" % n.name, "path": str(n.path), "date": "", "sort": "",
					"key": "faveur-sanction|%s|%s" % [n.path, side]})


## Éléments qui citent une personne (hors de sa propre fiche) : [{path, note, mtime, block, text, key}].
static func mentions(index: RefCounted, name: String) -> Array:
	var own: String = index.path_of_name(name)
	var out := []
	for e in index.rows("SELECT DISTINCT f.path, f.name AS note, f.mtime, e.block, e.text FROM links l JOIN elements e ON e.fid = l.fid AND e.line = l.line JOIN files f ON f.fid = l.fid WHERE l.target_key = ? AND e.kind = 'el' ORDER BY f.mtime DESC", [TextNorm.name_key(name)]):
		if str(e.path) == own:
			continue
		var b := str(e.block if e.block != null else "")
		e["key"] = (str(e.path) + "#" + b) if b != "" else (str(e.path) + "@" + str(e.text))
		out.append(e)
	return out


## Nouveaux éléments sur les personnes surveillées (étiquette « surveille »).
## `seen[nom]` : {t: horodatage, k: [clés des éléments déjà vus]} ; sans
## consultation enregistrée, tous les éléments qui la citent sont nouveaux.
static func _surveilles(index: RefCounted, seen: Dictionary, out: Array) -> void:
	for r in index.rows("SELECT f.path, f.name FROM files f JOIN props p ON p.fid = f.fid WHERE p.key = 'tags' AND lower(p.value) = 'surveille'"):
		var name := str(r.name)
		var known := {}
		var s: Variant = seen.get(name, {})
		if typeof(s) == TYPE_DICTIONARY:
			for k in s.get("k", []):
				known[str(k)] = true
		var news := mentions(index, name).filter(func(e): return not known.has(str(e.key)))
		if news.is_empty():
			continue
		var first: Dictionary = news[0]
		out.append({"kind": "surveille", "level": "attention",
			"title": "%s : %d nouvel élément%s" % [name, news.size(), "s" if news.size() > 1 else ""],
			"detail": "dernier : « %s » — %s" % [Schema.display_text(str(first.text)).left(100), first.note],
			"path": str(r.path), "date": "", "sort": "", "key": "surveille|" + name, "person": name,
			"items": news})
