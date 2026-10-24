extends "res://tests/base.gd"
## Alertes : échéances, faveurs en retard, sanctions, personnes surveillées.

const RepoAccess := preload("res://core/storage/repo_access.gd")
const IndexStore := preload("res://core/index/index_store.gd")
const Scanner := preload("res://core/sync/scanner.gd")
const Alerts := preload("res://core/analysis/alerts.gd")

const TODAY := "2026-10-21"
var index: RefCounted
var _n := 0


func _note(root: String, rel: String, type_name: String, props: String, body: String) -> void:
	_n += 1
	var prefix: String = {"personnage": "per", "source": "src", "soiree": "soi", "domaine": "dom", "faveur": "fav"}[type_name]
	write_file(root + "/" + rel, "---\ntype: %s\nid: %s-a%07d\nschema: 1\n%s---\n%s" % [type_name, prefix, _n, props, body])


func _prepare() -> void:
	var root := temp_dir("coffre-alertes")
	_note(root, "Domaines/Ysère.md", "domaine", "", "# Ysère\n")
	for p in [["Alix", ""], ["Bruno", ""], ["Chloé", "sanctions:\n  - chasse_au_sang\n"], ["Denis", "statut: mort_finale\nsanctions:\n  - parjure\n"],
			["Eva", "tags:\n  - surveille\n"], ["Félix", "sanctions:\n  - paria\n"]]:
		_note(root, "Personnages/%s.md" % p[0], "personnage", p[1], "# %s\n" % p[0])
	_note(root, "Sources/Notes/Cour.md", "source", "nature: note\ntitre: Cour\nfiabilite: B\ndate: 2026-10-01\n",
		"## Éléments\n" +
		"- r1 [nature:: observe] [credibilite:: 2] [relation:: reconnait] [de:: [[Alix]]] [vers:: [[Bruno]]] [qualificatif:: Loyal] [jusqu_au:: 2026-10-31] ^el-aaaaaaa1\n" +
		"- r2 [nature:: observe] [credibilite:: 2] [relation:: sobriquet] [de:: [[Alix]]] [vers:: [[Félix]]] [qualificatif:: Lâche] [jusqu_au:: 2026-10-16] ^el-aaaaaaa2\n" +
		"- r3 [nature:: observe] [credibilite:: 2] [relation:: reconnait] [de:: [[Alix]]] [vers:: [[Félix]]] [qualificatif:: Lointain] [jusqu_au:: 2027-06-01] ^el-aaaaaaa3\n" +
		"- Probation de [[Bruno]] jusqu'à fin novembre. [nature:: rapporte] [credibilite:: 3] [jusqu_au:: 2026-11] ^el-aaaaaaa4\n" +
		"- [[Eva]] a été vue au port. [nature:: rapporte] [credibilite:: 3] ^el-aaaaaaa5\n")
	for d in ["2026-08-20", "2026-09-10", "2026-10-15"]:
		_note(root, "Soirees/2026/%s Ysère - Assemblée.md" % d, "soiree", "date: %s\ndomaine: \"[[Ysère]]\"\n" % d, "# s\n")
	var fav := func(name: String, niv: String, statut: String, deb: String, cre: String, mv: String) -> void:
		_note(root, "Faveurs/%s.md" % name, "faveur", "niveau: %s\ndebiteur: \"[[%s]]\"\ncreancier: \"[[%s]]\"\nstatut: %s\ncredibilite: 1\ndate: 2026-07-01\ndomaine: \"[[Ysère]]\"\n" % [niv, deb, cre, statut],
			"## Mouvements\n- c [mv:: creation] [date:: 2026-07-01] ^mv-%s1\n%s" % [name.to_lower().left(6).lpad(6, "x"), mv])
	fav.call("Retard", "mineure", "reclamee", "Alix", "Bruno", "- r [mv:: reclamation] [date:: 2026-08-01] ^mv-retard02\n")
	fav.call("Recente", "mineure", "reclamee", "Bruno", "Alix", "- r [mv:: reclamation] [date:: 2026-10-10] ^mv-recent02\n")
	fav.call("Sang", "sang", "reclamee", "Alix", "Félix", "- r [mv:: reclamation] [date:: 2026-01-10] ^mv-sangsa02\n")
	fav.call("Sansdate", "triviale", "reclamee", "Félix", "Alix", "")
	fav.call("Chassee", "triviale", "active", "Chloé", "Alix", "")
	var db := OS.get_user_data_dir() + "/tests_tmp/alertes.sqlite"
	IndexStore.delete_files(db)
	index = IndexStore.new()
	index.open(db)
	Scanner.new(RepoAccess.new(root), index).scan()


