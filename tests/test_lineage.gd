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
	write_file(root + "/Groupes/Lignée Titi.md", "---\ntype: groupe\nid: grp-6b000014\nschema: 1\nnature: lignee\n---\n")
	write_file(root + "/Groupes/Lignée Tutu.md", "---\ntype: groupe\nid: grp-6b000015\nschema: 1\nnature: lignee\nclan: \"[[Nosferatu]]\"\n---\n")
	write_file(root + "/Groupes/Lignée X.md", "---\ntype: groupe\nid: grp-6b000016\nschema: 1\nnature: lignee\n---\n")
	write_file(root + "/Sources/Notes/2026-10-02 Lignées.md", "---\ntype: source\nid: src-6b000017\nschema: 1\nnature: note\nfiabilite: B\n---\n## Éléments\n"
		+ "- [[Dora]] est de la lignée de [[Lignée Tutu]]. [nature:: rapporte] [credibilite:: 3] [relation:: lignee_de] [de:: [[Dora]]] [vers:: [[Lignée Tutu]]] ^el-6b000018\n"
		+ "- [[Lignée Tutu]] est de la lignée de [[Lignée Titi]]. [nature:: rapporte] [credibilite:: 2] [relation:: lignee_de] [de:: [[Lignée Tutu]]] [vers:: [[Lignée Titi]]] ^el-6b000019\n"
		+ "- [[Aïeul]] est de la lignée de [[Lignée Titi]]. [nature:: rapporte] [credibilite:: 2] [relation:: lignee_de] [de:: [[Aïeul]]] [vers:: [[Lignée Titi]]] ^el-6b00001a\n"
		+ "- [[Cyprien]] est membre de [[Lignée X]]. [nature:: rapporte] [credibilite:: 3] [relation:: membre_de] [de:: [[Cyprien]]] [vers:: [[Lignée X]]] ^el-6b00001b\n"
		+ "- [[Hélène]] est membre de [[Lignée Tutu]]. [nature:: rapporte] [credibilite:: 3] [relation:: membre_de] [de:: [[Hélène]]] [vers:: [[Lignée Tutu]]] ^el-6b00001c\n"
		+ "- [[Lignée X]] est de la lignée de [[Lignée Titi]]. [nature:: rapporte] [credibilite:: 3] [relation:: lignee_de] [de:: [[Lignée X]]] [vers:: [[Lignée Titi]]] ^el-6b00001e\n"
		+ "- [[Gaspard]] est de la lignée de [[Lignée X]]. [nature:: rapporte] [credibilite:: 3] [relation:: lignee_de] [de:: [[Gaspard]]] [vers:: [[Lignée X]]] ^el-6b00001d\n")
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
	ok(fams.size() == 2 and fams[0].size == 10, "lignées comprises : %d lignage(s), %d nœuds dans le premier" % [fams.size(), fams[0].size if not fams.is_empty() else 0])
	var f: Dictionary = fams[0]
	var lv := {}
	for k in f.nodes:
		if f.nodes[k].kind == "personne":
			lv[f.nodes[k].name] = f.nodes[k].level
	ok(lv["Brune"] > lv["Aïeul"] and lv["Dora"] > lv["Brune"] and lv["Ézéchiel"] > lv["Cyprien"], "générations dans l'ordre : " + str(lv))
	var ez := TextNorm_key("Ézéchiel")
	ok(f.conflicts.has(ez) and f.parent[ez] == TextNorm_key("Brune"), "Ézéchiel a deux sires : signalé ; la fiche l'emporte pour la disposition")
	eq(f.nodes[TextNorm_key("Aïeul")].clan, "Nosferatu", "clan lu dans la fiche")
	eq(Lineage.family_index(fams, "Hélène"), 0, "retrouver la famille d'une personne")
	eq(Lineage.family_index(fams, "Isolé"), 1, "une ancienne fiche qui porte la lignée en clan : avec sa lignée")
	eq(Lineage.family_index(fams, "Personne"), -1, "personne inconnue")
	index.close()


