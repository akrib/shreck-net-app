extends VBoxContainer
## Écran « Enquête » : les outils de vue d'ensemble, calculés depuis l'index.
##  - Chronologie : notes datées et éléments ayant une date des faits, sur une
##    ligne verticale ; la date s'affiche au survol ;
##  - Alertes : échéances, faveurs en retard, sanctions, personnes surveillées ;
##  - Alibis : qui était où telle nuit, qui était là à plusieurs incidents, où était une personne ;
##  - Faveurs : qui doit quoi à qui ;
##  - Indices : par statut, avec les signaux de contradiction ;
##  - Dossiers : questions ouvertes ;
##  - Informateurs : fiabilité calculée d'après les affirmations confirmées ou réfutées ;
##  - À faire : tâches ouvertes de toutes les notes, par domaine, à cocher ici.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const Dates := preload("res://core/model/dates.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Picker := preload("res://ui/widgets/picker.gd")
const Timeline := preload("res://ui/widgets/timeline.gd")
const AlertList := preload("res://ui/widgets/alert_list.gd")
const AlibiView := preload("res://ui/widgets/alibi_view.gd")
const SortTable := preload("res://ui/widgets/sort_table.gd")
const FusionDialog := preload("res://ui/widgets/fusion_dialog.gd")
const Informants := preload("res://core/analysis/informants.gd")
const Contradictions := preload("res://core/analysis/contradictions.gd")

const TABS := [["alertes", "Alertes"], ["trancher", "À trancher"], ["chrono", "Chronologie"], ["alibis", "Alibis"], ["faveurs", "Faveurs"], ["indices", "Indices"],
	["dossiers", "Dossiers"], ["informateurs", "Informateurs"], ["taches", "À faire"]]
const MAX_ROWS := 300
## Ce que dit un onglet vide.
const EMPTY := {
	"indices": "Aucun indice pour l'instant. Un indice est une affirmation à évaluer (« X est l'infant de Y ») : on lui rattache les éléments pour et contre, et on lui donne un statut. Créez-en un avec « + Nouvelle note » → Indice.",
	"dossiers": "Aucun dossier d'enquête ouvert. Un dossier réunit une question (« Qui a incendié l'entrepôt ? »), ses hypothèses et ses indices. Créez-en un avec « + Nouvelle note » → Dossier d'enquête.",
	"taches": "Rien à faire : aucune case « - [ ] » non cochée dans vos notes.",
}

var app: Node
var main: Control
var tab := "chrono"
var _tab_buttons := {}
var _filters: VBoxContainer
var _list: VBoxContainer
var _info: Label
# filtres
var _domaine := ""
var _person := ""
var _text := ""
var _with_elements := true
var _all_faveurs := false
var _alibi_state := AlibiView.new_state()
var _timer: Timer
var _confirm: ConfirmationDialog
var _pending_fix := {}


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var bar := UiKit.flow(6)
	for t in TABS:
		var key: String = t[0]
		var b := UiKit.button(t[1], func(): show_tab(key))
		b.toggle_mode = true
		_tab_buttons[key] = b
		bar.add_child(b)
	add_child(bar)
	var tools := UiKit.flow(6)
	tools.add_child(UiKit.button("Graphe des relations", func(): main.show_graph(""), "Relations, faveurs, clans, coprésence"))
	tools.add_child(UiKit.button("Chemin entre deux fiches", func(): main.show_paths(), "Les liens les plus probables, selon l'échelle de l'Amirauté"))
	tools.add_child(UiKit.button("Préparer une séance", func(): main.show_screen("seance"), "Qui sera là, faveurs, questions, tâches"))
	tools.add_child(UiKit.button("Rapport de soirée", func(): main.show_report(), "Présents par préséance, informations, texte à publier"))
	tools.add_child(UiKit.button("Filiations", func(): main.show_lineage(), "Arbres des sires et des infants, clans et lignées"))
	tools.add_child(UiKit.button("Statistiques", func(): main.show_stats(), "Personnages et informations en camemberts : statuts, âges, villes, clans, échelle de l'Amirauté…"))
	tools.add_child(UiKit.button("Échanges avec Claude", func(): main.show_screen("echanges"), "Exporter des notes, importer un lot"))
	add_child(tools)
	_filters = UiKit.vbox([], 6)
	add_child(_filters)
	_info = UiKit.muted("")
	add_child(_info)
	_list = UiKit.vbox([], 6)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL  # un tableau peut prendre la hauteur restante
	add_child(UiKit.scroll(_list))
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.3
	_timer.timeout.connect(_refresh_list)
	add_child(_timer)


