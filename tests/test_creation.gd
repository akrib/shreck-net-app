extends "res://tests/base.gd"
## Création de notes depuis les formulaires, notes rapides et leur transformation.

const AppService := preload("res://core/app/app_service.gd")
const Schema := preload("res://core/model/schema.gd")
const Scanner := preload("res://core/sync/scanner.gd")

var app: Node
var root := ""


func _prepare(dir_name := "coffre-creation") -> void:
	AppService.settings_file = "user://tests_tmp/reglages-creation.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	root = temp_dir(dir_name)
	copy_tree(example_vault(), root)
	app = AppService.new()
	app.set_repo_path(root)
	IndexStoreReset()
	Scanner.new(app.repo, app.index).scan()


func IndexStoreReset() -> void:
	# Index propre pour ce test (le chemin dépend du dossier du coffre).
	var db: String = app.db_path()
	app.index.close()
	preload("res://core/index/index_store.gd").delete_files(db)
	app._open_read_index()


func _done() -> void:
	app.index.close()
	app.free()


func _text(rel: String) -> String:
	return FileAccess.get_file_as_string(root + "/" + rel)


func test_creation_de_chaque_type() -> void:
	_prepare("coffre-creation-types")
	var ctx := {"last_domaine": "Valombre", "now": {"year": 2026, "month": 10, "day": 19, "hour": 1, "minute": 52}}
	# Soirée : date et domaine préremplis
	var v := Schema.defaults("soiree", ctx)
	eq(v.get("domaine"), "[[Valombre]]", "soirée : dernier domaine prérempli")
	eq(v.get("fiabilite"), "A", "soirée : fiabilité A pour mes propres notes")
	eq(v.get("moi_present"), true, "soirée : j'étais présent")
	v["date"] = "2026-10-24"
	v["presents"] = ["[[Victor Morel]]", "[[Élise Varga]]"]
	var r: Dictionary = app.create_note("soiree", v)
	ok(r.ok, "soirée créée : " + str(r.get("error", "")))
	eq(r.get("rel"), "Soirees/2026/2026-10-24 Valombre - Assemblée.md", "nom et dossier de la soirée")
	var t := _text(r.rel)
	ok(t.begins_with("---\ntype: soiree\nid: soi-"), "frontmatter : type puis id")
	ok(t.contains("date: 2026-10-24\n"), "date écrite sans guillemets (type Date d'Obsidian)")
	ok(t.contains("domaine: \"[[Valombre]]\"\n"), "lien entre guillemets")
	ok(t.contains("presents:\n  - \"[[Victor Morel]]\"\n  - \"[[Élise Varga]]\"\n"), "liste de présents")
	ok(t.contains("# Assemblée de Valombre — 24 octobre 2026\n\n## Déroulé\n"), "titre lisible et sections")
	ok(t.contains("## Éléments\n") and t.contains("## À faire\n"), "sections Éléments et À faire")
	# Source : fiabilité selon la nature
	v = Schema.defaults("source", ctx)
	eq(v.get("nature"), "note", "source : nature par défaut")
	eq(v.get("fiabilite"), "B", "source note personnelle : fiabilité B")
	v["nature"] = "presse"
	v["fiabilite"] = Schema.FIABILITE_PAR_NATURE["presse"]
	v["canal"] = "Gazette de Valombre"
	v["titre"] = "Incendie: les pompiers parlent"
	v["date"] = "2026-10-20"
	r = app.create_note("source", v)
	ok(r.ok, "source créée : " + str(r.get("error", "")))
	eq(r.get("rel"), "Sources/Presse/2026-10-20 Gazette de Valombre - Incendie les pompiers parlent.md", "caractère interdit « : » retiré du nom")
	ok(_text(r.rel).contains("fiabilite: C\n"), "presse : fiabilité C")
	# Personnage
	v = Schema.defaults("personnage", ctx)
	v["nom"] = "Louise Andral"
	v["clan"] = "[[Toreador]]"
	r = app.create_note("personnage", v)
	ok(r.ok and r.rel == "Personnages/Louise Andral.md", "personnage créé")
	t = _text(r.rel)
	ok(t.contains("statut: actif\n") and t.contains("identite: connue\n") and t.contains("fiabilite: F\n"), "valeurs par défaut du personnage")
	ok(t.contains("## Portrait\n\n## Notes\n"), "sections du personnage")
	# Doublon de nom : jamais d'écrasement
	r = app.create_note("personnage", v)
	ok(r.ok and r.rel == "Personnages/Louise Andral (2).md", "nom déjà pris : « (2) » ajouté, rien d'écrasé")
	# Faveur : mouvement de création écrit
	v = Schema.defaults("faveur", ctx)
	v["debiteur"] = "[[Victor Morel]]"
	v["creancier"] = "[[Louise Andral]]"
	v["harpie"] = "[[Armand Lescure]]"
	v["niveau"] = "mineure"
	v["date"] = "2026-10-24"
	r = app.create_note("faveur", v)
	ok(r.ok and r.rel == "Faveurs/2026-10-24 Victor Morel envers Louise Andral.md", "faveur créée")
	t = _text(r.rel)
	ok(t.contains("[mv:: creation] [date:: 2026-10-24] [niveau:: mineure] [debiteur:: [[Victor Morel]]] [creancier:: [[Louise Andral]]] [harpie:: [[Armand Lescure]]] ^mv-"), "mouvement de création")
	ok(t.contains("transferable: true\n") and t.contains("enregistree: false\n"), "cases à cocher écrites")
	# Indice, événement, dossier, groupe, lieu, domaine, objet, concept
	r = app.create_note("indice", {"enonce": "Victor Morel doit une faveur à Louise Andral", "statut": "non_verifie",
		"credibilite": 3, "pour": ["[[2026-10-10 Valombre - Assemblée#^el-gq9x1xqg]]"], "sujets": ["[[Victor Morel]]"]})
	ok(r.ok and r.rel.begins_with("Indices/"), "indice créé")
	ok(_text(r.rel).contains("credibilite: 3\n"), "crédibilité écrite comme un nombre")
	r = app.create_note("evenement", {"description": "Duel sur les quais", "date_floue": "2026-10~", "statut": "non_verifie", "credibilite": 4})
	ok(r.ok and r.rel == "Evenements/2026-10 Duel sur les quais.md", "événement : mois en tête du nom")
	ok(_text(r.rel).contains("date_floue: 2026-10~\n") or _text(r.rel).contains("date_floue: \"2026-10~\"\n"), "date floue conservée")
	r = app.create_note("evenement", {"description": "Fête au port", "date_floue": "2026-10-03", "statut": "non_verifie", "credibilite": 4})
	ok(r.ok and _text(r.rel).contains("\ndate: 2026-10-03\n") and not _text(r.rel).contains("date_floue"), "date exacte saisie en date floue : rangée dans « date »")
	r = app.create_note("dossier", {"question": "Qui a mis le feu à l'entrepôt ?", "statut": "ouvert", "priorite": "haute"})
	ok(r.ok and r.rel == "Dossiers/Dossier - Qui a mis le feu à l'entrepôt.md", "dossier créé (« ? » retiré du nom)")
	r = app.create_note("groupe", {"nom": "Brujah", "nature": "clan"})
	ok(r.ok and _text(r.rel).contains("nature: clan\n"), "groupe créé")
	r = app.create_note("lieu", {"nom": "Le Corbeau", "nature_libre": "bar", "domaine": "[[Valombre]]"})
	ok(r.ok and _text(r.rel).contains("nature: bar\n"), "lieu : nature libre écrite dans « nature »")
	r = app.create_note("domaine", {"nom": "Grenoble", "region": "Isère"})
	ok(r.ok and r.rel == "Domaines/Grenoble.md", "domaine créé")
	r = app.create_note("objet", {"nom": "Dague d'os", "detenteur": "[[Victor Morel]]"})
	ok(r.ok, "objet créé")
	r = app.create_note("concept", {"nom": "Prestation"})
	ok(r.ok, "concept créé")
	# Formulaire incomplet : refusé, rien d'écrit
	r = app.create_note("faveur", {"niveau": "mineure", "statut": "active", "credibilite": 2})
	ok(not r.ok and str(r.error).contains("Débiteur"), "champ obligatoire manquant signalé : " + str(r.get("error", "")))
	r = app.create_note("soiree", {"date": "2026-13-40", "domaine": "[[Valombre]]"})
	ok(not r.ok and str(r.error).contains("date invalide"), "date invalide refusée")
	_done()


