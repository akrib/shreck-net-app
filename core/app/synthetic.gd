extends RefCounted
## Jeu de données synthétique et reproductible, au format v1, pour mesurer les
## performances. Il est écrit dans un DOSSIER DE BANC séparé, jamais dans le coffre.

const MARKER := ".nosferatu-banc"

const PRENOMS := ["Adèle", "Albane", "Ambroise", "Anselme", "Apolline", "Armand", "Aurèle", "Bastien",
	"Bérénice", "Blanche", "Cassien", "Céleste", "Clément", "Clotilde", "Corentin", "Daphné",
	"Désiré", "Edmée", "Élise", "Éloi", "Émeric", "Esther", "Eudes", "Fantine", "Félicien",
	"Firmin", "Gaspard", "Gervaise", "Gilles", "Hélène", "Héloïse", "Honoré", "Ignace", "Irène",
	"Isaure", "Jérôme", "Joachim", "Josèphe", "Laure", "Léandre", "Léonie", "Lucien", "Mahaut",
	"Marcellin", "Margaux", "Mathurin", "Mélisande", "Nestor", "Noémie", "Octave", "Odile",
	"Orphée", "Pacôme", "Pélagie", "Philémon", "Prosper", "Quentin", "Rosalie", "Séverin",
	"Solène", "Sylvain", "Thaïs", "Théophile", "Ursule", "Valère", "Victor", "Zélie"]
const NOMS := ["Abelard", "Aubrac", "Beaumont", "Bellanger", "Berthier", "Blanchard", "Bonnevie",
	"Carrel", "Chastel", "Clairmont", "Corbin", "Dauphin", "Delorme", "Desmarets", "Duroc",
	"Escoffier", "Faucher", "Ferrand", "Fontaine", "Garnier", "Gaudin", "Giraud", "Grandval",
	"Guérin", "Hardy", "Hervé", "Jourdain", "Lacombe", "Lafleur", "Lambert", "Lanier", "Laroche",
	"Lebrun", "Leclerc", "Lefèvre", "Lescure", "Lombard", "Marchal", "Marest", "Mercier",
	"Montfort", "Morel", "Morin", "Noiret", "Olivier", "Pasquier", "Peyrol", "Picard", "Poirier",
	"Prévost", "Quillet", "Raynal", "Renaud", "Rivière", "Rochas", "Roux", "Saunier", "Sauvage",
	"Séguin", "Tessier", "Thibault", "Toussaint", "Valmont", "Varga", "Vasseur", "Verdier",
	"Vidal", "Villeneuve", "Voisin", "Werner"]
const DEBUTS := ["Val", "Noir", "Mont", "Roche", "Clair", "Bois", "Pierre", "Haut", "Sombre", "Grand",
	"Ombre", "Brume", "Fer", "Lune", "Cendre"]
const FINS := ["ombre", "fort", "lac", "mont", "vic", "bourg", "sac", "dun", "val", "pierre"]
const MOTS := ["nuit", "sang", "harpie", "élysée", "rumeur", "faveur", "prince", "domaine", "secret",
	"dette", "alliance", "trahison", "ancien", "infant", "masque", "ombre", "conseil", "réunion",
	"message", "lettre", "témoin", "accord", "menace", "refuge", "territoire", "chasse", "discret",
	"public", "serment", "prestige", "émissaire", "frontière", "silence", "archives", "cérémonie",
	"vengeance", "pacte", "héritage", "influence", "loyauté", "méfiance", "rivalité", "déclaration"]
const VERBES := ["a rencontré", "se méfie de", "a menacé", "protège", "a trahi", "soutient",
	"a parlé longuement avec", "évite", "a félicité", "a défié", "doit quelque chose à", "surveille"]
const RELATIONS := [["allie", "pp"], ["ennemi", "pp"], ["rival", "pp"], ["membre_de", "pg"],
	["contact_de", "pp"], ["protege", "pp"], ["influence", "pp"], ["sire_de", "pp"]]
const NIVEAUX := ["triviale", "mineure", "majeure", "sang", "vie"]
const NATURES_SRC := ["presse", "forum", "discord", "conversation", "document", "note"]
const DOSSIERS_SRC := {"presse": "Presse", "forum": "Forum", "discord": "Discord",
	"conversation": "Conversations", "document": "Documents", "note": "Notes"}

var rng := RandomNumberGenerator.new()
var root := ""
var counts := {}
var bytes_written := 0


