extends "res://tests/base.gd"
## Alibis et chronologie : où était chacun, telle nuit, présences communes à plusieurs incidents.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Dates := preload("res://core/model/dates.gd")
const Where := preload("res://core/analysis/whereabouts.gd")

var index: RefCounted
var _n := 0


func _note(root: String, rel: String, type_name: String, props: String, body := "") -> void:
	_n += 1
	var prefix: String = {"personnage": "per", "source": "src", "soiree": "soi", "domaine": "dom", "lieu": "lie",
		"evenement": "evt", "indice": "ind"}[type_name]
	write_file(root + "/" + rel, "---\ntype: %s\nid: %s-b%07d\nschema: 1\n%s---\n%s" % [type_name, prefix, _n, props, body])


func _links(names: Array) -> String:
	return "".join(PackedStringArray(names.map(func(x): return "  - \"[[%s]]\"\n" % x)))


func _prepare() -> void:
	var root := temp_dir("coffre-alibis")
	_note(root, "Domaines/Ysère.md", "domaine", "")
	_note(root, "Domaines/Drôme.md", "domaine", "")
	_note(root, "Lieux/Élysée.md", "lieu", "domaine: \"[[Ysère]]\"\n")
	_note(root, "Lieux/Docks.md", "lieu", "domaine: \"[[Ysère]]\"\n")
	_note(root, "Lieux/Manoir.md", "lieu", "domaine: \"[[Drôme]]\"\n")
	for p in ["Alix", "Bruno", "Chloé", "Denis", "Eva", "Félix", "Gaspard", "Inconnu - Masque"]:
		_note(root, "Personnages/%s.md" % p, "personnage", "")
	var soiree := func(name: String, date: String, dom: String, lieu: String, pres: Array, inc: Array, abs: Array) -> void:
		_note(root, "Soirees/%s.md" % name, "soiree", "date: %s\ndomaine: \"[[%s]]\"\n%spresents:\n%spresents_incertains:\n%sabsents:\n%s" % [
			date, dom, ("lieu: \"[[%s]]\"\n" % lieu) if lieu != "" else "", _links(pres), _links(inc), _links(abs)])
	soiree.call("2026-10-14 Ysère - Assemblée", "2026-10-14", "Ysère", "Élysée", ["Alix", "Bruno", "Chloé"], ["Denis"], ["Eva"])
	soiree.call("2026-10-14 Drôme - Assemblée", "2026-10-14", "Drôme", "Manoir", ["Eva", "Félix", "Bruno"], [], [])
	soiree.call("2026-09-20 Ysère - Assemblée", "2026-09-20", "Ysère", "Élysée", ["Alix", "Chloé", "Félix"], [], [])
	var evt := func(name: String, date: String, lieu: String, statut: String, parts: Array) -> void:
		_note(root, "Evenements/%s.md" % name, "evenement", "description: %s\ndate_floue: \"%s\"\nstatut: %s\ncredibilite: 3\ndomaine: \"[[Ysère]]\"\n%sparticipants:\n%s" % [
			name, date, statut, ("lieu: \"[[%s]]\"\n" % lieu) if lieu != "" else "", _links(parts)])
	evt.call("Agression aux docks", "2026-10-14", "Docks", "corrobore", ["Chloé"])
	evt.call("Incendie des docks", "2026-09-20", "Docks", "non_verifie", [])
	evt.call("Menace contre la Harpie", "2026-10-14", "", "non_verifie", [])
	evt.call("Disparition démentie", "2026-08", "Docks", "refute", ["Alix"])
	_note(root, "Sources/Notes/Rapport.md", "source", "nature: note\ntitre: Rapport\nfiabilite: B\ndate: 2026-10-16\n",
		"## Éléments\n" +
		"- Denis aux docks. [nature:: observe] [credibilite:: 2] [relation:: present_a] [de:: [[Denis]]] [vers:: [[Docks]]] [date_faits:: 2026-10-14] ^el-bbbbbbb1\n" +
		"- Eva aux docks. [nature:: rapporte] [credibilite:: 3] [relation:: present_a] [de:: [[Eva]]] [vers:: [[Docks]]] [date_faits:: 2026-09-20] ^el-bbbbbbb2\n" +
		"- Le masque à l'agression. [nature:: rapporte] [credibilite:: 3] [relation:: present_a] [de:: [[Inconnu - Masque]]] [vers:: [[Agression aux docks]]] ^el-bbbbbbb3\n" +
		"- Le masque aux docks. [nature:: rumeur] [credibilite:: 4] [relation:: present_a] [de:: [[Inconnu - Masque]]] [vers:: [[Docks]]] [date_faits:: 2026-09-20] ^el-bbbbbbb4\n" +
		"- Félix aux docks en septembre. [nature:: rumeur] [credibilite:: 4] [relation:: present_a] [de:: [[Félix]]] [vers:: [[Docks]]] [date_faits:: 2026-09] ^el-bbbbbbb5\n" +
		"- Gaspard aux docks en septembre. [nature:: rumeur] [credibilite:: 4] [relation:: present_a] [de:: [[Gaspard]]] [vers:: [[Docks]]] [date_faits:: 2026-09] ^el-bbbbbbb6\n" +
		"- Alix à l'Élysée en octobre ? [nature:: hypothese] [credibilite:: 5] [relation:: present_a] [de:: [[Alix]]] [vers:: [[Élysée]]] [date_faits:: 2026-10] ^el-bbbbbbb7\n")
	_note(root, "Indices/Chloé aux docks.md", "indice", "enonce: Chloé était aux docks\nstatut: non_verifie\ncredibilite: 3\nrelation: present_a\nde: \"[[Chloé]]\"\nvers: \"[[Docks]]\"\ndate_floue: \"2026-09-20\"\n")
	var db := OS.get_user_data_dir() + "/tests_tmp/alibis.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()


