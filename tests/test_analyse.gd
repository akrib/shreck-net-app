extends "res://tests/base.gd"
## Graphe des relations et préparation de séance, sur le coffre d'exemple.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const GraphData := preload("res://core/analysis/graph_data.gd")
const SessionPrep := preload("res://core/analysis/session_prep.gd")

var index: RefCounted


func _prepare() -> void:
	var root := temp_dir("coffre-analyse")
	copy_tree(example_vault(), root)
	var db := OS.get_user_data_dir() + "/tests_tmp/analyse.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()


func test_graphe() -> void:
	_prepare()
	var g: Dictionary = GraphData.build(index, {"center": "Victor Morel", "depth": 1})
	ok(g.nodes.has("victor morel"), "le centre est dans le graphe")
	ok(g.nodes.has("cercle des lanternes"), "relation membre_de vers le Cercle des Lanternes")
	var kinds := {}
	for e in g.edges:
		kinds[e.kind] = true
	ok(kinds.has("relation") and kinds.has("faveur") and kinds.has("structure"), "relations, faveur et clan : %s" % str(kinds.keys()))
	var fav := false
	for e in g.edges:
		if e.kind == "faveur" and e.a == "victor morel" and e.b == "élise varga":
			fav = true
	ok(fav, "faveur orientée du débiteur vers le créancier")
	var g2: Dictionary = GraphData.build(index, {"center": "Victor Morel", "depth": 1, "faveurs": false, "structure": false})
	for e in g2.edges:
		ok(e.kind in ["relation", "indice"], "filtre : plus de faveur ni de clan (%s)" % e.kind)
	var g3: Dictionary = GraphData.build(index, {"center": "Victor Morel", "depth": 1, "copresence": true})
	var co := false
	for e in g3.edges:
		if e.kind == "copresence":
			co = true
	ok(co, "coprésence aux soirées")
	var all: Dictionary = GraphData.build(index, {"center": ""})
	ok(all.nodes.size() >= 4, "vue d'ensemble : %d fiches" % all.nodes.size())
	var strict: Dictionary = GraphData.build(index, {"center": "Victor Morel", "max_cred": 1, "faveurs": false, "structure": false})
	for e in strict.edges:
		ok(int(e.cred) <= 1, "crédibilité filtrée")
	index.close()


func test_preparation_de_seance() -> void:
	_prepare()
	var p: Dictionary = SessionPrep.build(index, "Valombre")
	eq(p.soirees, 1, "une soirée connue à Valombre")
	var names := []
	for e in p.people:
		names.append(e.name)
	ok(names.has("Victor Morel") and names.has("Élise Varga"), "personnes vues à Valombre : %s" % str(names))
	ok(p.faveurs.size() == 1, "la faveur en cours entre elles")
	ok(p.tasks.size() >= 1, "tâches ouvertes du domaine")
	ok(not p.questions.is_empty(), "questions ouvertes")
	var md := SessionPrep.to_markdown(p, "19/10/2026")
	ok(md.begins_with("# Préparation de séance — Valombre") and md.contains("## Faveurs en cours"), "version texte à copier")
	var later: Dictionary = SessionPrep.build(index, "Valombre", "2028-01-01")
	eq(later.people.size(), 0, "deux ans après : plus personne de probable")
	eq(later.others.size(), p.people.size() + p.others.size(), "tous passés dans les moins probables")
	var none: Dictionary = SessionPrep.build(index, "Ailleurs")
	eq(none.people.size(), 0, "domaine inconnu : rien")
	index.close()


func test_seance_morts_et_disparus() -> void:
	var root := temp_dir("coffre-seance")
	write_file(root + "/Domaines/Ici.md", "---\ntype: domaine\nid: dom-5ea00001\nschema: 1\n---\n")
	write_file(root + "/Soirees/2026/2026-10-10 Ici - Assemblée.md", "---\ntype: soiree\nid: soi-5ea00002\nschema: 1\ndate: 2026-10-10\ndomaine: \"[[Ici]]\"\npresents:\n  - \"[[Aline]]\"\n  - \"[[Bruno]]\"\n  - \"[[Cyril]]\"\n---\n")
	write_file(root + "/Soirees/2026/2026-09-10 Ici - Assemblée.md", "---\ntype: soiree\nid: soi-5ea00008\nschema: 1\ndate: 2026-09-10\ndomaine: \"[[Ici]]\"\npresents:\n  - \"[[Bruno]]\"\n---\n")
	write_file(root + "/Soirees/2020/2020-01-10 Ici - Assemblée.md", "---\ntype: soiree\nid: soi-5ea00003\nschema: 1\ndate: 2020-01-10\ndomaine: \"[[Ici]]\"\npresents:\n  - \"[[Denis]]\"\n---\n")
	write_file(root + "/Personnages/Aline.md", "---\ntype: personnage\nid: per-5ea00004\nschema: 1\nstatut: mort_finale\nsanctions:\n  - chasse_au_sang\n---\n")
	write_file(root + "/Personnages/Bruno.md", "---\ntype: personnage\nid: per-5ea00005\nschema: 1\nstatut: actif\nsanctions:\n  - chasse_au_sang\n---\n")
	write_file(root + "/Personnages/Cyril.md", "---\ntype: personnage\nid: per-5ea00006\nschema: 1\nstatut: actif\n---\n")
	write_file(root + "/Personnages/Denis.md", "---\ntype: personnage\nid: per-5ea00007\nschema: 1\nstatut: disparu\n---\n")
	var db := OS.get_user_data_dir() + "/tests_tmp/seance.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()
	var contra := [{"who": ["Bruno", "Zoé"], "title": "Bruno et Zoé : la même personne ?", "paths": ["Personnages/Bruno.md"]},
		{"who": ["Xavier", "Yves"], "title": "Xavier et Yves : la même personne ?", "paths": ["Personnages/Xavier.md"]}]
	var p: Dictionary = SessionPrep.build(index, "Ici", "2026-10-20", contra)
	var pn: Array = p.people.map(func(e): return e.name)
	pn.sort()
	eq(pn, ["Bruno", "Cyril"], "morts et disparus écartés des personnes probables")
	var qs: Array = p.questions.map(func(q): return q.text)
	eq(qs, ["À trancher : Bruno et Zoé : la même personne ?", "Sur Bruno (vu(e) 2 fois) : clan, statut d'âge ?"],
		"questions : le point à trancher qui touche une personne probable, puis les trous de la fiche de qui est venu deux fois")
	eq(p.gone.size(), 2, "mais gardés à part")
	eq(SessionPrep.presence_kind(p.people[0]), "vue", "présence notée dans vos présents : « vue »")
	eq(SessionPrep.presence_kind({"count": 2, "sure": false, "reported": 2}), "rapportée", "seulement par des comptes rendus : « rapportée »")
	eq(SessionPrep.presence_kind({"count": 1, "sure": false, "reported": 0}), "incertaine", "seulement en présence incertaine")
	eq(SessionPrep.presence_kind({"count": 0}), "rattachée", "jamais vue : fiche du domaine")
	var texts: Array = p.alerts.map(func(a): return a.text)
	ok(texts.has("Bruno : Chasse au Sang"), "sanction d'une personne en vie : %s" % str(texts))
	ok(texts.has("Aline : mort finale (vu(e) le 2026-10-10)"), "mort récente rappelée, sans sa sanction")
	ok(not texts.any(func(t): return str(t).begins_with("Denis")), "disparu depuis des années : pas d'alerte")
	eq(texts.size(), 2, "deux alertes seulement")
	index.close()
