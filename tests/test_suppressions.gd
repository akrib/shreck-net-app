extends "res://tests/base.gd"
## Suppressions ciblées (boutons × des fiches) : une seule ligne, un seul lien,
## gardés dans le journal et restaurables.

const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")

const SRC := "Sources/Notes/2026-10-12 Notes.md"


func _app() -> Array:
	var root := temp_dir("coffre-suppressions")
	write_file(root + "/Personnages/Victor.md", "---\ntype: personnage\nid: per-7c000001\nschema: 1\nclan: \"[[Toreador]]\"\n---\n")
	write_file(root + "/Personnages/Élise.md", "---\ntype: personnage\nid: per-7c000002\nschema: 1\n---\n")
	write_file(root + "/Groupes/Toreador.md", "---\ntype: groupe\nid: grp-7c000003\nschema: 1\nnature: clan\n---\n")
	write_file(root + "/" + SRC, "---\ntype: source\nid: src-7c000004\nschema: 1\nnature: note\nfiabilite: B\n---\n## Éléments\n"
		+ "- [[Victor]] est allié d'[[Élise]]. [nature:: rapporte] [credibilite:: 3] [relation:: allie] [de:: [[Victor]]] [vers:: [[Élise]]] ^el-7c000005\n"
		+ "    - sous-point : vu deux fois\n"
		+ "- [[Victor]] boite. [nature:: observe] [credibilite:: 2] ^el-7c000006\n"
		+ "- [[Élise]] sourit. [nature:: observe] [credibilite:: 2]\n"
		+ "\n## Notes\nTexte libre.\n")
	write_file(root + "/Indices/Victor allié d'Élise.md", "---\ntype: indice\nid: ind-7c000007\nschema: 1\nstatut: non_verifie\ncredibilite: 3\npour:\n  - \"[[2026-10-12 Notes#^el-7c000005]]\"\n---\n")
	write_file(root + "/Soirees/2026/2026-10-10 Valombre - Assemblée.md", "---\ntype: soiree\nid: soi-7c000008\nschema: 1\ndate: 2026-10-10\ndomaine: \"[[Valombre]]\"\npresents:\n  - \"[[Victor]]\"\n  - \"[[Élise]]\"\n---\n## Éléments\n")
	var AppService = load("res://core/app/app_service.gd")
	AppService.settings_file = "user://tests_tmp/reglages-suppressions.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	var app: Node = AppService.new()
	app.background_jobs = false
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	IndexStore.delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()
	return [app, root]


func test_ligne_et_lien() -> void:
	var a := _app()
	var app: Node = a[0]
	var root: String = a[1]
	var cites: Array = app.element_citations(SRC, "el-7c000005")
	ok(cites.size() == 1 and str(cites[0].name) == "Victor allié d'Élise", "un élément cité par un indice : la citation est trouvée")
	var r: Dictionary = app.remove_element(SRC, "el-7c000005", "")
	var txt := FileAccess.get_file_as_string(root + "/" + SRC)
	ok(r.ok and not txt.contains("est allié") and not txt.contains("sous-point"), "la ligne et son sous-point sont retirés")
	ok(txt.contains("[[Victor]] boite.") and txt.contains("[[Élise]] sourit.") and txt.contains("## Notes\nTexte libre."), "le reste de la note est intact")
	var r2: Dictionary = app.remove_element(SRC, "", "[[Élise]] sourit.")
	ok(r2.ok and not FileAccess.get_file_as_string(root + "/" + SRC).contains("sourit"), "un élément sans identifiant : retrouvé par son énoncé")
	ok(not app.remove_element(SRC, "el-7c000005", "").ok, "une seconde fois : introuvable, rien n'est écrit")
	var sv := "Soirees/2026/2026-10-10 Valombre - Assemblée.md"
	var r3: Dictionary = app.remove_link(sv, "presents", "Élise")
	var stxt := FileAccess.get_file_as_string(root + "/" + sv)
	ok(r3.ok and stxt.contains("presents:\n  - \"[[Victor]]\"\n") and not stxt.contains("Élise"), "un seul présent retiré")
	var r4: Dictionary = app.remove_link("Personnages/Victor.md", "clan", "Toreador")
	ok(r4.ok and not FileAccess.get_file_as_string(root + "/Personnages/Victor.md").contains("Toreador"), "une valeur seule : la propriété est vidée")
	var j: Array = app.removed_lines()
	eq(j.map(func(x): return str(x.entry.kind)), ["prop", "prop", "element", "element"], "le journal garde tout, le plus récent d'abord")
	# restaurer la première ligne retirée (l'alliance) et le présent
	var first: Dictionary = j.filter(func(x): return str(x.entry.get("block", "")) == "el-7c000005")[0]
	ok(app.restore_removed(int(first.i)).ok, "restauration de la ligne")
	txt = FileAccess.get_file_as_string(root + "/" + SRC)
	ok(txt.contains("- [[Victor]] est allié d'[[Élise]]. [nature:: rapporte] [credibilite:: 3] [relation:: allie] [de:: [[Victor]]] [vers:: [[Élise]]] ^el-7c000005\n    - sous-point : vu deux fois\n"),
		"la ligne revient avec son sous-point, dans Éléments")
	var pres: Dictionary = app.removed_lines().filter(func(x): return str(x.entry.get("key", "")) == "presents")[0]
	ok(app.restore_removed(int(pres.i)).ok and FileAccess.get_file_as_string(root + "/" + sv).contains("\"[[Élise]]\""), "le présent revient")
	eq(app.removed_lines().size(), 2, "le journal ne garde que ce qui n'est pas restauré")
	app.index.close()
	app.free()
