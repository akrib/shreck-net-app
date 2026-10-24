extends RefCounted
## Modèle des notes du format v1.3 : types, champs, listes de choix, noms de
## fichiers et modèles de texte. C'est la seule source de ces règles dans
## l'application (formulaires de création, éditeur de propriétés, outils).
## Les vocabulaires peuvent être étendus par .nosferatu/config.json (voir Vocab).

const FlatYaml := preload("res://core/format/flat_yaml.gd")
const Ids := preload("res://core/format/ids.gd")

# ------------------------------------------------------------------ listes de choix

const FIABILITE := [["A", "A — Entièrement fiable"], ["B", "B — Habituellement fiable"],
	["C", "C — Assez fiable"], ["D", "D — Habituellement peu fiable"], ["E", "E — Non fiable"],
	["F", "F — Ne peut être évaluée"]]

const CREDIBILITE := [[1, "1 — Confirmée"], [2, "2 — Probablement vraie"],
	[3, "3 — Possiblement vraie"], [4, "4 — Douteuse"], [5, "5 — Improbable"],
	[6, "6 — Ne peut être évaluée"]]

const ENUMS := {
	"personnage.statut": [["actif", "Actif"], ["torpeur", "Torpeur"], ["disparu", "Disparu"], ["mort_finale", "Mort finale"], ["inconnu", "Inconnu"]],
	"personnage.identite": [["connue", "Connue"], ["incertaine", "Incertaine"], ["inconnue", "Inconnue"]],
	"personnage.sanctions": [["chasse_au_sang", "Chasse au Sang"], ["parjure", "Parjure"], ["banni", "Banni"],
		["liste_ecarlate", "Liste Écarlate"], ["paria", "Paria"]],
	"personnage.nature": [["vampire", "Vampire"], ["goule", "Goule"], ["revenant", "Revenant"], ["mortel", "Mortel"],
		["chasseur", "Chasseur"], ["loup_garou", "Loup-garou"], ["mage", "Mage"], ["fae", "Fae"],
		["fantome", "Fantôme"], ["demon", "Démon"], ["autre", "Autre"]],
	# Statut d'âge, du plus élevé au plus bas (Règles FCF p. 766)
	"personnage.rang": [["venerable", "Vénérable"], ["ancien", "Ancien"], ["ancilla", "Ancilla"],
		["nouveau_ne", "Nouveau-né"], ["infant", "Infant sous tutelle"]],
	"groupe.nature": [["clan", "Clan"], ["lignee", "Lignée"], ["secte", "Secte"], ["faction", "Faction"],
		["coterie", "Coterie"], ["meute", "Meute (Sabbat)"], ["organisation", "Organisation"], ["autre", "Autre"]],
	"concept.nature": [["discipline", "Discipline"], ["poste", "Poste"], ["tradition", "Tradition"],
		["notion", "Notion"], ["rituel", "Rituel"], ["autre", "Autre"]],
	"soiree.nature": [["assemblee", "Assemblée"], ["elysium", "Élysium"], ["conclave", "Conclave"],
		["reunion", "Réunion"], ["autre", "Autre"]],
	"source.nature": [["note", "Note personnelle"], ["conversation", "Conversation"], ["discord", "Discord"],
		["forum", "Forum"], ["presse", "Presse"], ["document", "Document"], ["analyse", "Analyse"]],
	"indice.statut": [["non_verifie", "Non vérifié"], ["corrobore", "Corroboré"], ["conteste", "Contesté"],
		["refute", "Réfuté"], ["obsolete", "Obsolète"]],
	"evenement.statut": [["non_verifie", "Non vérifié"], ["corrobore", "Corroboré"], ["conteste", "Contesté"],
		["refute", "Réfuté"], ["obsolete", "Obsolète"]],
	"faveur.niveau": [["triviale", "Triviale"], ["mineure", "Mineure"], ["majeure", "Majeure"],
		["sang", "De sang"], ["vie", "De vie"]],
	"faveur.statut": [["active", "Active"], ["reclamee", "Réclamée"], ["soldee", "Soldée"],
		["ignoree", "Ignorée"], ["suspendue", "Suspendue"], ["annulee", "Annulée"]],
	"dossier.statut": [["ouvert", "Ouvert"], ["en_pause", "En pause"], ["resolu", "Résolu"],
		["abandonne", "Abandonné"]],
	"dossier.priorite": [["haute", "Haute"], ["moyenne", "Moyenne"], ["basse", "Basse"]],
	"en_cours.statut": [["a_traiter", "À traiter"], ["traitee", "Traitée"]],
	"element.nature": [["observe", "Observé (vu ou entendu moi-même)"], ["rapporte", "Rapporté (affirmé par quelqu'un)"],
		["rumeur", "Rumeur"], ["deduction", "Déduction"], ["hypothese", "Hypothèse"]],
}

