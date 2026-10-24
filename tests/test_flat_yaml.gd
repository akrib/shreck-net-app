extends "res://tests/base.gd"
## Parseur et écrivain du frontmatter, comparés à PyYAML (tools/yaml_reference.py).

const FlatYaml := preload("res://core/format/flat_yaml.gd")


func _typed(v: Variant) -> Array:
	match typeof(v):
		TYPE_NIL:
			return ["null"]
		TYPE_BOOL:
			return ["bool", v]
		TYPE_INT:
			return ["int", v]
		TYPE_FLOAT:
			return ["float", v]
		TYPE_STRING:
			return ["str", v]
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(_typed(x))
			return ["list", out]
	return ["?", str(v)]


func _norm_expected(v: Variant) -> Variant:
	# JSON lit tous les nombres comme des flottants : on remet les entiers.
	if typeof(v) == TYPE_ARRAY:
		if v.size() == 2 and str(v[0]) == "int":
			return ["int", int(v[1])]
		var out := []
		for x in v:
			out.append(_norm_expected(x))
		return out
	return v


func test_corpus_pyyaml() -> void:
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/yaml_cases.json"))
	ok(cases.size() >= 40, "corpus chargé (%d cas)" % cases.size())
	for c in cases:
		var lines: PackedStringArray = PackedStringArray() if c.yaml == "" else c.yaml.split("\n")
		var r := FlatYaml.parse(lines)
		match c.attendu:
			"ok":
				ok(r.ok, "« %s » doit être accepté (erreurs : %s)" % [c.nom, str(r.errors)])
				var got := {}
				for k in r.data:
					got[k] = _typed(r.data[k])
				var want := {}
				for k in c.valeur:
					want[k] = _norm_expected(c.valeur[k])
				ok(JSON.stringify(got, "", true) == JSON.stringify(want, "", true),
					"« %s » : %s ≠ PyYAML %s" % [c.nom, JSON.stringify(got), JSON.stringify(want)])
			"erreur":
				ok(not r.ok, "« %s » doit être refusé" % c.nom)
			"ambigu":
				ok(r.ok, "« %s » accepté" % c.nom)
				ok(r.warnings.size() > 0, "« %s » signalé comme ambigu" % c.nom)
				var got := {}
				for k in r.data:
					got[k] = _typed(r.data[k])
				ok(JSON.stringify(got) == JSON.stringify(c.valeur), "« %s » lu comme texte" % c.nom)


func test_messages_utiles() -> void:
	var r := FlatYaml.parse(PackedStringArray(["clan: [[Toreador]]"]))
	ok(not r.ok and str(r.errors[0].msg).contains("guillemets"), "message lien non entre guillemets")
	r = FlatYaml.parse(PackedStringArray(["a: 1", "b: x", "a: 2"]))
	eq(int(r.errors[0].line), 2, "ligne de la clé en double")


func test_aller_retour_ecriture() -> void:
	var valeurs := ["simple", "Élise « la Rouge »", "L'inconnu", "a: b", "#salon", "- tiret",
		"  espaces  ", "yes", "0042", "2026-10-10", "2026-09", "[[Victor Morel]]", "C#",
		"guillemet \" et \\ antislash", "ligne1\nligne2", "tab\tici", "", "null", "true", "3", "2.5",
		"1e3", "21h30", "émoji 🦇", "x".repeat(3000)]
	for v in valeurs:
		var lines := FlatYaml.dump_entry("cle", v)
		var r := FlatYaml.parse(lines)
		ok(r.ok, "écriture relisible : %s" % lines[0].left(60))
		eq(r.data.get("cle"), v, "aller-retour de « %s »" % v.left(40))
	var liste := ["[[A]]", "b", "c, d", ""]
	var r2 := FlatYaml.parse(FlatYaml.dump_entry("l", liste))
	eq(r2.data.get("l"), liste, "aller-retour d'une liste")
	eq(FlatYaml.dump_entry("d", "2026-10-10", "date")[0], "d: 2026-10-10", "date sans guillemets")
	eq(FlatYaml.dump_entry("v", [])[0], "v: []", "liste vide")
	eq(FlatYaml.dump_entry("n", null)[0], "n:", "valeur vide")
	eq(FlatYaml.dump_entry("b", true)[0], "b: true", "booléen")
	eq(FlatYaml.dump_entry("s", "simple")[0], "s: simple", "texte simple sans guillemets")


func test_patch_minimal() -> void:
	var src := PackedStringArray([
		"type: personnage",
		"# commentaire conservé",
		"aliases:",
		"  - Le Notaire",
		"clan: \"[[Toreador]]\"",
		"statut:   actif   ",
		"tags: [a, b]",
	])
	var parsed := FlatYaml.parse(src)
	ok(parsed.ok, "source lisible")
	var out := FlatYaml.patch(src, parsed, {"statut": "disparu"})
	eq(out.size(), src.size(), "même nombre de lignes")
	for i in src.size():
		if i != 5:
			eq(out[i], src[i], "ligne %d inchangée" % i)
	eq(out[5], "statut: disparu", "ligne modifiée")
	out = FlatYaml.patch(src, parsed, {"aliases": FlatYaml.REMOVE, "domaine": "[[Valombre]]"})
	ok(not "\n".join(out).contains("Le Notaire"), "liste supprimée")
	eq(out[out.size() - 1], "domaine: \"[[Valombre]]\"", "nouvelle propriété ajoutée à la fin")
	ok("\n".join(out).contains("# commentaire conservé"), "commentaire conservé")
	out = FlatYaml.patch(src, parsed, {"aliases": ["Le Notaire", "Le Silencieux"]})
	var r := FlatYaml.parse(out)
	eq(r.data.aliases, ["Le Notaire", "Le Silencieux"], "liste modifiée")
	eq(r.order, parsed.order, "ordre des clés conservé")


func test_style_obsidian() -> void:
	# Ce qu'Obsidian écrit couramment doit être lu sans erreur.
	var src := PackedStringArray([
		"tags:", "  - exemple", "aliases:", "  - \"[[X]]\"", "date: 2026-10-10",
		"moi_present: true", "credibilite: 2", "cssclasses: []", "vide:",
	])
	var r := FlatYaml.parse(src)
	ok(r.ok, "style Obsidian lu sans erreur : %s" % str(r.errors))
	eq(r.data.date, "2026-10-10", "date lue comme texte")
	eq(r.data.credibilite, 2, "nombre entier")
	eq(r.data.vide, null, "valeur vide")
