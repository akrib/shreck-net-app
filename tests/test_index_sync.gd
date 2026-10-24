extends "res://tests/base.gd"
## Index SQLite + synchronisation incrémentale sur une copie du coffre d'exemple.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const NoteDocument := preload("res://core/format/note_document.gd")
const SafeWriter := preload("res://core/storage/safe_writer.gd")

var root := ""
var repo: RefCounted
var index: RefCounted
var sc: RefCounted


func _prepare() -> void:
	root = temp_dir("coffre")
	copy_tree(example_vault(), root)
	repo = RepoAccess.new(root)
	var db := OS.get_user_data_dir() + "/tests_tmp/index.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	ok(index.open(db), "ouverture de l'index : " + index.last_error)
	sc = Scanner.new(repo, index)


func test_cycle_complet() -> void:
	_prepare()
	print("    (FTS5 %s)" % ("disponible" if index.fts else "absent : recherche simple"))
	# 1. première indexation
	var r: Dictionary = sc.scan()
	eq(r.files, 21, "21 notes vues : 20 typées + FORMAT.md (Modeles, Tableaux, Pieces ignorés)")
	eq(r.new, 21, "toutes nouvelles")
	var s: Dictionary = index.stats()
	eq(s.elements, 12, "12 éléments (comme valider.py)")
	eq(s.movements, 1, "1 mouvement (comme valider.py)")
	eq(s.errors, 0, "aucune erreur sur le coffre d'exemple")
	eq(int(s.types.get("personnage", 0)), 4, "4 personnages")
	eq(index.broken_link_count(), 0, "aucun lien cassé")
	var fp1: String = index.fingerprint()
	# 2. rien n'a changé
	r = sc.scan()
	eq(r.new + r.modified + r.deleted, 0, "resynchronisation sans changement")
	# 3. modification externe (comme GitSync ou Obsidian)
	var rel := "Personnages/Élise Varga.md"
	write_file(repo.abs_path(rel), FileAccess.get_file_as_string(repo.abs_path(rel)) + "\nAjout externe [[Note absente]].\n")
	r = sc.scan()
	eq(r.modified, 1, "modification externe détectée")
	eq(index.broken_link_count(), 1, "lien cassé détecté")
	# 4. renommage externe : même id, nouveau chemin
	DirAccess.rename_absolute(repo.abs_path("Lieux/Entrepôt des quais.md"), repo.abs_path("Lieux/Entrepôt du port.md"))
	r = sc.scan()
	eq(r.renamed.size(), 1, "renommage détecté par l'identifiant")
	eq(r.deleted, 0, "pas compté comme suppression")
	ok(index.broken_link_count() > 1, "les liens vers l'ancien nom sont signalés comme cassés")
	# 5. suppression externe
	DirAccess.remove_absolute(repo.abs_path("Concepts/Praxis.md"))
	r = sc.scan()
	eq(r.deleted, 1, "suppression détectée")
	# 6. identifiant en double (copie de fichier)
	write_file(repo.abs_path("Personnages/Copie de Victor.md"), FileAccess.get_file_as_string(repo.abs_path("Personnages/Victor Morel.md")))
	sc.scan()
	var doublon := false
	for p in index.problems():
		if str(p.message).contains("per-12m0sc1s"):
			doublon = true
	ok(doublon, "identifiant en double signalé")
	# 7. fichier invalide : signalé, jamais modifié
	write_file(repo.abs_path("Personnages/Cassé.md"), "---\ntype: personnage\ninfos:\n  age: 3\n---\n")
	sc.scan()
	var casse := false
	for p in index.problems():
		if p.path == "Personnages/Cassé.md" and p.level == "ERREUR":
			casse = true
	ok(casse, "note invalide signalée")
	eq(FileAccess.get_file_as_string(repo.abs_path("Personnages/Cassé.md")), "---\ntype: personnage\ninfos:\n  age: 3\n---\n", "note invalide intacte")
	# 8. reconstruction : supprimer l'index et le refaire donne le même contenu
	var fp_avant: String = index.fingerprint()
	var dump_avant: String = index.dump_text()
	var db: String = index.path
	index.close()
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	sc = Scanner.new(repo, index)
	sc.scan()
	eq(index.fingerprint(), fp_avant, "reconstruction identique à l'index incrémental")
	if index.fingerprint() != fp_avant:
		write_file(OS.get_user_data_dir() + "/tests_tmp/dump_incremental.txt", dump_avant)
		write_file(OS.get_user_data_dir() + "/tests_tmp/dump_reconstruit.txt", index.dump_text())
	ok(fp1 != fp_avant, "l'empreinte change bien quand le coffre change")
	var v: Dictionary = sc.verify()
	eq(v.hash_mismatch.size() + v.missing_in_index.size() + v.missing_on_disk.size(), 0, "vérification complète sans écart")
	index.close()


