extends RefCounted
## Dates exactes et floues (FORMAT §7, sous-ensemble d'EDTF) : clé de tri et
## libellé lisible. Une date incertaine n'est jamais convertie en date exacte :
## la clé de tri sert seulement à ordonner la chronologie.

const MONTHS := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
	"septembre", "octobre", "novembre", "décembre"]


## Clé triable « AAAA-MM-JJ » (00 pour une partie inconnue). « inconnue » -> "".
static func sort_key(edtf: Variant) -> String:
	var s := str(edtf if edtf != null else "").strip_edges()
	if s == "" or s == "inconnue":
		return ""
	var part := s
	if s.begins_with("../"):
		part = s.substr(3)
	elif s.contains("/"):
		part = s.split("/")[0]
	part = part.replace("~", "").replace("?", "").replace("%", "").replace("X", "0")
	var bits := part.split("-")
	var y := bits[0] if bits.size() > 0 else "0000"
	var m := bits[1] if bits.size() > 1 else "00"
	var d := bits[2] if bits.size() > 2 else "00"
	return "%s-%s-%s" % [y.lpad(4, "0"), m.lpad(2, "0"), d.lpad(2, "0")]


## Libellé : « 10 octobre 2026 », « vers octobre 2026 », « depuis mars 2026 »…
static func label(edtf: Variant) -> String:
	var s := str(edtf if edtf != null else "").strip_edges()
	if s == "" or s == "inconnue":
		return "date inconnue"
	if s.begins_with("../"):
		return "avant " + _one(s.substr(3))
	if s.ends_with("/.."):
		return "depuis " + _one(s.substr(0, s.length() - 3))
	if s.contains("/"):
		var p := s.split("/")
		return "de %s à %s" % [_one(p[0]), _one(p[1])]
	return _one(s)


static func _one(s: String) -> String:
	var q := ""
	var core := s
	if core.ends_with("%"):
		q = " (vers, incertain)"
		core = core.trim_suffix("%")
	elif core.ends_with("~"):
		core = core.trim_suffix("~")
		return "vers " + _plain(core)
	elif core.ends_with("?"):
		q = " ?"
		core = core.trim_suffix("?")
	return _plain(core) + q


static func _plain(s: String) -> String:
	var b := s.split("-")
	if b.size() >= 3 and b[2] != "XX" and b[1] != "XX":
		return "%d %s %s" % [b[2].to_int(), _month(b[1]), b[0]]
	if b.size() >= 2 and b[1] != "XX":
		return "%s %s" % [_month(b[1]), b[0]]
	if b[0].ends_with("XX"):
		return "au %se siècle" % str(b[0].substr(0, 2).to_int() + 1)
	return b[0]


static func _month(m: String) -> String:
	var k := m.to_int()
	return MONTHS[k - 1] if k >= 1 and k <= 12 else m


## En-tête de groupe de la chronologie : « octobre 2026 », « 2026 », « date inconnue ».
static func group_label(key: String) -> String:
	if key == "":
		return "Date inconnue"
	var y := key.substr(0, 4)
	var m := key.substr(5, 2).to_int()
	if m >= 1 and m <= 12:
		return "%s %s" % [MONTHS[m - 1].capitalize(), y]
	return y


## Jours couverts par une date floue : [premier, dernier] (« AAAA-MM-JJ »), ou
## ["", ""] si elle est inconnue. « 2026-10 » couvre le mois ; « 2026-04/.. »
## (depuis) va jusqu'à 9999-12-31 ; « ../2026-03 » (avant) part de 0000-01-01.
## « vers » (~) et « incertain » (?, %) gardent la même étendue.
static func span(edtf: Variant) -> Array:
	var s := str(edtf if edtf != null else "").strip_edges()
	if s == "" or s == "inconnue":
		return ["", ""]
	var a := s
	var b := s
	if s.contains("/"):
		var p := s.split("/")
		a = p[0]
		b = p[1] if p.size() > 1 else ".."
	var first := "0000-01-01" if a == ".." else _bound(a, false)
	var last := "9999-12-31" if b == ".." else _bound(b, true)
	if first == "" or last == "":
		return ["", ""]
	return [first, last]


## Date au jour près, sans approximation (« 2026-10-14 »).
static func is_day(edtf: Variant) -> bool:
	var s := str(edtf if edtf != null else "").strip_edges()
	return RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(s) != null


## Deux étendues [premier, dernier] se recouvrent-elles ? (fausse si l'une est inconnue)
static func overlap(a: Array, b: Array) -> bool:
	if a.size() < 2 or b.size() < 2 or str(a[0]) == "" or str(b[0]) == "":
		return false
	return str(a[0]) <= str(b[1]) and str(b[0]) <= str(a[1])


static func days_in_month(y: int, m: int) -> int:
	return [31, 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][clampi(m - 1, 0, 11)]


static func _bound(s: String, end: bool) -> String:
	var c := s.replace("~", "").replace("?", "").replace("%", "")
	var b := c.split("-")
	if b[0].length() != 4:
		return ""
	var y := b[0].replace("X", "9" if end else "0")
	if not y.is_valid_int():
		return ""
	var mo := b[1] if b.size() > 1 and not b[1].contains("X") else ""
	var d := b[2] if b.size() > 2 and mo != "" and not b[2].contains("X") else ""
	if (mo != "" and not (mo.is_valid_int() and mo.length() == 2)) or (d != "" and not (d.is_valid_int() and d.length() == 2)):
		return ""
	if not end:
		return "%s-%s-%s" % [y, mo if mo != "" else "01", d if d != "" else "01"]
	if mo == "":
		return y + "-12-31"
	if d != "":
		return "%s-%s-%s" % [y, mo, d]
	return "%s-%s-%02d" % [y, mo, days_in_month(y.to_int(), mo.to_int())]


## Nombre de jours entre deux dates « AAAA-MM-JJ » (b − a).
static func days_between(a: String, b: String) -> int:
	var ua := Time.get_unix_time_from_datetime_string(a + "T00:00:00")
	var ub := Time.get_unix_time_from_datetime_string(b + "T00:00:00")
	return int(round(float(ub - ua) / 86400.0))