func on_show() -> void:
	show_tab(tab)


func on_job_finished(_job: String, _result: Dictionary) -> void:
	if is_inside_tree():
		_refresh_list()


## Onglet Alibis sur une vue donnée : « personne » (nom), « nuit » (date), « incidents » (chemin coché).
func open_alibis(mode: String, value := "") -> void:
	tab = "alibis"
	if mode == "":
		return
	_alibi_state.mode = mode
	match mode:
		"personne":
			_alibi_state.person = value
		"nuit":
			_alibi_state.day = value
		"incidents":
			if value != "" and not _alibi_state.sel.has(value):
				_alibi_state.sel.append(value)


func show_tab(key: String) -> void:
	tab = key
	for k in _tab_buttons:
		_tab_buttons[k].button_pressed = k == key
	_build_filters()
	_refresh_list()


# ------------------------------------------------------------------ filtres

func _build_filters() -> void:
	for c in _filters.get_children():
		c.queue_free()
	match tab:
		"chrono":
			_filters.add_child(UiKit.hbox([_domaine_filter(), _person_button()]))
			var txt := UiKit.line_edit("Filtrer par mot (nom, texte)…", _text)
			txt.text_changed.connect(_on_text)
			_filters.add_child(txt)
			var cb := CheckButton.new()
			cb.text = "Inclure les éléments ayant une date des faits"
			cb.button_pressed = _with_elements
			cb.custom_minimum_size.y = UiKit.TOUCH
			cb.toggled.connect(_on_with_elements)
			_filters.add_child(cb)
		"faveurs":
			var o := UiKit.option_button(["En cours", "Toutes les faveurs"], 1 if _all_faveurs else 0)
			o.item_selected.connect(_on_faveurs_scope)
			_filters.add_child(UiKit.hbox([o, _person_button()]))
		"taches":
			_filters.add_child(_domaine_filter())


func _domaine_filter() -> OptionButton:
	var names := ["Tous les domaines"]
	var codes := [""]
	if app.index != null:
		var doms: Array = app.index.find_notes("", ["domaine"], 200)
		doms.sort_custom(func(a, b): return str(a.name) < str(b.name))
		for d in doms:
			names.append(str(d.name))
			codes.append(str(d.name))
	var o := UiKit.option_button(names, maxi(0, codes.find(_domaine)))
	o.item_selected.connect(_on_domaine.bind(codes))
	return o


func _on_text(t: String) -> void:
	_text = t
	_timer.start()


func _on_with_elements(on: bool) -> void:
	_with_elements = on
	_refresh_list()


func _on_faveurs_scope(i: int) -> void:
	_all_faveurs = i == 1
	_refresh_list()


func _on_domaine(i: int, codes: Array) -> void:
	_domaine = codes[i]
	_refresh_list()


func _person_button() -> Button:
	var b := UiKit.button(("Personne : " + _person) if _person != "" else "Toutes les personnes", func():
		if _person != "":
			_person = ""
			_build_filters()
			_refresh_list()
		else:
			Picker.open_in(main, app, "Filtrer par personne", "notes", ["personnage", "groupe"], func(v):
				_person = Schema.link_name(v)
				_build_filters()
				_refresh_list()))
	b.tooltip_text = "Appuyez à nouveau pour retirer le filtre"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


# ------------------------------------------------------------------ listes

func _clear_list() -> void:
	for c in _list.get_children():
		c.queue_free()


func _row(text: String, path: String, accent := Color(0, 0, 0, 0)) -> Button:
	var b := UiKit.button(text, func(): main.open_note(path))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if accent.a > 0:
		b.add_theme_color_override("font_color", accent)
	_list.add_child(b)
	return b


func _group(title: String) -> void:
	var h := UiKit.label(title, true, 17)
	h.add_theme_color_override("font_color", Color("c8b6ff"))
	_list.add_child(h)


func _refresh_list() -> void:
	_clear_list()
	if app.index == null:
		_info.text = "Aucun coffre ouvert."
		return
	match tab:
		"alertes":
			_alertes()
		"trancher":
			_trancher()
		"informateurs":
			_informateurs()
		"alibis":
			_alibis()
		"chrono":
			_chrono()
		"faveurs":
			_faveurs()
		"indices":
			_indices()
		"dossiers":
			_dossiers()
		"taches":
			_taches()
	# onglet vide : dire à quoi il sert et comment le remplir
	if EMPTY.has(tab) and _list.get_children().all(func(c): return c.is_queued_for_deletion()):
		var hint := UiKit.label(EMPTY[tab], true, 16)
		hint.add_theme_color_override("font_color", Color("a59cb3"))
		hint.custom_minimum_size.x = 600
		_list.add_child(hint)