const RELATIONS := [["allie", "est allié de"], ["ennemi", "est ennemi de"], ["rival", "est rival de"],
	["lie_a", "est lié à (nature inconnue)"], ["membre_de", "est membre de"], ["dirige", "dirige"],
	["sire_de", "est le sire de"], ["mentor_de", "est le mentor de"], ["contact_de", "est un contact de"],
	["sert", "est au service de"], ["protege", "protège"], ["chantage", "fait chanter"],
	["influence", "a de l'influence sur"], ["lien_de_sang", "est lié par le sang à"],
	["present_a", "était présent à"], ["possede", "possède"], ["reside_a", "réside à"],
	["reconnait", "a reconnu (patronage)"], ["sobriquet", "a affublé d'un sobriquet"], ["nomme", "a nommé à un poste"]]

## Postes proposés dans « titres » (Règles FCF p. 781-794), par secte, dans l'ordre hiérarchique.
const POSTES := {
	"Camarilla": ["Prince", "Duc", "Marquis", "Seigneur", "Sénéchal", "Bailli", "Fléau", "Gardien d'Élysée", "Prévôt",
		"Maître des Harpies", "Primogène", "Fouet", "Sentinelle", "Héraut", "Harpie", "Justicar", "Archonte", "Alastor", "Servire"],
	"Anarchs": ["Baron", "Défenseur", "Gendarme", "Architecte", "Ambassadeur"],
	"Sabbat": ["Régent", "Cardinal", "Archevêque", "Évêque", "Templier", "Paladin", "Priscus", "Ductus", "Prêtre", "Abbé"],
}

## Disciplines « communes » ou cardinales (Règles FCF p. 346) : elles peuvent
## s'apprendre hors clan ; les autres sont des indices forts de l'origine du sang.
const DISCIPLINES_COMMUNES := ["Animalisme", "Auspex", "Célérité", "Dissimulation", "Domination",
	"Force d'âme", "Présence", "Puissance"]

## Spécialisations d'influence (Règles FCF p. 815) ; catégories Gotha et Pègre.
const INFLUENCES := ["Bureaucratie", "Crime", "Éducation", "Finances", "Haute Société", "Industrie", "Loi", "Média",
	"Occulte", "Police", "Politique", "Religion", "Rue", "Santé", "Transport"]

## Fiabilité proposée par défaut selon la nature de la source (GUIDE-CONVERSION §5).
const FIABILITE_PAR_NATURE := {"note": "B", "conversation": "C", "discord": "C", "forum": "C",
	"presse": "C", "document": "F", "analyse": "F"}

## Crédibilité proposée par défaut selon la nature d'un élément (jamais 1 : §8).
const CREDIBILITE_PAR_NATURE := {"observe": 2, "rapporte": 3, "rumeur": 4, "deduction": 3, "hypothese": 5}

const SOURCE_DOSSIERS := {"presse": "Presse", "forum": "Forum", "discord": "Discord",
	"conversation": "Conversations", "document": "Documents", "note": "Notes", "analyse": "Analyses"}

# ------------------------------------------------------------------ champs
# kind : text, date, date_floue, link, links, enum, multi, bool, fiabilite,
#        credibilite, textlist, elements, relation
# targets : types de notes proposés dans le sélecteur ([] = tous)

