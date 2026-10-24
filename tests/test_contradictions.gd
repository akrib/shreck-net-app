extends "res://tests/base.gd"
## Contradictions à trancher : deux endroits la même nuit, deux sires, alliés et
## ennemis, poste unique tenu deux fois, faveur et mort, même personne ?

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Contra := preload("res://core/analysis/contradictions.gd")

var index: RefCounted


func _perso(root: String, name: String, id: String, extra := "") -> void:
	write_file(root + "/Personnages/%s.md" % name, "---\ntype: personnage\nid: per-%s\nschema: 1\n%s---\n# %s\n" % [id, extra, name])


func _prepare() -> String:
	var root := temp_dir("coffre-contradictions")
	_perso(root, "Aline", "c0a00001", "sire: \"[[Bruno]]\"\n")
	_perso(root, "Bruno", "c0a00002")
	_perso(root, "Cyril", "c0a00003")
	_perso(root, "Denis", "c0a00004", "titres:\n  - Prince de Valombre\n")
	_perso(root, "Émile", "c0a00005", "titres:\n  - Prince de Valombre\n  - Prince\n")
	_perso(root, "Fanny", "c0a00006", "statut: mort_finale\ntitres:\n  - Prince de Valombre\n")
	_perso(root, "Gaston", "c0a00007", "titres:\n  - Prince\n")
	_perso(root, "Hugo", "c0a00008", "statut: mort_finale\n")
	_perso(root, "Iris", "c0a00009", "aliases:\n  - La Rousse\n")
	_perso(root, "Jade", "c0a0000a", "aliases:\n  - La Rousse\n")
	_perso(root, "Karl", "c0a0000b", "peut_etre:\n  - \"[[Léo]]\"\n")
	_perso(root, "Léo", "c0a0000c", "aliases:\n  - Karl\n")
	write_file(root + "/Domaines/Valombre.md", "---\ntype: domaine\nid: dom-c0a0000d\nschema: 1\n---\n")
	write_file(root + "/Lieux/Élysée.md", "---\ntype: lieu\nid: lie-c0a0000e\nschema: 1\ndomaine: \"[[Valombre]]\"\n---\n")
	write_file(root + "/Lieux/Entrepôt.md", "---\ntype: lieu\nid: lie-c0a0000f\nschema: 1\ndomaine: \"[[Valombre]]\"\n---\n")
	write_file(root + "/Soirees/2026/2026-10-10 Valombre - Assemblée.md", "---\ntype: soiree\nid: soi-c0a00010\nschema: 1\ndate: 2026-10-10\ndomaine: \"[[Valombre]]\"\nlieu: \"[[Élysée]]\"\npresents:\n  - \"[[Bruno]]\"\n---\n")
	write_file(root + "/Faveurs/2026-10-01 Denis envers Hugo.md", "---\ntype: faveur\nid: fav-c0a00011\nschema: 1\ndebiteur: \"[[Denis]]\"\ncreancier: \"[[Hugo]]\"\nniveau: mineure\nstatut: active\ncredibilite: 2\n---\n")
	write_file(root + "/Sources/Notes/2026-10-12 Notes.md", "---\ntype: source\nid: src-c0a00012\nschema: 1\nnature: note\nfiabilite: C\n---\n## Éléments\n"
		+ "- Cyril est le sire d'Aline. [nature:: rapporte] [credibilite:: 3] [relation:: sire_de] [de:: [[Cyril]]] [vers:: [[Aline]]] ^el-c0a00013\n"
		+ "- Bruno et Cyril sont alliés. [nature:: observe] [credibilite:: 2] [relation:: allie] [de:: [[Bruno]]] [vers:: [[Cyril]]] ^el-c0a00014\n"
		+ "- Cyril hait Bruno. [nature:: rapporte] [credibilite:: 3] [relation:: ennemi] [de:: [[Cyril]]] [vers:: [[Bruno]]] ^el-c0a00015\n"
		+ "- Denis serait l'ennemi d'Iris. [nature:: rumeur] [credibilite:: 5] [relation:: ennemi] [de:: [[Denis]]] [vers:: [[Iris]]] ^el-c0a00016\n"
		+ "- Denis et Iris sont alliés. [nature:: observe] [credibilite:: 2] [relation:: allie] [de:: [[Denis]]] [vers:: [[Iris]]] ^el-c0a00017\n"
		+ "- [[Bruno]] était à l'entrepôt ce soir-là. [nature:: observe] [credibilite:: 1] [relation:: present_a] [de:: [[Bruno]]] [vers:: [[Entrepôt]]] [date_faits:: 2026-10-10] ^el-c0a00018\n")
	var db := OS.get_user_data_dir() + "/tests_tmp/contradictions.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()
	return root


func _of(all: Array, kind: String) -> Array:
	return all.filter(func(c): return c.kind == kind)


func test_contradictions() -> void:
	_prepare()
	var all: Array = Contra.build(index)
	var two := _of(all, "deux_endroits")
	eq(two.size(), 1, "Bruno noté à l'Élysée et à l'entrepôt la même nuit")
	ok(two.size() == 1 and str(two[0].title).begins_with("Bruno, nuit du 2026-10-10"), "titre : " + (str(two[0].title) if two.size() > 0 else ""))
	var sires := _of(all, "sire")
	eq(sires.size(), 1, "deux sires pour Aline (fiche : Bruno ; élément : Cyril)")
	ok(sires.size() == 1 and sires[0].who.has("Bruno") and sires[0].who.has("Cyril"), "les deux sires nommés : " + str(sires[0].who if sires.size() > 0 else []))
	var rel := _of(all, "relation")
	eq(rel.size(), 1, "Bruno et Cyril alliés et ennemis ; Denis et Iris non (l'inimitié est réfutée, crédibilité 5)")
	ok(rel.size() == 1 and str(rel[0].title).contains("Bruno et Cyril"), "le bon couple")
	var postes := _of(all, "poste")
	eq(postes.size(), 1, "« Prince de Valombre » sur deux fiches en vie (pas Fanny, morte ; « Prince » seul ne compte pas)")
	ok(postes.size() == 1 and postes[0].who == ["Denis", "Émile"], "Denis et Émile : " + str(postes[0].who if postes.size() > 0 else []))
	var fav := _of(all, "faveur")
	eq(fav.size(), 1, "faveur active envers Hugo, mort")
	var ids := _of(all, "identite")
	eq(ids.size(), 2, "Iris et Jade (« La Rousse ») ; Karl et Léo (peut-être, et alias), une seule fois")
	var kl: Array = ids.filter(func(c): return str(c.title).begins_with("Karl et Léo"))
	ok(kl.size() == 1 and kl[0].detail.size() == 2, "Karl et Léo : les deux raisons réunies : " + str(kl[0].detail if kl.size() > 0 else []))
	eq(all[0].kind, "deux_endroits", "les plus graves d'abord")
	ok(all.all(func(c): return not (c.paths as Array).is_empty()), "chaque contradiction mène à des notes")
	index.close()