func _id(prefix: String) -> String:
	var s := prefix + "-"
	for k in 8:
		s += "0123456789abcdefghjkmnpqrstvwxyz"[rng.randi() % 32]
	return s


func _pick(a: Array) -> Variant:
	return a[rng.randi() % a.size()]


func _words(n: int) -> String:
	var w := PackedStringArray()
	for k in n:
		w.append(_pick(MOTS))
	var s := " ".join(w)
	return s[0].to_upper() + s.substr(1) + "."


func _para(sentences: int) -> String:
	var p := PackedStringArray()
	for k in sentences:
		p.append(_words(6 + rng.randi() % 10))
	return " ".join(p)


func _write(rel: String, text: String) -> void:
	var p := root + "/" + rel
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	bytes_written += text.to_utf8_buffer().size()


func _l(name: String) -> String:
	return "\"[[" + name + "]]\""


static func check_target(path: String, repo_root: String) -> String:
	var p := path.strip_edges().replace("\\", "/").trim_suffix("/")
	if p == "":
		return "choisissez un dossier de banc"
	var r := repo_root.strip_edges().replace("\\", "/").trim_suffix("/")
	if r != "" and (p == r or p.begins_with(r + "/") or r.begins_with(p + "/")):
		return "le dossier de banc ne doit pas être le coffre ni le contenir"
	if DirAccess.dir_exists_absolute(p):
		var d := DirAccess.open(p)
		if d == null:
			return "dossier de banc illisible"
		d.include_hidden = true
		var content := Array(d.get_files()) + Array(d.get_directories())
		if not content.is_empty() and not FileAccess.file_exists(p + "/" + MARKER):
			return "le dossier n'est pas vide et n'est pas un dossier de banc : choisissez un dossier vide"
	return ""