func test_note_rapide_et_transformation() -> void:
	_prepare("coffre-creation-rapide")
	eq(app.index.quick_notes_todo_count(), 0, "aucune note rapide au départ")
	var q: Dictionary = app.create_quick_note()
	ok(q.ok and q.rel.begins_with("En cours/") and q.rel.ends_with(" Note rapide.md"), "note rapide créée : " + str(q.get("rel", q.get("error"))))
	var t := _text(q.rel)
	ok(t.contains("type: en_cours\n") and t.contains("statut: a_traiter\n"), "note rapide à traiter")
	eq(app.index.quick_notes_todo_count(), 1, "compteur : 1 à traiter")
	# on écrit dedans
	var rd: Dictionary = app.read_note(q.rel)
	rd.doc.set_body("Vu un Nosferatu inconnu parler à Victor près du port.\n")
	ok(app.save_note(q.rel, rd.doc, rd.hash).ok, "texte de la note rapide enregistré")
	# transformation en personnage
	var v := Schema.defaults("personnage", app.schema_ctx())
	v["nom"] = "Inconnu - Nosferatu du port"
	v["identite"] = "inconnue"
	var r: Dictionary = app.create_note("personnage", v, "Vu un Nosferatu inconnu parler à Victor près du port.", q.rel)
	ok(r.ok, "transformée en personnage : " + str(r.get("error", "")))
	ok(not r.has("warning"), "note rapide mise à jour : " + str(r.get("warning", "")))
	var p := _text(r.rel)
	ok(p.contains("## Notes\nVu un Nosferatu inconnu parler à Victor près du port.\n\n*Repris de la note rapide [["), "texte repris, avec sa provenance")
	t = _text(q.rel)
	ok(t.contains("statut: traitee\n") and t.contains("devenue:\n  - \"[[Inconnu - Nosferatu du port]]\"\n"), "note rapide : traitée, lien vers le résultat")
	ok(t.contains("Vu un Nosferatu inconnu parler"), "note rapide conservée (rien supprimé)")
	eq(app.index.quick_notes_todo_count(), 0, "compteur revenu à 0")
	# une deuxième transformation ajoute un second lien
	r = app.create_note("indice", {"enonce": "Un Nosferatu surveille Victor", "statut": "non_verifie", "credibilite": 5,
		"pour": ["[[x#^el-00000000]]"]}, "Vu un Nosferatu inconnu parler à Victor près du port.", q.rel)
	ok(r.ok and _text(q.rel).contains("  - \"[[Un Nosferatu surveille Victor]]\"\n"), "deuxième note issue de la même note rapide")
	_done()