const FIELDS := {
	"nom": {"label": "Nom", "kind": "text", "form_only": true},
	"titre": {"label": "Titre court", "kind": "text", "form_only": true},
	"enonce": {"label": "Énoncé (une phrase)", "kind": "text", "form_only": true},
	"description": {"label": "Description courte", "kind": "text", "form_only": true},
	"date": {"label": "Date", "kind": "date"},
	"date_floue": {"label": "Date approximative", "kind": "date_floue",
		"help": "2026-10 (mois), 2026-10~ (vers), 2026-10? (peut-être), 2026-03/.. (depuis), inconnue"},
	"domaine": {"label": "Domaine (ville)", "kind": "link", "targets": ["domaine"]},
	"lieu": {"label": "Lieu", "kind": "link", "targets": ["lieu"]},
	"clan": {"label": "Clan", "kind": "link", "targets": ["groupe"], "natures": ["clan", "lignee"]},
	"secte": {"label": "Secte", "kind": "link", "targets": ["groupe"], "natures": ["secte"]},
	"rang": {"label": "Statut d'âge", "kind": "enum"},
	"generation": {"label": "Génération (si connue)", "kind": "number"},
	"disciplines": {"label": "Disciplines", "kind": "links", "targets": ["concept"], "natures": ["discipline"]},
	"influences": {"label": "Influences connues", "kind": "textlist", "suggest_list": "influences"},
	"qualificatif": {"label": "Qualificatif (reconnaissance, sobriquet, poste)", "kind": "text"},
	"discipline": {"label": "Discipline employée (pouvoir constaté)", "kind": "link", "targets": ["concept"], "natures": ["discipline"]},
	"sire": {"label": "Sire", "kind": "link", "targets": ["personnage"]},
	"detenteur": {"label": "Détenteur", "kind": "link", "targets": ["personnage", "groupe"]},
	"auteur": {"label": "Auteur (en jeu)", "kind": "link", "targets": ["personnage", "groupe"]},
	"rapporteur": {"label": "Transmis par", "kind": "link", "targets": ["personnage"]},
	"soiree": {"label": "Soirée concernée", "kind": "link", "targets": ["soiree"]},
	"debiteur": {"label": "Débiteur (celui qui doit)", "kind": "link", "targets": ["personnage"]},
	"creancier": {"label": "Créancier (à qui c'est dû)", "kind": "link", "targets": ["personnage"]},
	"harpie": {"label": "Harpie qui l'a enregistrée", "kind": "link", "targets": ["personnage"]},
	"de": {"label": "De", "kind": "link", "targets": []},
	"vers": {"label": "Vers", "kind": "link", "targets": []},
	"presents": {"label": "Présents (constatés)", "kind": "links", "targets": ["personnage"]},
	"presents_incertains": {"label": "Présents incertains", "kind": "links", "targets": ["personnage"]},
	"absents": {"label": "Absences remarquées", "kind": "links", "targets": ["personnage"]},
	"peut_etre": {"label": "Peut-être la même personne que", "kind": "links", "targets": ["personnage"]},
	"participants": {"label": "Participants", "kind": "links", "targets": ["personnage", "groupe"]},
	"sujets": {"label": "Sujets concernés", "kind": "links", "targets": []},
	"indices": {"label": "Indices du dossier", "kind": "links", "targets": ["indice"]},
	"devenue": {"label": "Transformée en", "kind": "links", "targets": []},
	"pour": {"label": "Éléments pour", "kind": "elements"},
	"contre": {"label": "Éléments contre", "kind": "elements"},
	"statut": {"label": "Statut", "kind": "enum"},
	"nature": {"label": "Nature", "kind": "enum"},
	"identite": {"label": "Identité", "kind": "enum"},
	"niveau": {"label": "Niveau", "kind": "enum"},
	"priorite": {"label": "Priorité", "kind": "enum"},
	"sanctions": {"label": "Sanctions", "kind": "multi"},
	"fiabilite": {"label": "Fiabilité de la source (A–F)", "kind": "fiabilite"},
	"credibilite": {"label": "Crédibilité de l'information (1–6)", "kind": "credibilite"},
	"relation": {"label": "Relation", "kind": "relation"},
	"moi_present": {"label": "J'étais présent", "kind": "bool"},
	"enregistree": {"label": "Enregistrée par une Harpie", "kind": "bool"},
	"transferable": {"label": "Transférable", "kind": "bool"},
	"fiche_reconnaissance": {"label": "Fiche de reconnaissance (hors jeu)", "kind": "bool"},
	"aliases": {"label": "Autres noms, surnoms", "kind": "textlist"},
	"titres": {"label": "Titres et postes connus", "kind": "textlist", "suggest_list": "postes"},
	"tags": {"label": "Étiquettes", "kind": "textlist"},
	"canal": {"label": "Canal (journal, salon, section)", "kind": "text", "suggest": true},
	"region": {"label": "Région", "kind": "text", "suggest": true},
	"question": {"label": "Question centrale", "kind": "text"},
	"url": {"label": "Adresse web", "kind": "text"},
	"nature_libre": {"label": "Nature", "kind": "text", "suggest": true},
	# champs des lignes structurées (éléments)
	"par": {"label": "Dit par (s'il diffère de l'auteur)", "kind": "link", "targets": ["personnage"]},
	"date_faits": {"label": "Date des faits (si connue)", "kind": "date_floue",
		"help": "2026-10, 2026-10~ (vers), 2026-04~/.. (depuis)…"},
	"jusqu_au": {"label": "Jusqu'au (échéance d'une reconnaissance, d'une tance, d'un poste…)", "kind": "date_floue",
		"help": "2026-11-28, ou 2026-12 (jusqu'à la fin du mois)"},
	# format 1.3
	"preseance": {"label": "Préséance des clans (dans l'ordre)", "kind": "links", "targets": ["groupe"], "natures": ["clan", "lignee"]},
	"rapport": {"label": "Ordre des informations du rapport", "kind": "elements"},
}

