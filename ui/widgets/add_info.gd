extends PanelContainer
## Fenêtre des boutons « + » des fiches : ajoute une information à l'endroit où
## le format veut qu'elle soit écrite (FORMAT §1.3, « on écrit une fois ») :
##  - une information est un **élément** d'une soirée ou d'une source : par défaut
##    « Mes notes » du jour (créée au premier ajout), sinon la soirée ou la source
##    choisie. La fiche la retrouve ensuite par ses rétroliens ;
##  - ce qui est une propriété d'une fiche (le clan ou la secte d'un personnage)
##    s'écrit dans cette fiche-là.
## Rien n'est écrit avant « Ajouter » ; la ligne qui sera écrite est montrée.
##
## Genres (`spec.kind`) : membre, relation, statut, discipline, mention, presence
## (présence à une soirée), rattache (personnage rattaché à un domaine).
## Usage : AddInfo.open_in(main, app, {kind, subject, subject_type, group_nature}, func(msg): …)

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const Dates := preload("res://core/model/dates.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Picker := preload("res://ui/widgets/picker.gd")

## Natures de groupe dont l'appartenance est une propriété de la fiche du personnage.
## Une lignée n'en fait pas partie : on y appartient en plus de son clan, comme à
## une faction (élément « est membre de »).
const PROPERTY_NATURES := {"clan": "clan", "secte": "secte"}
const STATUT_KINDS := [["reconnait", "Reconnaissance (patronage)"], ["sobriquet", "Sobriquet (tance)"],
	["nomme", "Nomination à un poste"]]

## Dernière note choisie pour les ajouts, le temps de la session ("" = mes notes du jour).
static var last_dest := ""

var app: Node
var main: Control
var spec := {}
var on_added := Callable()

var _box: VBoxContainer
var _what: VBoxContainer
var _info_part: VBoxContainer
var _text: LineEdit
var _text_touched := false
var _auto_text := ""
var _setting := false
var _dest: OptionButton
var _dest_items: Array = []   ## [[chemin ("" = mes notes du jour), libellé]] ; « Autre… » vient après
var _dest_prev := 0
var _nature: OptionButton
var _cred: OptionButton
var _cred_touched := false
var _nature_touched := false
var _date: LineEdit
var _until: LineEdit
var _preview: Label
var _status: Label
var _go: Button
# choix propres à chaque genre
var _a := ""            # membre : le personnage ; relation : l'autre fiche ; statut : qui donne ; discipline : la discipline
var _a_btn: Button
var _role: OptionButton
var _rel_codes: Array = []
var _rel_opt: OptionButton
var _dir_opt: OptionButton
var _kind_opt: OptionButton
var _qual: LineEdit
var _also_title: CheckBox
var _how: OptionButton   ## présence : vue, incertaine, rapportée


static func open_in(p_main: Control, p_app: Node, p_spec: Dictionary, cb: Callable) -> Control:
	var d = load("res://ui/widgets/add_info.gd").new()
	d._setup(p_app, p_main, p_spec, cb)
	p_main.open_overlay(d)
	return d


func close() -> void:
	main.close_overlay(self)


func subject() -> String:
	return str(spec.get("subject", ""))


func kind() -> String:
	return str(spec.get("kind", "mention"))


## Mode « propriété » : l'ajout s'écrit dans une fiche, pas dans une source.
func property_mode() -> bool:
	if kind() == "membre":
		return PROPERTY_NATURES.has(str(spec.get("group_nature", "")))
	if kind() == "rattache":
		return true
	if kind() == "presence":
		return _how == null or _how.selected < 2
	return false


func _setup(p_app: Node, p_main: Control, p_spec: Dictionary, cb: Callable) -> void:
	app = p_app
	main = p_main
	spec = p_spec
	on_added = cb
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("16131a")
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	_box = UiKit.vbox([], 12)
	add_child(UiKit.scroll(_box, 900))
	var head := UiKit.hbox([])
	var t := UiKit.heading(_title())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiKit.button("Annuler", close))
	_box.add_child(head)
	_what = UiKit.vbox([], 8)
	_box.add_child(_what)
	_build_what()
	# l'information : énoncé, provenance, évaluation
	_info_part = UiKit.vbox([], 8)
	_box.add_child(_info_part)
	_info_part.add_child(UiKit.muted("Ce qui sera noté (une phrase ; les noms entre [[ ]] font le lien avec les fiches)"))
	_text = UiKit.line_edit("Ce que vous savez, avec les noms en [[liens]]")
	_text.text_changed.connect(func(_t):
		if not _setting:
			_text_touched = true
		_refresh())
	_info_part.add_child(UiKit.hbox([_text, UiKit.button("+ Lien", _insert_link, "Insérer un lien vers une fiche")]))
	_info_part.add_child(UiKit.muted("D'où le savez-vous ? L'information est écrite dans cette note, comme un élément."))
	_dest = UiKit.option_button([])
	_fill_dest()
	_dest.item_selected.connect(_on_dest)
	_info_part.add_child(_dest)
	var natures: Array = Schema.ENUMS["element.nature"]
	_nature = UiKit.option_button(natures.map(func(n): return n[1]))
	_nature.item_selected.connect(func(i):
		_nature_touched = true
		if not _cred_touched:
			_cred.select(int(Schema.CREDIBILITE_PAR_NATURE[natures[i][0]]) - 1)
		_refresh())
	_cred = UiKit.option_button(Schema.CREDIBILITE.map(func(c): return c[1]))
	_cred.item_selected.connect(func(_i):
		_cred_touched = true
		_refresh())
	_info_part.add_child(_side_by_side([[UiKit.muted("Nature"), _nature], [UiKit.muted("Crédibilité de l'information (1–6)"), _cred]]))
	_date = UiKit.line_edit("facultatif : 2026-10, 2026-10~ (vers), 2026-04~/.. (depuis)…")
	_date.text_changed.connect(func(_t): _refresh())
	_info_part.add_child(UiKit.vbox([UiKit.muted("Date des faits (si connue)"), _date], 3))
	for c in _info_part.get_children():
		(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_part.visible = not property_mode()
	_preview = UiKit.muted("")
	_box.add_child(_preview)
	_status = UiKit.warn("")
	_box.add_child(_status)
	_go = UiKit.button("Ajouter", _apply)
	_go.custom_minimum_size.x = 200
	_box.add_child(UiKit.hbox([_go, UiKit.button("Annuler", close)]))
	_on_dest(_dest.selected, true)
	_refresh()
	if kind() == "mention":
		_text.grab_focus.call_deferred()


## Colonnes de même largeur : [[libellé, contrôle], …].
static func _side_by_side(cols: Array) -> HBoxContainer:
	var h := UiKit.hbox([], 12)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in cols:
		var v := UiKit.vbox(c, 3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
	return h


func _title() -> String:
	if spec.has("title"):
		return str(spec.title)
	match kind():
		"membre":
			return "Ajouter un membre à « %s »" % subject()
		"relation":
			return "Ajouter une relation de « %s »" % subject()
		"statut":
			return "Reconnaissance, sobriquet ou poste de « %s »" % subject()
		"discipline":
			return "Discipline constatée chez « %s »" % subject()
		"presence":
			return "Présence de « %s » à une soirée" % subject()
		"rattache":
			return "Rattacher un personnage au domaine « %s »" % subject()
	return "Ajouter une information sur « %s »" % subject()


# ------------------------------------------------------------------ ce qu'on ajoute

func _pick_button(placeholder: String, title: String, types: Array, natures: Array = []) -> Button:
	var b := Button.new()
	b.text = placeholder
	b.custom_minimum_size.y = UiKit.TOUCH
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		Picker.open_in(main, app, title, "notes", types, func(v):
			_a = Schema.link_name(v)
			b.text = _a
			_refresh(), "", natures))
	return b


func _build_what() -> void:
	match kind():
		"membre":
			_what.add_child(UiKit.muted("Personnage"))
			_a_btn = _pick_button("Choisir le personnage…", "Membre de « %s »" % subject(), ["personnage"])
			_what.add_child(_a_btn)
			if not property_mode():
				_role = UiKit.option_button(["est membre de « %s »" % subject(), "dirige « %s »" % subject()])
				_role.item_selected.connect(func(_i): _refresh())
				_what.add_child(UiKit.vbox([UiKit.muted("Rôle"), _role], 3))
		"relation":
			for r in Schema.RELATIONS:
				if not str(r[0]) in ["present_a", "reconnait", "sobriquet", "nomme"]:
					_rel_codes.append(r)
			_rel_opt = UiKit.option_button(_rel_codes.map(func(r): return r[1]))
			_rel_opt.item_selected.connect(func(_i): _refresh())
			_dir_opt = UiKit.option_button(["« %s » … l'autre fiche" % subject(), "l'autre fiche … « %s »" % subject()])
			_dir_opt.item_selected.connect(func(_i): _refresh())
			_a_btn = _pick_button("Choisir l'autre fiche…", "Relation avec « %s »" % subject(), [])
			# relation et sens préréglés (« + Sire », « + Infant » des filiations)
			if spec.has("relation"):
				for i in _rel_codes.size():
					if str(_rel_codes[i][0]) == str(spec.relation):
						_rel_opt.select(i)
			if spec.has("dir"):
				_dir_opt.select(int(spec.dir))
			_what.add_child(_side_by_side([[UiKit.muted("Sens"), _dir_opt], [UiKit.muted("Relation"), _rel_opt]]))
			_what.add_child(UiKit.vbox([UiKit.muted("Autre fiche"), _a_btn], 3))
		"statut":
			_kind_opt = UiKit.option_button(STATUT_KINDS.map(func(k): return k[1]))
			_kind_opt.item_selected.connect(func(_i): _refresh())
			_a_btn = _pick_button("Choisir qui l'a donné…", "Donné à « %s » par…" % subject(), ["personnage"])
			_qual = UiKit.line_edit("le mot (« Courageux ») ou le poste (« Prévôt de Lyon »)")
			_qual.text_changed.connect(func(_t): _refresh())
			_until = UiKit.line_edit("facultatif : 2026-11-28, ou 2026-12")
			_until.text_changed.connect(func(_t): _refresh())
			_what.add_child(UiKit.vbox([UiKit.muted("Quoi"), _kind_opt], 3))
			_what.add_child(UiKit.vbox([UiKit.muted("Donné par"), _a_btn], 3))
			_what.add_child(UiKit.vbox([UiKit.muted("Mot ou poste"), _qual], 3))
			_what.add_child(UiKit.vbox([UiKit.muted("Jusqu'au (s'il a une durée)"), _until], 3))
			_also_title = CheckBox.new()
			_also_title.text = "Ajouter aussi ce poste à ses titres (fiche de « %s »)" % subject()
			_also_title.button_pressed = true
			_also_title.toggled.connect(func(_on): _refresh())
			_what.add_child(_also_title)
		"discipline":
			_a_btn = _pick_button("Choisir la discipline…", "Discipline constatée", ["concept"], ["discipline"])
			_what.add_child(UiKit.vbox([UiKit.muted("Discipline"), _a_btn], 3))
		"presence":
			_a_btn = _pick_button("Choisir la soirée…", "Soirée où était « %s »" % subject(), ["soiree"])
			_how = UiKit.option_button(["Je l'ai vu(e) : dans les présents de la soirée", "Je crois l'avoir vu(e) : dans les présents incertains de la soirée",
				"On me l'a rapporté : une information dans une source"])
			_how.item_selected.connect(func(_i): _refresh())
			_what.add_child(UiKit.vbox([UiKit.muted("Soirée"), _a_btn], 3))
			_what.add_child(UiKit.vbox([UiKit.muted("Comment le savez-vous ?"), _how], 3))
		"rattache":
			_a_btn = _pick_button("Choisir le personnage…", "Rattaché à « %s »" % subject(), ["personnage"])
			_what.add_child(UiKit.vbox([UiKit.muted("Personnage"), _a_btn], 3))


## {mode: "element"|"property", text, fields} ou {mode: "property", rel, changes, label}, avec `missing` si incomplet.
func _compute() -> Dictionary:
	var s := "[[%s]]" % subject()
	var a := "[[%s]]" % _a if _a != "" else ""
	match kind():
		"membre":
			if property_mode():
				var key: String = PROPERTY_NATURES[str(spec.group_nature)]
				return {"mode": "property", "key": key, "value": s, "missing": "Choisissez le personnage." if _a == "" else ""}
			var code := "dirige" if _role != null and _role.selected == 1 else "membre_de"
			return {"mode": "element", "missing": "Choisissez le personnage." if _a == "" else "",
				"text": ("%s %s %s." % [a, "dirige" if code == "dirige" else "est membre de", s]) if _a != "" else "",
				"fields": {"relation": code, "de": a, "vers": s}}
		"relation":
			var r: Array = _rel_codes[_rel_opt.selected]
			var de := s if _dir_opt.selected == 0 else a
			var vers := a if _dir_opt.selected == 0 else s
			return {"mode": "element", "missing": "Choisissez l'autre fiche." if _a == "" else "",
				"text": ("%s %s %s." % [de, str(r[1]).split(" (")[0], vers]) if _a != "" else "",
				"fields": {"relation": r[0], "de": de, "vers": vers}}
		"statut":
			var code: String = STATUT_KINDS[_kind_opt.selected][0]
			_also_title.visible = code == "nomme"
			var q := _qual.text.strip_edges().replace("[", "").replace("]", "")
			var miss := ""
			if _a == "":
				miss = "Choisissez qui l'a donné."
			elif q == "" and code == "nomme":
				miss = "Écrivez le poste."
			var txt := ""
			if _a != "":
				match code:
					"reconnait":
						txt = "%s reconnaît %s%s." % [a, s, (" « %s »" % q) if q != "" else ""]
					"sobriquet":
						txt = "%s affuble %s du sobriquet%s." % [a, s, (" « %s »" % q) if q != "" else ""]
					"nomme":
						txt = "%s nomme %s %s." % [a, s, q]
			return {"mode": "element", "missing": miss, "text": txt,
				"fields": {"relation": code, "de": a, "vers": s, "qualificatif": q, "jusqu_au": _until.text.strip_edges()}}
		"discipline":
			return {"mode": "element", "missing": "Choisissez la discipline." if _a == "" else "",
				"text": ("%s a fait usage de %s." % [s, a]) if _a != "" else "", "fields": {"discipline": a}}
		"presence":
			if property_mode():
				return {"mode": "property", "list": true, "target": _a, "key": "presents" if _how.selected == 0 else "presents_incertains",
					"value": s, "missing": "Choisissez la soirée." if _a == "" else ""}
			return {"mode": "element", "missing": "Choisissez la soirée." if _a == "" else "",
				"text": ("%s était présent à %s." % [s, a]) if _a != "" else "",
				"fields": {"relation": "present_a", "de": s, "vers": a}}
		"rattache":
			return {"mode": "property", "key": "domaine", "value": s, "missing": "Choisissez le personnage." if _a == "" else ""}
	return {"mode": "element", "missing": "", "text": s + " ", "fields": {}}


# ------------------------------------------------------------------ provenance

func _fill_dest() -> void:
	_dest_items = []
	var d: Dictionary = app.day_notes(false)
	_dest_items.append(["", "Mes notes du jour — « %s »%s" % [d.get("name", "Mes notes"),
		"" if str(d.get("rel", "")) != "" else " (créée au premier ajout)"]])
	if app.index != null:
		for r in app.index.list_by_type("soiree", 4, true):
			_dest_items.append([str(r.path), _dest_label(str(r.path))])
		var n := 0
		for r in app.index.recent_notes(60):
			if str(r.type) == "source" and str(r.path) != str(d.get("rel", "")) and n < 4 and not _has_dest(str(r.path)):
				_dest_items.append([str(r.path), _dest_label(str(r.path))])
				n += 1
		if last_dest != "" and not _has_dest(last_dest) and app.index.path_of_name(last_dest.get_file().get_basename()) == last_dest:
			_dest_items.append([last_dest, _dest_label(last_dest)])
	_render_dest(last_dest)


func _has_dest(p: String) -> bool:
	return _dest_items.any(func(it): return str(it[0]) == p)


static func _dest_label(p: String) -> String:
	var kind := "Soirée" if p.begins_with("Soirees/") else ("Source" if p.begins_with("Sources/") else "Note")
	return "%s · %s" % [kind, p.get_file().get_basename()]


func _render_dest(select: String) -> void:
	_dest.clear()
	for it in _dest_items:
		_dest.add_item(str(it[1]))
	_dest.add_item("Autre soirée ou source…")
	var at := 0
	for k in _dest_items.size():
		if str(_dest_items[k][0]) == select:
			at = k
	_dest.select(at)
	_dest_prev = at


func dest_path() -> String:
	var i := _dest.selected
	return "?" if i < 0 or i >= _dest_items.size() else str(_dest_items[i][0])


func _on_dest(i: int, initial := false) -> void:
	if i >= _dest_items.size():
		# « Autre soirée ou source… » : on garde le choix précédent tant que rien n'est choisi
		_dest.select(_dest_prev)
		Picker.open_in(main, app, "Où écrire l'information ?", "notes", ["soiree", "source"], func(v):
			var p: String = app.index.path_of_name(Schema.link_name(v))
			if p == "":
				return
			if not _has_dest(p):
				_dest_items.append([p, _dest_label(p)])
			_render_dest(p)
			_on_dest(_dest.selected))
		return
	_dest_prev = i
	# une soirée, c'est ce que vous avez vu ; une source, ce qu'on vous a dit
	if not _nature_touched:
		var nat := "observe" if dest_path().begins_with("Soirees/") else "rapporte"
		var natures: Array = Schema.ENUMS["element.nature"]
		for k in natures.size():
			if natures[k][0] == nat:
				_nature.select(k)
		if not _cred_touched:
			_cred.select(int(Schema.CREDIBILITE_PAR_NATURE[nat]) - 1)
	if not initial:
		_refresh()


func _insert_link() -> void:
	Picker.open_in(main, app, "Insérer un lien", "notes", [], func(v):
		_text.insert_text_at_caret(v)
		_text.grab_focus())


# ------------------------------------------------------------------ aperçu, écriture

func _element_fields(c: Dictionary) -> Dictionary:
	var natures: Array = Schema.ENUMS["element.nature"]
	var f := {"nature": natures[_nature.selected][0], "credibilite": _cred.selected + 1, "date_faits": _date.text.strip_edges()}
	f.merge(c.get("fields", {}), true)
	return f


func _refresh() -> void:
	var c := _compute()
	_info_part.visible = c.mode == "element"
	# l'énoncé proposé suit les choix tant qu'on ne l'a pas réécrit
	if c.mode == "element" and not _text_touched and _text.text == _auto_text:
		_setting = true
		_auto_text = str(c.get("text", ""))
		_text.text = _auto_text
		_text.caret_column = _text.text.length()
		_setting = false
	var problem := _problem(c)
	_status.text = problem
	_go.disabled = problem != ""
	if c.mode == "property":
		if _a == "":
			_preview.text = "Écrit dans la fiche choisie, propriété « %s »." % c.key
			return
		var p: String = app.index.path_of_name(_a)
		if c.get("list", false):
			_preview.text = "Écrit dans « %s », %s : ajout de %s" % [_a, c.key, c.value]
			if _already_listed(p, c):
				_preview.text = "« %s » le dit déjà (%s)." % [_a, c.key]
			return
		var cur := Schema.link_name(app.index.props_of(p).get(c.key, "")) if p != "" else ""
		_preview.text = "Écrit dans la fiche « %s » : %s: \"%s\"" % [_a, c.key, c.value]
		if cur != "" and TextNorm.fold(cur) != TextNorm.fold(subject()):
			_preview.text += "\nSa fiche dit aujourd'hui %s : %s. « Ajouter » le remplace." % [c.key, cur]
		elif cur != "":
			_preview.text = "La fiche « %s » le dit déjà." % _a
		return
	var where := "Mes notes du jour" if dest_path() == "" else dest_path().get_file().get_basename()
	_preview.text = "Écrit dans « %s », section Éléments :\n%s ^el-…" % [where, StructuredLines.element_line(_text.text, _element_fields(c))]
	var t := _title_to_add(c)
	if t != "":
		_preview.text += "\nEt dans la fiche « %s », titres : %s" % [subject(), t]


func _already_listed(p: String, c: Dictionary) -> bool:
	if p == "":
		return false
	for x in _as_list(app.index.props_of(p).get(c.key, [])):
		if TextNorm.fold(Schema.link_name(x)) == TextNorm.fold(subject()):
			return true
	return false


## Poste à ajouter aux `titres` de la fiche (nomination, case cochée, pas déjà présent), sinon "".
func _title_to_add(c: Dictionary) -> String:
	if kind() != "statut" or _also_title == null or not _also_title.button_pressed or not _also_title.visible:
		return ""
	var q := str(c.get("fields", {}).get("qualificatif", "")).strip_edges()
	if q == "":
		return ""
	var sp: String = app.index.path_of_name(subject()) if app.index != null else ""
	if sp == "":
		return ""
	for x in _as_list(app.index.props_of(sp).get("titres", [])):
		if TextNorm.fold(str(x)) == TextNorm.fold(q):
			return ""
	return q


static func _as_list(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return (v as Array).duplicate()
	return [] if str(v).strip_edges() == "" else [v]


func _problem(c: Dictionary) -> String:
	if str(c.get("missing", "")) != "":
		return str(c.missing)
	if c.mode == "property":
		return ""
	var t := _text.text.strip_edges()
	if t == "" or t == "[[%s]]" % subject():
		return "Écrivez ce que vous savez."
	if not TextNorm.fold(t).contains(TextNorm.fold("[[%s" % subject())):
		return "L'énoncé doit citer [[%s]] : c'est ce qui le relie à la fiche." % subject()
	var d := _date.text.strip_edges()
	if d != "" and not Dates.is_valid(d):
		return "Date des faits non conforme : 2026-10-14, 2026-10, 2026-10~, 2026-04~/.. …"
	if _until != null and _until.text.strip_edges() != "" and not Dates.is_valid(_until.text.strip_edges()):
		return "« Jusqu'au » non conforme : 2026-11-28 ou 2026-12."
	if dest_path() == "?":
		return "Choisissez la note où l'écrire."
	return ""


func _apply() -> void:
	var c := _compute()
	var problem := _problem(c)
	if problem != "":
		_status.text = problem
		return
	var msg := ""
	if c.mode == "property":
		var p: String = app.index.path_of_name(_a)
		if p == "":
			_status.text = "Fiche introuvable : « %s »." % _a
			return
		var value: Variant = c.value
		if c.get("list", false):
			if _already_listed(p, c):
				close()
				if on_added.is_valid():
					on_added.call("« %s » le disait déjà (%s)." % [_a, c.key])
				return
			value = _as_list(app.index.props_of(p).get(c.key, []))
			value.append(c.value)
		var r: Dictionary = app.set_note_properties(p, {c.key: value})
		if not r.ok:
			_status.text = "NON enregistré : " + str(r.get("error", "?"))
			return
		msg = ("« %s » : %s ajouté aux %s ✓" % [_a, subject(), str(c.key).replace("_", " ").replace("presents", "présents")]) if c.get("list", false) else ("« %s » : %s %s, écrit dans sa fiche ✓" % [_a, c.key, subject()])
	else:
		var line := StructuredLines.element_line(_text.text, _element_fields(c))
		var r: Dictionary = app.add_element_line(dest_path(), line)
		if not r.ok:
			_status.text = "NON enregistré : " + str(r.get("error", "?"))
			return
		last_dest = dest_path() if dest_path() != "" else ""
		msg = "Ajouté dans « %s »%s ✓" % [r.name, " (note créée)" if r.get("created", false) else ""]
		var t := _title_to_add(c)
		if t != "":
			var sp: String = app.index.path_of_name(subject())
			var titres := _as_list(app.index.props_of(sp).get("titres", []))
			titres.append(t)
			var r2: Dictionary = app.set_note_properties(sp, {"titres": titres})
			msg += (" ; « %s » ajouté à ses titres ✓" % t) if r2.ok else (" ; titres NON modifiés : " + str(r2.get("error", "?")))
	close()
	if on_added.is_valid():
		on_added.call(msg)