## Écrit le jeu de données. scale = 1.0 : volume complet (voir PROTOTYPE.md).
func generate(p_root: String, scale: float, seed_value := 42, progress := Callable()) -> Dictionary:
	root = p_root.replace("\\", "/").trim_suffix("/")
	rng.seed = seed_value
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(root)
	_write(MARKER, "Dossier de banc Nosferatu : contenu synthétique, supprimable.\n")
	_write(".nosferatu/config.json", "{\"format\": \"nosferatu\", \"schema\": 1}\n")
	var n_per := maxi(20, int(3000 * scale))
	var n_grp := maxi(5, int(120 * scale))
	var n_dom := maxi(3, int(25 * scale))
	var n_lie := maxi(5, int(300 * scale))
	var n_src := maxi(10, int(1500 * scale))
	var n_soi := maxi(5, int(300 * scale))
	var n_ind := maxi(5, int(2000 * scale))
	var n_fav := maxi(5, int(800 * scale))
	var n_dos := maxi(2, int(50 * scale))
	counts = {"personnage": 0, "groupe": 0, "domaine": 0, "lieu": 0, "source": 0, "soiree": 0,
		"indice": 0, "faveur": 0, "dossier": 0, "elements": 0, "relations": 0, "presences": 0}

	# domaines
	var domaines := []
	var k := 0
	while domaines.size() < n_dom:
		var nm: String = DEBUTS[k % DEBUTS.size()] + FINS[(k / DEBUTS.size()) % FINS.size()]
		if k >= DEBUTS.size() * FINS.size():
			nm += " " + str(k)
		domaines.append(nm)
		_write("Domaines/%s.md" % nm, "---\ntype: domaine\nid: %s\nschema: 1\n---\n# %s\n\n%s\n" % [_id("dom"), nm, _para(3)])
		counts.domaine += 1
		k += 1
	# groupes
	var groupes := []
	for g in n_grp:
		var nm := "Groupe %s %03d" % [_pick(["des Lanternes", "du Fer", "de la Brume", "des Cendres", "du Lac"]), g]
		groupes.append(nm)
		var nat: String = "clan" if g < 13 else _pick(["faction", "coterie", "organisation"])
		_write("Groupes/%s.md" % nm, "---\ntype: groupe\nid: %s\nschema: 1\nnature: %s\n---\n# %s\n\n%s\n" % [_id("grp"), nat, nm, _para(2)])
		counts.groupe += 1
	# personnages
	var persos := []
	var used := {}
	var i := 0
	while persos.size() < n_per:
		var nm: String = PRENOMS[i % PRENOMS.size()] + " " + NOMS[(i / PRENOMS.size()) % NOMS.size()]
		if i >= PRENOMS.size() * NOMS.size():
			nm += " (" + str(i) + ")"
		i += 1
		if used.has(nm):
			continue
		used[nm] = true
		persos.append(nm)
		var body := "# %s\n\n## Portrait\n%s\n" % [nm, _para(2 + rng.randi() % 4)]
		if rng.randf() < 0.05:
			body += "\n## Notes\n" + _para(60)
		var aliases := ""
		if rng.randf() < 0.2:
			aliases = "aliases:\n  - %s\n" % ("Le " + _pick(["Notaire", "Comte", "Silencieux", "Rouge", "Vieux", "Masque"]))
		_write("Personnages/%s.md" % nm, "---\ntype: personnage\nid: %s\nschema: 1\n%sclan: %s\ndomaine: %s\nstatut: actif\nfiabilite: %s\n---\n%s" % [
			_id("per"), aliases, _l(groupes[rng.randi() % mini(13, groupes.size())]), _l(_pick(domaines)),
			_pick(["A", "B", "C", "C", "D", "F"]), body])
		counts.personnage += 1
	_prog(progress, "personnages")
	# lieux
	for l in n_lie:
		var dom: String = _pick(domaines)
		var nm := "Lieu %03d de %s" % [l, dom]
		_write("Lieux/%s.md" % nm, "---\ntype: lieu\nid: %s\nschema: 1\nnature: refuge\ndomaine: %s\n---\n# %s\n" % [_id("lie"), _l(dom), nm])
		counts.lieu += 1
	# soirées
	var elements_ref := []   # [nom de note, id bloc]
	var soirees := []
	for s in n_soi:
		var dom: String = _pick(domaines)
		var day := 1 + rng.randi() % 28
		var month := 1 + rng.randi() % 12
		var year := 2024 + rng.randi() % 3
		var nm := "%04d-%02d-%02d %s - Assemblée" % [year, month, day, dom]
		if soirees.has(nm):
			nm += " %d" % s
		soirees.append(nm)
		var pres := PackedStringArray()
		var chosen := {}
		for p in 15 + rng.randi() % 20:
			var who: String = _pick(persos)
			if not chosen.has(who):
				chosen[who] = true
				pres.append("  - " + _l(who))
		counts.presences += pres.size()
		var els := PackedStringArray()
		for e in 5 + rng.randi() % 10:
			var bid := _id("el")
			els.append("- [[%s]] %s [[%s]]. [nature:: observe] [credibilite:: %d] ^%s" % [
				_pick(persos), _pick(VERBES), _pick(persos), 1 + rng.randi() % 3, bid])
			elements_ref.append([nm, bid])
			counts.elements += 1
		_write("Soirees/%d/%s.md" % [year, nm], "---\ntype: soiree\nid: %s\nschema: 1\ndate: %04d-%02d-%02d\ndomaine: %s\nnature: assemblee\nmoi_present: true\npresents:\n%s\nfiabilite: A\n---\n# %s\n\n## Déroulé\n%s\n\n## Éléments\n%s\n\n## À faire\n- [ ] Revoir [[%s]].\n" % [
			_id("soi"), year, month, day, _l(dom), "\n".join(pres), nm, _para(4), "\n".join(els), _pick(persos)])
		counts.soiree += 1
	_prog(progress, "soirées")
	# sources
	for s in n_src:
		var nat: String = _pick(NATURES_SRC)
		var dom: String = _pick(domaines)
		var nm := "%04d-%02d-%02d %s - Source %04d" % [2024 + rng.randi() % 3, 1 + rng.randi() % 12, 1 + rng.randi() % 28, dom, s]
		var contenu := _para(5 + rng.randi() % 20)
		if rng.randf() < 0.03:
			contenu = _para(400)
		var els := PackedStringArray()
		for e in 5 + rng.randi() % 31:
			var bid := _id("el")
			var a: String = _pick(persos)
			var line := "- [[%s]] %s [[%s]] (%s). [nature:: %s] [credibilite:: %d]" % [
				a, _pick(VERBES), _pick(persos), _words(4).trim_suffix("."),
				_pick(["rapporte", "rapporte", "rumeur", "observe"]), 2 + rng.randi() % 5]
			if rng.randf() < 0.3:
				line += " [par:: [[%s]]]" % _pick(persos)
			if rng.randf() < 0.3:
				line += " [date_faits:: %04d-%02d~]" % [2023 + rng.randi() % 4, 1 + rng.randi() % 12]
			if rng.randf() < 0.5:
				var rel: Array = _pick(RELATIONS)
				var vers: String = _pick(groupes) if rel[1] == "pg" else _pick(persos)
				line += " [relation:: %s] [de:: [[%s]]] [vers:: [[%s]]]" % [rel[0], a, vers]
				counts.relations += 1
			els.append(line + " ^" + bid)
			elements_ref.append([nm, bid])
			counts.elements += 1
		_write("Sources/%s/%s.md" % [DOSSIERS_SRC[nat], nm], "---\ntype: source\nid: %s\nschema: 1\nnature: %s\ndate: %04d-%02d-%02d\ndomaine: %s\ncanal: Canal %d\nauteur: %s\nfiabilite: %s\n---\n# %s\n\n## Contenu\n%s\n\n## Éléments\n%s\n" % [
			_id("src"), nat, 2024 + rng.randi() % 3, 1 + rng.randi() % 12, 1 + rng.randi() % 28,
			_l(dom), rng.randi() % 20, _l(_pick(persos)), _pick(["B", "C", "C", "D", "F"]), nm, contenu, "\n".join(els)])
		counts.source += 1
		if s % 100 == 0:
			_prog(progress, "sources %d/%d" % [s, n_src])
	# indices
	for d in n_ind:
		var e1: Array = _pick(elements_ref)
		var e2: Array = _pick(elements_ref)
		var a: String = _pick(persos)
		var b: String = _pick(persos)
		var nm := "Indice %05d %s et %s" % [d, a, b]
		_write("Indices/%s.md" % nm, "---\ntype: indice\nid: %s\nschema: 1\nstatut: %s\ncredibilite: %d\nsujets:\n  - %s\n  - %s\nrelation: allie\nde: %s\nvers: %s\ndate_floue: \"%04d~/..\"\npour:\n  - \"[[%s#^%s]]\"\n  - \"[[%s#^%s]]\"\n---\n# %s\n\n## Analyse\n%s\n" % [
			_id("ind"), _pick(["non_verifie", "corrobore", "conteste"]), 2 + rng.randi() % 4,
			_l(a), _l(b), _l(a), _l(b), 2023 + rng.randi() % 4, e1[0], e1[1], e2[0], e2[1], nm, _para(3)])
		counts.indice += 1
		counts.relations += 1
	# faveurs
	for f in n_fav:
		var deb: String = _pick(persos)
		var cre: String = _pick(persos)
		var niv: String = NIVEAUX[mini(rng.randi() % 7, 4)]
		var nm := "2026-%02d-%02d %s envers %s %d" % [1 + rng.randi() % 9, 1 + rng.randi() % 28, deb, cre, f]
		var stat: String = _pick(["active", "active", "reclamee", "soldee"])
		var mvts := "- Contractée. [mv:: creation] [date:: 2026-01-10] [niveau:: %s] [debiteur:: [[%s]]] [creancier:: [[%s]]] ^%s\n" % [niv, deb, cre, _id("mv")]
		if stat == "reclamee" or stat == "soldee":
			mvts += "- Réclamée. [mv:: reclamation] [date:: 2026-02-14] ^%s\n" % _id("mv")
		if stat == "soldee":
			mvts += "- Payée. [mv:: paiement] [date:: 2026-03-14] ^%s\n" % _id("mv")
		_write("Faveurs/%s.md" % nm, "---\ntype: faveur\nid: %s\nschema: 1\nniveau: %s\ndebiteur: %s\ncreancier: %s\nstatut: %s\ncredibilite: %d\ndate: 2026-01-10\nenregistree: true\ntransferable: true\n---\n# %s\n\n## Stipulations\n%s\n\n## Mouvements\n%s" % [
			_id("fav"), niv, _l(deb), _l(cre), stat, 1 + rng.randi() % 4, nm, _para(1), mvts])
		counts.faveur += 1
	# dossiers
	for d in n_dos:
		var nm := "Dossier - Enquête %03d" % d
		_write("Dossiers/%s.md" % nm, "---\ntype: dossier\nid: %s\nschema: 1\nstatut: ouvert\nquestion: \"Que cache %s ?\"\npriorite: haute\nsujets:\n  - %s\n---\n# %s\n\n## À rechercher\n- [ ] Interroger [[%s]].\n" % [
			_id("dos"), _pick(persos), _l(_pick(persos)), nm, _pick(persos)])
		counts.dossier += 1
	return {"counts": counts, "bytes": bytes_written, "ms": Time.get_ticks_msec() - t0}


func _prog(cb: Callable, phase: String) -> void:
	if cb.is_valid():
		cb.call(0, 0, phase)