func _who(list: Array, name: String) -> Dictionary:
	for x in list:
		if str(x.get("who", "")) == name:
			return x
	return {}


func _path_of(name: String) -> String:
	return index.path_of_name(name)


func test_dates() -> void:
	eq(Dates.span("2026-10"), ["2026-10-01", "2026-10-31"], "un mois")
	eq(Dates.span("2026-02"), ["2026-02-01", "2026-02-28"], "février")
	eq(Dates.span("2026-03/2026-09"), ["2026-03-01", "2026-09-30"], "intervalle")
	eq(Dates.span("2026-04~/.."), ["2026-04-01", "9999-12-31"], "depuis")
	eq(Dates.span("../2026"), ["0000-01-01", "2026-12-31"], "avant")
	eq(Dates.span("19XX"), ["1900-01-01", "1999-12-31"], "siècle")
	eq(Dates.span("inconnue"), ["", ""], "inconnue")
	ok(Dates.is_day("2026-10-14") and not Dates.is_day("2026-10-14~") and not Dates.is_day("2026-10"), "date au jour près")
	ok(Dates.overlap(Dates.span("2026-09"), Dates.span("2026-09-20")) and not Dates.overlap(Dates.span("2026-09"), Dates.span("2026-10-14")), "recouvrement")


func test_alibis() -> void:
	_prepare()
	var all := Where.facts(index)
	eq(all.size(), 20, "présences : 11 de soirées, 1 participant (l'événement réfuté ne compte pas), 7 éléments, 1 indice")
	# où était-il ?
	var bruno := Where.of_person(index, "Bruno", all)
	eq(bruno.size(), 2, "Bruno : deux soirées")
	eq(Where.conflicts(bruno).keys(), ["2026-10-14"], "Bruno noté présent à deux assemblées le même soir")
	var eva := Where.of_person(index, "Eva", all)
	eq(eva.map(func(f): return f.how), ["present", "absent", "rapporte"], "Eva : présente en Drôme, absente en Ysère, puis aux docks en septembre")
	ok(Where.conflicts(eva).is_empty(), "absente ici et présente ailleurs : cohérent")
	eq(Where.how_label(eva[2]), "présent selon Rapport", "libellé d'une présence rapportée")
	var masque := Where.of_person(index, "Inconnu - Masque", all)
	eq(masque[0].date, "2026-10-14", "élément sans date des faits : date de l'événement visé")
	# telle nuit
	var n := Where.night(index, "2026-10-14", all)
	eq(n.places.map(func(p): return [p.where, p.facts.size()]), [["2026-10-14 Ysère - Assemblée", 5], ["2026-10-14 Drôme - Assemblée", 3],
		["Agression aux docks", 2], ["Docks", 1]], "lieux de la nuit du 14 et nombre de présences")
	ok(_who(n.people, "Bruno").conflict and _who(n.people, "Chloé").conflict, "Bruno et Chloé vus à deux endroits")
	ok(not _who(n.people, "Denis").conflict, "présence incertaine : pas de contradiction")
	eq(n.people[0].conflict, true, "les contradictions d'abord")
	eq(n.approx.map(func(f): return f.who), ["Alix"], "date floue (octobre) qui inclut ce jour : à titre indicatif")
	eq(Where.nights(index, all)[0], {"day": "2026-10-14", "count": 11}, "nuits documentées, la plus récente d'abord")
	# incidents
	var inc := Where.incidents(index)
	ok(inc.size() == 7 and str(inc[0].date) == "2026-10-14", "incidents proposés : soirées et événements, les plus récents d'abord")
	var c := Where.common(index, [_path_of("Agression aux docks"), _path_of("Incendie des docks")], all)
	eq(c.incidents.map(func(i): return i.name), ["Incendie des docks", "Agression aux docks"], "incidents dans l'ordre des dates")
	eq(c.people.map(func(p): return p.who), ["Chloé", "Inconnu - Masque", "Denis", "Eva", "Gaspard"], "classement : sur place aux deux, puis à un, puis date compatible")
	var ch := _who(c.people, "Chloé")
	ok(ch.all and ch.count == 2 and ch.at[1].contradiction, "Chloé : sur place aux deux, mais vue à l'assemblée le soir de l'agression")
	var ma := _who(c.people, "Inconnu - Masque")
	ok(ma.all and ma.at[0].force == 1 and ma.at[1].force == 2, "le masque : aux deux, sur une rumeur puis un rapport")
	var ev := _who(c.people, "Eva")
	eq(ev.at.map(func(s): return s.kind), ["sur_place", "alibi"], "Eva : aux docks le 20 septembre, en Drôme le 14 octobre")
	eq(str(ev.at[1].facts[0].where), "2026-10-14 Drôme - Assemblée", "son alibi")
	ok(_who(c.people, "Alix").is_empty() and _who(c.people, "Bruno").is_empty(), "vus ailleurs aux deux nuits : hors de la liste")
	var c2 := Where.common(index, [_path_of("Incendie des docks")], all)
	eq(_who(c2.people, "Gaspard").at[0].kind, "compatible", "aux docks « en septembre » : date compatible")
	ok(_who(c2.people, "Félix").is_empty(), "rumeur de septembre, mais vu à l'assemblée ce soir-là : alibi")
	var c3 := Where.common(index, [_path_of("Menace contre la Harpie")], all)
	eq(_who(c3.people, "Alix").at[0].kind, "parages", "lieu inconnu, même domaine, même nuit : dans les parages")
	ok(_who(c3.people, "Eva").is_empty(), "en Drôme ce soir-là : alibi")
	var c4 := Where.common(index, [_path_of("2026-10-14 Ysère - Assemblée")], all)
	var de := _who(c4.people, "Denis")
	ok(de.at[0].kind == "sur_place" and de.at[0].force == 1 and de.at[0].contradiction, "Denis : présence incertaine à l'assemblée, mais vu aux docks le même soir")
	eq(_who(c4.people, "Eva").size(), 0, "Eva : absente et vue en Drôme")
	index.close()
