extends "res://tests/base.gd"
## Une note relue puis réécrite sans modification doit être identique à l'octet près.

const NoteDocument := preload("res://core/format/note_document.gd")


func _round(bytes: PackedByteArray, label: String) -> void:
	var doc = NoteDocument.from_bytes(bytes)
	eq(doc.to_bytes(), bytes, "aller-retour identique : " + label)


func test_aller_retour_octet_pres() -> void:
	var cas := {
		"LF": "---\ntype: lieu\nid: lie-7vqn8agc\n---\n# Titre\n\nCorps é à ç\n",
		"CRLF": "---\r\ntype: lieu\r\n---\r\n# Titre\r\nCorps\r\n",
		"sans saut final": "---\ntype: lieu\n---\n# Titre",
		"fermeture en dernière ligne": "---\ntype: lieu\n---",
		"frontmatter vide": "---\n---\nCorps\n",
		"sans frontmatter": "# Juste un titre\n\nTexte.\n",
		"vide": "",
		"frontmatter non fermé": "---\ntype: lieu\nCorps sans fin\n",
		"mélange de fins de ligne": "---\ntype: x\n---\nA\r\nB\nC\r\n",
	}
	for label in cas:
		_round(cas[label].to_utf8_buffer(), label)
	var bom := PackedByteArray([0xEF, 0xBB, 0xBF])
	bom.append_array("---\ntype: lieu\n---\nCorps\n".to_utf8_buffer())
	_round(bom, "BOM")
	for f in DirAccess.get_files_at(example_vault() + "/Personnages"):
		_round(FileAccess.get_file_as_bytes(example_vault() + "/Personnages/" + f), f)


func test_modifier_une_propriete_garde_le_corps() -> void:
	var src := "---\r\ntype: personnage\r\nstatut: actif\r\n---\r\n# Victor\r\n\r\nTexte  avec espaces  \r\n"
	var doc = NoteDocument.from_text(src)
	eq(doc.eol, "\r\n", "fins de ligne CRLF détectées")
	eq(doc.set_properties({"statut": "disparu"}), "", "propriété modifiée")
	var out: String = doc.to_text()
	eq(out, src.replace("statut: actif", "statut: disparu"), "seule la ligne modifiée change")


func test_modifier_le_corps() -> void:
	var doc = NoteDocument.from_text("---\r\ntype: x\r\n---\r\nAncien\r\n")
	doc.set_body("Nouveau\nsur deux lignes\n")
	eq(doc.to_text(), "---\r\ntype: x\r\n---\r\nNouveau\r\nsur deux lignes\r\n", "corps réécrit en CRLF")
	var doc2 = NoteDocument.from_text("# Sans propriétés\n")
	eq(doc2.set_properties({"type": "concept", "schema": 1}), "", "ajout de propriétés")
	eq(doc2.to_text(), "---\ntype: concept\nschema: 1\n---\n# Sans propriétés\n", "frontmatter créé")


func test_proprietes_illisibles_protegees() -> void:
	var doc = NoteDocument.from_text("---\ninfos:\n  age: 3\n---\nCorps\n")
	ok(not doc.can_edit_properties(), "propriétés non conformes : édition refusée")
	ok(doc.set_properties({"x": "y"}) != "", "set_properties refuse")
	eq(doc.to_text(), "---\ninfos:\n  age: 3\n---\nCorps\n", "texte intact")
	var bad := PackedByteArray([0x2D, 0x2D, 0x2D, 0x0A, 0xFF, 0xFE, 0x0A])
	var doc3 = NoteDocument.from_bytes(bad)
	ok(not doc3.utf8_ok, "UTF-8 invalide détecté")
