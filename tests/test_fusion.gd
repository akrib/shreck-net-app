extends "res://tests/base.gd"
## Fusion de deux fiches : un inconnu identifié est repris dans la bonne fiche,
## les liens suivent, rien n'est supprimé.

const AppService := preload("res://core/app/app_service.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Fusion := preload("res://core/app/fusion.gd")

var app: Node
var root := ""
const SOIREE := "Soirees/2026/2026-10-10 Valombre - Assemblée.md"
const INCONNU := "Personnages/Inconnu - Manteau gris.md"
const VICTOR := "Personnages/Victor Morel.md"


func _prepare() -> void:
	AppService.settings_file = "user://tests_tmp/reglages-fusion.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	root = temp_dir("coffre-fusion")
	copy_tree(example_vault(), root)
	app = AppService.new()
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	preload("res://core/index/index_store.gd").delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()


func _text(rel: String) -> String:
	return FileAccess.get_file_as_string(root + "/" + rel)


func test_reecriture_des_liens() -> void:
	var r := Fusion.rewrite_links("a [[Old]] b [[old|l'autre]] c ![[Old#^el-1]] [[Oldie]]\n```\n[[Old]]\n```", "old", "Old", "New")
	eq(r.text, "a [[New|Old]] b [[New|l'autre]] c ![[New#^el-1|Old]] [[Oldie]]\n```\n[[Old]]\n```", "texte affiché conservé, code intact")
	eq(r.count, 3, "trois liens réécrits")
	eq(Fusion.rewrite_links("[[Old]]", "old", "Old", "New", true).text, "[[New]]", "valeur de propriété : lien nu")
	var sp := Fusion.split_old_body("# Titre\n\nTexte.\n## Notes\nN\n### Sous\nS\n## Éléments\n- e [nature:: observe] [credibilite:: 2] ^el-aaaaaaaa\n\n## Fin\nF")
	eq(sp.elements, ["- e [nature:: observe] [credibilite:: 2] ^el-aaaaaaaa"], "éléments repris tels quels")
	eq(sp.text, "Texte.\n### Notes\nN\n#### Sous\nS\n### Fin\nF", "titres abaissés, titre principal retiré")


func test_fusion() -> void:
	_prepare()
	var before_inconnu := _text(INCONNU)
	var plan: Dictionary = app.merge_plan("Inconnu - Manteau gris", "Victor Morel")
	ok(plan.ok, "plan : %s" % plan.error)
	eq(plan.linked, 2, "deux notes citent l'inconnu (soirée, dossier)")
	ok(" ".join(plan.summary).contains("rien n'est supprimé"), "aperçu : " + " / ".join(plan.summary))
	eq(_text(INCONNU), before_inconnu, "le plan n'écrit rien")
	var r: Dictionary = app.merge_notes(plan)
	ok(r.ok and r.done.size() == 4, "fusion appliquée : %s" % str(r))
	var v := _text(VICTOR)
	ok(v.contains("  - Inconnu - Manteau gris"), "le nom de l'inconnu devient un alias de Victor Morel")
	ok(not v.contains("identite: inconnue") and not v.contains("statut: inconnu"), "identité et statut « inconnus » non repris")
	ok(v.contains("## Repris de « Inconnu - Manteau gris »") and v.contains("Grand, manteau gris long, gants."), "texte de l'inconnu repris")
	var s := _text(SOIREE)
	ok(s.contains("L'[[Victor Morel|inconnu au manteau gris]] a parlé"), "lien du texte réécrit, texte affiché conservé")
	ok(not s.contains("Inconnu - Manteau gris]]"), "plus aucun lien vers l'ancienne fiche")
	ok(not s.contains("presents_incertains:\n  - \"[[Victor Morel]]\""), "Victor Morel n'est plus présent « incertain » (déjà présent)")
	var stub := _text(INCONNU)
	ok(stub.begins_with("---\nfusionnee_dans: \"[[Victor Morel]]\"") and stub.contains(before_inconnu.strip_edges()), "l'ancienne fiche devient un renvoi qui garde tout son contenu")
	eq(app.index.path_of_name("Inconnu - Manteau gris"), INCONNU, "la note de renvoi existe toujours")
	var t: Array = app.index.rows("SELECT type FROM files WHERE path = ?", [INCONNU])
	eq(str(t[0].type), "", "le renvoi n'a plus de type : il ne compte plus comme fiche")
	eq(app.index.backlinks("Inconnu - Manteau gris").size(), 0, "plus aucun rétrolien vers l'ancienne fiche")
	var refus: Dictionary = app.merge_plan("Victor Morel", "Valombre")
	ok(not refus.ok and refus.error.contains("même type"), "types différents : refusé")
	app.index.close()
	app.free()


func test_conflit_pendant_la_fusion() -> void:
	_prepare()
	var plan: Dictionary = app.merge_plan("Inconnu - Manteau gris", "Victor Morel")
	write_file(root + "/" + SOIREE, _text(SOIREE) + "\nModifié ailleurs.\n")
	var r: Dictionary = app.merge_notes(plan)
	ok(not r.ok and r.error.contains("modifié ailleurs"), "conflit : arrêt — %s" % r.error)
	ok(_text(INCONNU).begins_with("---\ntype: personnage"), "l'ancienne fiche n'est pas touchée après un arrêt")
	app.index.close()
	app.free()