## Natures en texte libre (lieu, objet) : suggestions mais pas de liste fermée.
const FREE_NATURE := ["lieu", "objet"]

# ------------------------------------------------------------------ types

const TYPE_ORDER := ["en_cours", "soiree", "personnage", "source", "indice", "faveur",
	"evenement", "groupe", "lieu", "domaine", "objet", "dossier", "concept"]

const TYPES := {
	"en_cours": {"label": "Note rapide", "desc": "Bloc-notes, à trier plus tard", "prefix": "enc",
		"fields": ["date", "domaine"], "required": [],
		"defaults": {"date": "$today", "domaine": "$last_domaine", "statut": "a_traiter"},
		"section": "", "color": "e0b04a"},
	"soiree": {"label": "Soirée", "desc": "Assemblée d'un domaine, ce soir", "prefix": "soi",
		"fields": ["date", "domaine", "nature", "lieu", "moi_present", "fiabilite", "presents", "presents_incertains", "absents", "rapport"],
		"form": ["date", "domaine", "nature", "lieu", "moi_present", "fiabilite", "presents", "presents_incertains", "absents"],
		"required": ["date", "domaine"],
		"defaults": {"date": "$today", "domaine": "$last_domaine", "nature": "assemblee", "moi_present": true, "fiabilite": "A"},
		"keep_empty": ["presents", "presents_incertains"], "section": "Déroulé", "color": "c8b6ff"},
	"personnage": {"label": "Personnage", "desc": "Un Semblable, connu ou non", "prefix": "per",
		"fields": ["nom", "nature", "clan", "secte", "rang", "domaine", "titres", "statut", "identite", "sire",
			"generation", "disciplines", "influences", "aliases", "fiabilite", "sanctions", "peut_etre"],
		"form": ["nom", "nature", "clan", "secte", "rang", "domaine", "titres", "identite", "aliases", "fiabilite"],
		"required": ["nom"], "defaults": {"domaine": "$last_domaine", "statut": "actif", "identite": "connue",
			"fiabilite": "F", "nature": "vampire"},
		"labels": {"nature": "Créature", "fiabilite": "Fiabilité comme informateur (A–F)"},
		"section": "Notes", "color": "8fd3ff"},
	"source": {"label": "Source", "desc": "Article, forum, Discord, conversation", "prefix": "src",
		"fields": ["nature", "titre", "date", "fiabilite", "canal", "domaine", "auteur", "rapporteur", "soiree", "url"],
		"required": ["nature", "titre", "fiabilite"],
		"defaults": {"nature": "$last_source_nature", "date": "$today", "fiabilite": "$fiabilite_nature", "domaine": "$last_domaine"},
		"section": "Contenu", "color": "9be3a8"},
	"indice": {"label": "Indice", "desc": "Une affirmation à évaluer", "prefix": "ind",
		"fields": ["enonce", "statut", "credibilite", "sujets", "pour", "contre", "relation", "de", "vers", "date_floue"],
		"required": ["enonce", "statut", "credibilite"],
		"defaults": {"statut": "non_verifie", "credibilite": 6}, "section": "Analyse", "color": "ffb38a"},
	"faveur": {"label": "Faveur", "desc": "Une dette entre deux Semblables", "prefix": "fav",
		"fields": ["debiteur", "creancier", "niveau", "statut", "credibilite", "date", "domaine", "harpie", "enregistree", "transferable", "fiche_reconnaissance"],
		"required": ["debiteur", "creancier", "niveau", "statut", "credibilite"],
		"defaults": {"niveau": "triviale", "statut": "active", "credibilite": 2, "date": "$today",
			"domaine": "$last_domaine", "enregistree": false, "transferable": true},
		"section": "Stipulations", "color": "ff8aa8"},
	"evenement": {"label": "Événement", "desc": "Un fait qui s'est produit", "prefix": "evt",
		"fields": ["description", "date_floue", "statut", "credibilite", "domaine", "lieu", "participants", "pour"],
		"required": ["description", "statut", "credibilite"],
		"defaults": {"date_floue": "$this_month", "statut": "non_verifie", "credibilite": 3, "domaine": "$last_domaine"},
		"section": "Récit", "color": "f5e08a"},
	"groupe": {"label": "Groupe", "desc": "Clan, faction, coterie", "prefix": "grp",
		"fields": ["nom", "nature", "clan", "secte", "domaine", "disciplines"], "required": ["nom"], "defaults": {"nature": "clan"},
		"section": "Notes", "color": "8fd3ff"},
	"lieu": {"label": "Lieu", "desc": "Refuge, Élysée, bar…", "prefix": "lie",
		"fields": ["nom", "nature_libre", "domaine"], "required": ["nom"], "defaults": {"domaine": "$last_domaine"},
		"section": "Notes", "color": "8fd3ff"},
	"domaine": {"label": "Domaine", "desc": "Une ville", "prefix": "dom",
		"fields": ["nom", "region", "preseance"], "form": ["nom", "region"], "required": ["nom"], "defaults": {}, "section": "Notes", "color": "8fd3ff"},
	"objet": {"label": "Objet", "desc": "Un artefact, un document", "prefix": "obj",
		"fields": ["nom", "nature_libre", "detenteur", "lieu"], "required": ["nom"], "defaults": {},
		"section": "Notes", "color": "8fd3ff"},
	"dossier": {"label": "Dossier d'enquête", "desc": "Une question à résoudre", "prefix": "dos",
		"fields": ["question", "statut", "priorite", "sujets", "indices"], "required": ["question", "statut"],
		"defaults": {"statut": "ouvert", "priorite": "moyenne"}, "section": "Hypothèses", "color": "d7a6ff"},
	"concept": {"label": "Concept", "desc": "Discipline, poste, règle, notion", "prefix": "cpt",
		"fields": ["nom", "nature", "secte"], "required": ["nom"], "defaults": {}, "section": "Notes", "color": "8fd3ff"},
}

