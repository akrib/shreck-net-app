extends "res://tests/base.gd"
## Filiations : liens sire → infant (fiche, éléments, indices), familles et
## générations, double sire ; clans et lignées.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Lineage := preload("res://core/analysis/lineage.gd")


func _prepare() -> RefCounted:
	var root := temp_dir("coffre-filiations")
	var per := func(name: String, id: String, extra := "") -> void:
		write_file(root + "/Personnages/%s.md" % name, "---\ntype: personnage\nid: per-%s\nschema: 1\n%s---\n" % [id, extra])
	per.call("Aïeul", "6b000001", "clan: \"[[Nosferatu]]\"\nrang: venerable\n")
	per.call("Brune", "6b000002", "clan: \"[[Nosferatu]]\"\nsire: \"[[Aïeul]]\"\n")
	per.call("Cyprien", "6b000003", "clan: \"[[Nosferatu]]\"\n")
	per.call("Dora", "6b000004")
	per.call("Ézéchiel", "6b000005", "sire: \"[[Brune]]\"\n")
	per.call("Fantôme", "6b000006")
	per.call("Gaspard", "6b000007")
	per.call("Hélène", "6b000008")
	per.call("Isolé", "6b000009", "clan: \"[[Nosferatu antitribu]]\"\n")
	write_file(root + "/Sources/Notes/2026-10-01 Notes.md", "---\ntype: source\nid: src-6b00000a\nschema: 1\nnature: note\nfiabilite: B\n---\n## Éléments\n"
		+ "- [[Aïeul]] a étreint [[Cyprien]]. [nature:: rapporte] [credibilite:: 2] [relation:: sire_de] [de:: [[Aïeul]]] [vers:: [[Cyprien]]] ^el-6b00000b\n"
		+ "- [[Brune]] a étreint [[Dora]]. [nature:: rumeur] [credibilite:: 4] [relation:: sire_de] [de:: [[Brune]]] [vers:: [[Dora]]] ^el-6b00000c\n"
		+ "- [[Cyprien]] serait le sire d'[[Ézéchiel]]. [nature:: rapporte] [credibilite:: 3] [relation:: sire_de] [de:: [[Cyprien]]] [vers:: [[Ézéchiel]]] ^el-6b00000d\n"
		+ "- [[Aïeul]] aurait étreint [[Fantôme]]. [nature:: rumeur] [credibilite:: 5] [relation:: sire_de] [de:: [[Aïeul]]] [vers:: [[Fantôme]]] ^el-6b00000e\n"
		+ "- [[Aïeul]] a étreint [[Cyprien]], dit-on aussi. [nature:: rumeur] [credibilite:: 4] [relation:: sire_de] [de:: [[Aïeul]]] [vers:: [[Cyprien]]] ^el-6b00000f\n")
	write_file(root + "/Indices/Gaspard sire d'Hélène.md", "---\ntype: indice\nid: ind-6b000010\nschema: 1\nstatut: non_verifie\ncredibilite: 3\nrelation: sire_de\nde: \"[[Gaspard]]\"\nvers: \"[[Hélène]]\"\npour:\n  - \"[[2026-10-01 Notes#^el-6b00000b]]\"\n---\n")
	write_file(root + "/Groupes/Nosferatu.md", "---\ntype: groupe\nid: grp-6b000011\nschema: 1\nnature: clan\n---\n")
	write_file(root + "/Groupes/Nosferatu antitribu.md", "---\ntype: groupe\nid: grp-6b000012\nschema: 1\nnature: lignee\nclan: \"[[Nosferatu]]\"\n---\n")
	write_file(root + "/Groupes/Gargouilles.md", "---\ntype: groupe\nid: grp-6b000013\nschema: 1\nnature: lignee\n---\n")
	var db := OS.get_user_data_dir() + "/tests_tmp/filiations.sqlite"
	IndexStore.delete_files(db)
	var index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()
	return index


func test_liens_et_familles() -> void:
	var index = _prepare()
	var links: Array = Lineage.sire_links(index)
	var pairs := links.map(func(l): return "%s>%s" % [l.sire, l.infant])
	pairs.sort()
	eq(pairs, ["Aïeul>Brune", "Aïeul>Cyprien", "Brune>Dora", "Brune>Ézéchiel", "Cyprien>Ézéchiel", "Gaspard>Hélène"],
		"fiche, éléments, indice ; la rumeur de crédibilité 5 est écartée")
	var ac: Array = links.filter(func(l): return l.infant == "Cyprien")
	ok(ac[0].sources.size() == 2 and ac[0].cred == 2 and ac[0].sure, "deux sources pour un même lien : la meilleure crédibilité")
	ok(not links.filter(func(l): return l.infant == "Dora")[0].sure, "une rumeur (crédibilité 4) : lien incertain")
	var fams: Array = Lineage.families(index, links)
	eq(fams.map(func(f): return [f.label, f.size, f.depth]), [["Lignage de Aïeul", 5, 3], ["Lignage de Gaspard", 2, 2]], "deux familles, la plus grande d'abord")
	var f: Dictionary = fams[0]
	var lv := {}
	for k in f.nodes:
		lv[f.nodes[k].name] = f.nodes[k].level
	eq(lv, {"Aïeul": 0, "Brune": 1, "Cyprien": 1, "Dora": 2, "Ézéchiel": 2}, "générations")
	var ez := TextNorm_key("Ézéchiel")
	ok(f.conflicts.has(ez) and f.parent[ez] == TextNorm_key("Brune"), "Ézéchiel a deux sires : signalé ; la fiche l'emporte pour la disposition")
	eq(f.nodes[TextNorm_key("Aïeul")].clan, "Nosferatu", "clan lu dans la fiche")
	eq(Lineage.family_index(fams, "Hélène"), 1, "retrouver la famille d'une personne")
	eq(Lineage.family_index(fams, "Isolé"), -1, "personne sans sire ni infant connu")
	index.close()


func test_clans_et_lignees() -> void:
	var index = _prepare()
	var t: Array = Lineage.clans_tree(index)
	eq(t.map(func(c): return c.name), ["Nosferatu", "Clan inconnu"], "les clans, puis les lignées sans clan")
	eq([t[0].members, t[0].lignees.map(func(l): return [l.name, l.members])], [3, [["Nosferatu antitribu", 1]]], "membres du clan, lignée et son membre")
	eq(t[1].lignees.map(func(l): return l.name), ["Gargouilles"], "lignée sans clan connu")
	index.close()


static func TextNorm_key(s: String) -> String:
	return preload("res://core/format/text_norm.gd").name_key(s)
