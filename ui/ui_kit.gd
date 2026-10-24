extends RefCounted
## Petits constructeurs de contrôles, avec des cibles tactiles confortables.

const TOUCH := 44.0


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("16131a")
	t.set_stylebox("panel", "PanelContainer", bg)
	var nav := StyleBoxFlat.new()
	nav.bg_color = Color("221d29")
	t.set_stylebox("panel", "Panel", nav)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color("2d2636"), "hover": Color("3a3146"), "pressed": Color("4b3f5c"),
			"focus": Color("2d2636"), "disabled": Color("231e2a")}[state]
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		if state == "focus":
			sb.draw_center = false
			sb.border_color = Color("c8b6ff")
			sb.set_border_width_all(2)
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Label", Color("e8e2f0"))
	t.set_color("font_color", "Button", Color("e8e2f0"))
	# Listes déroulantes : éléments plus hauts, faciles à toucher sur téléphone.
	t.set_constant("v_separation", "PopupMenu", 18)
	t.set_font_size("font_size", "PopupMenu", 18)
	t.set_constant("item_start_padding", "PopupMenu", 12)
	t.set_constant("item_end_padding", "PopupMenu", 12)
	# menus et listes déroulantes aux couleurs de l'application (et non le gris par défaut)
	var pop := StyleBoxFlat.new()
	pop.bg_color = Color("2d2636")
	pop.border_color = Color("4b3f5c")
	pop.set_border_width_all(1)
	pop.set_corner_radius_all(6)
	pop.set_content_margin_all(4)
	t.set_stylebox("panel", "PopupMenu", pop)
	var pop_hover := StyleBoxFlat.new()
	pop_hover.bg_color = Color("4b3f5c")
	pop_hover.set_corner_radius_all(4)
	t.set_stylebox("hover", "PopupMenu", pop_hover)
	t.set_color("font_color", "PopupMenu", Color("e8e2f0"))
	t.set_color("font_hover_color", "PopupMenu", Color("ffffff"))
	t.set_font_size("font_size", "FoldableContainer", 17)
	# Tableaux (liste des fiches) : lignes aérées, titres de colonne cliquables.
	var tree_bg := StyleBoxFlat.new()
	tree_bg.bg_color = Color("1b1720")
	tree_bg.set_corner_radius_all(6)
	tree_bg.set_content_margin_all(4)
	t.set_stylebox("panel", "Tree", tree_bg)
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color("3a3146")
	t.set_stylebox("selected", "Tree", sel)
	t.set_stylebox("selected_focus", "Tree", sel)
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color("2d2636")
	t.set_stylebox("hovered", "Tree", hov)
	for st in ["title_button_normal", "title_button_hover", "title_button_pressed"]:
		var tb := StyleBoxFlat.new()
		tb.bg_color = Color("2d2636") if st == "title_button_normal" else Color("3a3146")
		tb.content_margin_left = 10
		tb.content_margin_top = 8
		tb.content_margin_bottom = 8
		t.set_stylebox(st, "Tree", tb)
	t.set_color("title_button_color", "Tree", Color("c8b6ff"))
	t.set_color("font_color", "Tree", Color("e8e2f0"))
	t.set_color("font_selected_color", "Tree", Color("ffffff"))
	t.set_constant("v_separation", "Tree", 8)
	t.set_constant("inner_item_margin_left", "Tree", 10)
	t.set_constant("item_margin", "Tree", 0)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_constant("draw_guides", "Tree", 0)
	# boîtes de dialogue aux couleurs de l'application (et non le gris par défaut)
	var dlg := StyleBoxFlat.new()
	dlg.bg_color = Color("221d29")
	dlg.set_content_margin_all(16)
	t.set_stylebox("panel", "AcceptDialog", dlg)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("2d2636")
	frame.border_color = Color("4b3f5c")
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(8)
	frame.expand_margin_left = 8
	frame.expand_margin_right = 8
	frame.expand_margin_bottom = 8
	frame.expand_margin_top = 34
	t.set_stylebox("embedded_border", "Window", frame)
	t.set_stylebox("embedded_unfocused_border", "Window", frame)
	t.set_color("title_color", "Window", Color("e8e2f0"))
	return t


