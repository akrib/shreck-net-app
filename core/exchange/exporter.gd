extends RefCounted
## Export d'une sélection de notes pour une conversation avec Claude.
## Le texte produit contient : les consignes (format, prudence), l'annuaire des
## fiches (pour réutiliser les noms exacts) et le contenu intégral des notes
## choisies. Il est copié dans le presse-papiers et rangé dans `_Export/` en
## .txt (ni Obsidian ni l'application ne l'indexent). Aucune note n'est modifiée.

const Schema := preload("res://core/model/schema.gd")
const TextNorm := preload("res://core/format/text_norm.gd")

const MAX_NOTES := 80
const MAX_BYTES := 400000
const ENTITY_TYPES := ["personnage", "groupe", "domaine", "lieu", "objet", "concept"]

const SCOPES := [["fiche", "Une fiche et ses liens"], ["domaine", "Un domaine (soirées, sources, personnes)"],
	["rapides", "Les notes rapides à traiter"], ["recentes", "Les notes modifiées ces 30 derniers jours"]]


## Choisit les notes d'un périmètre. Renvoie [chemins] (le plus important d'abord).
static func select(index: RefCounted, scope: String, subject: String) -> Array:
	var out := []
	var seen := {}
	var add := func(p: String) -> void:
		if p != "" and not seen.has(p) and out.size() < MAX_NOTES:
			seen[p] = true
			out.append(p)
	match scope:
		"fiche":
			add.call(index.path_of_name(subject))
			# notes vers lesquelles elle pointe, puis celles qui pointent vers elle
			var rel: String = index.path_of_name(subject)
			for r in index.rows("SELECT DISTINCT g.path FROM links l JOIN files f ON f.fid = l.fid JOIN files g ON g.name_key = l.target_key WHERE f.path = ? ORDER BY g.name_key", [rel]):
				add.call(str(r.path))
			for b in index.backlinks(subject, 200):
				add.call(str(b.path))
		"domaine":
			add.call(index.path_of_name(subject))
			# d'abord ce qui s'est passé (soirées, sources, faveurs, événements), puis les fiches
			for r in index.linked_from(subject, ["domaine"]):
				if str(r.type) in ["soiree", "source", "faveur", "evenement"]:
					add.call(str(r.path))
			for r in index.linked_from(subject, ["domaine"]):
				add.call(str(r.path))
		"rapides":
			for r in index.quick_notes_todo(MAX_NOTES):
				add.call(str(r.path))
		"recentes":
			var since := int(Time.get_unix_time_from_system()) - 30 * 86400
			for r in index.rows("SELECT path FROM files WHERE mtime >= ? AND type != '' ORDER BY mtime DESC LIMIT ?", [since, MAX_NOTES]):
				add.call(str(r.path))
	return out


## Construit le texte d'export. `read` : Callable(rel) -> String (contenu du fichier).
static func build(index: RefCounted, paths: Array, subject_label: String, read: Callable) -> Dictionary:
	var d := Time.get_datetime_dict_from_system()
	var t := PackedStringArray()
	t.append("# Export Nosferatu Intelligence — %s — %02d/%02d/%04d" % [subject_label, d.day, d.month, d.year])
	t.append("")
	t.append("Ces notes viennent de mon coffre (format Nosferatu v1.2 : voir FORMAT.md et GUIDE-CONVERSION.md dans le projet).")
	t.append("")
	t.append("Consignes :")
	t.append("- N'invente aucune information de jeu. Ne transforme jamais une hypothèse ou une rumeur en fait.")
	t.append("- Distingue ce que disent les sources (avec leur fiabilité et leur crédibilité) de tes propres déductions.")
	t.append("- Si je te demande des notes, rends un lot d'import conforme (dossier `_Import/AAAA-MM-JJ sujet/` avec `_lot.md`), avec des identifiants complets. Ne modifie aucune note existante : propose les changements dans `_lot.md`.")
	t.append("- Réutilise exactement les noms de l'annuaire ci-dessous pour les liens [[…]].")
	t.append("- Les notes « En cours » sont des notes rapides prises sur le vif : à transformer en sources et éléments, sans les recopier telles quelles.")
	t.append("")
	t.append("## Annuaire des fiches (nom · type · identifiant)")
	var n_ann := 0
	for r in index.rows("SELECT name, type, id FROM files WHERE type IN ('personnage','groupe','domaine','lieu','objet','concept') ORDER BY type, name_key"):
		t.append("- %s · %s · %s" % [r.name, r.type, "" if r.id == null else str(r.id)])
		n_ann += 1
	t.append("")
	t.append("## Notes (%d)" % paths.size())
	var bytes := 0
	var included := 0
	var truncated := false
	for p in paths:
		var content: String = read.call(p)
		if bytes + content.length() > MAX_BYTES and included > 0:
			truncated = true
			break
		t.append("")
		t.append("### " + str(p))
		t.append("```markdown")
		t.append(content.strip_edges())
		t.append("```")
		bytes += content.length()
		included += 1
	if truncated:
		t.append("")
		t.append("*(Export limité à %d notes pour rester lisible : affinez le périmètre pour voir le reste.)*" % included)
	var text := "\n".join(t) + "\n"
	return {"text": text, "notes": included, "annuaire": n_ann, "truncated": truncated, "chars": text.length()}


static func file_name(subject_label: String) -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02dh%02d Export %s.txt" % [d.year, d.month, d.day, d.hour, d.minute, Schema.clean_name(subject_label).left(60)]