## À trancher : ce que vos notes disent de contradictoire (deux endroits la même
## nuit, deux sires, alliés et ennemis, poste tenu deux fois, faveur et mort,
## même personne ?) et ce qu'il faut réparer (bouton, après confirmation).
## « Écarter » vaut pour cet ordinateur.
func _trancher() -> void:
	var all: Array = app.contradictions()
	var hidden: int = app.dismissed_contradictions().size()
	_info.text = "%d point(s) à trancher. Calculé depuis vos notes : rien n'y est écrit sans vous. Corrigez la fiche, réparez, fusionnez ou écartez." % all.size()
	if all.is_empty():
		_list.add_child(UiKit.label("Rien à trancher : aucune contradiction trouvée dans vos notes." if hidden == 0 else "Rien à trancher (hors points écartés).", true, 16))
	var kind := ""
	for c in all:
		if c.kind != kind:
			kind = c.kind
			var n: int = all.filter(func(x): return x.kind == kind).size()
			var h := UiKit.label("%s (%d)" % [c.label, n], false, 17)
			h.add_theme_color_override("font_color", Color("c8b6ff"))
			_list.add_child(h)
		_list.add_child(_contradiction_card(c))
	if hidden > 0:
		_list.add_child(UiKit.hbox([UiKit.muted("%d point(s) écarté(s) sur cet ordinateur." % hidden),
			UiKit.button("Tout réafficher", func():
				app.restore_contradictions()
				_refresh_list())]))


const KIND_COLOR := {"reparer": Color("9be3a8"), "completer": Color("b79cff"), "deux_endroits": Color("ff7a6b"), "sire": Color("ff7a6b"), "relation": Color("e0b04a"),
	"poste": Color("e0b04a"), "faveur": Color("e0b04a"), "identite": Color("8fd3ff")}


func _contradiction_card(c: Dictionary) -> Control:
	var title := UiKit.label(str(c.title), true, 16)
	var lines := [title]
	for l in c.detail:
		lines.append(UiKit.muted(str(l)))
	var actions := UiKit.flow(6)
	for p in (c.paths as Array).slice(0, 6):
		var path: String = str(p)
		actions.add_child(UiKit.button(path.get_file().get_basename(), func(): main.open_note(path), "Ouvrir " + path))
	var who: Array = c.who
	match str(c.kind):
		"identite":
			actions.add_child(UiKit.button("Fusionner…", func():
				FusionDialog.open_in(main, app, str(who[0]), str(who[1]), func(keep_rel: String):
					main.open_note(keep_rel)), "Aperçu de la fusion, puis confirmation ; rien n'est supprimé"))
		"deux_endroits":
			actions.add_child(UiKit.button("Voir la nuit", func(): main.show_alibis("nuit", str(who[1])), "Enquête → Alibis, cette nuit-là"))
		"reparer", "completer":
			var fix: Dictionary = c.get("fix", {})
			if not fix.is_empty():
				var b := UiKit.button(str(fix.label), func(): _ask_fix(fix), "Réparer, après confirmation")
				b.add_theme_color_override("font_color", Color("9be3a8"))
				actions.add_child(b)
	var key := str(c.key)
	actions.add_child(UiKit.button("Écarter", func():
		app.dismiss_contradiction(key)
		_refresh_list(), "Ce n'est pas une contradiction : ne plus l'afficher (sur cet ordinateur)"))
	lines.append(actions)
	return UiKit.card(lines, KIND_COLOR.get(str(c.kind), Color("c8b6ff")))


## Réparation d'un point « À réparer » : confirmation, puis écriture vérifiée.
func _ask_fix(fix: Dictionary) -> void:
	if _confirm == null:
		_confirm = UiKit.confirm_dialog()
		_confirm.confirmed.connect(_do_fix)
		add_child(_confirm)
	_pending_fix = fix
	var t := ""
	match str(fix.action):
		"nature":
			t = "Passer %d groupe(s) en « %s » ?\n\nSeule la propriété « nature » de chaque note change (écriture vérifiée). Les membres déjà notés comptent aussitôt dans les filiations et les lignages." % [
				(fix.paths as Array).size(), Contradictions.NATURE_LABEL.get(str(fix.value), str(fix.value))]
		"chef":
			var lines := PackedStringArray()
			for x in (fix.pairs as Array).slice(0, 14):
				lines.append("%s : %s" % [str(x[0]).get_file().get_basename(), x[1]])
			t = "Renseigner le chef de %d lignée(s), d'après leur nom ?\n\n%s%s\n\nSeule la propriété « chef » de chaque fiche de lignée change. Un chef se retire ou se change sur la fiche de la lignée." % [
				(fix.pairs as Array).size(), "\n".join(lines), "\n…" if (fix.pairs as Array).size() > 14 else ""]
		"rename":
			t = "Renommer %d fichier(s) ?\n\nChaque note garde son dossier, son contenu et son identifiant : seul le nom du fichier retrouve ses accents. Les liens qui visent déjà le bon nom fonctionnent ensuite." % (fix.pairs as Array).size()
	UiKit.confirm(_confirm, t, "Réparer")


