extends "res://tests/base.gd"
## Ajouts depuis les fiches (« + ») : membres d'un groupe, ligne d'élément,
## « Mes notes » du jour, dates conformes.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Members := preload("res://core/analysis/members.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const Dates := preload("res://core/model/dates.gd")


func _vault() -> String:
	var root := temp_dir("coffre-ajouts")
	write_file(root + "/Groupes/Cercle des Lanternes.md", "---\ntype: groupe\nid: grp-5a000001\nschema: 1\nnature: faction\n---\n")
	write_file(root + "/Groupes/Nosferatu.md", "---\ntype: groupe\nid: grp-5a000002\nschema: 1\nnature: clan\n---\n")
	write_file(root + "/Personnages/Victor.md", "---\ntype: personnage\nid: per-5a000003\nschema: 1\nclan: \"[[Nosferatu]]\"\n---\n")
	write_file(root + "/Personnages/Élise.md", "---\ntype: personnage\nid: per-5a000004\nschema: 1\n---\n")
	write_file(root + "/Personnages/Armand.md", "---\ntype: personnage\nid: per-5a000005\nschema: 1\n---\n")
	write_file(root + "/Groupes/Nosferatu antitribu.md", "---\ntype: groupe\nid: grp-5a00000a\nschema: 1\nnature: lignee\nclan: \"[[Nosferatu]]\"\n---\n")
	write_file(root + "/Personnages/Ancien.md", "---\ntype: personnage\nid: per-5a00000b\nschema: 1\nclan: \"[[Nosferatu antitribu]]\"\n---\n")
	write_file(root + "/Sources/Notes/2026-10-12 Notes.md", "---\ntype: source\nid: src-5a000006\nschema: 1\nnature: note\nfiabilite: B\n---\n## Éléments\n"
		+ "- [[Victor]] porte l'insigne du [[Cercle des Lanternes]]. [nature:: observe] [credibilite:: 2] [relation:: membre_de] [de:: [[Victor]]] [vers:: [[Cercle des Lanternes]]] ^el-5a000007\n"
		+ "- [[Élise]] préside le [[Cercle des Lanternes]]. [nature:: rapporte] [credibilite:: 3] [relation:: dirige] [de:: [[Élise]]] [vers:: [[Cercle des Lanternes]]] ^el-5a000008\n")
	write_file(root + "/Indices/Armand membre du Cercle.md", "---\ntype: indice\nid: ind-5a000009\nschema: 1\nstatut: refute\ncredibilite: 5\nrelation: membre_de\nde: \"[[Armand]]\"\nvers: \"[[Cercle des Lanternes]]\"\npour:\n  - \"[[2026-10-12 Notes#^el-5a000007]]\"\n---\n")
	return root


func test_membres_et_lignes() -> void:
	var root := _vault()
	var db := OS.get_user_data_dir() + "/tests_tmp/ajouts.sqlite"
	IndexStore.delete_files(db)
	var index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()
	var m: Array = Members.of_group(index, "Cercle des Lanternes")
	eq(m.map(func(x): return x.name), ["Élise", "Victor"], "qui dirige d'abord ; l'indice réfuté ne compte pas")
	eq([m[0].roles, m[1].roles], [["dirige"], ["membre"]], "rôles lus dans les éléments")
	ok(Members.describe(m[1]).contains("selon 2026-10-12 Notes (crédibilité 2)"), "la source est citée : " + Members.describe(m[1]))
	var clan: Array = Members.of_group(index, "Nosferatu")
	ok(clan.size() == 1 and clan[0].from_fiche and clan[0].roles == ["clan"], "un clan : les fiches qui le portent")
	var lig: Array = Members.of_group(index, "Nosferatu antitribu")
	ok(lig.size() == 1 and Members.describe(lig[0]) == "Ancien — lignée (fiche)", "une fiche qui porte la lignée en clan : « lignée (fiche) »")
	eq(StructuredLines.element_line(" [[Victor]] est membre de [[Cercle]]. ", {"relation": "membre_de", "nature": "rapporte", "credibilite": 3,
		"de": "[[Victor]]", "vers": "[[Cercle]]", "date_faits": "", "qualificatif": null}),
		"- [[Victor]] est membre de [[Cercle]]. [nature:: rapporte] [credibilite:: 3] [relation:: membre_de] [de:: [[Victor]]] [vers:: [[Cercle]]]",
		"ligne d'élément : champs dans l'ordre du format, vides omis")
	eq(StructuredLines.element_line("x", {"qualificatif": "[Avisé]"}), "- x [qualificatif:: Avisé]", "crochets retirés du qualificatif")
	for d in ["2026-10-14", "2026-10", "2026-10~", "2026-04~/..", "../2026-08", "2025/2026-09", "inconnue", "2026-XX"]:
		ok(Dates.is_valid(d), "date conforme : " + d)
	for d in ["octobre", "2026-13", "26-10", "2026-10-32", "2026-10-14 vers minuit"]:
		ok(not Dates.is_valid(d), "date refusée : " + d)
	index.close()


func test_mes_notes_du_jour() -> void:
	var root := _vault()
	var AppService = load("res://core/app/app_service.gd")
	AppService.settings_file = "user://tests_tmp/reglages-ajouts.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	var app: Node = AppService.new()
	app.background_jobs = false
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	IndexStore.delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()
	app.settings.set_value("saisie", "source_nature", "forum")
	var before: Dictionary = app.day_notes(false)
	ok(before.ok and before.rel == "" and str(before.name).ends_with("Note personnelle - Mes notes"), "pas encore de notes du jour : " + str(before.name))
	var line := StructuredLines.element_line("[[Armand]] est membre du [[Cercle des Lanternes]].", {"nature": "rapporte", "credibilite": 3,
		"relation": "membre_de", "de": "[[Armand]]", "vers": "[[Cercle des Lanternes]]"})
	var r: Dictionary = app.add_element_line("", line)
	ok(r.ok and r.created and str(r.rel).begins_with("Sources/Notes/"), "premier ajout : la note du jour est créée (%s)" % str(r.get("rel", r)))
	var text := FileAccess.get_file_as_string(root + "/" + r.rel)
	ok(text.contains("nature: note") and text.contains("fiabilite: B") and text.contains("## Éléments\n" + line + " ^" + r.block), "source « note personnelle », l'élément dans ses Éléments")
	eq(app.settings.get_value("saisie", "source_nature"), "forum", "la nature retenue pour le formulaire de source ne change pas")
	var r2: Dictionary = app.add_element_line("", StructuredLines.element_line("[[Élise]] a fait usage de [[Domination]].", {"nature": "observe", "credibilite": 2, "discipline": "[[Domination]]"}))
	ok(r2.ok and not r2.created and r2.rel == r.rel, "deuxième ajout : même note")
	var m: Array = Members.of_group(app.index, "Cercle des Lanternes")
	eq(m.map(func(x): return x.name), ["Élise", "Armand", "Victor"], "le nouveau membre est relu aussitôt")
	var r3: Dictionary = app.add_element_line("Sources/Notes/2026-10-12 Notes.md", "- [[Victor]] a quitté la ville. [nature:: rumeur] [credibilite:: 4]")
	ok(r3.ok and FileAccess.get_file_as_string(root + "/Sources/Notes/2026-10-12 Notes.md").contains("a quitté la ville. [nature:: rumeur] [credibilite:: 4] ^el-"), "ajout dans une source choisie")
	app.index.close()
	app.free()
