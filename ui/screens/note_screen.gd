extends VBoxContainer
## Écran « Note » : à gauche, l'ajout rapide d'un élément et le texte ; à droite,
## dans un panneau escamotable, la fiche (propriétés avec listes déroulantes et
## sélecteurs), les renseignements calculés et les rétroliens.
## Une note rapide s'affiche comme un simple bloc-notes, avec « Transformer ».
## L'enregistrement passe toujours par AppService.save_note (écriture sûre,
## contrôle de conflit, puis index). Rien n'est annoncé « enregistré » avant
## la vérification du fichier sur disque.

const UiKit := preload("res://ui/ui_kit.gd")
const Ids := preload("res://core/format/ids.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const Schema := preload("res://core/model/schema.gd")
const FieldEditor := preload("res://ui/widgets/field_editor.gd")
const Picker := preload("res://ui/widgets/picker.gd")
const FicheInfo := preload("res://ui/widgets/fiche_info.gd")
const FusionDialog := preload("res://ui/widgets/fusion_dialog.gd")
const SlidePanel := preload("res://ui/widgets/slide_panel.gd")
const Informants := preload("res://core/analysis/informants.gd")
const InformantBox := preload("res://ui/widgets/informant_box.gd")

## Types de fiches qu'on peut fusionner (un inconnu identifié, un doublon).
const MERGEABLE := ["personnage", "groupe", "lieu", "objet", "domaine", "concept"]

const LIST_KEYS := ["aliases", "tags", "cssclasses", "sanctions", "peut_etre", "titres", "presents",
	"presents_incertains", "absents", "pour", "contre", "sujets", "participants", "indices", "devenue"]
const HINTS := {"date": "date"}
const HIDDEN := ["type", "id", "schema"]

var app: Node
var main: Control
var rel := ""
var doc: RefCounted = null
var hash := ""
var _parsed := {}
var _typed := {}      ## clé de propriété -> FieldEditor
var _generic := {}    ## clé -> {control, kind}
var _originals := {}
var _comments_ok := false
var _dirty := false
var _building := false

var _col: VBoxContainer          ## colonne principale : ajout d'élément, texte
var _side_col: VBoxContainer     ## panneau de droite : fiche, renseignements, rétroliens
var _side_panel: Control
var _title: Label
var _path_label: Label
var _status: Label
var _body: TextEdit
var _new_key: LineEdit
var _new_val: LineEdit
var _el_text: LineEdit
var _el_nature: OptionButton
var _el_cred: OptionButton
var _el_cred_touched := false
var _el_more := {}
var _confirm: ConfirmationDialog
var _pending := ""


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var back := UiKit.button("←", func(): main.go_back(), "Retour")
	back.custom_minimum_size.x = UiKit.TOUCH + 8
	var top := UiKit.hbox([back])
	_title = UiKit.label("", false, 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = 60
	top.add_child(_title)
	top.add_child(UiKit.button("Enregistrer", save, "Ctrl+S"))
	var del := UiKit.button("Supprimer…", _ask_delete, "Mettre la note à la corbeille du coffre (restaurable)")
	del.add_theme_color_override("font_color", Color("ff9b8a"))
	top.add_child(del)
	add_child(top)
	_path_label = UiKit.muted("")
	add_child(_path_label)
	_status = UiKit.label("")
	add_child(_status)
	_col = UiKit.vbox([], 10)
	_side_col = UiKit.vbox([], 10)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var main_scroll := UiKit.scroll(_col, 1100)
	main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(main_scroll)
	_side_panel = SlidePanel.make(app, "note", "right", 460, UiKit.scroll(_side_col), true, Color("1b1721"))
	body.add_child(_side_panel)
	add_child(body)
	_confirm = UiKit.confirm_dialog()
	_confirm.confirmed.connect(_on_confirmed)
	add_child(_confirm)


func has_note() -> bool:
	return doc != null


func is_dirty() -> bool:
	return _dirty


## Ouvre une note (relue sur disque). Renvoie false si la lecture échoue.
func open(p_rel: String) -> bool:
	if _dirty and rel != "" and p_rel != rel:
		save_draft()
	var r: Dictionary = app.read_note(p_rel)
	if not r.ok:
		app._log("Lecture impossible de %s : %s" % [p_rel, r.error])
		return false
	rel = p_rel
	doc = r.doc
	hash = r.hash
	_parsed = r.parsed
	_comments_ok = false
	_build()
	_set_status("")
	_check_draft()
	return true


func on_show() -> void:
	if doc == null:
		return
	# La note a-t-elle changé sur disque pendant qu'elle était affichée ?
	if not _dirty:
		var r: Dictionary = app.read_note(rel)
		if r.ok and r.hash != hash:
			open(rel)
			_set_status("Note rechargée : elle a été modifiée ailleurs (GitSync, Obsidian…).")


func _clear() -> void:
	for c in _col.get_children():
		c.queue_free()
	for c in _side_col.get_children():
		c.queue_free()
	_typed.clear()
	_generic.clear()
	_originals.clear()
	_el_more.clear()
	_el_text = null
	_new_key = null


func note_name() -> String:
	return rel.get_file().get_basename()


func _build() -> void:
	_building = true
	_clear()
	_dirty = false
	var t: String = doc.type_name()
	_title.text = note_name()
	_path_label.text = "%s · %s" % [Schema.type_label(t), rel]
	var probs: Array = app.index.problems_of(rel) if app.index != null else []
	for p in probs:
		if p.level != "INFO" or str(p.message).contains("commentaires"):
			var l := UiKit.error("%s ligne %d : %s" % [p.level, p.line, p.message]) if p.level == "ERREUR" \
				else UiKit.warn("%s ligne %d : %s" % [p.level, p.line, p.message])
			_col.add_child(l)
	if not doc.utf8_ok:
		_col.add_child(UiKit.warn("Fichier non UTF-8 : lecture seule."))
	var sans_id := 0
	for e in _parsed.get("elements", []) + _parsed.get("movements", []):
		if str(e.block) == "":
			sans_id += 1
	if sans_id > 0 and doc.utf8_ok:
		_col.add_child(UiKit.warn("%d ligne(s) structurée(s) sans identifiant (^el-…) : on ne peut pas les citer." % sans_id))
		_col.add_child(UiKit.button("Attribuer les identifiants manquants", _assign_ids, "Ajoute ^el-… ou ^mv-… en fin de ligne, rien d'autre"))
	var quick: bool = t == "en_cours" and doc.can_edit_properties()
	_side_panel.visible = not quick
	if quick:
		_build_quick()
		_building = false
		return
	var props: Dictionary = doc.properties()
	if t == "soiree":
		var me := rel
		_col.add_child(UiKit.button("Rapport de soirée", func(): main.show_report(me), "Présents par préséance, informations dans l'ordre, texte à publier"))
	elif t == "dossier":
		var me := rel
		_col.add_child(UiKit.hbox([UiKit.button("Tableau des hypothèses", func(): main.show_hypotheses(me),
			"Les indices du dossier face aux éléments : la moins contredite d'abord")]))
	# Pendant une soirée ou la lecture d'une source, l'ajout d'élément passe en premier.
	if t in ["soiree", "source"] and doc.can_edit_properties():
		_build_element_form(t)
	if doc.can_edit_properties():
		if Schema.TYPES.has(t):
			_side_col.add_child(UiKit.heading("Fiche"))
			for f in Schema.prop_fields(t):
				_add_typed(t, f, props)
		var others := []
		for key in doc.fm.order:
			if not _typed.has(key) and not (Schema.TYPES.has(t) and key in HIDDEN):
				others.append(key)
		var box: Container = _side_col
		if Schema.TYPES.has(t):
			var fold := FoldableContainer.new()
			fold.title = "Autres propriétés (%d)" % others.size()
			fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # titre long : jamais plus large que l'écran
			fold.folded = true
			var inner := UiKit.vbox([], 8)
			fold.add_child(inner)
			_side_col.add_child(fold)
			box = inner
			if props.has("id"):
				inner.add_child(UiKit.muted("Identifiant : %s · schéma %s" % [str(props.id), str(props.get("schema", "?"))]))
		else:
			_side_col.add_child(UiKit.heading("Propriétés"))
		for key in others:
			_add_generic(box, key, props[key])
		_new_key = UiKit.line_edit("nouvelle propriété")
		_new_val = UiKit.line_edit("valeur")
		box.add_child(UiKit.hbox([_new_key, _new_val]))
	else:
		_side_col.add_child(UiKit.warn("Propriétés non conformes au format : elles ne sont pas modifiables ici (corrigez-les dans Obsidian ou un éditeur de texte). Le texte reste modifiable."))
		var raw := UiKit.report_box(120)
		raw.text = "\n".join(doc.fm_lines)
		_side_col.add_child(raw)
	# Fiche (personnage, groupe, lieu…) : ce qu'on en sait passe dans la colonne large ;
	# le formulaire reste dans le panneau de droite.
	var wide: bool = t in MERGEABLE and app.index != null
	var actions := UiKit.flow(6)
	if wide:
		var head := _summary(t, props)
		if head != null:
			_col.add_child(head)
		_col.add_child(actions)
	else:
		_side_col.add_child(actions)
	# texte
	_col.add_child(UiKit.hbox([UiKit.heading("Notes" if wide else "Texte"), UiKit.button("+ Lien", _insert_link_body, "Insérer un lien vers une fiche")]))
	_body = TextEdit.new()
	_body.text = doc.body_for_edit()
	_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body.scroll_fit_content_height = true
	_body.custom_minimum_size.y = 110 if wide else 220
	_body.editable = doc.utf8_ok
	_body.text_changed.connect(_mark_dirty)
	_col.add_child(_body)
	_col.add_child(UiKit.hbox([UiKit.button("Enregistrer", save), UiKit.button("Recharger depuis le disque", _reload)]))
	# renseignements calculés et rétroliens
	if t in ["personnage", "groupe"] and app.index != null:
		var nm := note_name()
		var gb := actions
		gb.add_child(UiKit.button("Voir dans le graphe", func(): main.show_graph(nm), "Relations, faveurs, clan, sire"))
		gb.add_child(UiKit.button("Chemin vers…", func(): main.show_paths(nm, ""), "Les liens les plus probables vers une autre fiche"))
		if t == "personnage":
			gb.add_child(UiKit.button("Où était-il ?", func(): main.show_alibis("personne", nm), "Enquête → Alibis : sa ligne de temps"))
		if doc.can_edit_properties():
			var watched := _is_watched()
			var wb := UiKit.button("Ne plus surveiller" if watched else "Surveiller", _toggle_watch,
				"Alerte à chaque nouvel élément qui la cite (étiquette « surveille »)")
			if watched:
				wb.add_theme_color_override("font_color", Color("e0b04a"))
				# ouvrir la fiche, c'est la consulter : ses nouveaux éléments sont lus
				app.mark_seen(nm)
			gb.add_child(wb)
	if t in MERGEABLE and app.index != null and doc.can_edit_properties():
		actions.add_child(UiKit.button("Fusionner…", _merge, "Avec une autre fiche (un inconnu identifié, un doublon) : les liens suivent, rien n'est supprimé"))
	if actions.get_child_count() == 0:
		actions.queue_free()
	if app.index != null:
		var info: Control = FicheInfo.build(app, main, rel, note_name(), t, wide)
		if info != null:
			if wide:
				_col.add_child(UiKit.heading("Ce que disent vos sources"))
			(_col if wide else _side_col).add_child(info)
	if t == "personnage" and app.index != null:
		_side_col.add_child(InformantBox.build(app, main, Informants.evaluate(app.index, note_name()), _apply_reliability))
	if app.index != null:
		_add_backlinks()
	_building = false


## En-tête d'une fiche : ce qui la situe d'un coup d'œil (clan, statut d'âge, domaine, postes…).
func _summary(t: String, props: Dictionary) -> Control:
	var row := UiKit.flow(6)
	var add := func(v: Variant, color: Color) -> void:
		var s := Schema.display_text(str(v)).strip_edges()
		if s != "" and s != "<null>":
			row.add_child(UiKit.pill(s, color))
	if t == "personnage":
		add.call(props.get("clan", ""), Color("c8b6ff"))
		add.call(props.get("secte", ""), Color("8fd3ff"))
		if str(props.get("rang", "")) != "":
			add.call(Schema.option_label("personnage", "rang", props.rang), Color("9fd8a8"))
		if str(props.get("nature", "")) not in ["", "vampire"]:
			add.call(Schema.option_label("personnage", "nature", props.nature), Color("e0b04a"))
		var st := str(props.get("statut", ""))
		if st not in ["", "actif"]:
			add.call(Schema.option_label("personnage", "statut", st), Color("ff9b8a"))
		for x in _as_list(props.get("sanctions")):
			add.call(Schema.option_label("personnage", "sanctions", x), Color("ff9b8a"))
	else:
		add.call(props.get("nature", ""), Color("c8b6ff"))
		add.call(props.get("clan", ""), Color("c8b6ff"))
	add.call(props.get("domaine", ""), Color("8fd3ff"))
	for x in _as_list(props.get("titres")).slice(0, 6):
		add.call(x, Color("e0b04a"))
	for x in _as_list(props.get("aliases")).slice(0, 4):
		add.call("alias : " + str(x), Color("a59cb3"))
	if row.get_child_count() == 0:
		row.queue_free()
		return null
	return row


static func _as_list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v
	return [] if str(v).strip_edges() == "" else [v]


func _add_typed(t: String, f: String, props: Dictionary, box: Container = null) -> void:
	var key := Schema.prop_key(f)
	var ed = FieldEditor.make(app, main, t, f, props.get(key), (Schema.TYPES[t].required as Array).has(f))
	ed.changed.connect(_mark_dirty)
	_typed[key] = ed
	(box if box != null else _side_col).add_child(ed)


func _add_generic(box: Container, key: String, value: Variant) -> void:
	_originals[key] = value
	var v := UiKit.vbox([], 2)
	v.add_child(UiKit.muted(key))
	if typeof(value) == TYPE_ARRAY or key in LIST_KEYS:
		var t := TextEdit.new()
		var items := PackedStringArray()
		for x in (value if typeof(value) == TYPE_ARRAY else ([] if value == null else [value])):
			items.append("" if x == null else str(x))
		t.text = "\n".join(items)
		t.scroll_fit_content_height = true
		t.custom_minimum_size.y = UiKit.TOUCH
		t.placeholder_text = "un élément par ligne"
		t.text_changed.connect(_mark_dirty)
		v.add_child(t)
		_generic[key] = {"control": t, "kind": "list"}
	else:
		var e := UiKit.line_edit("", _display(value))
		e.clear_button_enabled = false
		e.text_changed.connect(func(_t): _mark_dirty())
		v.add_child(e)
		_generic[key] = {"control": e, "kind": "scalar"}
	box.add_child(v)


func _add_backlinks() -> void:
	var back: Array = app.index.backlinks(note_name(), 60)
	var fold := FoldableContainer.new()
	fold.title = "Rétroliens (%d)" % back.size()
	fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # titre long : jamais plus large que l'écran
	fold.folded = back.size() > 12
	var inner := UiKit.vbox([], 6)
	fold.add_child(inner)
	for b in back:
		if b.path == rel:
			continue
		var p: String = b.path
		var btn := UiKit.button("%s   · %s" % [b.name, Schema.type_label(str(b.type))], func(): main.open_note(p))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		inner.add_child(btn)
	_side_col.add_child(fold)


# ------------------------------------------------------------------ note rapide

func _build_quick() -> void:
	var props: Dictionary = doc.properties()
	var done := str(props.get("statut", "")) == "traitee"
	_col.add_child(UiKit.card([UiKit.label(("Note rapide — traitée" if done else "Note rapide — à traiter"), true, 18),
		UiKit.muted("Écrivez librement. Plus tard, « Transformer » en fait une soirée, une fiche, une source… en reprenant ce texte.")],
		Color("9be3a8") if done else Color("e0b04a")))
	_body = TextEdit.new()
	_body.text = doc.body_for_edit()
	_body.placeholder_text = "Écrivez ici…"
	_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body.custom_minimum_size.y = 340
	_body.scroll_fit_content_height = true
	_body.editable = doc.utf8_ok
	_body.text_changed.connect(_mark_dirty)
	_col.add_child(_body)
	_col.add_child(UiKit.hbox([UiKit.button("Enregistrer", save), UiKit.button("+ Lien", _insert_link_body, "Insérer un lien vers une fiche")]))
	var g := UiKit.grid(2)
	g.add_child(UiKit.tile("Transformer…", "En soirée, personnage, source…", _transform, Color("9be3a8"), 72))
	if done:
		g.add_child(UiKit.tile("Remettre à traiter", "", func(): _set_quick_status("a_traiter"), Color("e0b04a"), 72))
	else:
		g.add_child(UiKit.tile("Marquer traitée", "Sans créer d'autre note", func(): _set_quick_status("traitee"), Color("e0b04a"), 72))
	_col.add_child(g)
	_add_typed("en_cours", "domaine", props, _col)
	var dev: Variant = props.get("devenue", [])
	var lst: Array = dev if typeof(dev) == TYPE_ARRAY else ([] if dev == null else [dev])
	if not lst.is_empty():
		_col.add_child(UiKit.heading("Notes créées à partir de celle-ci"))
		for x in lst:
			var n := Schema.link_name(x)
			_col.add_child(UiKit.button(n, func():
				var p: String = app.index.path_of_name(n) if app.index != null else ""
				if p != "":
					main.open_note(p)))


func _transform() -> void:
	if _dirty:
		save()
		if _dirty:
			return
	var props: Dictionary = doc.properties()
	main.transform_quick(rel, doc.body_for_edit(), {"date": props.get("date"), "domaine": props.get("domaine")})


func _set_quick_status(statut: String) -> void:
	if _dirty:
		save()
		if _dirty:
			return
	var err: String = doc.set_properties({"statut": statut})
	if err != "":
		_set_status("Non enregistré : " + err)
		return
	var r: Dictionary = app.save_note(rel, doc, hash)
	if r.ok:
		open(rel)
		_set_status("Note rapide marquée « %s » ✓" % ("traitée" if statut == "traitee" else "à traiter"))
	else:
		open(rel)
		_set_status("NON enregistré : " + str(r.error))


# ------------------------------------------------------------------ fiabilité calculée

func _apply_reliability(letter: String) -> void:
	if _dirty:
		save()
		if _dirty:
			return
	var r: Dictionary = app.set_note_properties(rel, {"fiabilite": letter})
	open(rel)
	_set_status(("Fiabilité comme informateur : %s ✓" % letter) if r.ok else "NON enregistré : " + str(r.get("error", "?")))


# ------------------------------------------------------------------ surveillance

func _tags() -> Array:
	var v: Variant = doc.properties().get("tags", [])
	if typeof(v) == TYPE_ARRAY:
		return v.duplicate()
	return [] if v == null or str(v) == "" else [v]


func _is_watched() -> bool:
	return _tags().any(func(t): return str(t).to_lower() == "surveille")


## Surveiller une personne : étiquette « surveille » dans la fiche (Obsidian la
## voit aussi). Les éléments déjà connus ne déclenchent pas d'alerte.
func _toggle_watch() -> void:
	if _dirty:
		save()
		if _dirty:
			return
	var watched := _is_watched()
	var tags := _tags().filter(func(t): return str(t).to_lower() != "surveille")
	if not watched:
		tags.append("surveille")
	var r: Dictionary = app.set_note_properties(rel, {"tags": tags if not tags.is_empty() else null})
	if r.ok:
		app.mark_seen(note_name())
	open(rel)
	_set_status(("Surveillée ✓ : une alerte signalera chaque nouvel élément." if not watched else "Plus surveillée.") if r.ok else "NON enregistré : " + str(r.get("error", "?")))


# ------------------------------------------------------------------ fusion, identifiants

func _merge() -> void:
	if _dirty:
		save()
		if _dirty:
			return
	var me := note_name()
	var t: String = doc.type_name()
	Picker.open_in(main, app, "« %s » est en fait…" % me, "notes", [t], func(v):
		var other := Schema.link_name(v)
		if other.to_lower() == me.to_lower():
			_set_status("Choisissez une autre fiche.")
			return
		FusionDialog.open_in(main, app, me, other, func(keep_rel: String):
			main.open_note(keep_rel)
			main.screens.note._set_status("Fusion faite ✓ — « %s » est reprise ici ; l'ancienne fiche est devenue un renvoi." % me)))


func _assign_ids() -> void:
	if _dirty:
		save()
		if _dirty:
			return
	var r: Dictionary = app.assign_missing_ids(rel)
	open(rel)
	_set_status(("Identifiants attribués : %d ✓" % int(r.added)) if r.ok else "NON enregistré : " + str(r.get("error", "?")))


# ------------------------------------------------------------------ éléments

func _build_element_form(t: String) -> void:
	_col.add_child(UiKit.heading("Ajouter un élément (enregistré aussitôt)"))
	_el_text = UiKit.line_edit("Ce que vous avez vu ou appris, avec les noms en [[liens]]")
	_col.add_child(UiKit.hbox([_el_text, UiKit.button("+ Lien", _insert_link_element, "Insérer un lien vers une fiche")]))
	var natures: Array = Schema.ENUMS["element.nature"]
	var labels := []
	for n in natures:
		labels.append(n[1])
	var def_nature := "observe" if t == "soiree" else "rapporte"
	var idx := 0
	for k in natures.size():
		if natures[k][0] == def_nature:
			idx = k
	_el_nature = UiKit.option_button(labels, idx)
	var cred_labels := []
	for c in Schema.CREDIBILITE:
		cred_labels.append(c[1])
	_el_cred = UiKit.option_button(cred_labels, int(Schema.CREDIBILITE_PAR_NATURE[def_nature]) - 1)
	_el_cred_touched = false
	_el_nature.item_selected.connect(func(i):
		if not _el_cred_touched:
			_el_cred.select(int(Schema.CREDIBILITE_PAR_NATURE[natures[i][0]]) - 1))
	_el_cred.item_selected.connect(func(_i): _el_cred_touched = true)
	_col.add_child(UiKit.vbox([UiKit.muted("Nature"), _el_nature], 3))
	_col.add_child(UiKit.vbox([UiKit.muted("Crédibilité de l'information (1–6)"), _el_cred], 3))
	var fold := FoldableContainer.new()
	fold.title = "Plus de détails : qui, quand, pouvoir, relation"
	fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # titre long : jamais plus large que l'écran
	fold.folded = true
	var inner := UiKit.vbox([], 8)
	fold.add_child(inner)
	for f in ["par", "date_faits", "discipline", "relation", "de", "vers", "qualificatif", "jusqu_au"]:
		var ed = FieldEditor.make(app, main, "element", f, null, false)
		_el_more[f] = ed
		inner.add_child(ed)
	inner.add_child(UiKit.muted("Une relation se renseigne en entier : relation, de et vers. Pour une reconnaissance, un sobriquet (tance) ou une nomination, choisissez la relation correspondante et écrivez le mot ou le poste dans « Qualificatif ». « Jusqu'au » : quand elle a une durée (« pour trois mois »)."))
	_col.add_child(fold)
	_col.add_child(UiKit.button("Ajouter l'élément", _add_element))


func _insert_link_element() -> void:
	Picker.open_in(main, app, "Insérer un lien", "notes", [], func(v):
		_el_text.insert_text_at_caret(v)
		_el_text.grab_focus())


func _insert_link_body() -> void:
	Picker.open_in(main, app, "Insérer un lien", "notes", [], func(v):
		_body.insert_text_at_caret(v)
		_body.grab_focus())


func _add_element() -> void:
	var t := _el_text.text.strip_edges().replace("\n", " ")
	if t == "":
		_set_status("Écrivez d'abord l'énoncé.")
		return
	var natures: Array = Schema.ENUMS["element.nature"]
	var line := "- %s [nature:: %s] [credibilite:: %d]" % [t, natures[_el_nature.selected][0], _el_cred.selected + 1]
	var par: Variant = _el_more.par.get_value()
	if par != null:
		line += " [par:: %s]" % str(par)
	var df: Variant = _el_more.date_faits.get_value()
	if df != null:
		line += " [date_faits:: %s]" % str(df)
	var relv: Variant = _el_more.relation.get_value()
	var de: Variant = _el_more.de.get_value()
	var vers: Variant = _el_more.vers.get_value()
	var n_rel := int(relv != null) + int(de != null) + int(vers != null)
	if n_rel > 0 and n_rel < 3:
		_set_status("Relation incomplète : renseignez relation, de et vers, ou aucun des trois.")
		return
	if n_rel == 3:
		line += " [relation:: %s] [de:: %s] [vers:: %s]" % [str(relv), str(de), str(vers)]
	var disc: Variant = _el_more.discipline.get_value()
	if disc != null:
		line += " [discipline:: %s]" % str(disc)
	var qual: Variant = _el_more.qualificatif.get_value()
	if qual != null:
		line += " [qualificatif:: %s]" % str(qual).replace("]", "").replace("[", "")
	var until: Variant = _el_more.jusqu_au.get_value()
	if until != null:
		line += " [jusqu_au:: %s]" % str(until)
	line += " ^" + Ids.generate("el")
	_body.text = StructuredLines.append_to_section(_body.text, "Éléments", line)
	_el_text.text = ""
	save()


# ------------------------------------------------------------------ enregistrement

func _display(v: Variant) -> String:
	if v == null:
		return ""
	if typeof(v) == TYPE_BOOL:
		return "true" if v else "false"
	return str(v)


func _convert(text: String, original: Variant) -> Variant:
	var t := text.strip_edges()
	if t == "":
		return null
	match typeof(original):
		TYPE_BOOL:
			if t.to_lower() in ["true", "false"]:
				return t.to_lower() == "true"
		TYPE_INT:
			if t.is_valid_int():
				return t.to_int()
		TYPE_FLOAT:
			if t.is_valid_float():
				return t.to_float()
	return t


func _collect_changes() -> Dictionary:
	var changes := {}
	for key in _typed:
		var ed = _typed[key]
		if ed.is_modified():
			changes[key] = ed.get_value()
	for key in _generic:
		var ed: Dictionary = _generic[key]
		var orig: Variant = _originals.get(key)
		if ed.kind == "list":
			var items := []
			for l in ed.control.text.split("\n"):
				if l.strip_edges() != "":
					items.append(l.strip_edges())
			var orig_list: Array = orig if typeof(orig) == TYPE_ARRAY else ([] if orig == null else [orig])
			var same := orig_list.size() == items.size()
			if same:
				for i in items.size():
					if str(orig_list[i]) != items[i]:
						same = false
			if not same:
				changes[key] = items
		else:
			var nv: Variant = _convert(ed.control.text, orig)
			if not (typeof(nv) == typeof(orig) and nv == orig):
				changes[key] = nv
	if _new_key != null and _new_key.text.strip_edges() != "":
		var k := _new_key.text.strip_edges()
		var v := _new_val.text.strip_edges()
		changes[k] = [v] if k in LIST_KEYS and v != "" else (v if v != "" else null)
	return changes


func _mark_dirty() -> void:
	if _building:
		return
	_dirty = true
	_set_status("Modifications non enregistrées")


func _set_status(t: String) -> void:
	_status.text = t


## Enregistre la note. Ordre : propriétés validées, texte, écriture sûre, index.
func save() -> void:
	if doc == null:
		return
	if not doc.utf8_ok:
		_set_status("Lecture seule : fichier non UTF-8.")
		return
	var changes := _collect_changes()
	if not changes.is_empty():
		if doc.fm.get("has_comments", false) and not _comments_ok:
			_ask("comments", "Cette note contient des commentaires YAML. Seules les propriétés modifiées seront réécrites ; un commentaire placé sur ces lignes-là serait perdu. Continuer ?")
			return
		for k in changes:
			if not (k in ["aliases", "tags", "cssclasses"] or RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(k)):
				_set_status("Nom de propriété invalide : « %s » (minuscules, chiffres, _)" % k)
				return
		var err: String = doc.set_properties(changes, HINTS)
		if err != "":
			_set_status("Non enregistré : " + err)
			return
	doc.set_body(_body.text)
	if not doc.is_dirty():
		_dirty = false
		_set_status("Aucune modification à enregistrer.")
		return
	var r: Dictionary = app.save_note(rel, doc, hash)
	if r.ok:
		var msg := "Enregistré ✓ (fichier relu et vérifié)"
		if not r.get("index_ok", true):
			msg += " — index à mettre à jour : relancez la synchronisation"
		open(rel)
		_set_status(msg)
	elif r.conflict:
		_ask("conflict", "Cette note a été modifiée ailleurs (GitSync, Obsidian…) depuis son ouverture. Rien n'a été écrasé.\n\nConserver votre version dans _Conflits/ et recharger la version du disque ?")
	else:
		_set_status("NON enregistré : " + str(r.error))


func _ask(kind: String, text: String, ok_text := "OK") -> void:
	_pending = kind
	UiKit.confirm(_confirm, text, ok_text)


## Suppression : la note part dans la corbeille du coffre (.trash/), jamais effacée.
func _ask_delete() -> void:
	if doc == null or rel == "":
		return
	var info: Dictionary = app.delete_info(rel)
	var t := "Mettre « %s » à la corbeille ?\n\nLa note part dans le dossier .trash du coffre, comme la corbeille d'Obsidian : elle disparaît de l'application et d'Obsidian, mais rien n'est effacé. Vous pourrez la restaurer depuis Réglages → Corbeille." % note_name()
	if int(info.count) > 0:
		var names := PackedStringArray()
		for b in (info.backlinks as Array).slice(0, 8):
			names.append(str(b.name))
		t += "\n\n%d note(s) la citent encore : %s%s Leurs liens deviendront des liens cassés (signalés dans le diagnostic) ; ils se réparent d'eux-mêmes si vous la restaurez." % [
			int(info.count), ", ".join(names), "…" if int(info.count) > 8 else "."]
	if _dirty:
		t += "\n\nVos modifications non enregistrées seront perdues."
	_ask("trash", t, "Mettre à la corbeille")


func _on_confirmed() -> void:
	match _pending:
		"comments":
			_comments_ok = true
			save()
		"trash":
			var name := note_name()
			var r: Dictionary = app.trash_note(rel, hash)
			if r.ok:
				doc = null
				rel = ""
				_dirty = false
				main.go_back()
				main._set_status("« %s » est dans la corbeille — Réglages → Corbeille pour la restaurer." % name)
			else:
				_set_status("NON supprimée : " + str(r.error))
		"conflict":
			var c: Dictionary = app.keep_conflict_copy(rel, doc)
			open(rel)
			_set_status("Votre version est dans _Conflits/ ; la version du disque est affichée." if c.ok else "Copie impossible : " + str(c.error))
	_pending = ""


func _reload() -> void:
	open(rel)
	_set_status("Rechargée depuis le disque.")


# ------------------------------------------------------------------ brouillons

func save_draft() -> void:
	if doc == null or not _dirty:
		return
	var typed := {}
	for key in _typed:
		if _typed[key].is_modified():
			typed[key] = _typed[key].get_value()
	var generic := {}
	for key in _generic:
		generic[key] = _generic[key].control.text
	app.save_draft(rel, {"base_hash": hash, "typed": var_to_str(typed), "props": generic, "body": _body.text})
	app._log("Brouillon conservé pour " + rel)


func _check_draft() -> void:
	var d: Dictionary = app.load_draft(rel)
	if d.is_empty():
		return
	var banner := UiKit.vbox([], 6)
	var same: bool = d.get("base_hash", "") == hash
	var restore := func() -> void:
		var typed: Variant = str_to_var(str(d.get("typed", "{}")))
		if typeof(typed) == TYPE_DICTIONARY:
			for key in typed:
				if _typed.has(key):
					_typed[key].set_value(typed[key])
		var props: Dictionary = d.get("props", {})
		for key in props:
			if _generic.has(key):
				_generic[key].control.text = props[key]
		_body.text = d.get("body", _body.text)
		_mark_dirty()
		banner.queue_free()
	var discard := func() -> void:
		app.clear_draft(rel)
		banner.queue_free()
	if same:
		banner.add_child(UiKit.label("Brouillon non enregistré du %s." % d.get("saved_at", "?")))
		banner.add_child(UiKit.hbox([UiKit.button("Restaurer", restore), UiKit.button("Ignorer", discard)]))
	else:
		banner.add_child(UiKit.label("Un brouillon existe, mais la note a changé depuis. Texte du brouillon ci-dessous, à recopier si besoin :"))
		var box := UiKit.report_box(120)
		box.text = d.get("body", "")
		banner.add_child(box)
		banner.add_child(UiKit.button("Supprimer ce brouillon", discard))
	_col.add_child(banner)
	_col.move_child(banner, 0)
