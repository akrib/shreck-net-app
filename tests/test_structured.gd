extends "res://tests/base.gd"
## Lignes structurées (éléments, mouvements), liens, blocs et tâches.

const NoteDocument := preload("res://core/format/note_document.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")


func _load(rel: String) -> Dictionary:
	var doc = NoteDocument.from_bytes(FileAccess.get_file_as_bytes(example_vault() + "/" + rel))
	return StructuredLines.parse_body(doc.body, doc.body_first_line)


func test_soiree_exemple() -> void:
	var p := _load("Soirees/2026/2026-10-10 Valombre - Assemblée.md")
	eq(p.elements.size(), 5, "5 éléments")
	eq(p.tasks.size(), 2, "2 tâches")
	eq(p.problems.size(), 0, "aucun problème")
	var e0: Dictionary = p.elements[0]
	eq(e0.block, "el-gq9x1xqg", "identifiant de bloc")
	eq(e0.fields.nature, "rapporte", "nature")
	eq(e0.fields.credibilite, "3", "crédibilité")
	eq(e0.fields.vers, "[[Cercle des Lanternes]]", "champ contenant un lien")
	eq(e0.text, "[[Victor Morel]] dit avoir rejoint le [[Cercle des Lanternes]] « au printemps ».", "énoncé")
	eq(e0.line, 29, "numéro de ligne dans le fichier")
	eq(StructuredLines.link_target(e0.fields.de), "Victor Morel", "cible du lien")
	var alias_link := false
	for l in p.links:
		if l.target == "Inconnu - Manteau gris":
			alias_link = true
	ok(alias_link, "lien avec texte affiché résolu vers la note")


func test_faveur_mouvements() -> void:
	var p := _load("Faveurs/2026-10-10 Victor Morel envers Élise Varga.md")
	eq(p.movements.size(), 1, "1 mouvement")
	eq(p.movements[0].fields.mv, "creation", "type de mouvement")
	eq(p.movements[0].block, "mv-22gtqnez", "identifiant du mouvement")


func test_totaux_comme_le_validateur() -> void:
	# valider.py compte 12 éléments et 1 mouvement sur le coffre d'exemple.
	var nb_el := 0
	var nb_mv := 0
	for rel in ["Soirees/2026/2026-10-10 Valombre - Assemblée.md",
			"Sources/Presse/2026-10-12 Gazette de Valombre - Nominations.md",
			"Sources/Discord/2026-10-14 Discord Valombre - Salon de la Harpie.md",
			"Sources/Analyses/2026-10-18 Analyse - Allégeances de Victor Morel.md",
			"Faveurs/2026-10-10 Victor Morel envers Élise Varga.md"]:
		var p := _load(rel)
		nb_el += p.elements.size()
		nb_mv += p.movements.size()
	eq(nb_el, 12, "même nombre d'éléments que valider.py")
	eq(nb_mv, 1, "même nombre de mouvements que valider.py")


func test_cas_limites() -> void:
	var body := "## Éléments\n- A [nature:: observe] [credibilite:: 2 ^el-aaaaaaaa\n" + \
		"Paragraphe perdu\n- [ ] tâche mal placée\n```\n- [[Dans du code]] [nature:: x] ^el-bbbbbbbb\n```\n" + \
		"## Ailleurs\n- [[Libre]] [nature:: x]\n"
	var p := StructuredLines.parse_body(body, 1)
	eq(p.elements.size(), 1, "seule la ligne de la section compte")
	var msgs := []
	for pr in p.problems:
		msgs.append(pr.msg)
	ok(" ".join(msgs).contains("non fermé"), "champ non fermé signalé")
	ok(" ".join(msgs).contains("non structuré"), "paragraphe signalé")
	ok(" ".join(msgs).contains("tâche"), "tâche mal placée signalée")
	for l in p.links:
		ok(l.target != "Dans du code", "les liens dans le code sont ignorés")


func test_ajout_element() -> void:
	var body := "# T\n\n## Déroulé\nTexte\n\n## Éléments\n- Un. [nature:: observe] [credibilite:: 1] ^el-aaaaaaaa\n\n## À faire\n- [ ] x\n"
	var out := StructuredLines.append_to_section(body, "Éléments", "- Deux. [nature:: rumeur] [credibilite:: 4] ^el-bbbbbbbb")
	ok(out.contains("^el-aaaaaaaa\n- Deux."), "ajouté après le dernier élément")
	ok(out.contains("## À faire\n- [ ] x\n"), "la suite est intacte")
	eq(StructuredLines.parse_body(out, 1).elements.size(), 2, "2 éléments après ajout")
	var out2 := StructuredLines.append_to_section("# Note\nTexte", "Éléments", "- Un. ^el-cccccccc")
	eq(out2, "# Note\nTexte\n\n## Éléments\n- Un. ^el-cccccccc\n", "section créée à la fin")