func _do_fix() -> void:
	var fix := _pending_fix
	_pending_fix = {}
	var r: Dictionary = {"done": [], "failed": []}
	match str(fix.get("action", "")):
		"nature":
			r = app.repair_group_natures(fix.paths, str(fix.value))
		"rename":
			r = app.repair_file_names(fix.pairs)
		"chef":
			r = app.set_lignee_chefs(fix.pairs)
	_refresh_list()
	var msg := "Réparé : %d." % (r.done as Array).size()
	if not (r.failed as Array).is_empty():
		msg += " Refusé : %d (%s)." % [(r.failed as Array).size(), " ; ".join(PackedStringArray((r.failed as Array).slice(0, 3)))]
	_info.text = msg + " " + _info.text


func _alertes() -> void:
	var al: Array = app.alerts()
	_info.text = "%d alerte(s) : urgentes d'abord. Échéances à 30 jours (et passées depuis moins de 30 jours), faveurs réclamées dont le délai est dépassé, sanctions en cours, nouveaux éléments sur les personnes surveillées." % al.size()
	if al.is_empty():
		_list.add_child(UiKit.label("Aucune alerte ✓"))
		return
	_list.add_child(AlertList.build(app, main, al, 0, _refresh_list))


## Alibis : présences calculées depuis les soirées, les événements et les
## éléments « était présent à » (voir ui/widgets/alibi_view.gd).
func _alibis() -> void:
	_info.text = "Où était chacun, d'après les présents des soirées, les participants des événements et les éléments « était présent à ». Rien n'est écrit dans vos notes."
	var v: Control = AlibiView.build(app, main, _alibi_state, _refresh_list)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(v)


## Fiabilité calculée des informateurs : la lettre proposée d'après leurs
## affirmations confirmées ou réfutées ; « Appliquer » l'écrit dans la fiche.
## Informateurs : en tête, ceux dont la lettre proposée diffère de la fiche (avec
## « Appliquer ») ; puis tous, dans un tableau triable.
func _informateurs() -> void:
	var all: Array = Informants.all(app.index)
	var todo: Array = all.filter(func(x): return x.proposed != x.current and x.proposed != "F")
	_info.text = "%d informateur(s), dont %d dont la lettre proposée diffère de la fiche. Une affirmation est tranchée par un indice ou un événement qui la cite, sinon par sa crédibilité 1 ou 5. Moins de 3 affirmations tranchées : F." % [all.size(), todo.size()]
	if not todo.is_empty():
		var card := UiKit.card([UiKit.label("À revoir : la lettre proposée diffère de la fiche (%d)" % todo.size(), true, 17)], Color("e0b04a"))
		var v: VBoxContainer = card.get_child(0)
		for x in todo:
			var cur := str(x.current) if str(x.current) != "" else "—"
			var path: String = x.path
			var b := UiKit.button("%s — proposée %s, actuelle %s · %s" % [x.name, x.proposed, cur, Informants.summary(x)], func():
				if path != "":
					main.open_note(path))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_color_override("font_color", Color("e0b04a"))
			var row := UiKit.hbox([b], 8)
			if path != "":
				var letter: String = x.proposed
				row.add_child(UiKit.button("Appliquer %s" % letter, func():
					var r: Dictionary = app.set_note_properties(path, {"fiabilite": letter})
					_refresh_list()
					_info.text = ("Fiabilité de %s : %s ✓" % [x.name, letter]) if r.ok else "NON enregistré : " + str(r.get("error", "?")), "Écrit la fiabilité dans la fiche"))
			v.add_child(row)
		_list.add_child(card)
	if all.is_empty():
		return
	var table := SortTable.new()
	table.setup([{"key": "name", "title": "Informateur", "ratio": 3.0}, {"key": "proposed", "title": "Proposée", "ratio": 0.8},
		{"key": "current", "title": "Actuelle", "ratio": 0.8}, {"key": "confirmed", "title": "Confirmées", "ratio": 1.0, "numeric": true},
		{"key": "refuted", "title": "Réfutées", "ratio": 1.0, "numeric": true}, {"key": "open", "title": "Non tranchées", "ratio": 1.0, "numeric": true}])
	var rows := []
	for x in all:
		var differs: bool = x.proposed != x.current and x.proposed != "F"
		rows.append({"path": str(x.path), "cells": {"name": str(x.name), "proposed": str(x.proposed),
			"current": str(x.current) if str(x.current) != "" else "—", "confirmed": str(x.confirmed),
			"refuted": str(x.refuted), "open": str(x.open)},
			"colors": {"proposed": Color("e0b04a")} if differs else {}})
	table.set_rows(rows)
	table.row_opened.connect(func(p): main.open_note(p))
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.custom_minimum_size.y = 320
	_list.add_child(table)