func test_recherche_et_retroliens() -> void:
	_prepare()
	sc.scan()
	var noms := func(rows: Array) -> Array:
		var out := []
		for r in rows:
			out.append(r.name)
		return out
	ok(noms.call(index.search("elysee")).has("Élysée de Valombre"), "recherche sans accents")
	ok(noms.call(index.search("ÉLYSÉE")).has("Élysée de Valombre"), "recherche en majuscules accentuées")
	ok(noms.call(index.search("notaire")).has("Victor Morel"), "recherche par alias")
	ok(noms.call(index.search("manteau gris")).has("Inconnu - Manteau gris"), "plusieurs mots")
	eq(index.search("zzzzzz").size(), 0, "aucun résultat")
	eq(index.search("vict", 50, "personnage").size(), 1, "préfixe + filtre par type")
	var back: Array = noms.call(index.backlinks("Victor Morel"))
	ok(back.has("2026-10-10 Valombre - Assemblée"), "rétrolien depuis la soirée")
	ok(back.has("Victor Morel membre du Cercle des Lanternes"), "rétrolien depuis l'indice")
	index.close()


func test_enregistrement_puis_index() -> void:
	_prepare()
	sc.scan()
	var rel := "Soirees/2026/2026-10-10 Valombre - Assemblée.md"
	var bytes := FileAccess.get_file_as_bytes(repo.abs_path(rel))
	var doc = NoteDocument.from_bytes(bytes)
	doc.set_properties({"presents": ["[[Victor Morel]]", "[[Élise Varga]]"]})
	var w: Dictionary = SafeWriter.new(repo).write(rel, doc.to_bytes(), RepoAccess.hash_bytes(bytes))
	ok(w.ok, "enregistrement vérifié")
	eq(sc.reindex_one(rel), "", "réindexation")
	var r: Dictionary = sc.scan()
	eq(r.modified, 0, "la synchronisation suivante ne voit rien de nouveau")
	var after := FileAccess.get_file_as_string(repo.abs_path(rel))
	ok(after.contains("## Éléments\n- [[Victor Morel]] dit avoir rejoint"), "corps intact")
	ok(not after.contains("Armand Lescure]]\"\npresents_incertains"), "liste modifiée")
	index.close()