func test_selecteurs_et_requetes() -> void:
	_prepare()
	var names := func(rows: Array) -> Array:
		var out := []
		for x in rows:
			out.append(x.name)
		return out
	ok(names.call(app.index.find_notes("elise", ["personnage"])).has("Élise Varga"), "sélecteur : sans accents")
	ok(names.call(app.index.find_notes("notaire", ["personnage"])).has("Victor Morel"), "sélecteur : par alias")
	eq(app.index.find_notes("elise", ["groupe"]).size(), 0, "sélecteur : filtré par type")
	ok(app.index.find_notes("", ["personnage"]).size() == 4, "sélecteur vide : les personnages")
	var els: Array = app.index.find_elements("printemps")
	ok(els.size() == 1 and str(els[0].block) == "el-gq9x1xqg", "recherche d'éléments par leur texte")
	var s: Dictionary = app.create_stub("personnage", "Marc Fauvel")
	ok(s.ok and s.rel == "Personnages/Marc Fauvel.md", "fiche minimale créée depuis le sélecteur")
	var pres: Array = app.index.linked_from("Victor Morel", ["presents", "presents_incertains"])
	ok(pres.size() >= 1 and str(pres[0].type) == "soiree", "présences aux soirées")
	ok(app.index.relations_of("Victor Morel").size() >= 1, "relations de Victor Morel")
	ok(app.index.dated_notes().size() >= 5, "notes datées pour la chronologie")
	ok(app.index.elements_with_dates().size() >= 1, "éléments avec date des faits")
	ok(app.index.open_tasks().size() >= 1, "tâches ouvertes")
	# cocher une tâche
	var tk: Dictionary = app.index.open_tasks()[0]
	var before := _text(tk.path)
	var w: Dictionary = app.set_task_done(tk.path, int(tk.line), tk.text, true)
	ok(w.ok, "tâche cochée : " + str(w.get("error", "")))
	var after := _text(tk.path)
	ok(after.contains("- [x]") and after.length() == before.length(), "seule la case a changé")
	ok(not app.set_task_done(tk.path, int(tk.line), "texte qui ne correspond pas", false).ok, "ligne inattendue : refus")
	_done()


