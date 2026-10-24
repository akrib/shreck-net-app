extends RefCounted
## Fiabilité calculée des informateurs (A-FAIRE §2) : l'application propose la
## lettre A–F d'un personnage d'après ce qu'il a affirmé et ce qu'il en est
## advenu. Rien n'est écrit : vous validez la lettre proposée.
##
## Ses affirmations : les éléments dont il est la voix — champ `par`, ou, sans
## `par`, auteur (sinon rapporteur) de la source. Natures retenues : observé,
## rapporté, rumeur ; les déductions et hypothèses ne sont pas les siennes.
##
## Ce qu'il en est advenu, par ordre de priorité :
##  1. les indices et événements qui citent l'élément dans `pour` ou `contre` :
##     pour + corroboré (ou obsolète, « c'était vrai ») = confirmé ;
##     pour + réfuté = réfuté ; contre + corroboré = réfuté ; contre + réfuté =
##     confirmé ; contesté ou non vérifié = non tranché ;
##  2. sinon, la crédibilité de l'élément : 1 (confirmée) = confirmé,
##     5 (improbable) = réfuté ; les autres ne tranchent pas.
##
## Lettre proposée (n = confirmées + réfutées, taux = confirmées / n) :
##   moins de 3 affirmations tranchées : F (ne peut être évaluée) ;
##   A : au moins 8 tranchées et aucune réfutée ; B : taux ≥ 0,8 ;
##   C : taux ≥ 0,6 ; D : taux ≥ 0,4 ; E : en dessous.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")

const MIN_JUDGED := 3
const STATEMENT_NATURES := ["observe", "rapporte", "rumeur"]


## Lettre proposée d'après les nombres d'affirmations confirmées et réfutées.
static func letter(confirmed: int, refuted: int) -> String:
	var n := confirmed + refuted
	if n < MIN_JUDGED:
		return "F"
	if n >= 8 and refuted == 0:
		return "A"
	var rate := float(confirmed) / float(n)
	if rate >= 0.8:
		return "B"
	if rate >= 0.6:
		return "C"
	if rate >= 0.4:
		return "D"
	return "E"


## Verdicts des indices et événements : clé « note#bloc » -> [verdict…]
## (« confirme », « refute », « ouvert ») avec la note qui tranche.
static func verdicts(index: RefCounted) -> Dictionary:
	var out := {}
	for t in ["indice", "evenement"]:
		for n in index.notes_with_props(t, ["pour", "contre", "statut"]):
			var st := str(n.props.get("statut", ""))
			for side in ["pour", "contre"]:
				var v: Variant = n.props.get(side, [])
				for ref in (v if typeof(v) == TYPE_ARRAY else ([] if v == null or str(v) == "" else [v])):
					var s := str(ref).strip_edges()
					if s.begins_with("[[") and s.ends_with("]]"):
						s = s.substr(2, s.length() - 4)
					var parts := s.split("|")[0].split("#")
					if parts.size() < 2 or not parts[1].begins_with("^"):
						continue
					var key := TextNorm.name_key(parts[0].get_file()) + "#" + parts[1].substr(1)
					var verdict := "ouvert"
					if st in ["corrobore", "obsolete"]:
						verdict = "confirme" if side == "pour" else "refute"
					elif st == "refute":
						verdict = "refute" if side == "pour" else "confirme"
					if not out.has(key):
						out[key] = []
					out[key].append({"verdict": verdict, "by": str(n.name), "path": str(n.path), "statut": st})
	return out