const FORBIDDEN := "\\/:*?\"<>|#^[]"
const MONTHS := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
	"septembre", "octobre", "novembre", "décembre"]


## Vocabulaires du coffre (.nosferatu/config.json) : codes ajoutés aux listes
## par défaut, relations remplacées si le coffre en définit.
static var _extra_enums := {}
static var _relations: Array = RELATIONS


static func load_vocab(config: Dictionary) -> void:
	_extra_enums = {}
	_relations = RELATIONS
	var valeurs: Variant = config.get("valeurs", {})
	if typeof(valeurs) == TYPE_DICTIONARY:
		for k in valeurs:
			if typeof(valeurs[k]) != TYPE_ARRAY:
				continue
			var known := {}
			for o in ENUMS.get(k, []):
				known[str(o[0])] = true
			var add := []
			for code in valeurs[k]:
				if not known.has(str(code)):
					add.append([str(code), str(code).replace("_", " ")])
			if not add.is_empty():
				_extra_enums[k] = add
	# Les relations du coffre complètent celles du format (FORMAT §11) : rien n'est retiré.
	var rel: Variant = config.get("relations", [])
	if typeof(rel) == TYPE_ARRAY and not rel.is_empty():
		var out: Array = RELATIONS.duplicate(true)
		for r in rel:
			if typeof(r) != TYPE_DICTIONARY or not r.has("code"):
				continue
			var found := false
			for o in out:
				if o[0] == str(r.code):
					o[1] = str(r.get("libelle", o[1]))
					found = true
			if not found:
				out.append([str(r.code), str(r.get("libelle", r.code))])
		_relations = out