func test_proprietes_des_regles() -> void:
	_prepare("coffre-creation-regles")
	ok(Schema.suggestions("postes", "Lyon").has("Prévôt de Lyon"), "postes proposés avec le domaine")
	ok(Schema.suggestions("influences").has("Police (Gotha)") and Schema.suggestions("influences").has("Rue (Pègre)"), "influences Gotha et Pègre")
	# fiches de référence minimales créées depuis un sélecteur filtré
	var c: Dictionary = app.create_stub("concept", "Obténébration", "discipline")
	ok(c.ok and _text(c.rel).contains("nature: discipline\n"), "discipline créée avec sa nature")
	var g: Dictionary = app.create_note("groupe", {"nom": "Lasombra", "nature": "clan", "disciplines": ["[[Domination]]", "[[Obténébration]]", "[[Puissance]]"]})
	ok(g.ok and _text(g.rel).contains("disciplines:\n  - \"[[Domination]]\""), "clan avec ses disciplines de clan")
	var sec: Dictionary = app.create_stub("groupe", "Camarilla", "secte")
	ok(sec.ok and _text(sec.rel).contains("nature: secte\n"), "secte créée")
	eq(app.index.find_notes("obten", ["concept"], 10, ["discipline"]).size(), 1, "sélecteur filtré par nature : discipline trouvée")
	eq(app.index.find_notes("obten", ["concept"], 10, ["poste"]).size(), 0, "… et pas parmi les postes")
	# personnage complet
	var v := Schema.defaults("personnage", app.schema_ctx())
	eq(v.get("nature"), "vampire", "créature : vampire par défaut")
	v.merge({"nom": "Isaure de Brétigny", "clan": "[[Lasombra]]", "secte": "[[Camarilla]]", "rang": "ancilla",
		"generation": 11, "titres": ["Prévôt de Valombre"], "disciplines": ["[[Obténébration]]"],
		"influences": ["Police (Gotha)"]}, true)
	var p: Dictionary = app.create_note("personnage", v)
	ok(p.ok, "personnage créé : " + str(p.get("error", "")))
	var t := _text(p.rel)
	ok(t.contains("nature: vampire\n") and t.contains("secte: \"[[Camarilla]]\"\n") and t.contains("rang: ancilla\n"), "nature, secte, rang")
	ok(t.contains("generation: 11\n"), "génération écrite comme un nombre")
	ok(t.contains("titres:\n  - Prévôt de Valombre\n") and t.contains("influences:\n  - Police (Gotha)\n"), "postes et influences")
	# pouvoir constaté en soirée
	var srel := "Soirees/2026/2026-10-10 Valombre - Assemblée.md"
	var rd: Dictionary = app.read_note(srel)
	rd.doc.set_body(rd.doc.body_for_edit().replace("## Éléments\n", "## Éléments\n- [[Isaure de Brétigny]] a plongé le salon dans l'ombre. [nature:: observe] [credibilite:: 2] [discipline:: [[Obténébration]]] ^el-x0000001\n"))
	ok(app.save_note(srel, rd.doc, rd.hash).ok, "élément avec pouvoir constaté enregistré")
	eq(app.index.elements_with_discipline().size(), 1, "pouvoir constaté indexé")
	_done()


func test_nom_sans_valeur_nulle() -> void:
	var now := {"year": 2026, "month": 10, "day": 21, "hour": 15, "minute": 0}
	eq(Schema.build_name("source", {"date": "2026-10-21", "canal": null, "titre": "Rencontre", "nature": "note"}, now),
		"2026-10-21 Note personnelle - Rencontre", "canal vide : jamais « null » dans le nom du fichier")
	eq(Schema.build_name("evenement", {"date": null, "date_floue": "2026-09~", "description": "Incendie"}, now),
		"2026-09 Incendie", "date floue reprise quand la date exacte est vide")
	eq(Schema.choice_label("source", "nature", "discord", "Discord"), "C · Discord", "nature d'une source : fiabilité par défaut devant le libellé")
	eq(Schema.choice_label("element", "nature", "observe", "Observé"), "Observé", "les autres listes ne changent pas")
