extends "res://tests/base.gd"
## Fiabilité calculée des informateurs.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Informants := preload("res://core/analysis/informants.gd")

var index: RefCounted
var _n := 0


func _note(root: String, rel: String, type_name: String, props: String, body: String) -> void:
	_n += 1
	var prefix: String = {"personnage": "per", "source": "src", "soiree": "soi", "domaine": "dom", "indice": "ind", "evenement": "evt"}[type_name]
	write_file(root + "/" + rel, "---\ntype: %s\nid: %s-f%07d\nschema: 1\n%s---\n%s" % [type_name, prefix, _n, props, body])


func _prepare() -> void:
	var root := temp_dir("coffre-informateurs")
	_note(root, "Personnages/Alix.md", "personnage", "fiabilite: C\n", "# Alix\n")
	_note(root, "Personnages/Bruno.md", "personnage", "", "# Bruno\n")
	_note(root, "Personnages/Chloé.md", "personnage", "", "# Chloé\n")
	_note(root, "Domaines/Ysère.md", "domaine", "", "# Ysère\n")
	var lines := ""
	for i in range(1, 8):
		lines += "- affirmation %d [nature:: rapporte] [credibilite:: 3] ^el-alix000%d\n" % [i, i]
	_note(root, "Sources/Conversations/S1.md", "source", "nature: conversation\ntitre: S1\nfiabilite: C\ndate: 2026-10-01\nauteur: \"[[Alix]]\"\n", "## Éléments\n" + lines)
	var ind := func(name: String, statut: String, pour: Array, contre: Array) -> void:
		var p := "statut: %s\ncredibilite: 2\npour:\n" % statut
		for x in pour:
			p += "  - \"[[S1#^%s]]\"\n" % x
		if not contre.is_empty():
			p += "contre:\n"
			for x in contre:
				p += "  - \"[[S1#^%s]]\"\n" % x
		_note(root, "Indices/%s.md" % name, "indice", p, "# %s\n" % name)
	ind.call("I1", "corrobore", ["el-alix0001", "el-alix0002", "el-alix0007"], [])
	ind.call("I2", "refute", ["el-alix0003"], [])
	ind.call("I3", "corrobore", ["el-alix0006"], ["el-alix0004"])
	ind.call("I4", "refute", ["el-alix0007"], ["el-alix0005"])
	ind.call("I5", "conteste", ["el-alix0007"], [])
	_note(root, "Soirees/2026/2026-10-10 Ysère - Assemblée.md", "soiree", "date: 2026-10-10\ndomaine: \"[[Ysère]]\"\nfiabilite: A\n",
		"## Éléments\n" +
		"- b1 [nature:: rapporte] [credibilite:: 1] [par:: [[Bruno]]] ^el-bruno001\n" +
		"- b2 [nature:: rapporte] [credibilite:: 1] [par:: [[Bruno]]] ^el-bruno002\n" +
		"- b3 [nature:: rumeur] [credibilite:: 1] [par:: [[Bruno]]] ^el-bruno003\n" +
		"- b4 [nature:: rapporte] [credibilite:: 3] [par:: [[Bruno]]] ^el-bruno004\n" +
		"- b5 [nature:: hypothese] [credibilite:: 5] [par:: [[Bruno]]] ^el-bruno005\n" +
		"- c1 [nature:: rapporte] [credibilite:: 1] [par:: [[Chloé]]] ^el-chloe001\n" +
		"- moi [nature:: observe] [credibilite:: 1] ^el-moi00001\n")
	_note(root, "Sources/Notes/S2.md", "source", "nature: note\ntitre: S2\nfiabilite: B\ndate: 2026-10-02\nrapporteur: \"[[Chloé]]\"\n",
		"## Éléments\n- c2 [nature:: rapporte] [credibilite:: 5] ^el-chloe002\n")
	_note(root, "Sources/Analyses/A.md", "source", "nature: analyse\ntitre: A\nfiabilite: F\ndate: 2026-10-03\nauteur: Claude\n",
		"## Éléments\n- d [nature:: deduction] [credibilite:: 1] ^el-claude01\n")
	var db := OS.get_user_data_dir() + "/tests_tmp/informateurs.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()


func test_lettre() -> void:
	eq(Informants.letter(1, 1), "F", "moins de 3 affirmations tranchées : F")
	eq(Informants.letter(8, 0), "A", "8 confirmées, aucune réfutée : A")
	eq(Informants.letter(7, 0), "B", "7 confirmées seulement : B")
	eq(Informants.letter(4, 1), "B", "80 % : B")
	eq(Informants.letter(3, 2), "C", "60 % : C")
	eq(Informants.letter(2, 2), "D", "50 % : D")
	eq(Informants.letter(1, 3), "E", "25 % : E")


func test_informateurs() -> void:
	_prepare()
	var alix := Informants.evaluate(index, "Alix")
	eq([alix.confirmed, alix.refuted, alix.open], [4, 2, 1], "Alix : pour+corroboré, contre+réfuté = confirmées ; pour+réfuté, contre+corroboré = réfutées ; verdicts contradictoires = non tranché")
	ok(alix.current == "C" and alix.proposed == "C", "Alix : C proposé, C actuel")
	var bruno := Informants.evaluate(index, "Bruno")
	eq([bruno.confirmed, bruno.refuted, bruno.open], [3, 0, 1], "Bruno : crédibilité 1 = confirmée ; ses hypothèses ne comptent pas")
	eq(bruno.proposed, "B", "Bruno : B (3 sur 3, mais moins de 8 pour un A)")
	var chloe := Informants.evaluate(index, "Chloé")
	eq([chloe.confirmed, chloe.refuted], [1, 1], "Chloé : par:: dans une soirée, et rapporteur d'une source")
	eq(chloe.proposed, "F", "Chloé : trop peu pour juger")
	var all := Informants.all(index)
	eq(all.map(func(x): return x.name), ["Bruno", "Alix", "Chloé"], "la liste : proposition différente de l'actuelle d'abord")
	ok(not Informants.statements(index).has("claude"), "une analyse n'est pas un informateur")
	eq(Informants.summary(alix), "4 confirmées, 2 réfutées, 1 non tranchée", "bilan lisible")
	index.close()