func _match_person(text: String) -> bool:
	return _person == "" or text.to_lower().contains(_person.to_lower())


func _chrono() -> void:
	var items := []
	var q := _text.strip_edges().to_lower()
	for n in app.index.dated_notes():
		if str(n.type) in ["domaine", "personnage", "groupe", "lieu", "objet", "concept"]:
			continue
		var d: Variant = n.date if n.date != null and str(n.date) != "" else n.date_floue
		if _domaine != "" and Schema.link_name(n.domaine).to_lower() != _domaine.to_lower():
			continue
		var nm := _strip_date(str(n.name))
		var tl_name := Schema.type_label(str(n.type))
		var label := tl_name if nm == "" or nm == tl_name else "%s · %s" % [tl_name, nm]
		if q != "" and not (label + " " + Dates.label(d)).to_lower().contains(q):
			continue
		if _person != "" and not _note_mentions(n.path, _person) and not str(n.name).to_lower().contains(_person.to_lower()):
			continue
		items.append([Dates.sort_key(d), label, n.path, false, str(d)])
	if _with_elements:
		# les faits d'une même source à une même date forment une seule entrée :
		# la source une fois, puis un fait par ligne ; les présences (« était
		# présent à ») sont réunies en une ligne par lieu
		var buckets := {}
		var order := []
		for e in app.index.elements_with_dates():
			var f: Variant = JSON.parse_string(str(e.fields))
			if typeof(f) != TYPE_DICTIONARY or str(f.get("date_faits", "")) == "":
				continue
			if _domaine != "" and Schema.link_name(e.domaine).to_lower() != _domaine.to_lower():
				continue
			var text := Schema.display_text(str(e.text))
			if q != "" and not (text + " " + str(e.note) + " " + Dates.label(f.date_faits)).to_lower().contains(q):
				continue
			if not _match_person(str(e.text)):
				continue
			var key := str(e.path) + "|" + str(f.date_faits)
			if not buckets.has(key):
				buckets[key] = {"path": str(e.path), "note": _strip_date(str(e.note)), "date": str(f.date_faits),
					"facts": [], "presences": {}, "creds": {}}
				order.append(key)
			var bk: Dictionary = buckets[key]
			bk.creds[str(e.cred)] = true
			if str(f.get("relation", "")) == "present_a" and str(f.get("de", "")) != "" and str(f.get("vers", "")) != "":
				var where := _strip_date(Schema.link_name(f.vers))
				if not bk.presences.has(where):
					bk.presences[where] = []
				bk.presences[where].append(Schema.link_name(f.de))
			else:
				bk.facts.append(_cut(text, 240))
		for key in order:
			var bk: Dictionary = buckets[key]
			var creds: Array = bk.creds.keys()
			creds.sort()
			var cred := "crédibilité %s" % "–".join(PackedStringArray([creds[0], creds[-1]] if creds.size() > 1 else creds))
			var lines := PackedStringArray()
			for t in bk.facts:
				lines.append("• " + t)
			for where in bk.presences:
				var names: Array = bk.presences[where]
				var shown := ", ".join(PackedStringArray(names.slice(0, 30)))
				if names.size() > 30:
					shown += ", … (+%d)" % (names.size() - 30)
				lines.append("• Présents à %s (%d) : %s" % [where, names.size(), shown])
			var n_facts: int = bk.facts.size() + bk.presences.size()
			var head := "Fait rapporté" if n_facts == 1 and bk.presences.is_empty() else "Faits rapportés"
			var label := "%s · %s (%s)\n%s" % [head, bk.note, cred, "\n".join(lines)]
			items.append([Dates.sort_key(bk.date), label, bk.path, true, bk.date])
	items.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	_info.text = "%d entrée(s), de la plus récente à la plus ancienne. Passez la souris sur une entrée pour voir sa date. Point plein : date exacte ; cercle : date approximative. Un trait sur la ligne marque le changement d'année." % items.size()
	var tl := Timeline.new()
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(tl)
	var last_year := "§"
	for it in items.slice(0, MAX_ROWS):
		var key: String = it[0]
		var year := key.substr(0, 4) if key != "" else ""
		var path: String = it[2]
		tl.add_entry(it[4], it[1], Color("f5e08a") if it[3] else Color(0, 0, 0, 0),
			func(): main.open_note(path), year != last_year and last_year != "§")
		last_year = year
	if items.size() > MAX_ROWS:
		_list.add_child(UiKit.muted("… %d entrées de plus : affinez les filtres." % (items.size() - MAX_ROWS)))


