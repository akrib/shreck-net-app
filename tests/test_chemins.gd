extends "res://tests/base.gd"
## Chemins les plus probables entre deux fiches (échelle de l'Amirauté).

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Paths := preload("res://core/analysis/paths.gd")

var index: RefCounted
var _n := 0


func _note(root: String, rel: String, type_name: String, props: String, body: String) -> void:
	_n += 1
	var prefix: String = {"personnage": "per", "source": "src", "groupe": "grp", "soiree": "soi", "domaine": "dom", "indice": "ind", "faveur": "fav"}[type_name]
	write_file(root + "/" + rel, "---\ntype: %s\nid: %s-%s\nschema: 1\n%s---\n%s" % [type_name, prefix, ("t%07d" % _n), props, body])


func _vault() -> String:
	var root := temp_dir("coffre-chemins")
	for n in ["Alice", "Bruno", "Chloé", "David", "Eva"]:
		_note(root, "Personnages/%s.md" % n, "personnage", "", "# %s\n" % n)
	_note(root, "Personnages/Menteur.md", "personnage", "fiabilite: E\n", "# Menteur\n")
	_note(root, "Groupes/Ventrue.md", "groupe", "nature: clan\n", "# Ventrue\n")
	_note(root, "Domaines/Ysère.md", "domaine", "", "# Ysère\n")
	# Source A : Alice — Bruno — Chloé, bien attesté ; deux fois le même lien dans la même note
	_note(root, "Sources/Notes/S1.md", "source", "nature: note\ntitre: S1\nfiabilite: A\ndate: 2026-01-10\n",
		"## Éléments\n- a [nature:: observe] [credibilite:: 2] [relation:: allie] [de:: [[Alice]]] [vers:: [[Bruno]]] ^el-aaaaaaa1\n" +
		"- a2 [nature:: observe] [credibilite:: 2] [relation:: allie] [de:: [[Alice]]] [vers:: [[Bruno]]] ^el-aaaaaaa2\n" +
		"- b [nature:: observe] [credibilite:: 2] [relation:: sert] [de:: [[Chloé]]] [vers:: [[Bruno]]] ^el-aaaaaaa3\n" +
		"- clan [nature:: observe] [credibilite:: 1] [relation:: membre_de] [de:: [[Alice]]] [vers:: [[Ventrue]]] ^el-aaaaaaa4\n" +
		"- clan [nature:: observe] [credibilite:: 1] [relation:: membre_de] [de:: [[Chloé]]] [vers:: [[Ventrue]]] ^el-aaaaaaa5\n")
	# Source B : Alice — David — Chloé, moins sûr
	_note(root, "Sources/Notes/S2.md", "source", "nature: conversation\ntitre: S2\nfiabilite: B\n",
		"## Éléments\n- c [nature:: rapporte] [credibilite:: 1] [relation:: contact_de] [de:: [[David]]] [vers:: [[Alice]]] ^el-bbbbbbb1\n" +
		"- d [nature:: rapporte] [credibilite:: 3] [relation:: chantage] [de:: [[David]]] [vers:: [[Chloé]]] ^el-bbbbbbb2\n")
	# Source C : lien direct très douteux, et une corroboration d'Alice — Bruno par une autre note
	_note(root, "Sources/Discord/S3.md", "source", "nature: discord\ntitre: S3\nfiabilite: E\n",
		"## Éléments\n- e [nature:: rumeur] [credibilite:: 5] [relation:: ennemi] [de:: [[Alice]]] [vers:: [[Chloé]]] ^el-ccccccc1\n")
	_note(root, "Sources/Notes/S4.md", "source", "nature: note\ntitre: S4\nfiabilite: C\n",
		"## Éléments\n- f [nature:: rapporte] [credibilite:: 3] [relation:: allie] [de:: [[Alice]]] [vers:: [[Bruno]]] ^el-ddddddd1\n" +
		"- g [nature:: rapporte] [credibilite:: 2] [par:: [[Menteur]]] [relation:: lie_a] [de:: [[Eva]]] [vers:: [[Alice]]] [date_faits:: 2015-03] ^el-ddddddd2\n")
	# Indice qui s'appuie sur S1 : ne renforce pas le lien Alice—Bruno au-delà de S1 lui-même
	_note(root, "Indices/Alice alliée de Bruno.md", "indice", "statut: corrobore\ncredibilite: 2\nrelation: allie\nde: \"[[Alice]]\"\nvers: \"[[Bruno]]\"\npour:\n  - \"[[S1#^el-aaaaaaa1]]\"\n", "# x\n")
	return root


