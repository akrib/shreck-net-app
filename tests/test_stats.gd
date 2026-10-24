extends "res://tests/base.gd"
## Statistiques : personnages (filtres, répartitions, informations et rétroliens,
## disciplines constatées) et informations (échelle de l'Amirauté).

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Stats := preload("res://core/analysis/stats.gd")

var index: RefCounted


func _prepare() -> void:
	var root := temp_dir("coffre-stats")
	write_file(root + "/Personnages/Aline.md", "---\ntype: personnage\nid: per-57a00001\nschema: 1\nstatut: actif\nrang: ancilla\nclan: \"[[Nosferatu]]\"\nsecte: \"[[Camarilla]]\"\ndomaine: \"[[Lyon]]\"\ndisciplines:\n  - \"[[Occultation]]\"\n---\n")
	write_file(root + "/Personnages/Bruno.md", "---\ntype: personnage\nid: per-57a00002\nschema: 1\nstatut: torpeur\nrang: ancien\nclan: \"[[Nosferatu]]\"\ndomaine: \"[[Lyon]]\"\n---\n")
	write_file(root + "/Personnages/Cyril.md", "---\ntype: personnage\nid: per-57a00003\nschema: 1\nstatut: mort_finale\nclan: \"[[Ventrue]]\"\n---\n")
	write_file(root + "/Personnages/Denis.md", "---\ntype: personnage\nid: per-57a00004\nschema: 1\n---\n")
	write_file(root + "/Sources/Forum/2026-10-01 Rapport.md", "---\ntype: source\nid: src-57a00005\nschema: 1\nnature: forum\nfiabilite: B\ndate: 2026-10-01\ndomaine: \"[[Lyon]]\"\nauteur: \"[[Aline]]\"\n---\n## Éléments\n"
		+ "- [[Aline]] a disparu de la vue de tous. [nature:: observe] [credibilite:: 1] [discipline:: [[Occultation]]] ^el-57a00006\n"
		+ "- [[Bruno]] dort sous la ville. [nature:: rumeur] [credibilite:: 4] ^el-57a00007\n"
		+ "- [[Aline]] et [[Bruno]] se parlent. [nature:: rapporte] [credibilite:: 2] [par:: [[Bruno]]] [date_faits:: 2025-03] ^el-57a00008\n")
	write_file(root + "/Sources/Notes/Notes.md", "---\ntype: source\nid: src-57a00009\nschema: 1\nnature: note\n---\nJ'ai croisé [[Aline]].\n\n## Éléments\n- [[Cyril]] serait revenu. [nature:: hypothese] [credibilite:: 6] [discipline:: [[Domination]]] ^el-57a0000a\n")
	var db := OS.get_user_data_dir() + "/tests_tmp/stats.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()


func _by(list: Array) -> Dictionary:
	var d := {}
	for p in list:
		d[p.name] = p
	return d


func test_personnages() -> void:
	_prepare()
	var all: Array = Stats.people(index)
	eq(all.size(), 4, "quatre fiches")
	var p := _by(all)
	eq([p.Aline.infos, p.Aline.backlinks], [2, 2], "Aline : deux éléments la citent, deux notes (le rapport, les notes)")
	eq([p.Bruno.infos, p.Denis.infos], [2, 0], "Bruno : deux éléments ; Denis : aucun")
	eq(p.Aline.disciplines, ["Occultation"], "discipline de la fiche et constatée, comptée une fois")
	eq(p.Cyril.disciplines, ["Domination"], "discipline constatée dans un élément qui le cite")
	var alive: Array = Stats.filter_people(all, {"statuts": ["actif", "torpeur"]})
	eq(_by(alive).keys().size(), 2, "filtre sur le statut")
	eq(Stats.filter_people(all, {"min_infos": 1}).size(), 3, "au moins une information")
	eq(Stats.filter_people(all, {"min_backlinks": 2}).size(), 1, "au moins deux rétroliens")
	var clans: Array = Stats.breakdown(all, "clan")
	eq(clans, [["Nosferatu", "Nosferatu", 2], ["Ventrue", "Ventrue", 1], ["", "Clan inconnu", 1]], "répartition par clan, l'inconnu en dernier")
	var st: Array = Stats.breakdown(all, "statut")
	ok(st.any(func(x): return x[1] == "Torpeur") and st[-1][1] == "Non renseigné", "statuts : la torpeur, le non renseigné en dernier")
	eq(Stats.breakdown(all, "rang")[0][2], 1, "âges")
	eq(Stats.breakdown(all, "discipline").map(func(x): return x[2]), [1, 1, 2], "disciplines : une par personne et par discipline, puis « aucune connue »")
	index.close()


func test_informations() -> void:
	_prepare()
	var all: Array = Stats.infos(index)
	eq(all.size(), 4, "quatre éléments")
	var cotes: Array = all.map(func(x): return x.cote)
	cotes.sort()
	eq(cotes, ["?6", "B1", "B2", "B4"], "cote : fiabilité de la note, crédibilité de l'élément")
	eq(Stats.info_breakdown(all, "fiab").map(func(x): return [x[1], x[2]]), [["B — Habituellement fiable", 3], ["Fiabilité non notée", 1]], "fiabilité, dans l'ordre de l'échelle")
	eq(Stats.info_breakdown(all, "cred").map(func(x): return x[0]), ["1", "2", "4", "6"], "crédibilité dans l'ordre")
	var years: Array = Stats.info_breakdown(all, "year").map(func(x): return x[0])
	eq(years, ["2026", "2025", ""], "années : date des faits, sinon de la note ; les plus récentes d'abord")
	var voices: Array = Stats.info_breakdown(all, "voice")
	ok(voices[0][1] == "Aline" and voices[0][2] == 2, "voix : l'auteur, sauf « par »")
	ok(Stats.info_breakdown(all, "kind")[0][1] == "Source · Forum", "type de note")
	var s: Dictionary = Stats.info_summary(all)
	eq([s.total, s.notes, s.solid, s.weak, s.unrated, s.rumors], [4, 2, 2, 1, 1, 1], "chiffres clés")
	eq(Stats.admiralty_grid(all).get("B1", 0), 1, "grille de l'Amirauté")
	index.close()
