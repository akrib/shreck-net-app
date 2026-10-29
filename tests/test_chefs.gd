extends "res://tests/base.gd"
## Chef de lignée (format 1.7) : la lignée est montrée par son chef dans les
## lignages et le graphe ; la déduction s'arrête à lui ; ses lignées d'origine se
## déduisent de celles du chef ; chef proposé d'après le nom ; « À compléter ».

const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Lineage := preload("res://core/analysis/lineage.gd")
const GraphData := preload("res://core/analysis/graph_data.gd")
const Members := preload("res://core/analysis/members.gd")
const Contra := preload("res://core/analysis/contradictions.gd")


func _vault() -> String:
	var root := temp_dir("coffre-chefs")
	var per := func(name: String, id: String, extra := "") -> void:
		write_file(root + "/Personnages/%s.md" % name, "---\ntype: personnage\nid: per-%s\nschema: 1\n%s---\n" % [id, extra])
	per.call("Ancêtre", "8c000001", "clan: \"[[Nosferatu]]\"\n")
	per.call("Karios", "8c000002", "clan: \"[[Nosferatu]]\"\nsire: \"[[Ancêtre]]\"\n")
	per.call("Istvan", "8c000003", "clan: \"[[Nosferatu]]\"\nsire: \"[[Karios]]\"\n")
	per.call("Monsieur K", "8c000004", "clan: \"[[Nosferatu]]\"\nsire: \"[[Istvan]]\"\n")
	per.call("Carolus", "8c000005", "clan: \"[[Nosferatu]]\"\nsire: \"[[Karios]]\"\n")
	per.call("Macrin", "8c000006", "clan: \"[[Nosferatu]]\"\nsire: \"[[Carolus]]\"\n")
	per.call("Hyacinthe", "8c000007", "clan: \"[[Nosferatu]]\"\n")
	per.call("Stanislas (Paris)", "8c000008", "clan: \"[[Nosferatu]]\"\n")
	per.call("Stanislas (Lille)", "8c000009", "clan: \"[[Brujah]]\"\n")
	per.call("La Dame Noire", "8c00000a", "clan: \"[[Nosferatu]]\"\n")
	per.call("Hans Guteberg", "8c00000b", "clan: \"[[Nosferatu]]\"\naliases:\n  - Carnage\n")
	var grp := func(name: String, id: String, extra := "") -> void:
		write_file(root + "/Groupes/%s.md" % name, "---\ntype: groupe\nid: grp-%s\nschema: 1\n%s---\n# %s\n" % [id, extra, name])
	grp.call("Nosferatu", "8c00000c", "nature: clan\n")
	grp.call("Lignée de Karios", "8c00000d", "nature: lignee\nclan: \"[[Nosferatu]]\"\nchef: \"[[Karios]]\"\n")
	grp.call("Lignée d'Istvan", "8c00000e", "nature: lignee\nclan: \"[[Nosferatu]]\"\nchef: \"[[Istvan]]\"\n")
	grp.call("Lignée de Macrin", "8c00000f", "nature: lignee\nclan: \"[[Nosferatu]]\"\n")
	grp.call("Lignée de Stanislas", "8c00000g", "nature: lignee\nclan: \"[[Nosferatu]]\"\n")
	grp.call("Lignée de la Dame Noire", "8c00000h", "nature: lignee\nclan: \"[[Nosferatu]]\"\n")
	grp.call("Lignée de Carnage", "8c00000j", "nature: lignee\nclan: \"[[Nosferatu]]\"\n")
	grp.call("Lignée de Ferrand", "8c00000k", "nature: lignee\nclan: \"[[Nosferatu]]\"\n")
	write_file(root + "/Sources/Notes/2026-10-29 Notes.md", "---\ntype: source\nid: src-8c00000m\nschema: 1\nnature: note\nfiabilite: B\n---\n## Éléments\n"
		+ "- [[Monsieur K]] est de la lignée de [[Lignée d'Istvan]]. [nature:: rapporte] [credibilite:: 2] [relation:: lignee_de] [de:: [[Monsieur K]]] [vers:: [[Lignée d'Istvan]]] ^el-8c00000n\n"
		+ "- [[Hyacinthe]] est de la lignée de [[Lignée de Macrin]]. [nature:: rapporte] [credibilite:: 3] [relation:: lignee_de] [de:: [[Hyacinthe]]] [vers:: [[Lignée de Macrin]]] ^el-8c00000p\n"
		+ "- [[Lignée de Macrin]] est de la lignée de [[Lignée de Karios]]. [nature:: rapporte] [credibilite:: 3] [relation:: lignee_de] [de:: [[Lignée de Macrin]]] [vers:: [[Lignée de Karios]]] ^el-8c00000q\n"
		+ "- [[Istvan]] est allié de [[Lignée de Karios]]. [nature:: rapporte] [credibilite:: 3] [relation:: allie] [de:: [[Istvan]]] [vers:: [[Lignée de Karios]]] ^el-8c00000r\n")
	return root