## Affirmations de tous les personnages : clé de nom -> [{path, note, block, text, cred, verdict, by}].
static func statements(index: RefCounted) -> Dictionary:
	var voice := {}   # chemin de source -> voix par défaut (auteur, sinon rapporteur)
	for n in index.notes_with_props("source", ["auteur", "rapporteur", "nature"]):
		if str(n.props.get("nature", "")) == "analyse":
			continue
		var who := Schema.link_name(n.props.get("auteur", ""))
		if who == "" or who == "Claude":
			who = Schema.link_name(n.props.get("rapporteur", ""))
		if who != "":
			voice[str(n.path)] = who
	var ver := verdicts(index)
	var out := {}
	for e in index.rows("SELECT f.path, f.name AS note, f.type, e.block, e.text, e.nature, e.cred, e.fields FROM elements e JOIN files f ON f.fid = e.fid WHERE e.kind = 'el'"):
		if not str(e.nature) in STATEMENT_NATURES:
			continue
		var f: Variant = JSON.parse_string(str(e.fields))
		if typeof(f) != TYPE_DICTIONARY:
			f = {}
		var who := Schema.link_name(f.get("par", ""))
		if who == "":
			who = str(voice.get(str(e.path), ""))
		if who == "":
			continue
		var block := str(e.block if e.block != null else "")
		var verdict := "ouvert"
		var by := ""
		var vs: Array = ver.get(TextNorm.name_key(str(e.note)) + "#" + block, []) if block != "" else []
		if not vs.is_empty():
			var kinds := {}
			for v in vs:
				kinds[v.verdict] = true
			if kinds.has("confirme") and not kinds.has("refute"):
				verdict = "confirme"
			elif kinds.has("refute") and not kinds.has("confirme"):
				verdict = "refute"
			by = ", ".join(PackedStringArray(vs.map(func(v): return str(v.by))))
		else:
			var c: int = int(e.cred) if e.cred != null else 6
			if c == 1:
				verdict = "confirme"
				by = "crédibilité 1"
			elif c == 5:
				verdict = "refute"
				by = "crédibilité 5"
		var k := TextNorm.name_key(who)
		if not out.has(k):
			out[k] = []
		out[k].append({"path": str(e.path), "note": str(e.note), "block": block, "text": str(e.text),
			"cred": e.cred, "verdict": verdict, "by": by, "who": who})
	return out


## Bilan d'un personnage : {name, path, current, proposed, confirmed, refuted, open, items}.
static func evaluate(index: RefCounted, name: String, all_statements := {}) -> Dictionary:
	var st: Dictionary = all_statements if not all_statements.is_empty() else statements(index)
	var items: Array = st.get(TextNorm.name_key(name), [])
	var path: String = index.path_of_name(name)
	var current := str(index.props_of(path).get("fiabilite", "")) if path != "" else ""
	var c := items.filter(func(x): return x.verdict == "confirme").size()
	var r := items.filter(func(x): return x.verdict == "refute").size()
	return {"name": name, "path": path, "current": current, "proposed": letter(c, r),
		"confirmed": c, "refuted": r, "open": items.size() - c - r, "items": items}


## Tous les informateurs (au moins une affirmation) : ceux dont la lettre
## proposée diffère de l'actuelle d'abord, puis les plus jugés, puis les plus bavards.
static func all(index: RefCounted) -> Array:
	var st := statements(index)
	var names: Dictionary = index.all_names()
	var out := []
	for k in st:
		var inf: Dictionary = names.get(k, {})
		if not inf.is_empty() and str(inf.get("type", "")) != "personnage":
			continue
		var nm: String = str(inf.get("name", st[k][0].who))
		out.append(evaluate(index, nm, st))
	out.sort_custom(func(a, b):
		var da: bool = a.proposed != a.current and a.proposed != "F"
		var db: bool = b.proposed != b.current and b.proposed != "F"
		if da != db:
			return da
		var na: int = a.confirmed + a.refuted
		var nb: int = b.confirmed + b.refuted
		if na != nb:
			return na > nb
		if a.items.size() != b.items.size():
			return a.items.size() > b.items.size()
		return TextNorm.fold(str(a.name)) < TextNorm.fold(str(b.name)))
	return out


## Phrase de bilan : « 5 confirmées, 1 réfutée, 2 non tranchées ».
static func summary(ev: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("%d confirmée%s" % [ev.confirmed, "s" if ev.confirmed > 1 else ""])
	parts.append("%d réfutée%s" % [ev.refuted, "s" if ev.refuted > 1 else ""])
	parts.append("%d non tranchée%s" % [ev.open, "s" if ev.open > 1 else ""])
	return ", ".join(parts)