func test_listage_et_pieces_jointes() -> void:
	_prepare()
	DirAccess.make_dir_recursive_absolute(repo.abs_path("Pieces"))
	write_file(repo.abs_path("Pieces/capture.png"), "pas une vraie image")
	write_file(repo.abs_path("Pieces/2026 Discord brut.md"), "texte brut\n")
	write_file(repo.abs_path("Sources/Avec pièces.md"), "---\ntype: source\n---\nVoir ![[capture.png]] et [[2026 Discord brut]].\n")
	DirAccess.make_dir_recursive_absolute(repo.abs_path(".cache"))
	write_file(repo.abs_path(".cache/Cachée.md"), "cachée\n")
	write_file(repo.abs_path("Personnages/.cachee.md"), "cachée\n")
	DirAccess.make_dir_recursive_absolute(repo.abs_path("Bizarre.md"))
	write_file(repo.abs_path("Bizarre.md/Dedans.md"), "dedans\n")
	DirAccess.make_dir_recursive_absolute(repo.abs_path("Saison 2.5"))
	write_file(repo.abs_path("Saison 2.5/Note de saison.md"), "saison\n")
	write_file(repo.abs_path("Personnages/MAJUSCULES.MD"), "maj\n")
	var lst: Dictionary = repo.list_files()
	ok(lst.md.has("Sources/Avec pièces.md"), "nouvelle note listée")
	ok(lst.md.has("Saison 2.5/Note de saison.md"), "dossier avec un point dans le nom parcouru")
	ok(lst.md.has("Personnages/MAJUSCULES.MD"), "extension .MD en majuscules")
	ok(not lst.md.has(".cache/Cachée.md") and not lst.md.has("Personnages/.cachee.md"), "noms commençant par un point ignorés")
	ok(not lst.md.has("Pieces/2026 Discord brut.md"), "note d'un dossier ignoré : pas indexée comme note")
	ok(lst.other.has("Pieces/2026 Discord brut.md") and lst.other.has("Pieces/capture.png"), "… mais listée comme pièce jointe")
	var sorted_md: Array = lst.md.duplicate()
	sorted_md.sort()
	eq(lst.md, sorted_md, "liste triée (résultat identique sur toutes les plateformes)")
	var r: Dictionary = sc.scan()
	eq(index.broken_link_count(), 0, "liens vers les pièces jointes (image et .md de Pieces) résolus")
	var err := ""
	for e in r.read_errors:
		err += str(e)
	ok(err.contains("Bizarre.md") and err.contains("dossier"), "dossier nommé « .md » signalé clairement : " + err)
	index.close()


func test_gros_lots() -> void:
	_prepare()
	sc.scan()
	var base: int = index.stats().files
	var fp_base: String = index.fingerprint()
	DirAccess.make_dir_recursive_absolute(repo.abs_path("Lot"))
	for i in 450:
		write_file(repo.abs_path("Lot/Note %03d.md" % i),
			"---\ntype: indice\nid: ind-%s\nschema: 1\n---\n## Éléments\n- [[Victor Morel]] fait %d. [nature:: observe] [credibilite:: 2] ^el-x%07d\n" % [
				"%08d" % i, i, i])
	var r: Dictionary = sc.scan()
	eq(r.new, 450, "450 nouvelles notes (plusieurs lots de lecture et d'écriture)")
	eq(index.stats().files, base + 450, "toutes indexées")
	eq(int(index.stats().elements), 12 + 450, "leurs éléments aussi")
	# modifications et renommages mêlés
	for i in 10:
		var p: String = repo.abs_path("Lot/Note %03d.md" % i)
		write_file(p, FileAccess.get_file_as_string(p) + "Ajout %d [[Élise Varga]].\n" % i)
	for i in range(10, 15):
		DirAccess.rename_absolute(repo.abs_path("Lot/Note %03d.md" % i), repo.abs_path("Lot/Renommée %03d.md" % i))
	r = sc.scan()
	eq(r.modified, 10, "10 modifications")
	eq(r.renamed.size(), 5, "5 renommages")
	var fp_mid: String = index.fingerprint()
	var db: String = index.path
	index.close()
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	sc = Scanner.new(repo, index)
	sc.scan()
	eq(index.fingerprint(), fp_mid, "reconstruction identique après lots mêlés")
	# suppression de tout le lot (plus de 400 : plusieurs requêtes de suppression)
	for f in DirAccess.get_files_at(repo.abs_path("Lot")):
		DirAccess.remove_absolute(repo.abs_path("Lot/" + f))
	r = sc.scan()
	eq(r.deleted, 450, "450 suppressions")
	eq(index.fingerprint(), fp_base, "index revenu exactement à l'état initial")
	index.close()
