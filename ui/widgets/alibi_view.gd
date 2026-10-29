extends RefCounted
## Enquête → Alibis : trois vues sur les présences (core/analysis/whereabouts.gd).
##  - Telle nuit : qui était où, lieu par lieu ; les personnes vues à deux endroits d'abord ;
##  - Incidents en commun : on coche des événements ou des soirées ; pour chaque
##    personne, sur place, vue ailleurs (alibi), absente, ou dans les parages ;
##  - Une personne : où elle était, sur la ligne de temps.
## L'état (vue, nuit, incidents cochés, personne) est gardé par l'écran Enquête.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const Dates := preload("res://core/model/dates.gd")
const TextNorm := preload("res://core/format/text_norm.gd")
const Where := preload("res://core/analysis/whereabouts.gd")
const Timeline := preload("res://ui/widgets/timeline.gd")
const Picker := preload("res://ui/widgets/picker.gd")

const C_OK := Color("7fd59b")
const C_AWAY := Color("8fd3ff")
const C_WARN := Color("e0b04a")
const C_BAD := Color("ff7a6b")
const C_MUTED := Color("a59cb3")
const FORCE := {3: "sûr", 2: "probable", 1: "douteux"}
const MODES := [["nuit", "Telle nuit"], ["incidents", "Incidents en commun"], ["personne", "Une personne"]]
const MAX_INCIDENTS := 300

static var _R_DATE := RegEx.create_from_string("^\\d{4}(-\\d{2}(-\\d{2})?)?(\\s+\\d{2}h\\d{2})?\\s+")


## État par défaut, gardé par l'écran Enquête.
static func new_state() -> Dictionary:
	return {"mode": "nuit", "day": "", "person": "", "sel": [], "q": ""}


static func build(app: Node, main: Control, state: Dictionary, refresh: Callable) -> Control:
	var col := UiKit.vbox([], 10)
	var bar := UiKit.hbox([], 6)
	for m in MODES:
		var key: String = m[0]
		var b := UiKit.button(m[1], func():
			state.mode = key
			refresh.call())
		b.toggle_mode = true
		b.button_pressed = str(state.get("mode", "nuit")) == key
		bar.add_child(b)
	col.add_child(bar)
	var all: Array = Where.facts(app.index)
	match str(state.get("mode", "nuit")):
		"incidents":
			_incidents(app, main, col, state, refresh, all)
		"personne":
			_person(app, main, col, state, refresh, all)
		_:
			_night(app, main, col, state, refresh, all)
	return col


## Nom sans la date qui le commence : la date est déjà donnée à côté.
static func short(name: String) -> String:
	var s := _R_DATE.sub(name, "").strip_edges()
	return s if s != "" else name


## « présent (constaté) », « présent selon Discord Valombre… » (nom de note sans sa date).
static func how_label(f: Dictionary) -> String:
	if str(f.how) == "rapporte" and str(f.note) != "":
		return "présent selon " + short(str(f.note))
	return Where.how_label(f)


static func how_text(f: Dictionary) -> String:
	var t := how_label(f)
	if str(f.how) == "absent":
		return t
	if f.cred != null and str(f.how) in ["rapporte", "indice"]:
		t += ", crédibilité %s" % str(f.cred)
	return "%s · %s" % [t, FORCE.get(int(f.force), "")]


static func _place_text(f: Dictionary) -> String:
	var bits := PackedStringArray()
	for x in [f.lieu, f.domaine]:
		if str(x) != "" and str(x) != str(f.where):
			bits.append(str(x))
	return short(str(f.where)) + (" (%s)" % ", ".join(bits) if not bits.is_empty() else "")