func _index(root: String) -> RefCounted:
	var db := OS.get_user_data_dir() + "/tests_tmp/chefs.sqlite"
	IndexStore.delete_files(db)
	var index = IndexStore.new()
	index.open(db)
	Scanner.new(preload("res://core/storage/repo_access.gd").new(root), index).scan()
	return index


func test_modele() -> void:
	var index = _index(_vault())
	var ligs: Dictionary = Lineage.lignees(index)
	eq([ligs["lig:lignée de karios"].chef, ligs["lig:lignée de karios"].chef_key], ["Karios", "karios"], "le chef est lu dans la fiche de la lignée")
	eq(Lineage.chef_mention(["Lignée de Karios"]), "Chef de la lignée de Karios", "mention")
	eq(Lineage.chef_mention(["Lignée de Karios", "Lignée d'Istvan"]), "Chef de la lignée de Karios et de la lignée d'Istvan", "deux lignées")
	eq(Lineage.chef_mention(["Gargouilles"]), "Chef de la lignée Gargouilles", "lignée dont le nom ne commence pas par « Lignée »")
	var links: Array = Lineage.sire_links(index)
	var claims: Dictionary = Lineage.claims_with_chefs(index, ligs, links)
	var par: Dictionary = claims.parents.get("lig:lignée d'istvan", {})
	ok(par.has("lig:lignée de karios") and par["lig:lignée de karios"][0].get("deduced", false),
		"Istvan, chef de sa lignée, est l'infant du chef de la lignée de Karios : la lignée d'Istvan en descend (déduit, rien d'écrit)")
	var mem: Dictionary = Lineage.memberships(links, claims)
	ok(mem.get("karios", {}).has("lig:lignée de karios") and mem.karios["lig:lignée de karios"].declared, "le chef est de sa lignée")
	ok(not mem.get("ancêtre", {}).has("lig:lignée de karios"), "la déduction s'arrête au chef : son sire n'est pas de la lignée")
	ok(not mem.get("karios", {}).has("lig:lignée d'istvan"), "ni au-dessus du chef de la lignée d'Istvan")
	var fams: Array = Lineage.families(index, links)
	var fi := Lineage.family_index(fams, "Karios")
	var f: Dictionary = fams[fi]
	ok(not f.nodes.has("lig:lignée de karios") and not f.nodes.has("lig:lignée d'istvan"), "lignage : plus de case pour une lignée qui a un chef")
	eq(f.nodes.karios.heads, ["lig:lignée de karios"], "la case de Karios porte sa lignée")
	ok(f.nodes.has("lig:lignée de macrin"), "une lignée sans chef garde sa case")
	eq(Lineage.node_key(f, "lig:lignée de karios"), "karios", "la lignée renvoie à la case de son chef")
	eq(Lineage.lignee_name(f, "lig:lignée d'istvan"), "Lignée d'Istvan", "son nom reste connu")
	eq(Lineage.family_index(fams, "Lignée de Karios"), fi, "chercher la lignée trouve le lignage de son chef")
	var ki: Array = f.edges.filter(func(e): return e.a == "karios" and e.b == "istvan")
	ok(ki.size() == 1 and ki[0].kind == "sire", "Karios → Istvan : un seul trait, le lien sire → infant")
	var km: Array = f.edges.filter(func(e): return e.a == "karios" and e.b == "lig:lignée de macrin")
	ok(km.size() == 1 and km[0].kind == "hierarchie", "la lignée de Macrin est issue de la case de Karios")
	ok(f.edges.all(func(e): return not str(e.a).begins_with("lig:lignée de karios") and not str(e.b).begins_with("lig:lignée de karios")), "aucun lien ne vise la lignée elle-même")
	eq((f.lignees["lig:lignée d'istvan"].parents as Dictionary).keys(), ["lig:lignée de karios"], "la parenté des lignées reste dans le lignage")
	ok(f.incoherent.is_empty(), "rien d'incohérent : Monsieur K (Istvan) descend de Karios")
	var pl: Dictionary = Lineage.person_lignees(index, "Istvan")
	eq(pl.heads.map(func(h): return h.name), ["Lignée d'Istvan"], "fiche d'Istvan : chef de la lignée d'Istvan")
	ok((pl.bad as Array).is_empty(), "fiche d'Istvan : cohérente")
	var mk: Dictionary = Lineage.person_lignees(index, "Monsieur K")
	ok((mk.bad as Array).is_empty() and mk.lignees.has("lig:lignée d'istvan"), "fiche de Monsieur K : la lignée d'Istvan, cohérente")
	var rows: Array = Members.of_group(index, "Lignée de Karios")
	ok(rows.size() >= 1 and rows[0].name == "Karios" and rows[0].roles.has("chef") and Members.describe(rows[0]).contains("chef de lignée"),
		"membres de la lignée : le chef d'abord")
	index.close()