func _prepare() -> void:
	var root := _vault()
	var db := OS.get_user_data_dir() + "/tests_tmp/chemins.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func test_table_amiraute() -> void:
	var t := Paths.table({})
	ok(_near(Paths.p_of(t, "A", 1), 0.9025), "A1 = 0,95 × 0,95")
	ok(_near(Paths.p_of(t, "F", 6), 0.25), "F6 neutre : 0,5 × 0,5")
	ok(_near(Paths.p_of(t, "", null), 0.25), "sans évaluation : comme F6")
	var t2 := Paths.table({"amiraute": {"fiabilite": {"A": 1.0, "Z": 0.3}, "credibilite": {"1": "0.9", "2": 7}}})
	ok(_near(t2.fiabilite.A, 1.0) and not t2.fiabilite.has("Z"), "la table du coffre remplace les valeurs connues")
	ok(_near(t2.credibilite["1"], 0.9) and _near(t2.credibilite["2"], 0.8), "valeur hors [0, 1] ignorée")


func test_chemins() -> void:
	_prepare()
	var r: Dictionary = Paths.find(index, "Alice", "[[Chloé]]", {})
	ok(r.ok and r.paths.size() >= 3, "au moins trois chemins : %s" % str(r.paths.size()))
	var best: Dictionary = r.paths[0]
	eq(best.nodes, ["alice", "bruno", "chloé"], "le meilleur passe par Bruno, pas par le clan")
	# Alice—Bruno : S1 (A2 = 0,76, deux fois dans la même note : compte une fois) ou S4 (C3 = 0,36)
	var ab: Dictionary = r.links[best.links[0]]
	# l'indice (crédibilité 2 = 0,8) ne fait qu'un avec S1 qu'il cite : max(0,8 ; 0,76), puis S4 indépendante
	ok(_near(ab.p, 1.0 - (1.0 - 0.8) * (1.0 - 0.36)), "corroboration par une autre note, indice non recompté : %f" % ab.p)
	eq(ab.att.size(), 4, "quatre attestations conservées pour l'affichage (dont l'indice)")
	ok(_near(best.p, ab.p * 0.76), "probabilité du chemin = produit des liens")
	eq(r.paths[1].nodes, ["alice", "david", "chloé"], "deuxième chemin : par David")
	eq(r.paths[2].nodes, ["alice", "chloé"], "troisième : le lien direct douteux")
	for i in range(1, r.paths.size()):
		ok(r.paths[i].p <= r.paths[i - 1].p + 1e-9, "chemins classés du plus probable au moins probable")
	var with_hubs: Dictionary = Paths.find(index, "Alice", "Chloé", {"structure": true})
	eq(with_hubs.paths[0].nodes, ["alice", "ventrue", "chloé"], "avec les clans : le clan relie tout le monde")
	var sans_allie: Dictionary = Paths.find(index, "Alice", "Chloé", {"exclure": ["allie"]})
	eq(sans_allie.paths[0].nodes, ["alice", "david", "chloé"], "relations exclues : plus par Bruno")
	var sur: Dictionary = Paths.find(index, "Alice", "Chloé", {"max_cred": 2})
	for p in sur.paths:
		for li in p.links:
			for at in sur.links[li].att:
				ok(int(at.cred) <= 2, "crédibilité maximale respectée")
	ok(not sur.paths.any(func(p): return p.nodes == ["alice", "chloé"]), "le lien douteux (5) est écarté")
	var strict: Dictionary = Paths.find(index, "Alice", "Chloé", {"sans_inevaluable": true, "k": 1})
	eq(strict.paths.size(), 1, "k = 1")
	var g := Paths.to_graph(r)
	ok(g.nodes.has("bruno") and g.nodes.has("david") and not g.nodes.has("ventrue"), "vue : les fiches des chemins seulement")
	var ranks := {}
	for e in g.edges:
		ranks[e.rank] = true
	ok(ranks.has(0) and ranks.has(1), "rang des chemins pour le dessin")
	var s1: Array = ab.att.filter(func(x): return x.note == "S1")
	ok(Paths.describe(s1[0]).contains("Alice est allié de Bruno — S1, 10 janvier 2026, A/2 (76 %)"), "texte d'une attestation : %s" % Paths.describe(s1[0]))
	eq(Paths.describe(ab.att[0]), "Alice est allié de Bruno (indice corroboré) — Alice alliée de Bruno, crédibilité 2 (80 %)", "texte d'un indice")
	index.close()


func test_fiabilite_de_la_personne_et_periode() -> void:
	_prepare()
	var atts := Paths.attestations(index, {})
	var eva := {}
	for a in atts:
		if a.a == "eva":
			eva = a
	eq(eva.get("fiab", ""), "E", "un élément dit par un informateur peu fiable prend sa fiabilité")
	var recent := Paths.attestations(index, {"depuis": "2020-01-01"})
	var found := false
	for a in recent:
		if a.a == "eva":
			found = true
	ok(not found, "filtre de période : un fait de 2015 est écarté")
	var none: Dictionary = Paths.find(index, "Eva", "Chloé", {"depuis": "2020-01-01"})
	ok(none.paths.is_empty() and none.error.contains("Eva"), "pas de chemin : explication — %s" % none.error)
	var same: Dictionary = Paths.find(index, "Eva", "eva", {})
	ok(not same.error.is_empty(), "mêmes fiches refusées")
	index.close()
