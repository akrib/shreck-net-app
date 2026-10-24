extends "res://tests/base.gd"
## Tableau des hypothèses concurrentes : les indices d'un dossier en colonnes,
## leurs éléments pour et contre en lignes, le moins contredit d'abord.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Hyp := preload("res://core/analysis/hypotheses.gd")

var index: RefCounted


func _prepare() -> String:
	var root := temp_dir("coffre-hypotheses")
	write_file(root + "/Personnages/Victor.md", "---\ntype: personnage\nid: per-4c400001\nschema: 1\n---\n")
	write_file(root + "/Sources/Notes/2026-10-12 Notes.md", "---\ntype: source\nid: src-4c400002\nschema: 1\nnature: note\nfiabilite: B\n---\n## Éléments\n"
		+ "- [[Victor]] porte l'insigne du Cercle. [nature:: observe] [credibilite:: 1] ^el-4c400003\n"
		+ "- [[Victor]] défend le Cercle en assemblée. [nature:: observe] [credibilite:: 2] ^el-4c400004\n"
		+ "- [[Victor]] a rencontré un émissaire rival en secret. [nature:: rumeur] [credibilite:: 4] ^el-4c400005\n"
		+ "- [[Victor]] a quitté la ville deux nuits. [nature:: rapporte] [credibilite:: 3] ^el-4c400006\n")
	write_file(root + "/Indices/Victor loyal au Cercle.md", "---\ntype: indice\nid: ind-4c400007\nschema: 1\nstatut: non_verifie\ncredibilite: 3\npour:\n"
		+ "  - \"[[2026-10-12 Notes#^el-4c400003]]\"\n  - \"[[2026-10-12 Notes#^el-4c400004]]\"\ncontre:\n  - \"[[2026-10-12 Notes#^el-4c400005]]\"\n---\n# Victor est loyal au Cercle\n")
	write_file(root + "/Indices/Victor agent double.md", "---\ntype: indice\nid: ind-4c400008\nschema: 1\nstatut: non_verifie\ncredibilite: 4\npour:\n"
		+ "  - \"[[2026-10-12 Notes#^el-4c400005]]\"\n---\n# Victor est un agent double\n")
	write_file(root + "/Dossiers/Dossier - Victor.md", "---\ntype: dossier\nid: dos-4c400009\nschema: 1\nstatut: ouvert\nquestion: À qui Victor rend-il des comptes ?\nindices:\n"
		+ "  - \"[[Victor loyal au Cercle]]\"\n  - \"[[Victor agent double]]\"\n---\n# À qui Victor rend-il des comptes ?\n\n## Éléments examinés\n- [[2026-10-12 Notes#^el-4c400006]]\n- [[Introuvable#^el-4c40000a]]\n")
	var db := OS.get_user_data_dir() + "/tests_tmp/hypotheses.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()
	return root


func test_tableau() -> void:
	_prepare()
	eq(Hyp.parse_ref("[[2026-10-12 Notes#^el-4c400003]]"), ["2026-10-12 Notes", "el-4c400003"], "lien d'élément lu")
	eq(Hyp.parse_ref("[[Victor]]"), ["", ""], "un lien de fiche n'est pas un élément")
	var t: Dictionary = Hyp.build(index, "Dossiers/Dossier - Victor.md")
	eq(t.question, "À qui Victor rend-il des comptes ?", "la question du dossier")
	eq(t.hypotheses.map(func(h): return h.name), ["Victor loyal au Cercle", "Victor agent double"], "les indices du dossier en colonnes")
	eq(t.rows.size(), 5, "trois éléments jugés, un examiné sans jugement, un introuvable")
	var by := {}
	for r in t.rows:
		by[r.block] = r
	eq(by["el-4c400005"].cells, {0: "contre", 1: "pour"}, "la rencontre secrète : contre la loyauté, pour l'agent double")
	ok(by["el-4c400005"].diagnostic and not by["el-4c400006"].diagnostic, "elle départage ; l'élément pas encore jugé, non")
	ok(by["el-4c40000a"].missing and not by["el-4c400006"].missing, "un lien vers un élément absent est signalé")
	ok(by["el-4c400006"].examined and not by["el-4c400005"].examined, "les éléments cités par le dossier sont marqués « examinés »")
	ok(is_equal_approx(by["el-4c400003"].weight, 0.8 * 0.95), "poids : fiabilité B (0,8) × crédibilité 1 (0,95)")
	eq(t.rows[0].diagnostic, true, "les éléments qui départagent d'abord")
	var h0: Dictionary = t.hypotheses[0]
	eq([h0.n_pour, h0.n_contre], [2, 1], "loyauté : deux pour, un contre")
	eq(t.ranking, [1, 0], "l'agent double, jamais contredit, passe devant la loyauté, contredite une fois")
	eq([Hyp.next_cell(""), Hyp.next_cell("pour"), Hyp.next_cell("contre")], ["pour", "contre", ""], "un appui fait tourner la case")
	index.close()


func test_ecritures() -> void:
	var root := _prepare()
	index.close()
	var AppService = load("res://core/app/app_service.gd")
	AppService.settings_file = "user://tests_tmp/reglages-hypotheses.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	var app: Node = AppService.new()
	app.background_jobs = false
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	IndexStore.delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()
	var dos := "Dossiers/Dossier - Victor.md"
	var loyal := "Indices/Victor loyal au Cercle.md"
	var ref := "[[2026-10-12 Notes#^el-4c400006]]"
	# juger « a quitté la ville » : incohérent avec la loyauté
	ok(app.set_hypothesis_cell(loyal, ref, "contre").ok, "jugement écrit")
	var t: Dictionary = Hyp.build(app.index, dos)
	var row: Array = t.rows.filter(func(r): return r.block == "el-4c400006")
	eq(row[0].cells, {0: "contre"}, "la case est relue depuis l'indice")
	ok(read(root + "/" + loyal).contains("- \"[[2026-10-12 Notes#^el-4c400006]]\""), "l'indice cite l'élément dans « contre »")
	# puis « pas jugé » : retiré des deux listes, rien d'autre ne bouge
	ok(app.set_hypothesis_cell(loyal, ref, "").ok, "case remise à « pas jugé »")
	var after := read(root + "/" + loyal)
	ok(not after.contains("el-4c400006") and after.contains("el-4c400003") and after.contains("el-4c400005"), "seul cet élément est retiré")
	# nouvelle hypothèse : un indice non vérifié, cité par le dossier
	var h: Dictionary = app.add_hypothesis(dos, "Victor sert le Prince")
	ok(h.ok and str(h.rel).begins_with("Indices/"), "hypothèse créée : " + str(h))
	ok(read(root + "/" + dos).contains("[[Victor sert le Prince]]"), "ajoutée aux indices du dossier")
	eq(Hyp.build(app.index, dos).hypotheses.size(), 3, "trois hypothèses dans le tableau")
	# élément à examiner : une ligne dans « Éléments examinés »
	ok(app.add_examined_element(dos, "[[2026-10-12 Notes#^el-4c400004]]").ok, "élément ajouté au dossier")
	ok(read(root + "/" + dos).contains("## Éléments examinés\n- [[2026-10-12 Notes#^el-4c400006]]\n- [[Introuvable#^el-4c40000a]]\n- [[2026-10-12 Notes#^el-4c400004]]"), "à la suite des autres")
	app.index.close()
	app.free()


func read(p: String) -> String:
	return FileAccess.get_file_as_string(p)
