extends RefCounted
## Fiabilité calculée d'un informateur, sur sa fiche : lettre actuelle, lettre
## proposée et pourquoi (affirmations confirmées, réfutées, non tranchées),
## bouton « Appliquer ». Rien n'est écrit sans ce bouton.

const UiKit := preload("res://ui/ui_kit.gd")
const Schema := preload("res://core/model/schema.gd")
const Informants := preload("res://core/analysis/informants.gd")

const VERDICT := {"confirme": ["Confirmée", Color("7fd59b")], "refute": ["Réfutée", Color("ff7a6b")], "ouvert": ["Non tranchée", Color("a59cb3")]}


## `on_apply(lettre)` : appelé par le bouton « Appliquer ».
static func build(app: Node, main: Control, ev: Dictionary, on_apply: Callable) -> Control:
	var fold := FoldableContainer.new()
	var cur := str(ev.current) if str(ev.current) != "" else "—"
	fold.title = "Fiabilité comme informateur : %s proposée (actuelle %s)" % [ev.proposed, cur]
	fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fold.folded = ev.items.is_empty()
	var inner := UiKit.vbox([], 6)
	fold.add_child(inner)
	if ev.items.is_empty():
		inner.add_child(UiKit.muted("Aucune affirmation de sa part dans vos notes (champ « Dit par », ou auteur d'une source)."))
		return fold
	inner.add_child(UiKit.label("%d affirmation(s) : %s." % [ev.items.size(), Informants.summary(ev)]))
	var why := "Moins de 3 affirmations tranchées : F, « ne peut être évaluée »." if ev.proposed == "F" else \
		"Lettre proposée d'après le taux d'affirmations confirmées parmi celles qui sont tranchées."
	inner.add_child(UiKit.muted(why + " Une affirmation est tranchée par un indice ou un événement qui la cite (pour ou contre), sinon par sa crédibilité 1 ou 5."))
	if ev.proposed != ev.current and ev.proposed != "F":
		var letter: String = ev.proposed
		inner.add_child(UiKit.button("Appliquer %s" % Schema.option_label("", "fiabilite", letter), func(): on_apply.call(letter),
			"Écrit la fiabilité dans la fiche"))
	var shown := 0
	for v in ["refute", "confirme", "ouvert"]:
		for it in ev.items:
			if it.verdict != v:
				continue
			if shown >= 25:
				break
			shown += 1
			var path: String = it.path
			var txt := "%s · %s\n— %s%s" % [VERDICT[v][0], Schema.display_text(str(it.text)).left(140), it.note,
				(" (%s)" % it.by) if str(it.by) != "" else ""]
			var b := UiKit.button(txt, func(): main.open_note(path))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.add_theme_color_override("font_color", VERDICT[v][1])
			inner.add_child(b)
	if ev.items.size() > shown:
		inner.add_child(UiKit.muted("… et %d autre(s)" % (ev.items.size() - shown)))
	return fold