static func _btn(text: String, cb: Callable, color := Color(0, 0, 0, 0)) -> Button:
	var b := UiKit.button(text, cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if color.a > 0:
		b.add_theme_color_override("font_color", color)
	return b


static func _open(main: Control, path: String) -> Callable:
	return func():
		if path != "":
			main.open_note(path)


# ------------------------------------------------------------------ telle nuit

static func _night(app: Node, main: Control, col: VBoxContainer, state: Dictionary, refresh: Callable, all: Array) -> void:
	var ns: Array = Where.nights(app.index, all)
	var day := str(state.get("day", ""))
	if day == "" and not ns.is_empty():
		day = str(ns[0].day)
		state.day = day
	var row := UiKit.hbox([], 8)
	if not ns.is_empty():
		var items := []
		var codes := []
		for x in ns:
			items.append("%s — %d présence(s)" % [Dates.label(x.day), x.count])
			codes.append(str(x.day))
		if not codes.has(day):
			items.push_front("%s — aucune présence notée" % Dates.label(day))
			codes.push_front(day)
		var o := UiKit.option_button(items, maxi(0, codes.find(day)))
		o.tooltip_text = "Nuits pour lesquelles au moins une présence est datée au jour près"
		o.item_selected.connect(func(i):
			state.day = codes[i]
			refresh.call())
		row.add_child(o)
	var ed := UiKit.line_edit("AAAA-MM-JJ", day)
	ed.size_flags_horizontal = Control.SIZE_FILL
	ed.custom_minimum_size.x = 170
	var go := func():
		var t := ed.text.strip_edges()
		if Dates.is_day(t):
			state.day = t
			refresh.call()
	ed.text_submitted.connect(func(_t): go.call())
	row.add_child(ed)
	row.add_child(UiKit.button("Voir cette nuit", go, "Une date au jour près : 2026-10-14"))
	col.add_child(row)
	if day == "":
		col.add_child(UiKit.label("Aucune présence datée au jour près dans vos notes : renseignez les présents des soirées, ou la date des faits d'un élément « était présent à »."))
		return
	var n: Dictionary = Where.night(app.index, day, all)
	var conf: Array = n.people.filter(func(p): return p.conflict)
	col.add_child(UiKit.muted("Nuit du %s : %d lieu(x), %d personne(s), %d vue(s) à deux endroits. Une soirée datée d'un jour couvre la nuit qui suit. Les absences remarquées et les présences douteuses sont en gris." % [
		Dates.label(day), n.places.size(), n.people.size(), conf.size()]))
	if n.places.is_empty():
		col.add_child(UiKit.label("Aucune présence notée cette nuit-là."))
	if not conf.is_empty():
		var card := UiKit.card([UiKit.label("Vus à deux endroits cette nuit-là", true, 17)], C_BAD)
		var v: VBoxContainer = card.get_child(0)
		for p in conf:
			var where := PackedStringArray(p.facts.filter(func(f): return int(f.force) >= 2 or str(f.how) == "absent") \
				.map(func(f): return "%s — %s" % [_place_text(f), how_label(f)]))
			v.add_child(_btn("%s : %s" % [p.who, " ; ".join(where)], _open(main, str(p.who_path)), C_BAD))
		col.add_child(card)
	var conflicted := {}
	for p in conf:
		conflicted[TextNorm.name_key(str(p.who))] = true
	# un cadre par lieu (sur toute la largeur s'il n'y en a qu'un) ; dans chaque
	# cadre, les présences regroupées par source : la source une fois, puis les noms
	var g := UiKit.grid(clampi(n.places.size(), 1, 3), 12)
	for pl in n.places:
		var card := UiKit.card([], Color("c8b6ff"))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v: VBoxContainer = card.get_child(0)
		var tb := _btn("%s%s" % [short(str(pl.where)), "" if str(pl.where_type) == "" else " · " + Schema.type_label(str(pl.where_type)).to_lower()],
			_open(main, str(pl.where_path)))
		tb.add_theme_font_size_override("font_size", 17)
		v.add_child(tb)
		var bits := PackedStringArray()
		for x in [pl.lieu, pl.domaine]:
			if str(x) != "" and str(x) != str(pl.where):
				bits.append(str(x))
		if not bits.is_empty():
			v.add_child(UiKit.muted(", ".join(bits)))
		var groups := {}
		for f in pl.facts:
			var k := how_text(f)
			if not groups.has(k):
				groups[k] = []
			groups[k].append(f)
		for k in groups:
			var lst: Array = groups[k]
			var head := UiKit.label("%s — %d" % [k[0].to_upper() + k.substr(1), lst.size()], true, 14)
			head.add_theme_color_override("font_color", C_MUTED)
			head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var hrow := UiKit.hbox([head], 6)
			var src := str(lst[0].path)
			if str(lst[0].how) == "rapporte" and src != "" and lst.all(func(f): return str(f.path) == src):
				var sb := UiKit.button("Lire la source", _open(main, src), str(lst[0].note))
				sb.custom_minimum_size.y = 32
				hrow.add_child(sb)
			v.add_child(hrow)
			var fl := UiKit.flow(6)
			for f in lst:
				var color := Color(0, 0, 0, 0)
				if conflicted.has(str(f.who_key)) and (int(f.force) >= 2 or str(f.how) == "absent"):
					color = C_BAD
				elif str(f.how) == "absent" or int(f.force) <= 1:
					color = C_MUTED
				var path: String = str(f.who_path) if str(f.who_path) != "" else str(f.path)
				var b := UiKit.button(str(f.who), _open(main, path), "%s — %s (d'après %s)" % [f.who, how_text(f), f.note])
				b.custom_minimum_size.y = 36
				if color.a > 0:
					b.add_theme_color_override("font_color", color)
				fl.add_child(b)
			v.add_child(fl)
		g.add_child(card)
	col.add_child(g)
	if not n.approx.is_empty():
		col.add_child(UiKit.label("À une date approximative qui inclut ce jour (à titre indicatif)", true, 16))
		for f in n.approx.slice(0, 40):
			col.add_child(_btn("%s — %s, %s (%s)" % [f.who, _place_text(f), how_label(f), Dates.label(f.date)],
				_open(main, str(f.path)), C_MUTED))


# ------------------------------------------------------------------ incidents en commun

static func _incidents(app: Node, main: Control, col: VBoxContainer, state: Dictionary, refresh: Callable, all: Array) -> void:
	var incs: Array = Where.incidents(app.index)
	var sel: Array = state.get("sel", [])
	var left := UiKit.vbox([], 4)
	left.custom_minimum_size.x = 430
	var search := UiKit.line_edit("Chercher un incident (nom, date, lieu)…", str(state.get("q", "")))
	left.add_child(search)
	var count := UiKit.muted("%d incident(s) coché(s) sur %d" % [sel.size(), incs.size()])
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UiKit.hbox([count], 8)
	if not sel.is_empty():
		var clear := UiKit.button("Tout décocher", func():
			state.sel = []
			refresh.call())
		head.add_child(clear)
	left.add_child(head)
	var lst := UiKit.vbox([], 0)
	left.add_child(lst)
	var shown := 0
	# les incidents cochés d'abord, puis les autres du plus récent au plus ancien
	var ordered: Array = incs.filter(func(i): return sel.has(str(i.path))) + incs.filter(func(i): return not sel.has(str(i.path)))
	for inc in ordered:
		if shown >= MAX_INCIDENTS:
			break
		shown += 1
		var path: String = str(inc.path)
		var cb := CheckBox.new()
		cb.text = "%s · %s%s" % [Dates.label(inc.date) if str(inc.date) != "" else "date inconnue", short(str(inc.name)),
			(" · " + str(inc.lieu)) if str(inc.lieu) != "" else ""]
		cb.tooltip_text = "%s — %s%s" % [inc.name, Schema.type_label(str(inc.type)), (", " + str(inc.domaine)) if str(inc.domaine) != "" else ""]
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.custom_minimum_size = Vector2(380, 34)
		cb.button_pressed = sel.has(path)
		cb.set_meta("search", TextNorm.fold(cb.text + " " + str(inc.name) + " " + str(inc.domaine)))
		cb.toggled.connect(func(on: bool):
			var s: Array = state.get("sel", [])
			if on and not s.has(path):
				s.append(path)
			elif not on:
				s.erase(path)
			state.sel = s
			refresh.call())
		lst.add_child(cb)
	var apply_filter := func(t: String):
		state.q = t
		var q := TextNorm.fold(t.strip_edges())
		for c in lst.get_children():
			c.visible = q == "" or str(c.get_meta("search", "")).contains(q) or (c as CheckBox).button_pressed
	search.text_changed.connect(apply_filter)
	apply_filter.call(str(state.get("q", "")))
	var right := UiKit.vbox([], 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiKit.hbox([left, VSeparator.new(), right], 16))
	if sel.is_empty():
		right.add_child(UiKit.label("Cochez à gauche les incidents à comparer : des événements ou des soirées. Pour chacun, on voit qui était sur place, qui a été vu ailleurs la même nuit (un alibi), et qui était dans les parages."))
		right.add_child(UiKit.muted("Sur place : présent à l'incident lui-même, ou à son lieu le même jour. Vu ailleurs : présence au moins probable, la même nuit, à un autre lieu ou dans un autre domaine. Date compatible : à son lieu, à une date approximative qui recouvre celle de l'incident. Dans le domaine : même nuit, même domaine, lieu inconnu."))
		return
	var c: Dictionary = Where.common(app.index, sel, all)
	var n: int = c.incidents.size()
	var alls: Array = c.people.filter(func(p): return p.all)
	if n >= 2:
		if alls.is_empty():
			right.add_child(UiKit.label("Personne n'est noté sur place à tous les incidents choisis.", true, 17))
		else:
			var l := UiKit.label("Sur place à tous les incidents choisis : %s" % ", ".join(PackedStringArray(alls.map(func(p): return str(p.who)))), true, 17)
			l.add_theme_color_override("font_color", C_WARN)
			right.add_child(l)
	right.add_child(UiKit.muted("%d personne(s) sur place ou dans les parages d'au moins un incident ; celles qui ont été vues ailleurs à tous ne sont pas listées. Survolez une case pour voir d'où vient l'information." % c.people.size()))
	var g := GridContainer.new()
	g.columns = n + 1
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	right.add_child(g)
	var w := clampf(1180.0 / float(n + 1), 120.0, 260.0)
	var corner := UiKit.label("Personne", true, 15)
	corner.custom_minimum_size.x = w
	g.add_child(corner)
	for inc in c.incidents:
		var hb := _btn("%s\n%s" % [short(str(inc.name)), Dates.label(inc.date) if str(inc.date) != "" else "date inconnue"], _open(main, str(inc.path)))
		hb.custom_minimum_size.x = w
		hb.add_theme_color_override("font_color", Color("c8b6ff"))
		g.add_child(hb)
	for p in c.people.slice(0, 200):
		var pb := _btn("%s\n%d / %d sur place" % [p.who, p.count, n], _open(main, str(p.who_path)), C_WARN if p.all and n >= 2 else Color(0, 0, 0, 0))
		pb.custom_minimum_size.x = w
		g.add_child(pb)
		for st in p.at:
			g.add_child(_cell(st, w))


static func _cell(st: Dictionary, w: float) -> Label:
	var txt := ""
	var color := C_MUTED
	match str(st.kind):
		"sur_place":
			txt = "● sur place · %s" % FORCE.get(int(st.force), "")
			color = C_OK if int(st.force) >= 2 else C_WARN
			if st.contradiction:
				txt += "\n⚠ mais vu ailleurs"
				color = C_BAD
		"alibi":
			txt = "✗ vu ailleurs\n" + short(str(st.facts[0].where))
			color = C_AWAY
		"absent":
			txt = "✗ absence remarquée"
			color = C_AWAY
		"compatible":
			txt = "≈ au même lieu, date compatible"
			color = C_WARN
		"parages":
			txt = "· dans le domaine ce soir-là"
			color = C_WARN
		_:
			txt = "—"
	var l := UiKit.label(txt, true, 14)
	l.custom_minimum_size.x = w
	l.add_theme_color_override("font_color", color)
	var tips := PackedStringArray()
	for f in st.facts:
		tips.append("%s — %s, %s (d'après %s)" % [_place_text(f), how_text(f), Dates.label(f.date), f.note])
	for f in st.get("other", []):
		tips.append("mais aussi : %s — %s, %s (d'après %s)" % [_place_text(f), how_text(f), Dates.label(f.date), f.note])
	l.tooltip_text = "\n".join(tips) if not tips.is_empty() else "Rien de connu sur cette personne pour cet incident."
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


# ------------------------------------------------------------------ une personne

static func _person(app: Node, main: Control, col: VBoxContainer, state: Dictionary, refresh: Callable, all: Array) -> void:
	var name := str(state.get("person", ""))
	var pick := UiKit.button(("Personne : %s (changer)" % name) if name != "" else "Choisir une personne…", func():
		Picker.open_in(main, app, "Où était… ?", "notes", ["personnage"], func(v):
			state.person = Schema.link_name(v)
			refresh.call()))
	var row := UiKit.hbox([pick], 8)
	col.add_child(row)
	if name == "":
		col.add_child(UiKit.label("Choisissez une personne : ses présences connues s'affichent sur la ligne de temps, avec les nuits où elle est notée à deux endroits."))
		return
	var path: String = app.index.path_of_name(name)
	if path != "":
		row.add_child(UiKit.button("Ouvrir la fiche", _open(main, path)))
	var list: Array = Where.of_person(app.index, name, all)
	var conf: Dictionary = Where.conflicts(list)
	col.add_child(UiKit.muted("%d présence(s) connue(s) ; %d nuit(s) où %s est noté(e) à deux endroits (en rouge). Absences remarquées et présences douteuses en gris. Passez la souris sur une entrée pour voir sa date." % [
		list.size(), conf.size(), name]))
	if list.is_empty():
		col.add_child(UiKit.label("Aucune présence connue : ni dans les présents d'une soirée, ni comme participant d'un événement, ni dans un élément « était présent à »."))
		return
	col.add_child(timeline(main, list, conf, false))


## Ligne de temps des présences d'une personne (aussi sur sa fiche, en version compacte).
## Suppression ciblée d'une présence (bouton × des fiches) : le présent dans la
## soirée, le participant d'un événement, la ligne « était présent à », ou l'indice.
static func removal_of(f: Dictionary) -> Dictionary:
	match str(f.how):
		"present":
			return {"kind": "prop", "rel": str(f.path), "key": "presents", "target": str(f.who)}
		"incertain":
			return {"kind": "prop", "rel": str(f.path), "key": "presents_incertains", "target": str(f.who)}
		"absent":
			return {"kind": "prop", "rel": str(f.path), "key": "absents", "target": str(f.who)}
		"participant":
			return {"kind": "prop", "rel": str(f.path), "key": "participants", "target": str(f.who)}
		"rapporte":
			return {"kind": "element", "rel": str(f.path), "block": str(f.block), "text": str(f.text)}
		"indice":
			return {"kind": "note", "rel": str(f.path)}
	return {}


static func _x_button(cb: Callable) -> Button:
	var x := Button.new()
	x.text = "×"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.tooltip_text = "Supprimer seulement ceci (après confirmation)"
	x.custom_minimum_size = Vector2(40, 40)
	x.add_theme_color_override("font_color", Color("ff9b8a"))
	x.add_theme_font_size_override("font_size", 20)
	x.pressed.connect(cb)
	return x


static func timeline(main: Control, list: Array, conf: Dictionary, compact: bool, limit := 300, on_remove := Callable()) -> Control:
	var tl := Timeline.new()
	tl.compact = compact
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var last_year := "§"
	for f in list.slice(0, limit):
		var year := str(f.first).substr(0, 4) if str(f.first) != "" else ""
		var color := Color(0, 0, 0, 0)
		if f.exact and conf.has(str(f.first)) and (int(f.force) >= 2 or str(f.how) == "absent"):
			color = C_BAD
		elif str(f.how) == "absent" or int(f.force) <= 1:
			color = C_MUTED
		var txt := "%s\n%s" % [_place_text(f), how_text(f)]
		if str(f.note) != str(f.where) and not str(f.how) in ["rapporte"]:
			txt += " — d'après " + short(str(f.note))
		var x: Control = null
		if on_remove.is_valid():
			var spec := removal_of(f)
			if not spec.is_empty():
				x = _x_button(func(): on_remove.call(spec))
		tl.add_entry(str(f.date), txt, color, _open(main, str(f.path)), year != last_year and last_year != "§", x)
		last_year = year
	return tl