## Nom de note sans la date qui le commence (« 2026-10-12 Gazette… » -> « Gazette… ») :
## dans la chronologie, la date est portée par la ligne et s'affiche au survol.
static var _R_DATE_PREFIX := RegEx.create_from_string("^\\d{4}(-\\d{2}(-\\d{2})?)?(\\s+\\d{2}h\\d{2})?\\s+")


## Texte coupé à `n` caractères, à la fin d'un mot, avec « … ».
static func _cut(text: String, n: int) -> String:
	var t := text.strip_edges()
	if t.length() <= n:
		return t
	var cut := t.left(n)
	var sp := cut.rfind(" ")
	if sp > n / 2:
		cut = cut.left(sp)
	return cut.rstrip(" ,;:") + "…"


static func _strip_date(name: String) -> String:
	return _R_DATE_PREFIX.sub(name, "").strip_edges()


func _note_mentions(path: String, name: String) -> bool:
	for r in app.index.linked_from(name, ["presents", "presents_incertains", "absents", "participants", "sujets", "debiteur", "creancier", "auteur", "rapporteur", "de", "vers"]):
		if r.path == path:
			return true
	for b in app.index.backlinks(name, 400):
		if b.path == path:
			return true
	return false


## Faveurs : une ligne par couple « débiteur → créancier » (le bilan : combien,
## de quel niveau, la plus récente, ce qui cloche), dépliable en ses faveurs.
func _faveurs() -> void:
	var sanctions := {}
	for p in app.index.notes_with_props("personnage", ["sanctions"]):
		var s: Variant = p.props.get("sanctions", [])
		var lst: Array = s if typeof(s) == TYPE_ARRAY else ([] if s == null else [s])
		if lst.has("chasse_au_sang") or lst.has("parjure"):
			sanctions[str(p.name).to_lower()] = lst
	var levels: Array = Schema.ENUMS["faveur.niveau"].map(func(o): return o[0])
	var pairs := {}
	var by_level := {}
	var total := 0
	for n in app.index.notes_with_props("faveur", ["debiteur", "creancier", "niveau", "statut", "date", "date_floue", "enregistree"]):
		var pr: Dictionary = n.props
		var st := str(pr.get("statut", ""))
		if not _all_faveurs and not st in ["active", "reclamee", "suspendue"]:
			continue
		var deb := Schema.link_name(pr.get("debiteur", ""))
		var cre := Schema.link_name(pr.get("creancier", ""))
		if _person != "" and deb.to_lower() != _person.to_lower() and cre.to_lower() != _person.to_lower():
			continue
		var niv := str(pr.get("niveau", ""))
		by_level[niv] = by_level.get(niv, 0) + 1
		total += 1
		var key := deb + "\u0001" + cre
		if not pairs.has(key):
			pairs[key] = {"deb": deb, "cre": cre, "items": [], "best": -1, "last": "",
				"warn": sanctions.has(deb.to_lower()) or sanctions.has(cre.to_lower())}
		var pa: Dictionary = pairs[key]
		var d := str(pr.get("date", pr.get("date_floue", "")))
		pa.items.append({"path": str(n.path), "name": _strip_date(str(n.name)), "niv": niv, "st": st, "date": d,
			"libre": str(pr.get("enregistree", "")) != "true" and st in ["active", "reclamee"]})
		pa.best = maxi(pa.best, levels.find(niv))
		if Dates.sort_key(d) > Dates.sort_key(pa.last):
			pa.last = d
	var ordered: Array = pairs.values()
	ordered.sort_custom(func(a, b):
		if a.best != b.best:
			return a.best > b.best
		if a.items.size() != b.items.size():
			return a.items.size() > b.items.size()
		return TextNorm.fold(a.deb) < TextNorm.fold(b.deb))
	var parts := PackedStringArray()
	for o in Schema.ENUMS["faveur.niveau"]:
		if by_level.has(o[0]):
			parts.append(_count_label(by_level[o[0]], o[1]))
	_info.text = "%d faveur(s) entre %d couple(s)%s. Un couple qui a plusieurs faveurs se déplie d'un appui ; une faveur s'ouvre d'un appui." % [
		total, ordered.size(), (" : " + ", ".join(parts)) if not parts.is_empty() else ""]
	if ordered.is_empty():
		_list.add_child(UiKit.label("Aucune faveur %s." % ("connue" if _all_faveurs else "en cours")))
		return
	var tree := Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.column_titles_visible = true
	tree.add_theme_constant_override("item_margin", 22)
	tree.columns = 5
	var titles := [["Qui doit à qui", 3.0], ["Faveurs", 1.6], ["La plus récente", 1.2], ["État", 1.0], ["À noter", 2.0]]
	for i in titles.size():
		tree.set_column_title(i, titles[i][0])
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		tree.set_column_expand(i, true)
		tree.set_column_expand_ratio(i, titles[i][1])
		tree.set_column_clip_content(i, true)
	var root := tree.create_item()
	var muted := Color("a59cb3")
	var warn_c := Color("ffd27a")
	for pa in ordered:
		var it := tree.create_item(root)
		var items: Array = pa.items
		items.sort_custom(func(a, b): return Dates.sort_key(a.date) > Dates.sort_key(b.date))
		it.set_text(0, "%s  →  %s" % [pa.deb, pa.cre])
		var cnt := {}
		var sts := {}
		var libres := 0
		for x in items:
			cnt[x.niv] = cnt.get(x.niv, 0) + 1
			sts[x.st] = sts.get(x.st, 0) + 1
			if x.libre:
				libres += 1
		var cp := PackedStringArray()
		for i in range(levels.size() - 1, -1, -1):
			if cnt.has(levels[i]):
				cp.append(_count_label(cnt[levels[i]], Schema.option_label("faveur", "niveau", levels[i])))
		it.set_text(1, ", ".join(cp))
		it.set_text(2, Dates.label(pa.last) if pa.last != "" else "date inconnue")
		var sp := PackedStringArray()
		for k in sts:
			sp.append(_count_label(sts[k], Schema.option_label("faveur", "statut", k)) if sts.size() > 1 else Schema.option_label("faveur", "statut", k))
		it.set_text(3, ", ".join(sp))
		var notes := PackedStringArray()
		if pa.warn:
			notes.append("⚠ Chasse au Sang ou Parjure")
		if libres > 0:
			notes.append("non enregistrée" if items.size() == 1 else "%d non enregistrée(s)" % libres)
		it.set_text(4, " · ".join(notes))
		for c in range(1, 5):
			it.set_custom_color(c, muted)
		if pa.warn:
			it.set_custom_color(0, warn_c)
			it.set_custom_color(4, warn_c)
		it.set_tooltip_text(0, "%s doit %d faveur(s) à %s" % [pa.deb, items.size(), pa.cre])
		if items.size() == 1:
			it.set_metadata(0, items[0].path)
			continue
		it.collapsed = true
		for x in items:
			var ch := tree.create_item(it)
			ch.set_metadata(0, x.path)
			ch.set_text(0, x.name)
			ch.set_text(1, Schema.option_label("faveur", "niveau", x.niv))
			ch.set_text(2, Dates.label(x.date) if x.date != "" else "date inconnue")
			ch.set_text(3, Schema.option_label("faveur", "statut", x.st))
			ch.set_text(4, "non enregistrée" if x.libre else "")
			for c in range(5):
				ch.set_custom_color(c, muted)
	var act := func():
		var sel := tree.get_selected()
		if sel == null:
			return
		var p := str(sel.get_metadata(0)) if sel.get_metadata(0) != null else ""
		if p != "":
			main.open_note(p)
		else:
			sel.collapsed = not sel.collapsed
	tree.item_mouse_selected.connect(func(_pos, btn):
		if btn == MOUSE_BUTTON_LEFT:
			act.call())
	tree.item_activated.connect(act)
	# le tableau défile lui-même : il occupe la hauteur restante de l'écran
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 320
	_list.add_child(tree)


