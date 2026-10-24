extends VBoxContainer
## Écran « Rapport de soirée » (format 1.3) :
##  - présents rangés par clan (préséance du domaine), statut d'âge et points
##    de statut ; on en ajoute (fiche existante ou nouvelle), on en retire, on
##    les passe en « incertain » ;
##  - informations : éléments de la soirée, des sources rattachées à la soirée
##    et ce qu'on y lie ; on change leur ordre (propriété `rapport`), leur
##    fiabilité (note d'origine) et leur crédibilité (ligne de l'élément) ;
##  - texte prêt à publier, copié dans le presse-papiers.
## Toutes les écritures passent par AppService (relecture, écriture sûre, index).

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const Ids := preload("res://core/format/ids.gd")
const Dates := preload("res://core/model/dates.gd")
const Report := preload("res://core/analysis/soiree_report.gd")
const Picker := preload("res://ui/widgets/picker.gd")
const FieldEditor := preload("res://ui/widgets/field_editor.gd")

const NOTE_FIAB := ["source", "soiree"]   ## notes dont la fiabilité A–F se modifie ici

var app: Node
var main: Control
var rel := ""
var rep := {}
var cotes := false
var hypotheses := false

var _title: Label
var _sub: Label
var _status: Label
var _col: VBoxContainer       ## colonne de gauche : présents
var _col2: VBoxContainer      ## colonne de droite : informations
var _form: VBoxContainer
var _f_text: LineEdit
var _f_nature: OptionButton
var _f_cred: OptionButton
var _f_par: Control
var _f_cred_touched := false


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var back := UiKit.button("←", func(): main.go_back(), "Retour")
	back.custom_minimum_size.x = UiKit.TOUCH + 8
	_title = UiKit.label("Rapport de soirée", false, 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = 60
	add_child(UiKit.hbox([back, _title]))
	_sub = UiKit.muted("")
	add_child(_sub)
	var row := UiKit.flow(6)
	row.add_child(UiKit.button("Choisir une soirée", _pick_soiree))
	row.add_child(UiKit.button("Ouvrir la fiche", func():
		if rel != "":
			main.open_note(rel)))
	row.add_child(UiKit.button("Copier le texte", _copy, "Texte prêt à publier (forum, Discord)"))
	for t in [["Avec les cotes", "cotes", "Ajoute la cote (B2…) de chaque information"],
			["Avec hypothèses", "hypotheses", "Garde les déductions et hypothèses dans le texte copié"]]:
		var key: String = t[1]
		var b := UiKit.button(t[0], func(): pass, t[2])
		b.toggle_mode = true
		b.toggled.connect(func(on): set(key, on))
		row.add_child(b)
	add_child(row)
	_status = UiKit.label("")
	add_child(_status)
	# deux colonnes côte à côte en plein écran : présents à gauche, informations à droite
	_col = UiKit.vbox([], 8)
	_col2 = UiKit.vbox([], 8)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(UiKit.scroll(_col))
	cols.add_child(UiKit.scroll(_col2))
	add_child(cols)


## Ouvre le rapport d'une soirée (chemin de la note).
func open(p_rel: String) -> void:
	rel = p_rel
	_status.text = ""
	if is_inside_tree():
		refresh()


func on_show() -> void:
	if rel == "" and app.index != null:
		rel = _default_soiree()
	refresh()


func on_job_finished(_job: String, _r: Dictionary) -> void:
	if is_inside_tree():
		refresh()


## Soirée du jour, sinon la plus récente.
func _default_soiree() -> String:
	var today: String = app.today_soiree()
	if today != "":
		return today
	var best := ""
	var best_date := ""
	for n in app.index.notes_with_props("soiree", ["date"]):
		var d := str(n.props.get("date", ""))
		if d > best_date:
			best_date = d
			best = str(n.path)
	return best


func _pick_soiree() -> void:
	Picker.open_in(main, app, "Rapport de quelle soirée ?", "notes", ["soiree"], func(v):
		var p: String = app.index.path_of_name(Schema.link_name(v))
		if p != "":
			open(p))


func _config() -> Dictionary:
	return app.repo.config if app.repo != null else {}


func refresh() -> void:
	for c in _col.get_children() + _col2.get_children():
		c.queue_free()
	_form = null
	if app.index == null:
		_sub.text = "Aucun coffre ouvert."
		return
	if rel == "" or app.index.path_of_name(rel.get_file().get_basename()) == "":
		rel = ""
		_title.text = "Rapport de soirée"
		_sub.text = "Aucune soirée : créez-en une, ou choisissez-en une."
		_col.add_child(UiKit.button("+ Nouvelle soirée", func(): main.new_note("soiree")))
		return
	rep = Report.build(app.index, rel, _config())
	_title.text = "Rapport — " + str(rep.name)
	var when := Dates.label(rep.date) if str(rep.date) != "" else "date inconnue"
	_sub.text = "%s de %s · %s · fiabilité de la prise de notes : %s" % [rep.nature, rep.domaine, when,
		rep.fiabilite if str(rep.fiabilite) != "" else "—"]
	_build_people()
	_build_items()


# ------------------------------------------------------------------ présents

func _build_people() -> void:
	var head := UiKit.flow(6)
	var nrep: int = (rep.get("reported", []) as Array).size()
	head.add_child(UiKit.heading(("Présents (%d)" % rep.people.size()) + (("  ·  %d rapportée(s)" % nrep) if nrep > 0 else "")))
	head.add_child(UiKit.button("+ Présent", func(): _add_person("presents"), "Fiche existante, ou nouvelle fiche"))
	head.add_child(UiKit.button("+ Incertain", func(): _add_person("presents_incertains"), "Présence supposée"))
	_col.add_child(head)
	var order: Array = rep.get("preseance", [])
	if order.is_empty():
		_col.add_child(UiKit.muted("Aucune préséance pour %s : clans par ordre alphabétique. Renseignez « Préséance des clans » sur la fiche du domaine." % rep.domaine))
	var bar: Dictionary = rep.bareme
	_col.add_child(UiKit.muted(("Points de statut : barème du coffre." if bar.configure else
		"Points de statut : barème par défaut (1 par poste du domaine, +1 par reconnaissance, −1 par tance, en cours et de crédibilité 1 à 3). Réglable dans .nosferatu/config.json, section « statut ».")))
	for g in rep.groups:
		var lab := UiKit.label(str(g.clan) if str(g.clan) != "" else "Clan inconnu", false, 17)
		lab.add_theme_color_override("font_color", Color("c8b6ff"))
		_col.add_child(lab)
		for p in g.people:
			_col.add_child(_person_card(p, "presents"))
	if not rep.uncertain.is_empty():
		var lab2 := UiKit.label("Présences incertaines (%d)" % rep.uncertain.size(), false, 17)
		lab2.add_theme_color_override("font_color", Color("e0b04a"))
		_col.add_child(lab2)
		for p in rep.uncertain:
			_col.add_child(_person_card(p, "presents_incertains"))
	var reported: Array = rep.get("reported", [])
	if not reported.is_empty():
		var lab3 := UiKit.label("Présences rapportées (%d)" % reported.size(), false, 17)
		lab3.add_theme_color_override("font_color", Color("9fd8a8"))
		_col.add_child(lab3)
		# les comptes rendus une fois, puis les noms par clan en étiquettes ; un appui
		# sur un nom propose : ouvrir la fiche, lire le compte rendu, l'ajouter à vos présents
		var notes := {}
		for p in reported:
			for x in p.get("reported_by", []):
				notes[str(x.note)] = str(x.path)
		var src_row := UiKit.flow(6)
		var cited := UiKit.muted("Citées par %s, sans être dans vos présents. Un appui sur un nom : ouvrir sa fiche, lire le compte rendu, ou l'ajouter à vos présents si vous l'avez vu(e) vous-même." % (
			"« %s »" % notes.keys()[0] if notes.size() == 1 else "%d comptes rendus" % notes.size()))
		cited.custom_minimum_size.x = 420
		_col.add_child(cited)
		for nn in notes:
			var sp: String = notes[nn]
			src_row.add_child(UiKit.button("Lire « %s »" % nn if notes.size() > 1 else "Lire le compte rendu", func(): main.open_note(sp), nn))
		_col.add_child(src_row)
		for g in rep.reported_groups:
			var lab4 := UiKit.label(str(g.clan) if str(g.clan) != "" else "Clan inconnu", false, 15)
			lab4.add_theme_color_override("font_color", Color("b6c9b8"))
			_col.add_child(lab4)
			var fl := UiKit.flow(6)
			for p in g.people:
				fl.add_child(_reported_chip(p))
			_col.add_child(fl)


## Présence rapportée : une étiquette (nom, statut d'âge) ; le détail au survol,
## les actions dans un menu.
func _reported_chip(p: Dictionary) -> Control:
	var mb := MenuButton.new()
	mb.flat = false
	mb.custom_minimum_size.y = 36
	mb.text = str(p.name) + (("  · " + str(p.rang_label)) if str(p.rang_label) != "" else "")
	var tips := PackedStringArray([str(p.name), Report.points_label(p)])
	for x in p.postes:
		tips.append(str(x.titre) + (" (autre domaine)" if x.hors_domaine else ""))
	for pair in [[p.recos, "Reconnu"], [p.tances, "Tancé"]]:
		for x in pair[0]:
			if x.compte:
				tips.append("%s « %s »" % [pair[1], x.qualificatif] if str(x.qualificatif) != "" else pair[1])
	var srcs: Array = p.get("reported_by", [])
	var names := PackedStringArray()
	for x in srcs:
		if not names.has(str(x.note)):
			names.append(str(x.note))
	if not names.is_empty():
		tips.append("Cité par : " + " · ".join(names))
	if p.missing:
		tips.append("Pas encore de fiche.")
		mb.add_theme_color_override("font_color", Color("e0b04a"))
	if not (p.sanctions as Array).is_empty():
		tips.append("Sanction : " + ", ".join(PackedStringArray((p.sanctions as Array).map(func(s): return Schema.option_label("personnage", "sanctions", s)))))
		mb.add_theme_color_override("font_color", Color("ff7a6b"))
	mb.tooltip_text = "\n".join(tips)
	var nm := str(p.name)
	var path := str(p.path)
	var pm := mb.get_popup()
	if path != "":
		pm.add_item("Ouvrir la fiche", 0)
	if not srcs.is_empty():
		pm.add_item("Lire le compte rendu" if names.size() == 1 else "Lire le premier compte rendu", 1)
	pm.add_item("Je l'ai vu(e) : l'ajouter à mes présents", 2)
	var sp := str(srcs[0].path) if not srcs.is_empty() else ""
	pm.id_pressed.connect(_on_reported_menu.bind(nm, path, sp))
	return mb


func _on_reported_menu(id: int, nm: String, path: String, src: String) -> void:
	if id == 0:
		main.open_note(path)
	elif id == 1:
		main.open_note(src)
	elif id == 2:
		_move_person(nm, "", "presents")


func _person_card(p: Dictionary, list_key: String) -> Control:
	var parts := PackedStringArray()
	if str(p.rang_label) != "":
		parts.append(p.rang_label)
	parts.append(Report.points_label(p))
	var title := UiKit.label("%s — %s" % [p.name, " · ".join(parts)], true, 16)
	var lines := []
	lines.append(title)
	var bits := PackedStringArray()
	for x in p.postes:
		bits.append(str(x.titre) + (" (autre domaine)" if x.hors_domaine else ""))
	for pair in [[p.recos, "Reconnu"], [p.tances, "Tancé"]]:
		for x in pair[0]:
			var s: String = "%s « %s »" % [pair[1], x.qualificatif] if str(x.qualificatif) != "" else pair[1]
			if str(x.de) != "":
				s += " par " + str(x.de)
			if x.etat == "expire":
				s += " — expiré"
			elif not x.compte:
				s += " — crédibilité %d, non compté" % int(x.cred)
			elif str(x.jusqu_au) != "":
				s += " — jusqu'au " + Dates.label(x.jusqu_au)
			bits.append(s)
	if not bits.is_empty():
		lines.append(UiKit.muted(" · ".join(bits)))
	var srcs: Array = p.get("reported_by", [])
	if not srcs.is_empty():
		var names := PackedStringArray()
		for x in srcs:
			if not names.has(str(x.note)):
				names.append(str(x.note))
		lines.append(UiKit.muted("Aussi rapporté par : " + " · ".join(names)))
	if p.missing:
		lines.append(UiKit.warn("Pas encore de fiche."))
	if not (p.sanctions as Array).is_empty():
		lines.append(UiKit.error("Sanction : " + ", ".join(PackedStringArray((p.sanctions as Array).map(func(s): return Schema.option_label("personnage", "sanctions", s))))))
	var actions := UiKit.flow(6)
	var nm := str(p.name)
	var path := str(p.path)
	if path != "":
		actions.add_child(UiKit.button("Ouvrir", func(): main.open_note(path)))
	if list_key == "presents":
		actions.add_child(UiKit.button("Incertain", func(): _move_person(nm, "presents", "presents_incertains"), "Passer en présence incertaine"))
	else:
		actions.add_child(UiKit.button("Certain", func(): _move_person(nm, "presents_incertains", "presents"), "Présence constatée"))
	actions.add_child(UiKit.button("Retirer", func(): _move_person(nm, list_key, ""), "Retirer de la soirée (la fiche reste)"))
	lines.append(actions)
	return UiKit.card(lines, Color("8fd3ff") if list_key == "presents" else Color("e0b04a"))


func _list_prop(key: String) -> Array:
	var v: Variant = app.index.props_of(rel).get(key, [])
	if typeof(v) == TYPE_ARRAY:
		return v.duplicate()
	return [] if v == null or str(v) == "" else [v]


func _add_person(list_key: String) -> void:
	Picker.open_in(main, app, "Ajouter un présent" if list_key == "presents" else "Présence incertaine", "notes", ["personnage"], func(v):
		var nm := Schema.link_name(v)
		var changes := {}
		for k in ["presents", "presents_incertains"]:
			var lst := _list_prop(k).filter(func(x): return Schema.link_name(x).to_lower() != nm.to_lower())
			if k == list_key:
				lst.append("[[%s]]" % nm)
			changes[k] = lst
		_write_props(changes, "%s ajouté(e) ✓" % nm))


func _move_person(nm: String, from_key: String, to_key: String) -> void:
	var changes := {}
	if from_key != "":
		changes[from_key] = _list_prop(from_key).filter(func(x): return Schema.link_name(x).to_lower() != nm.to_lower())
	if to_key != "":
		var lst := _list_prop(to_key).filter(func(x): return Schema.link_name(x).to_lower() != nm.to_lower())
		lst.append("[[%s]]" % nm)
		changes[to_key] = lst
	_write_props(changes, ("%s retiré(e) de la soirée ✓" % nm) if to_key == "" else "%s : présence modifiée ✓" % nm)


func _write_props(changes: Dictionary, ok_text: String) -> void:
	var r: Dictionary = app.set_note_properties(rel, changes)
	_status.text = ok_text if r.ok else "NON enregistré : " + str(r.get("error", "?"))
	refresh()


# ------------------------------------------------------------------ informations

func _build_items() -> void:
	var head := UiKit.flow(6)
	head.add_child(UiKit.heading("Informations (%d)" % rep.items.size()))
	head.add_child(UiKit.button("+ Nouvelle", _toggle_form, "Écrire une information dans la soirée"))
	head.add_child(UiKit.button("+ Lier un élément", _link_element, "Un élément d'une autre note"))
	head.add_child(UiKit.button("+ Lier une note", _link_note, "Un événement, un indice, une source"))
	_col2.add_child(head)
	_col2.add_child(UiKit.muted("Les sources dont la propriété « Soirée concernée » vise cette soirée y figurent d'office. Les flèches changent l'ordre du rapport ; la fiabilité (A–F) et la crédibilité (1–6) s'écrivent dans la note d'où vient l'information."))
	if int(rep.missing_ids) > 0:
		_col2.add_child(UiKit.warn("%d information(s) sans identifiant : elles en recevront un au premier déplacement." % int(rep.missing_ids)))
	_form = UiKit.vbox([], 6)
	_form.visible = false
	_col2.add_child(_form)
	_build_form()
	var n := 0
	for i in rep.items.size():
		n += 1
		_col2.add_child(_item_card(i, n))


func _origin_label(it: Dictionary) -> String:
	if it.origin == "soiree":
		return "Soirée"
	return "%s · %s" % [it.note, Schema.type_label(str(it.note_type))]


func _item_card(i: int, n: int) -> Control:
	var it: Dictionary = rep.items[i]
	var lines := []
	var txt := UiKit.label("%d. %s" % [n, Schema.display_text(str(it.text))], true, 16)
	lines.append(txt)
	if it.kind == "absent":
		lines.append(UiKit.warn("Introuvable : la note ou l'élément a été renommé ou supprimé."))
	else:
		var meta := PackedStringArray([_origin_label(it)])
		if str(it.nature) != "":
			meta.append(Schema.option_label("element", "nature", it.nature).split(" (")[0])
		if str(it.get("par", "")) != "":
			meta.append("dit par " + str(it.par))
		if str(it.get("statut", "")) != "":
			meta.append(Schema.option_label(str(it.note_type), "statut", it.statut))
		lines.append(UiKit.muted(" · ".join(meta)))
	var row := UiKit.flow(6)
	if it.kind != "absent":
		if str(it.note_type) in NOTE_FIAB:
			var fo := UiKit.option_button(Schema.FIABILITE.map(func(o): return str(o[0])), 0)
			fo.custom_minimum_size.x = 70
			fo.size_flags_horizontal = Control.SIZE_FILL
			fo.tooltip_text = "Fiabilité de la note d'origine (%s) : vaut pour toutes ses informations" % it.note
			var codes: Array = Schema.FIABILITE.map(func(o): return str(o[0]))
			var cur := codes.find(str(it.fiab))
			if cur < 0:
				fo.add_item("—")
				cur = codes.size()
			fo.select(cur)
			fo.item_selected.connect(func(k):
				if k < codes.size():
					_set_fiab(it, codes[k]))
			row.add_child(fo)
		var co := UiKit.option_button(Schema.CREDIBILITE.map(func(o): return str(o[0])), 0)
		co.custom_minimum_size.x = 70
		co.size_flags_horizontal = Control.SIZE_FILL
		co.tooltip_text = "Crédibilité de l'information"
		if it.cred != null and int(it.cred) >= 1 and int(it.cred) <= 6:
			co.select(int(it.cred) - 1)
		else:
			co.add_item("—")
			co.select(6)
		co.item_selected.connect(func(k):
			if k < 6:
				_set_cred(it, k + 1))
		row.add_child(co)
	var up := UiKit.button("↑", func(): _move(i, -1), "Monter")
	up.disabled = i == 0
	var down := UiKit.button("↓", func(): _move(i, 1), "Descendre")
	down.disabled = i == rep.items.size() - 1
	for b in [up, down]:
		b.custom_minimum_size.x = UiKit.TOUCH
		row.add_child(b)
	var path := str(it.path)
	if path != "":
		row.add_child(UiKit.button("Ouvrir", func(): main.open_note(path)))
	if it.origin == "lien" or it.kind == "absent":
		row.add_child(UiKit.button("Retirer", func(): _unlink(i), "Retirer du rapport (la note n'est pas touchée)"))
	lines.append(row)
	var accent := Color("9be3a8")
	if str(it.nature) in ["hypothese", "deduction"]:
		accent = Color("d7a6ff")
	elif it.kind == "absent":
		accent = Color("ff9b8a")
	return UiKit.card(lines, accent)


func _set_fiab(it: Dictionary, letter: String) -> void:
	var r: Dictionary = app.set_note_properties(str(it.path), {"fiabilite": letter})
	_status.text = ("Fiabilité de « %s » : %s ✓" % [it.note, letter]) if r.ok else "NON enregistré : " + str(r.get("error", "?"))
	refresh()


func _set_cred(it: Dictionary, c: int) -> void:
	var r: Dictionary
	if it.kind == "note":
		r = app.set_note_properties(str(it.path), {"credibilite": c})
	else:
		r = app.update_element(str(it.path), str(it.block), int(it.line), str(it.text), {"credibilite": c})
	_status.text = ("Crédibilité : %d ✓ (écrite dans « %s »)" % [c, it.note]) if r.ok else "NON enregistré : " + str(r.get("error", "?"))
	refresh()


## Déplace une information. Les éléments sans identifiant en reçoivent un
## d'abord : l'ordre du rapport les cite par leur identifiant.
func _move(i: int, d: int) -> void:
	var j := i + d
	if j < 0 or j >= rep.items.size():
		return
	if int(rep.missing_ids) > 0:
		var notes := {}
		for it in rep.items:
			if it.kind == "element" and str(it.block) == "":
				notes[str(it.path)] = true
		var added := 0
		for p in notes:
			var a: Dictionary = app.assign_missing_ids(p)
			if not a.ok:
				_status.text = "NON enregistré : " + str(a.get("error", "?"))
				return
			added += int(a.added)
		rep = Report.build(app.index, rel, _config())
		_status.text = "Identifiant attribué à %d information(s)." % added
	var items: Array = rep.items.duplicate()
	var tmp: Variant = items[i]
	items[i] = items[j]
	items[j] = tmp
	_write_order(items, "Ordre enregistré ✓")


func _write_order(items: Array, ok_text: String) -> void:
	var refs := Report.order_refs(items)
	var r: Dictionary = app.set_note_properties(rel, {"rapport": refs})
	_status.text = ok_text if r.ok else "NON enregistré : " + str(r.get("error", "?"))
	refresh()


func _unlink(i: int) -> void:
	var items: Array = rep.items.duplicate()
	var it: Dictionary = items[i]
	items.remove_at(i)
	if it.kind == "absent":
		# référence cassée : on la retire telle qu'elle est écrite
		var refs := _list_prop("rapport").filter(func(x): return str(x) != str(it.ref))
		var r: Dictionary = app.set_note_properties(rel, {"rapport": refs})
		_status.text = "Retiré du rapport ✓" if r.ok else "NON enregistré : " + str(r.get("error", "?"))
		refresh()
		return
	_write_order(items, "Retiré du rapport ✓ (la note n'est pas modifiée)")


func _link(ref: String) -> void:
	var refs := Report.order_refs(rep.items)
	var low := ref.to_lower()
	for x in refs:
		if str(x).to_lower() == low:
			_status.text = "Déjà dans le rapport."
			return
	refs.append(ref)
	var r: Dictionary = app.set_note_properties(rel, {"rapport": refs})
	_status.text = "Information liée ✓" if r.ok else "NON enregistré : " + str(r.get("error", "?"))
	refresh()


func _link_element() -> void:
	Picker.open_in(main, app, "Lier un élément au rapport", "elements", [], func(v): _link(str(v)))


func _link_note() -> void:
	Picker.open_in(main, app, "Lier une note au rapport", "notes", ["evenement", "indice", "source"], func(v): _link(str(v)))


# ------------------------------------------------------------------ nouvelle information

func _toggle_form() -> void:
	if _form != null:
		_form.visible = not _form.visible
		if _form.visible:
			_f_text.grab_focus()


func _build_form() -> void:
	_f_text = UiKit.line_edit("Ce que vous avez vu ou appris, avec les noms en [[liens]]")
	_form.add_child(UiKit.hbox([_f_text, UiKit.button("+ Lien", func():
		Picker.open_in(main, app, "Insérer un lien", "notes", [], func(v):
			_f_text.insert_text_at_caret(v)
			_f_text.grab_focus()), "Insérer un lien vers une fiche")]))
	var natures: Array = Schema.ENUMS["element.nature"]
	_f_nature = UiKit.option_button(natures.map(func(o): return o[1]), 0)
	_f_cred = UiKit.option_button(Schema.CREDIBILITE.map(func(o): return o[1]), int(Schema.CREDIBILITE_PAR_NATURE["observe"]) - 1)
	_f_cred_touched = false
	_f_nature.item_selected.connect(func(k):
		if not _f_cred_touched:
			_f_cred.select(int(Schema.CREDIBILITE_PAR_NATURE[natures[k][0]]) - 1))
	_f_cred.item_selected.connect(func(_k): _f_cred_touched = true)
	_form.add_child(UiKit.vbox([UiKit.muted("Nature"), _f_nature], 3))
	_form.add_child(UiKit.vbox([UiKit.muted("Crédibilité (1–6)"), _f_cred], 3))
	_f_par = FieldEditor.make(app, main, "element", "par", null, false)
	_form.add_child(_f_par)
	_form.add_child(UiKit.button("Ajouter à la soirée", _add_info))


func _add_info() -> void:
	var t := _f_text.text.strip_edges().replace("\n", " ")
	if t == "":
		_status.text = "Écrivez d'abord l'information."
		return
	var natures: Array = Schema.ENUMS["element.nature"]
	var line := "- %s [nature:: %s] [credibilite:: %d]" % [t, natures[_f_nature.selected][0], _f_cred.selected + 1]
	var par: Variant = _f_par.get_value()
	if par != null:
		line += " [par:: %s]" % str(par)
	line += " ^" + Ids.generate("el")
	var r: Dictionary = app.append_element(rel, line)
	if not r.ok:
		_status.text = "NON enregistré : " + str(r.get("error", "?"))
		return
	_status.text = "Information ajoutée ✓ (à la fin du rapport)"
	refresh()


func _copy() -> void:
	if rep.is_empty():
		return
	DisplayServer.clipboard_set(Report.to_text(rep, cotes, hypotheses))
	_status.text = "Rapport copié ✓ — %s%s." % ["avec les cotes" if cotes else "sans les cotes",
		", hypothèses comprises" if hypotheses else ", sans les hypothèses ni les déductions"]