func test_graphe() -> void:
	var index = _index(_vault())
	var opts := {"relations": true, "indices": true, "faveurs": true, "structure": true, "copresence": false, "max_cred": 6,
		"max_nodes": 200, "lignees": true, "hide_codes": []}
	var g: Dictionary = GraphData.build(index, opts)
	ok(g.nodes.has("karios") and not g.nodes.has("lignée de karios"), "graphe : la lignée qui a un chef est montrée par lui")
	eq(g.nodes.karios.heads.map(func(h): return h.name), ["Lignée de Karios"], "graphe : la case de Karios porte la mention")
	var ally: Array = g.edges.filter(func(e): return e.a == "istvan" and e.b == "karios" and e.get("code", "") == "allie")
	ok(ally.size() == 1 and str(ally[0].get("suffix", "")).contains("Lignée de Karios"), "un lien vers la lignée passe au chef, en le disant")
	var g2: Dictionary = GraphData.build(index, opts.merged({"center": "Lignée de Karios", "depth": 1}))
	ok(g2.nodes.has("karios") and g2.nodes.karios.ring == 0, "centrer sur la lignée centre sur son chef")
	opts["chefs"] = false
	var g3: Dictionary = GraphData.build(index, opts)
	ok(g3.nodes.has("lignée de karios") and (g3.nodes.karios.heads as Array).is_empty(), "option décochée : la lignée a sa propre case")
	index.close()


func test_proposition_et_a_completer() -> void:
	var root := _vault()
	var index = _index(root)
	eq(Lineage.chef_candidates(index, "Lignée de Stanislas", "Nosferatu"), ["Stanislas (Paris)"], "homonyme précisé, du clan de la lignée")
	eq(Lineage.chef_candidates(index, "Lignée de Stanislas").size(), 2, "sans clan : les deux Stanislas")
	eq(Lineage.chef_candidates(index, "Lignée de la Dame Noire", "Nosferatu"), ["La Dame Noire"], "« de la » : La…")
	eq(Lineage.chef_candidates(index, "Lignée de Carnage", "Nosferatu"), ["Hans Guteberg"], "par l'alias")
	eq(Lineage.chef_candidates(index, "Lignée de Ferrand", "Nosferatu"), [], "personne de ce nom")
	eq(Lineage.chef_candidates(index, "Gargouilles"), [], "nom qui ne désigne personne")
	index.close()
	var AppService = load("res://core/app/app_service.gd")
	AppService.settings_file = "user://tests_tmp/reglages-chefs.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	var app: Node = AppService.new()
	app.background_jobs = false
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	IndexStore.delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()
	var comp: Array = Contra.build(app.index).filter(func(c): return c.kind == "completer")
	var prop: Array = comp.filter(func(c): return c.has("fix"))
	eq(prop.size(), 1, "« À compléter » : une proposition groupée")
	var pairs: Array = prop[0].fix.pairs
	pairs.sort_custom(func(a, b): return str(a[0]) < str(b[0]))
	eq(pairs, [["Groupes/Lignée de Carnage.md", "Hans Guteberg"], ["Groupes/Lignée de Macrin.md", "Macrin"],
		["Groupes/Lignée de Stanislas.md", "Stanislas (Paris)"], ["Groupes/Lignée de la Dame Noire.md", "La Dame Noire"]], "les chefs proposés d'après le nom")
	var free: Array = comp.filter(func(c): return not c.has("fix"))
	ok(free.size() == 1 and str(free[0].detail[1]).contains("Lignée de Ferrand"), "et la lignée sans proposition")
	var r: Dictionary = app.set_lignee_chefs(prop[0].fix.pairs)
	ok(r.done.size() == 4 and FileAccess.get_file_as_string(root + "/Groupes/Lignée de Macrin.md").contains("chef: \"[[Macrin]]\""), "« Renseigner » écrit le chef dans chaque fiche")
	ok(FileAccess.get_file_as_string(root + "/Groupes/Lignée de Macrin.md").contains("# Lignée de Macrin"), "le reste de la fiche est intact")
	eq(Contra.build(app.index).filter(func(c): return c.kind == "completer" and c.has("fix")).size(), 0, "plus de proposition")
	var fams: Array = Lineage.families(app.index)
	var f: Dictionary = fams[Lineage.family_index(fams, "Karios")]
	ok(not f.nodes.has("lig:lignée de macrin") and (f.nodes.macrin.heads as Array).has("lig:lignée de macrin"), "Macrin montre maintenant sa lignée")
	var hk: Array = f.edges.filter(func(e): return e.a == "macrin" and e.b == "hyacinthe")
	ok(hk.size() == 1 and hk[0].kind == "lignee", "Hyacinthe, de la lignée de Macrin, se rattache à Macrin")
	var c: Dictionary = app.create_note("groupe", {"nom": "Lignée de Hyacinthe", "nature": "lignee", "chef": "[[Hyacinthe]]"})
	ok(c.ok and FileAccess.get_file_as_string(root + "/" + str(c.rel)).contains("chef: \"[[Hyacinthe]]\""), "création d'une lignée avec son chef")
	app.index.close()
	app.free()