static func type_label(t: String) -> String:
	return str(TYPES[t].label) if TYPES.has(t) else (t if t != "" else "Note libre")


## Clé de propriété réelle d'un champ (nature_libre -> nature).
static func prop_key(field: String) -> String:
	return "nature" if field == "nature_libre" else field


## Options [[code, libellé]…] d'un champ à liste pour un type donné.
static func options(type_name: String, field: String) -> Array:
	match FIELDS.get(field, {}).get("kind", ""):
		"fiabilite":
			return FIABILITE
		"credibilite":
			return CREDIBILITE
		"relation":
			return _relations
	var key := type_name + "." + field
	return ENUMS.get(key, []) + _extra_enums.get(key, [])


static func option_label(type_name: String, field: String, code: Variant) -> String:
	for o in options(type_name, field):
		if str(o[0]) == str(code):
			return o[1]
	return "" if code == null else str(code)


## Libellé affiché dans une liste déroulante. La nature d'une source est
## précédée de sa fiabilité par défaut (« C · Discord ») : affichage seulement,
## option_label() reste le libellé nu (noms de fichiers, textes).
static func choice_label(type_name: String, field: String, code: Variant, label: String) -> String:
	if type_name == "source" and field == "nature":
		return "%s · %s" % [FIABILITE_PAR_NATURE.get(str(code), "F"), label]
	return label


## Champs du formulaire de création (sous-ensemble des champs du type).
static func form_fields(type_name: String) -> Array:
	return TYPES[type_name].get("form", TYPES[type_name].fields)


## Suggestions d'une liste de textes (postes, influences).
static func suggestions(list_name: String, domaine := "") -> Array:
	var out := []
	match list_name:
		"postes":
			for secte in POSTES:
				for p in POSTES[secte]:
					out.append(p + ((" de " + domaine) if domaine != "" else ""))
		"influences":
			for i in INFLUENCES:
				out.append(i + " (Gotha)")
				out.append(i + " (Pègre)")
	return out


## Champs connus d'un type, dans l'ordre d'affichage (propriétés réelles seulement).
static func prop_fields(type_name: String) -> Array:
	var out := []
	if not TYPES.has(type_name):
		return out
	for f in TYPES[type_name].fields:
		if not FIELDS.get(f, {}).get("form_only", false):
			out.append(f)
	if type_name == "en_cours":
		out.append_array(["statut", "devenue"])
	return out


## Valeurs préremplies d'un formulaire de création. `ctx` : {last_domaine, last_source_nature, now}.
static func defaults(type_name: String, ctx: Dictionary) -> Dictionary:
	var out := {}
	var now: Dictionary = ctx.get("now", Time.get_datetime_dict_from_system())
	for k in TYPES[type_name].defaults:
		var v: Variant = TYPES[type_name].defaults[k]
		if typeof(v) == TYPE_STRING and str(v).begins_with("$"):
			match v:
				"$today":
					v = "%04d-%02d-%02d" % [now.year, now.month, now.day]
				"$this_month":
					v = "%04d-%02d" % [now.year, now.month]
				"$last_domaine":
					var d := str(ctx.get("last_domaine", ""))
					v = ("[[%s]]" % d) if d != "" else null
				"$last_source_nature":
					v = str(ctx.get("last_source_nature", "note"))
				"$fiabilite_nature":
					v = null
		if v != null:
			out[k] = v
	if type_name == "source":
		out["fiabilite"] = FIABILITE_PAR_NATURE.get(out.get("nature", "note"), "F")
	return out


static func clean_name(s: String) -> String:
	var out := s
	for c in FORBIDDEN:
		out = out.replace(c, " ")
	while out.contains("  "):
		out = out.replace("  ", " ")
	out = out.strip_edges()
	while out.ends_with("."):
		out = out.substr(0, out.length() - 1).strip_edges()
	return out


## Nom affiché d'un lien "[[Nom|texte]]" -> "Nom".
static func link_name(v: Variant) -> String:
	var s := str(v if v != null else "").strip_edges()
	if s.begins_with("[[") and s.ends_with("]]"):
		s = s.substr(2, s.length() - 4)
		s = s.split("|")[0].split("#")[0]
	return s.strip_edges()


