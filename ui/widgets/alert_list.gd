extends RefCounted
## Liste d'alertes (accueil, enquête) : une ligne par alerte, couleur selon
## l'urgence ; un clic ouvre la note concernée. Pour une personne surveillée,
## « Vu » marque ses nouveaux éléments comme lus.

const UiKit := preload("res://ui/ui_kit.gd")

const COLORS := {"urgent": Color("ff7a6b"), "attention": Color("e0b04a"), "info": Color("a59cb3")}
const LABELS := {"urgent": "Urgent", "attention": "À surveiller", "info": "Pour information"}


## `limit` : nombre maximal de lignes (0 = toutes). `on_change` : rappelé après « Vu ».
static func build(app: Node, main: Control, alerts: Array, limit := 0, on_change := Callable()) -> VBoxContainer:
	var box := UiKit.vbox([], 6)
	var shown := alerts if limit <= 0 else alerts.slice(0, limit)
	for a in shown:
		var col: Color = COLORS.get(a.level, Color.WHITE)
		var path: String = str(a.path)
		var b := UiKit.button("%s\n%s" % [a.title, a.detail], func():
			if path != "":
				main.open_note(path))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", col.lightened(0.15))
		b.tooltip_text = LABELS.get(a.level, "")
		var mark := ColorRect.new()
		mark.color = col
		mark.custom_minimum_size = Vector2(5, 0)
		var row := UiKit.hbox([mark, b], 8)
		if a.kind == "surveille":
			var who: String = str(a.get("person", ""))
			row.add_child(UiKit.button("Vu", func():
				app.mark_seen(who)
				if on_change.is_valid():
					on_change.call(), "Marquer ces éléments comme lus"))
		box.add_child(row)
	if limit > 0 and alerts.size() > limit:
		box.add_child(UiKit.muted("… et %d autre(s)" % (alerts.size() - limit)))
	return box
