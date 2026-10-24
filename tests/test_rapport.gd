extends "res://tests/base.gd"
## Rapport de soirée : tri des présents (préséance, statut d'âge, points de
## statut), informations et leur ordre, modifications écrites dans les notes.

const AppService := preload("res://core/app/app_service.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Report := preload("res://core/analysis/soiree_report.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")

var app: Node
var root := ""
var _n := 0
const SOIREE := "Soirees/2026/2026-10-10 Ysère - Assemblée.md"


func _note(rel: String, type_name: String, props: String, body: String) -> void:
	_n += 1
	var prefix: String = {"personnage": "per", "source": "src", "groupe": "grp", "soiree": "soi", "domaine": "dom", "evenement": "evt"}[type_name]
	write_file(root + "/" + rel, "---\ntype: %s\nid: %s-r%07d\nschema: 1\n%s---\n%s" % [type_name, prefix, _n, props, body])


func _prepare(config := "") -> void:
	AppService.settings_file = "user://tests_tmp/reglages-rapport.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	root = temp_dir("coffre-rapport")
	if config != "":
		write_file(root + "/.nosferatu/config.json", config)
	for c in ["Ventrue", "Toréador", "Gangrel", "Brujah"]:
		_note("Groupes/%s.md" % c, "groupe", "nature: clan\n", "# %s\n" % c)
	_note("Groupes/Toréador antitribu.md", "groupe", "nature: lignee\nclan: \"[[Toréador]]\"\n", "# x\n")
	_note("Domaines/Ysère.md", "domaine", "preseance:\n  - \"[[Ventrue]]\"\n  - \"[[Toréador]]\"\n  - \"[[Gangrel]]\"\n", "# Ysère\n")
	_note("Domaines/Lyon.md", "domaine", "aliases:\n  - Terres Lyonnaises\n", "# Lyon\n")
	_note("Personnages/Alix.md", "personnage", "clan: \"[[Gangrel]]\"\nrang: ancien\n", "# Alix\n")
	_note("Personnages/Bastien.md", "personnage", "clan: \"[[Ventrue]]\"\nrang: ancilla\ntitres:\n  - Primogène Ventrue d'Ysère\n", "# Bastien\n")
	_note("Personnages/Corentin.md", "personnage", "clan: \"[[Ventrue]]\"\nrang: ancilla\n", "# Corentin\n")
	_note("Personnages/Diane.md", "personnage", "clan: \"[[Ventrue]]\"\nrang: ancien\ntitres:\n  - Prévôt de Lyon\n", "# Diane\n")
	_note("Personnages/Émile.md", "personnage", "clan: \"[[Toréador antitribu]]\"\nrang: nouveau_ne\n", "# Émile\n")
	_note("Personnages/Fanny.md", "personnage", "clan: \"[[Brujah]]\"\nrang: infant\n", "# Fanny\n")
	_note("Personnages/Gaspard.md", "personnage", "rang: ancilla\ntitres:\n  - Harpie des Terres Lyonnaises\n", "# Gaspard\n")
	# Corentin : deux reconnaissances en cours (dont une rapportée deux fois), une expirée, une future,
	# une douteuse, et une tance ; Bastien n'en a aucune mais a un poste.
	_note("Sources/Notes/Cour.md", "source", "nature: note\ntitre: Cour\nfiabilite: B\ndate: 2026-09-01\n",
		"## Éléments\n" +
		"- r1 [nature:: observe] [credibilite:: 1] [relation:: reconnait] [de:: [[Diane]]] [vers:: [[Corentin]]] [qualificatif:: Loyal] ^el-rrrrrrr1\n" +
		"- r1bis [nature:: rapporte] [credibilite:: 3] [relation:: reconnait] [de:: [[Diane]]] [vers:: [[Corentin]]] [qualificatif:: loyal] ^el-rrrrrrr2\n" +
		"- r2 [nature:: observe] [credibilite:: 2] [relation:: reconnait] [de:: [[Alix]]] [vers:: [[Corentin]]] [qualificatif:: Fin limier] [jusqu_au:: 2026-10] ^el-rrrrrrr3\n" +
		"- r3 [nature:: observe] [credibilite:: 1] [relation:: reconnait] [de:: [[Alix]]] [vers:: [[Corentin]]] [qualificatif:: Ancien] [jusqu_au:: 2026-09-30] ^el-rrrrrrr4\n" +
		"- r4 [nature:: observe] [credibilite:: 1] [relation:: reconnait] [de:: [[Alix]]] [vers:: [[Corentin]]] [qualificatif:: Futur] [date_faits:: 2026-11-02] ^el-rrrrrrr5\n" +
		"- r5 [nature:: rumeur] [credibilite:: 4] [relation:: reconnait] [de:: [[Alix]]] [vers:: [[Corentin]]] [qualificatif:: Douteux] ^el-rrrrrrr6\n" +
		"- t1 [nature:: observe] [credibilite:: 2] [relation:: sobriquet] [de:: [[Diane]]] [vers:: [[Corentin]]] [qualificatif:: Bavard] ^el-rrrrrrr7\n" +
		"- n1 [nature:: observe] [credibilite:: 1] [relation:: nomme] [de:: [[Diane]]] [vers:: [[Gaspard]]] [qualificatif:: Héraut d'Ysère] ^el-rrrrrrr8\n")
	_note(SOIREE, "soiree", "date: 2026-10-10\ndomaine: \"[[Ysère]]\"\nnature: assemblee\nfiabilite: A\npresents:\n  - \"[[Fanny]]\"\n  - \"[[Alix]]\"\n  - \"[[Corentin]]\"\n  - \"[[Bastien]]\"\n  - \"[[Diane]]\"\n  - \"[[Émile]]\"\n  - \"[[Gaspard]]\"\npresents_incertains:\n  - \"[[Inconnu]]\"\n",
		"# Assemblée\n\n## Éléments\n" +
		"- Premier fait [[Alix]]. [nature:: observe] [credibilite:: 1] ^el-sssssss1\n" +
		"- Deuxième fait. [nature:: observe] [credibilite:: 2]\n" +
		"- Ma supposition. [nature:: hypothese] [credibilite:: 5] ^el-sssssss3\n")
	_note("Sources/Conversations/Conv.md", "source", "nature: conversation\ntitre: Conv\nfiabilite: C\ndate: 2026-10-10\nsoiree: \"[[2026-10-10 Ysère - Assemblée]]\"\n",
		"## Éléments\n- Dit en aparté. [nature:: rapporte] [credibilite:: 3] [par:: [[Diane]]] ^el-ccccccc1\n")
	_note("Evenements/2026-10 Incident.md", "evenement", "description: Incident\nstatut: corrobore\ncredibilite: 2\ndate_floue: 2026-10\n", "# Incident\n")
	app = AppService.new()
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	preload("res://core/index/index_store.gd").delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()


func _done() -> void:
	app.index.close()
	app.free()


func _names(list: Array) -> Array:
	return list.map(func(p): return str(p.name))


func test_bareme_et_titres() -> void:
	var b := Report.bareme({})
	ok(b.poste_defaut == 1.0 and b.reconnaissance == 1.0 and b.tance == -1.0 and not b.configure, "barème par défaut")
	var b2 := Report.bareme({"statut": {"postes": {"Prince": 5, "Primogène": 3}, "reconnaissance": 2, "tance": "x"}})
	ok(b2.postes["primogene"] == 3.0 and b2.reconnaissance == 2.0 and b2.tance == -1.0 and b2.configure, "barème du coffre (valeurs invalides ignorées)")
	var t := Report.split_titre("Prévôt de Lyon")
	ok(t.poste == "Prévôt" and t.lieu == "Lyon", "poste et domaine : %s" % str(t))
	var t2 := Report.split_titre("Maître des Harpies de Lyon")
	eq(t2.poste, "Maître des Harpies", "le poste le plus long l'emporte")
	eq(Report.split_titre("Grand veneur").connu, false, "titre libre conservé")
	eq(Report.validity({"jusqu_au": "2026-10"}, "", "2026-10-31"), "ok", "échéance au mois : court jusqu'à la fin du mois")
	eq(Report.validity({"jusqu_au": "2026-10-09"}, "", "2026-10-10"), "expire", "échéance passée")
	eq(Report.validity({"date_faits": "2026-11"}, "2026-01-01", "2026-10-10"), "futur", "fait postérieur à la soirée")


func test_presents_tries() -> void:
	_prepare()
	var rep := Report.build(app.index, SOIREE, {})
	eq(_names(rep.people), ["Diane", "Bastien", "Corentin", "Émile", "Alix", "Fanny", "Gaspard"],
		"préséance du domaine, puis statut d'âge, puis postes, puis reconnaissances ; lignée avec son clan ; inconnus à la fin")
	var cor: Dictionary = rep.people[2]
	var counted: Array = cor.recos.filter(func(x): return x.compte).map(func(x): return x.qualificatif)
	eq(counted, ["Loyal", "Fin limier"], "reconnaissances en cours (doublon fusionné ; expirée, future et douteuse écartées)")
	var loyal: Dictionary = cor.recos.filter(func(x): return x.qualificatif == "Loyal")[0]
	eq(loyal.sources, 2, "deux sources pour la même reconnaissance")
	eq(cor.recos.filter(func(x): return x.etat == "expire").size(), 1, "une reconnaissance expirée, affichée")
	eq(cor.points, 1.0, "2 reconnaissances − 1 tance = 1 point")
	var dia: Dictionary = rep.people[0]
	ok(dia.postes[0].hors_domaine and dia.points == 0.0, "un poste d'un autre domaine ne compte pas ici")
	var bas: Dictionary = rep.people[1]
	eq(bas.points_postes, 1.0, "poste du domaine : 1 point par défaut")
	var gas: Dictionary = rep.people[6]
	eq(gas.postes.map(func(x): return x.titre), ["Harpie des Terres Lyonnaises", "Héraut d'Ysère"], "poste tiré d'une nomination")
	ok(gas.postes[0].hors_domaine and not gas.postes[1].hors_domaine, "domaine reconnu par son alias")
	eq(rep.groups.map(func(g): return g.clan), ["Ventrue", "Toréador antitribu", "Gangrel", "Brujah", ""], "groupes par clan")
	eq(_names(rep.uncertain), ["Inconnu"], "présences incertaines à part (fiche absente)")
	ok(rep.uncertain[0].missing, "fiche absente signalée")
	var pres := Report.presentation(cor)
	ok(pres.begins_with("Corentin, Ancilla du clan Ventrue") and pres.contains("reconnaissances « Loyal » par Diane ; « Fin limier » par Alix") and pres.contains("tance « Bavard » par Diane"),
		"présentation protocolaire : " + pres)
	var rep2 := Report.build(app.index, SOIREE, {"statut": {"postes": {"Primogène": 4}, "reconnaissance": 2, "tance": -3}})
	var cor2: Dictionary = rep2.people.filter(func(p): return p.name == "Corentin")[0]
	eq(cor2.points, 1.0, "barème du coffre : 2 × 2 − 3")
	eq(rep2.people.filter(func(p): return p.name == "Bastien")[0].points, 4.0, "barème du coffre : Primogène = 4")
	_done()


func test_presences_rapportees() -> void:
	_prepare()
	_note("Sources/Forum/Compte rendu.md", "source", "nature: forum\nfiabilite: B\ndate: 2026-10-10\nsoiree: \"[[2026-10-10 Ysère - Assemblée]]\"\n",
		"## Éléments\n" +
		"- [[Fanny]] était présente. [nature:: rapporte] [credibilite:: 2] [relation:: present_a] [de:: [[Fanny]]] [vers:: [[2026-10-10 Ysère - Assemblée]]] ^el-ppppppp1\n" +
		"- [[Hugo]] était présent. [nature:: rapporte] [credibilite:: 2] [relation:: present_a] [de:: [[Hugo]]] [vers:: [[2026-10-10 Ysère - Assemblée]]] ^el-ppppppp2\n" +
		"- [[Bastien]] ailleurs. [nature:: rapporte] [credibilite:: 2] [relation:: present_a] [de:: [[Bastien]]] [vers:: [[Lyon]]] ^el-ppppppp3\n" +
		"- Fait du compte rendu. [nature:: rapporte] [credibilite:: 3] ^el-ppppppp4\n")
	_note("Sources/Forum/Autre.md", "source", "nature: forum\nfiabilite: C\n",
		"## Éléments\n- [[Hugo]] y était aussi. [nature:: rumeur] [credibilite:: 4] [relation:: present_a] [de:: [[Hugo]]] [vers:: [[2026-10-10 Ysère - Assemblée]]] ^el-ppppppp5\n")
	Scanner.new(app.repo, app.index).scan()
	var rep := Report.build(app.index, SOIREE, {})
	eq(_names(rep.reported), ["Hugo"], "présence rapportée hors de vos présents (une seule fois, deux sources)")
	eq((rep.reported[0].reported_by as Array).map(func(x): return x.note), ["Autre", "Compte rendu"], "sources de la présence rapportée")
	ok(rep.reported[0].missing, "fiche absente signalée")
	var fan: Dictionary = rep.people.filter(func(p): return p.name == "Fanny")[0]
	eq((fan.get("reported_by", []) as Array).size(), 1, "un présent noté est corroboré par le compte rendu")
	eq(rep.reported_groups.size(), 1, "présences rapportées groupées par clan")
	var texts: Array = rep.items.map(func(i): return i.text)
	ok(texts.has("Fait du compte rendu.") and texts.has("[[Bastien]] ailleurs.") and not texts.has("[[Hugo]] était présent."),
		"les présences à cette soirée ne sont pas répétées dans les informations : " + str(texts))
	_done()


func test_preseance_par_defaut() -> void:
	_prepare("{\"preseance\": [\"Brujah\", \"Gangrel\"]}")
	var dom: String = app.index.path_of_name("Ysère")
	ok(app.set_note_properties(dom, {"preseance": null}).ok, "préséance retirée du domaine")
	var rep := Report.build(app.index, SOIREE, app.repo.config)
	eq(_names(rep.people).slice(0, 2), ["Fanny", "Alix"], "préséance de la configuration du coffre")
	_done()


func test_informations_et_ordre() -> void:
	_prepare("{\"moi\": \"[[Hermès]]\"}")
	var rep := Report.build(app.index, SOIREE, app.repo.config)
	eq(rep.items.map(func(i): return i.text), ["Premier fait [[Alix]].", "Deuxième fait.", "Ma supposition.", "Dit en aparté."],
		"éléments de la soirée puis de la source rattachée")
	eq(rep.missing_ids, 1, "un élément sans identifiant")
	eq(rep.items[3].fiab, "C", "fiabilité de la source rattachée")
	# ordre choisi + événement lié
	var order := ["[[Conv#^el-ccccccc1]]", "[[2026-10 Incident]]", "[[2026-10-10 Ysère - Assemblée#^el-sssssss1]]"]
	ok(app.set_note_properties(SOIREE, {"rapport": order}).ok, "ordre enregistré dans la soirée")
	rep = Report.build(app.index, SOIREE, app.repo.config)
	eq(rep.items.map(func(i): return i.text), ["Dit en aparté.", "Incident", "Premier fait [[Alix]].", "Deuxième fait.", "Ma supposition."],
		"ordre de « rapport », puis le reste dans l'ordre naturel")
	eq(rep.items[1].kind, "note", "événement lié : une note entière")
	eq(rep.items[1].cred, 2, "sa crédibilité")
	var txt := Report.to_text(rep)
	ok(txt.contains("**Présents**") and txt.contains("*Ventrue*\n- Diane, Ancien du clan Ventrue, Prévôt de Lyon"), "texte : présents par clan\n" + txt)
	ok(txt.contains("1. Dit en aparté.\n2. Incident\n3. Premier fait Alix.\n4. Deuxième fait.") and not txt.contains("supposition"), "texte : informations dans l'ordre, sans les hypothèses")
	ok(txt.strip_edges().ends_with("— Hermès"), "signature")
	ok(Report.to_text(rep, true, true).contains("1. Dit en aparté. (C3)") and Report.to_text(rep, true, true).contains("Ma supposition. (A5)"), "texte avec cotes et hypothèses")
	eq(Report.order_refs(rep.items).size(), 4, "l'élément sans identifiant n'entre pas dans « rapport »")
	_done()


func test_modifications() -> void:
	_prepare()
	# crédibilité modifiée dans la note d'origine
	var r: Dictionary = app.update_element("Sources/Conversations/Conv.md", "el-ccccccc1", 0, "", {"credibilite": 2})
	ok(r.ok, "crédibilité modifiée : %s" % str(r))
	var conv := FileAccess.get_file_as_string(root + "/Sources/Conversations/Conv.md")
	ok(conv.contains("- Dit en aparté. [nature:: rapporte] [credibilite:: 2] [par:: [[Diane]]] ^el-ccccccc1"), "seul le champ change")
	ok(app.set_note_properties("Sources/Conversations/Conv.md", {"fiabilite": "B"}).ok, "fiabilité de la source")
	var rep := Report.build(app.index, SOIREE, {})
	var it: Dictionary = rep.items.filter(func(i): return i.block == "ccccccc1" or i.block == "el-ccccccc1")[0]
	ok(it.fiab == "B" and it.cred == 2, "le rapport relit la note : %s%s" % [it.fiab, str(it.cred)])
	# élément sans identifiant : retrouvé par sa ligne et son texte
	var sans: Dictionary = rep.items.filter(func(i): return i.block == "")[0]
	ok(app.update_element(SOIREE, "", sans.line, sans.text, {"credibilite": 3}).ok, "élément sans identifiant modifié")
	ok(not app.update_element(SOIREE, "", sans.line, "autre texte", {"credibilite": 4}).ok, "texte différent : rien n'est écrit")
	var a: Dictionary = app.assign_missing_ids(SOIREE)
	ok(a.ok and a.added == 1, "identifiant attribué : %s" % str(a))
	ok(app.assign_missing_ids(SOIREE).added == 0, "rien à faire la seconde fois")
	var body := FileAccess.get_file_as_string(root + "/" + SOIREE)
	ok(RegEx.create_from_string("- Deuxième fait\\. \\[nature:: observe\\] \\[credibilite:: 3\\] \\^el-[a-z0-9]{8}\\n").search(body) != null, "ligne complétée sans rien perdre")
	ok(app.append_element(SOIREE, "- Nouveau. [nature:: observe] [credibilite:: 2] ^el-nnnnnnn1").ok, "information ajoutée")
	ok(FileAccess.get_file_as_string(root + "/" + SOIREE).contains("^el-sssssss3\n- Nouveau."), "à la fin de la section Éléments")
	_done()


func test_lignes_structurees() -> void:
	var l := "- Texte [[A]]. [nature:: observe] [credibilite:: 2] [par:: [[B]]] ^el-abcdefgh"
	eq(StructuredLines.set_line_field(l, "credibilite", "4"), "- Texte [[A]]. [nature:: observe] [credibilite:: 4] [par:: [[B]]] ^el-abcdefgh", "remplacement")
	eq(StructuredLines.set_line_field(l, "jusqu_au", "2026-12"), "- Texte [[A]]. [nature:: observe] [credibilite:: 2] [par:: [[B]]] [jusqu_au:: 2026-12] ^el-abcdefgh", "ajout avant l'identifiant")
	eq(StructuredLines.set_line_field("- x [nature:: observe]  ", "credibilite", "1"), "- x [nature:: observe] [credibilite:: 1]", "ajout en fin de ligne")
	eq(StructuredLines.add_block_id(l, "el-zzzzzzzz"), l, "identifiant déjà présent : inchangé")