## Texte lisible pour les listes : [[Nom|texte]] -> texte, [[Nom]] -> Nom,
## [[Note#^el-…]] -> Note ; les champs [clé:: valeur] et ^identifiants sont retirés.
static var _R_WIKI := RegEx.create_from_string("!?\\[\\[([^\\[\\]]+?)\\]\\]")
static var _R_BLOCK := RegEx.create_from_string("\\s\\^[A-Za-z0-9-]+\\s*$")


static func display_text(s: String) -> String:
	var out := ""
	var pos := 0
	for m in _R_WIKI.search_all(s):
		out += s.substr(pos, m.get_start() - pos)
		var inner := m.get_string(1)
		var parts := inner.split("|", true, 1)
		out += parts[1] if parts.size() > 1 else parts[0].split("#")[0]
		pos = m.get_end()
	out += s.substr(pos)
	return out


## Énoncé d'une tâche ou d'un élément, sans la case « - [ ] » ni les champs.
static func display_line(s: String) -> String:
	var t := s.strip_edges()
	var m := RegEx.create_from_string("^[-*+]\\s+(\\[[ xX]\\]\\s+)?").search(t)
	if m:
		t = t.substr(m.get_end())
	t = _R_BLOCK.sub(t, "")
	return display_text(t).strip_edges()


## Valeur texte d'un formulaire ("" pour une valeur absente ou nulle).
static func _txt(v: Dictionary, k: String) -> String:
	var x: Variant = v.get(k)
	return "" if x == null else str(x)


## Nom du fichier (sans .md) selon les conventions du §4.1.
static func build_name(type_name: String, v: Dictionary, now: Dictionary) -> String:
	var date := _txt(v, "date")
	var n := ""
	match type_name:
		"en_cours":
			n = "%04d-%02d-%02d %02dh%02d Note rapide" % [now.year, now.month, now.day, now.hour, now.minute]
		"soiree":
			n = "%s %s - %s" % [date, link_name(v.get("domaine")), option_label("soiree", "nature", v.get("nature", "assemblee"))]
		"source":
			var canal := _txt(v, "canal").strip_edges()
			if canal == "":
				canal = option_label("source", "nature", v.get("nature", ""))
			n = ("%s %s - %s" % [date, canal, _txt(v, "titre")]).strip_edges()
		"faveur":
			n = "%s %s envers %s" % [date, link_name(v.get("debiteur")), link_name(v.get("creancier"))]
		"indice":
			n = _txt(v, "enonce")
		"evenement":
			# « AAAA-MM Description », ou la description seule si le mois est inconnu
			var m := RegEx.create_from_string("^(\\d{4}-(0[1-9]|1[0-2]))").search((_txt(v, "date") if _txt(v, "date") != "" else _txt(v, "date_floue")))
			n = ((m.get_string(1) + " ") if m else "") + _txt(v, "description")
		"dossier":
			n = "Dossier - " + _txt(v, "question")
		_:
			n = _txt(v, "nom")
	return clean_name(n)


static func folder(type_name: String, v: Dictionary, now: Dictionary) -> String:
	match type_name:
		"en_cours":
			return "En cours"
		"soiree":
			var d := str(v.get("date", ""))
			return "Soirees/" + (d.substr(0, 4) if d.length() >= 4 else str(now.year))
		"source":
			return "Sources/" + SOURCE_DOSSIERS.get(str(v.get("nature", "")), "Notes")
		"personnage":
			return "Personnages"
		"groupe":
			return "Groupes"
		"domaine":
			return "Domaines"
		"lieu":
			return "Lieux"
		"objet":
			return "Objets"
		"concept":
			return "Concepts"
		"evenement":
			return "Evenements"
		"indice":
			return "Indices"
		"faveur":
			return "Faveurs"
		"dossier":
			return "Dossiers"
	return ""