func _find(alerts: Array, kind: String, contains: String) -> Dictionary:
	for a in alerts:
		if a.kind == kind and (str(a.title) + " " + str(a.detail)).contains(contains):
			return a
	return {}


func test_dates() -> void:
	eq(Alerts.end_day("2026-11"), "2026-11-30", "échéance au mois : dernier jour")
	eq(Alerts.end_day("2028-02"), "2028-02-29", "février bissextile")
	eq(Alerts.end_day("2026"), "2026-12-31", "échéance à l'année")
	eq(Alerts.end_day("2026-03/2026-09"), "2026-09-30", "intervalle : sa fin")
	eq(Alerts.end_day("2026-03/.."), "", "en cours : pas d'échéance")
	eq(Alerts.add_months("2026-01-31", 1), "2026-02-28", "un mois après le 31 janvier")
	eq(Alerts.days_between("2026-10-21", "2026-10-31"), 10, "jours entre deux dates")


func test_alertes() -> void:
	_prepare()
	var al := Alerts.build(index, {}, TODAY)
	var loyal := _find(al, "echeance", "Loyal")
	ok(not loyal.is_empty() and loyal.level == "attention" and loyal.detail.begins_with("expire dans 10 jours"), "reconnaissance qui expire bientôt : %s — %s" % [loyal.get("title", ""), loyal.get("detail", "")])
	ok(loyal.title == "Reconnaissance « Loyal » de Bruno par Alix", "texte : " + str(loyal.get("title", "")))
	var lache := _find(al, "echeance", "Lâche")
	ok(not lache.is_empty() and lache.level == "info" and lache.detail.begins_with("a expiré il y a 5 jours"), "tance expirée récemment : " + str(lache.get("detail", "")))
	ok(_find(al, "echeance", "Lointain").is_empty(), "échéance lointaine : pas d'alerte")
	var prob := _find(al, "echeance", "Probation")
	ok(prob.is_empty(), "échéance au mois (fin novembre, dans 40 jours) : hors de la fenêtre de 30 jours")
	ok(not _find(Alerts.build(index, {}, "2026-11-15"), "echeance", "Probation").is_empty(), "la même, vue le 15 novembre : signalée")
	var retard := _find(al, "faveur", "Alix envers Bruno")
	ok(not retard.is_empty() and retard.level == "urgent" and retard.detail.contains("3 séance(s) depuis"), "faveur mineure réclamée en retard : " + str(retard.get("detail", "")))
	ok(_find(al, "faveur", "Bruno envers Alix").is_empty(), "réclamée il y a 11 jours : dans les délais")
	ok(_find(al, "faveur", "de sang").is_empty(), "faveur de sang : délai non précisé, pas d'alerte")
	var sans := _find(al, "faveur", "Félix envers Alix")
	ok(not sans.is_empty() and sans.level == "info", "réclamée sans date : signalée pour information")
	var chasse := _find(al, "sanction", "Chloé")
	ok(not chasse.is_empty() and chasse.level == "urgent", "Chasse au Sang en cours : urgent")
	ok(_find(al, "sanction", "Denis").is_empty(), "un personnage en mort finale n'est plus signalé")
	ok(not _find(al, "sanction", "Félix : Paria").is_empty(), "paria signalé")
	ok(not _find(al, "faveur", "Chloé est sous le coup").is_empty(), "faveur active avec une partie chassée")
	var eva := _find(al, "surveille", "Eva")
	ok(not eva.is_empty() and eva.title == "Eva : 1 nouvel élément", "personne surveillée : " + str(eva.get("title", "")))
	var vus := {"Eva": {"t": 0, "k": Alerts.mentions(index, "Eva").map(func(e): return e.key)}}
	ok(_find(Alerts.build(index, {}, TODAY, vus), "surveille", "Eva").is_empty(), "éléments déjà vus : plus d'alerte")
	ok(not _find(Alerts.build(index, {}, TODAY, {"Eva": {"t": 0, "k": []}}), "surveille", "Eva").is_empty(), "un élément pas encore vu : alerte")
	eq(al[0].level, "urgent", "les urgences d'abord")
	var cfg := {"faveurs": {"niveaux": [{"code": "mineure", "delai_seances": 5, "delai_mois": 1}]}}
	ok(_find(Alerts.build(index, cfg, TODAY), "faveur", "Alix envers Bruno").is_empty(), "délais de la configuration du coffre : 5 séances, pas encore")
	index.close()