## « 3 majeures », « 1 de sang » : pluriel seulement pour un libellé d'un mot.
static func _count_label(n: int, label: String) -> String:
	var l := label.to_lower()
	return "%d %s%s" % [n, l, "s" if n > 1 and not l.contains(" ") else ""]


func _indices() -> void:
	var groups := {}
	var total := 0
	for n in app.index.notes_with_props("indice", ["statut", "credibilite", "pour", "contre"]):
		var pr: Dictionary = n.props
		var st := str(pr.get("statut", "non_verifie"))
		var pour: Array = _list_of(pr.get("pour"))
		var contre: Array = _list_of(pr.get("contre"))
		var notes := {}
		for x in pour:
			notes[Schema.link_name(x)] = true
		var flags := PackedStringArray()
		if st == "corrobore" and notes.size() < 2:
			flags.append("éléments pour venant d'une seule note")
		if not contre.is_empty() and st in ["non_verifie", "corrobore"]:
			flags.append("éléments contraires : « contesté » ?")
		if pour.is_empty():
			flags.append("aucun élément pour")
		var txt := "%s — crédibilité %s · %d pour, %d contre" % [n.name, str(pr.get("credibilite", "?")), pour.size(), contre.size()]
		if not flags.is_empty():
			txt += "\n⚠ " + " ; ".join(flags)
		if not groups.has(st):
			groups[st] = []
		groups[st].append([txt, n.path, not flags.is_empty()])
		total += 1
	_info.text = "%d indice(s). Les signaux ⚠ sont des suggestions : c'est vous qui posez le statut." % total
	for st in ["conteste", "non_verifie", "corrobore", "refute", "obsolete"]:
		if not groups.has(st):
			continue
		_group("%s (%d)" % [Schema.option_label("indice", "statut", st), groups[st].size()])
		for r in groups[st]:
			_row(r[0], r[1], Color("ffd27a") if r[2] else Color(0, 0, 0, 0))