## Frontmatter complet d'une nouvelle note (texte entre les « --- »).
static func build_frontmatter(type_name: String, v: Dictionary, note_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("type: " + type_name)
	out.append("id: " + note_id)
	out.append("schema: 1")
	var keep: Array = TYPES[type_name].get("keep_empty", [])
	var fields := prop_fields(type_name)
	# Une date exacte peut remplacer la date floue (et inversement) : FORMAT §7.
	if fields.has("date_floue") and not fields.has("date") and str(v.get("date", "")) != "":
		fields[fields.find("date_floue")] = "date"
	elif fields.has("date") and not fields.has("date_floue") and str(v.get("date_floue", "")) != "" and str(v.get("date", "")) == "":
		fields[fields.find("date")] = "date_floue"
	for f in fields:
		var key := prop_key(f)
		var val: Variant = v.get(f, v.get(key))
		var empty: bool = val == null or (typeof(val) == TYPE_STRING and str(val).strip_edges() == "") \
			or (typeof(val) == TYPE_ARRAY and val.is_empty())
		if empty and not keep.has(f):
			continue
		if empty and typeof(val) != TYPE_ARRAY:
			val = []
		out.append_array(FlatYaml.dump_entry(key, val, "date" if key == "date" else ""))
	return out


## Corps d'une nouvelle note. `text` : texte repris (note rapide), placé dans la section principale.
static func build_body(type_name: String, name: String, v: Dictionary, text: String, now: Dictionary) -> String:
	var t := text.strip_edges()
	match type_name:
		"en_cours":
			return (t + "\n") if t != "" else ""
		"soiree":
			var d := str(v.get("date", ""))
			var nice := d
			if d.length() == 10:
				nice = "%d %s %s" % [d.substr(8, 2).to_int(), MONTHS[clampi(d.substr(5, 2).to_int() - 1, 0, 11)], d.substr(0, 4)]
			return "# %s de %s — %s\n\n## Déroulé\n%s\n## Éléments\n\n## À faire\n" % [
				option_label("soiree", "nature", v.get("nature", "assemblee")), link_name(v.get("domaine")), nice,
				(t + "\n") if t != "" else ""]
		"source":
			return "# %s\n\n## Contenu\n%s\n## Éléments\n" % [str(v.get("titre", name)), (t + "\n") if t != "" else ""]
		"indice":
			return "# %s\n\n## Analyse\n%s" % [name, (t + "\n") if t != "" else ""]
		"evenement":
			return "# %s\n\n## Récit\n%s" % [str(v.get("description", name)), (t + "\n") if t != "" else ""]
		"faveur":
			var d := str(v.get("date", ""))
			var mv := "- Contractée. [mv:: creation] [date:: %s] [niveau:: %s] [debiteur:: %s] [creancier:: %s]" % [
				d if d != "" else "inconnue", str(v.get("niveau", "triviale")), str(v.get("debiteur", "")), str(v.get("creancier", ""))]
			if str(v.get("harpie", "")) != "":
				mv += " [harpie:: %s]" % str(v.harpie)
			mv += " ^" + Ids.generate("mv")
			return "# %s envers %s\n\n## Stipulations\n%s\n## Mouvements\n%s\n" % [
				link_name(v.get("debiteur")), link_name(v.get("creancier")), (t + "\n") if t != "" else "", mv]
		"dossier":
			return "# %s\n\n## Hypothèses\n%s\n## Contradictions\n\n## À rechercher\n- [ ] \n" % [name, (t + "\n") if t != "" else ""]
		"personnage":
			return "# %s\n\n## Portrait\n\n## Notes\n%s" % [name, (t + "\n") if t != "" else ""]
	return "# %s\n\n## Notes\n%s" % [name, (t + "\n") if t != "" else ""]


## Vérifie un formulaire. Renvoie la liste des problèmes (vide = prêt).
static func check(type_name: String, v: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for f in TYPES[type_name].required:
		var val: Variant = v.get(f)
		if val == null or (typeof(val) == TYPE_STRING and str(val).strip_edges() == "") \
				or (typeof(val) == TYPE_ARRAY and val.is_empty()):
			out.append("« %s » est obligatoire" % FIELDS[f].label)
	if type_name == "soiree" and str(v.get("date", "")) == "":
		out.append("la date de la soirée est obligatoire")
	if type_name == "evenement" and str(v.get("date_floue", "")) == "" and str(v.get("date", "")) == "":
		out.append("indiquez une date, même approximative (« inconnue » est accepté)")
	var d := str(v.get("date", ""))
	if d != "" and not RegEx.create_from_string("^\\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\\d|3[01])$").search(d):
		out.append("date invalide : %s (format AAAA-MM-JJ)" % d)
	return out