static func button(text: String, cb: Callable, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = TOUCH
	b.tooltip_text = tooltip
	b.pressed.connect(cb)
	return b


static func label(text: String, wrap := true, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 100
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


static func heading(text: String) -> Label:
	var l := label(text, false, 20)  # un titre ne se coupe pas au milieu d'un mot
	l.add_theme_color_override("font_color", Color("c8b6ff"))
	return l


static func muted(text: String) -> Label:
	var l := label(text, true, 13)
	l.add_theme_color_override("font_color", Color("a59cb3"))
	return l


static func line_edit(placeholder := "", text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size.y = TOUCH
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.clear_button_enabled = true
	return e


static func hbox(children: Array = [], sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


static func vbox(children: Array = [], sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for c in children:
		v.add_child(c)
	return v


## Zone de texte en lecture seule, sélectionnable et copiable.
static func report_box(min_height := 240.0) -> TextEdit:
	var t := TextEdit.new()
	t.editable = false
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.custom_minimum_size.y = min_height
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return t


## Colonne de lecture : largeur limitée et centrée (plein écran).
static func readable(content: Control, max_width := 1100.0) -> Container:
	var r = load("res://ui/widgets/readable.gd").new()
	r.max_width = max_width
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(content)
	return r


## Défilement vertical d'une colonne ; `max_width` > 0 : colonne de lecture centrée.
static func scroll(content: Control, max_width := 0.0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if max_width > 0.0:
		content = readable(content, max_width)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func check_mark(okv: Variant) -> String:
	return "✓" if okv == true else "✗"


## Grande tuile tactile (choix du type, accueil) : titre + sous-titre, bord coloré.
static func tile(title: String, subtitle: String, cb: Callable, accent := Color("c8b6ff"), min_h := 84.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(140, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = subtitle
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color("2d2636"), "hover": Color("3a3146"), "pressed": Color("4b3f5c"), "focus": Color("2d2636")}[state]
		sb.set_corner_radius_all(10)
		sb.border_color = accent
		sb.border_width_left = 6
		if state == "focus":
			sb.set_border_width_all(2)
			sb.border_width_left = 6
		b.add_theme_stylebox_override(state, sb)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 19)
	t.add_theme_color_override("font_color", Color("f2ecfa"))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := Label.new()
	st.text = subtitle
	st.visible = subtitle != ""
	st.add_theme_font_size_override("font_size", 14)
	st.add_theme_color_override("font_color", Color("b3a9c2"))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	v.add_child(st)
	m.add_child(v)
	b.add_child(m)
	# La tuile grandit si le texte passe sur plusieurs lignes (petits écrans).
	var fit := func() -> void:
		var need := v.get_combined_minimum_size().y + 16
		if absf(b.custom_minimum_size.y - maxf(min_h, need)) > 1.0:
			b.custom_minimum_size.y = maxf(min_h, need)
	v.resized.connect(fit)
	t.resized.connect(fit)
	st.resized.connect(fit)
	b.set_meta("title", t)
	b.set_meta("subtitle", st)
	b.pressed.connect(cb)
	return b


## Ligne de liste discrète : titre à gauche (coupé « … » si trop long), détail
## grisé à droite. Pour les listes courtes (accueil) ; un tableau = Tree.
static func list_row(title: String, detail: String, cb: Callable, tooltip := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size.y = 40
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = tooltip
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color("1f1a25"), "hover": Color("2d2636"), "pressed": Color("3a3146"), "focus": Color("1f1a25")}[state]
		sb.set_corner_radius_all(6)
		if state == "focus":
			sb.border_color = Color("c8b6ff")
			sb.set_border_width_all(1)
		b.add_theme_stylebox_override(state, sb)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 16)
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := Label.new()
	d.text = detail
	d.visible = detail != ""
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.add_theme_font_size_override("font_size", 14)
	d.add_theme_color_override("font_color", Color("a59cb3"))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	h.add_child(d)
	b.add_child(h)
	b.set_meta("title", t)
	b.pressed.connect(cb)
	return b


static func set_tile(b: Button, title: String, subtitle: String) -> void:
	(b.get_meta("title") as Label).text = title
	var st: Label = b.get_meta("subtitle")
	st.text = subtitle
	st.visible = subtitle != ""


static func tile_text(b: Button) -> String:
	return (b.get_meta("title") as Label).text + "\n" + (b.get_meta("subtitle") as Label).text


## Grille adaptée à la largeur : 2 colonnes sur téléphone, plus sur ordinateur.
static func grid(columns := 2, sep := 10) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


## Étiquette colorée non cliquable (clan, statut d'âge, poste…).
static func pill(text: String, color := Color("c8b6ff")) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.16)
	sb.border_color = Color(color, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color.lightened(0.25))
	l.add_theme_font_size_override("font_size", 15)
	p.add_child(l)
	return p


## Pastille (une personne d'une liste, un élément) : un appui la retire.
static func chip(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text + "  ×"
	b.custom_minimum_size.y = TOUCH
	b.tooltip_text = "Retirer"
	b.pressed.connect(cb)
	return b


static func option_button(items: Array, selected := 0) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size.y = TOUCH
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	o.clip_text = true
	for it in items:
		o.add_item(str(it))
	if items.size() > 0:
		o.select(clampi(selected, 0, items.size() - 1))
	return o


static func flow(sep := 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


## Boîte de confirmation en français, à la taille de son texte.
static func confirm_dialog(ok_text := "OK") -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.title = "Confirmation"
	d.ok_button_text = ok_text
	d.cancel_button_text = "Annuler"
	d.dialog_autowrap = true
	d.min_size = Vector2i(560, 0)
	return d


## Affiche une confirmation : largeur fixe, hauteur ajustée au texte.
static func confirm(d: ConfirmationDialog, text: String, ok_text := "") -> void:
	d.dialog_text = text
	if ok_text != "":
		d.ok_button_text = ok_text
	d.reset_size()
	d.popup_centered(Vector2i(760, 0))


static func card(children: Array = [], accent := Color("3a3146")) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("221d29")
	sb.border_color = accent
	sb.border_width_left = 4
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	var v := vbox(children, 6)
	p.add_child(v)
	return p


static func warn(text: String) -> Label:
	var l := label(text)
	l.add_theme_color_override("font_color", Color("ffd27a"))
	return l


static func error(text: String) -> Label:
	var l := label(text)
	l.add_theme_color_override("font_color", Color("ff9b8a"))
	return l