func _list_of(v: Variant) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_ARRAY:
		return v
	return [] if str(v) == "" else [v]


func _dossiers() -> void:
	var tasks := {}
	for t in app.index.open_tasks(2000):
		tasks[t.path] = tasks.get(t.path, 0) + 1
	var rows := []
	for n in app.index.notes_with_props("dossier", ["statut", "priorite", "question", "indices"]):
		var pr: Dictionary = n.props
		var st := str(pr.get("statut", ""))
		var prio := str(pr.get("priorite", "moyenne"))
		var order: int = int({"haute": 0, "moyenne": 1, "basse": 2}.get(prio, 1)) + (0 if st in ["ouvert", ""] else 10)
		var nh: int = _list_of(pr.get("indices")).size()
		rows.append([order, "%s\n%s · priorité %s · %d tâche(s) ouverte(s) · %d hypothèse(s)" % [str(pr.get("question", n.name)),
			Schema.option_label("dossier", "statut", st), prio, tasks.get(n.path, 0), nh], n.path])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	_info.text = "%d dossier(s), les ouverts et prioritaires d'abord. « Hypothèses » : le tableau des hypothèses concurrentes du dossier." % rows.size()
	for r in rows:
		var b := _row(r[1], r[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var path: String = r[2]
		_list.remove_child(b)
		_list.add_child(UiKit.hbox([b, UiKit.button("Hypothèses", func(): main.show_hypotheses(path), "Tableau des hypothèses concurrentes")], 8))


func _taches() -> void:
	var groups := {}
	for t in app.index.open_tasks(1000):
		var dom := Schema.link_name(t.domaine)
		if _domaine != "" and dom.to_lower() != _domaine.to_lower():
			continue
		var g := dom if dom != "" else "Sans domaine"
		if not groups.has(g):
			groups[g] = []
		groups[g].append(t)
	var keys := groups.keys()
	keys.sort()
	var n := 0
	for g in keys:
		_group("%s (%d)" % [g, groups[g].size()])
		for t in groups[g]:
			n += 1
			var task: Dictionary = t
			var label := Schema.display_line(str(task.text))
			var cb := UiKit.button("Fait", func(): _toggle_task(task, true, null), "Marque la tâche faite dans la note (- [x])")
			cb.custom_minimum_size = Vector2(64, UiKit.TOUCH)
			var b := UiKit.button("%s\n— %s" % [label, task.name], func(): main.open_note(str(task.path)))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_list.add_child(UiKit.hbox([cb, b]))
	_info.text = "%d tâche(s) ouverte(s) (lignes « - [ ] » de vos notes). Cocher l'écrit dans la note." % n


func _toggle_task(task: Dictionary, on: bool, _cb: Variant = null) -> void:
	var r: Dictionary = app.set_task_done(str(task.path), int(task.line), str(task.text), on)
	if not r.ok:
		_info.text = "Non enregistré : " + str(r.get("error", "?"))
	else:
		_refresh_list.call_deferred()
		_info.set_deferred("text", "Tâche « %s » marquée %s ✓" % [str(task.text).left(40), "faite" if on else "à faire"])