func test_lignees() -> void:
	var index = _prepare()
	var fams: Array = Lineage.families(index)
	var f: Dictionary = fams[0]
	var key := func(n: String) -> String: return TextNorm_key(n)
	var tutu := "lig:" + TextNorm_key("Lignée Tutu")
	var titi := "lig:" + TextNorm_key("Lignée Titi")
	var lx := "lig:" + TextNorm_key("Lignée X")
	var brune: Dictionary = f.nodes[key.call("Brune")].lignees
	ok(brune.has(tutu) and not brune[tutu].declared and brune[tutu].via == [key.call("Dora")], "Dora est de Tutu : son sire Brune l'est aussi (déduit)")
	var aieul: Dictionary = f.nodes[key.call("Aïeul")].lignees
	ok(aieul.has(titi) and not aieul.has(tutu) and not aieul.has(lx), "Aïeul, déclaré de Titi (dont Tutu et X descendent) : la déduction s'arrête, sans incohérence")
	eq(f.incoherent.keys().map(func(k): return f.nodes[k].name), ["Gaspard"], "Gaspard : Lignée X déclarée, Tutu déduite d'Hélène — incohérent")
	var by := {}
	for e in f.edges:
		by["%s>%s" % [e.a, e.b]] = e
	ok(by.has(tutu + ">" + key.call("Brune")) and by[tutu + ">" + key.call("Brune")].style == "lig_dashed", "Tutu → Brune : lignée déduite (pointillés)")
	ok(not by.has(tutu + ">" + key.call("Dora")), "Tutu passe par Brune : pas de second trait vers Dora")
	ok(by.has(titi + ">" + tutu) and by[titi + ">" + tutu].kind == "hierarchie", "Titi → Tutu : une lignée issue d'une autre")
	ok(by[lx + ">" + key.call("Gaspard")].style == "bad" and by[tutu + ">" + key.call("Gaspard")].style == "bad", "lignées incohérentes : en rouge")
	ok(by[lx + ">" + key.call("Cyprien")].style == "lig", "« est membre de » une lignée vaut « est de la lignée de »")
	var ar: Dictionary = Lineage.around(f, key.call("Dora"))
	var arn := ar.keys().map(func(k): return f.nodes[k].name)
	arn.sort()
	eq(arn, ["Aïeul", "Brune", "Dora", "Lignée Titi", "Lignée Tutu"], "point de départ Dora : ses ascendants, sires et lignées")
	var pl: Dictionary = Lineage.person_lignees(index, "Brune")
	ok(pl.lignees.has(tutu) and pl.lignees[tutu].via == ["Dora"] and pl.bad.is_empty(), "fiche de Brune : Tutu, déduite de Dora")
	var pg: Dictionary = Lineage.person_lignees(index, "Gaspard")
	eq(pg.bad.size(), 2, "fiche de Gaspard : deux lignées qui ne s'accordent pas")
	eq(Lineage.person_lignees(index, "Aïeul").specific, [titi], "fiche d'Aïeul : Titi")
	index.close()


func test_clans_et_lignees() -> void:
	var index = _prepare()
	var t: Array = Lineage.clans_tree(index)
	eq(t.map(func(c): return c.name), ["Nosferatu", "Clan inconnu"], "les clans, puis les lignées sans clan")
	eq([t[0].members, t[0].lignees.map(func(l): return [l.name, l.members])], [3, [["Lignée Tutu", 2], ["Nosferatu antitribu", 1]]], "membres du clan, lignées et leurs membres")
	eq(t[1].lignees.map(func(l): return l.name), ["Gargouilles", "Lignée Titi", "Lignée X"], "lignées sans clan connu")
	index.close()


static func TextNorm_key(s: String) -> String:
	return preload("res://core/format/text_norm.gd").name_key(s)
