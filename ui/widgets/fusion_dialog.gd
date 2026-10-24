extends PanelContainer
## Fusion de deux fiches : aperçu de ce qui sera écrit, choix de la fiche
## gardée, puis confirmation. Le calcul et l'écriture sont dans AppService
## (merge_plan, merge_notes) ; cet écran n'écrit rien lui-même.

const UiKit := preload("res://ui/ui_kit.gd")

var app: Node
var main: Control
var old_name := ""
var keep_name := ""
var plan := {}
var on_done := Callable()

var _box: VBoxContainer
var _go: Button


static func open_in(p_main: Control, p_app: Node, p_old: String, p_keep: String, cb := Callable()) -> Control:
	var d = load("res://ui/widgets/fusion_dialog.gd").new()
	d.app = p_app
	d.main = p_main
	d.old_name = p_old
	d.keep_name = p_keep
	d.on_done = cb
	d._setup()
	p_main.open_overlay(d)
	return d


func _setup() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("16131a")
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var v := UiKit.vbox([], 10)
	var head := UiKit.hbox([])
	var t := UiKit.heading("Fusionner deux fiches")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiKit.button("Annuler", close))
	v.add_child(head)
	_box = UiKit.vbox([], 8)
	v.add_child(UiKit.scroll(_box))
	var row := UiKit.flow(6)
	row.add_child(UiKit.button("⇄ Garder l'autre", _swap, "Inverser : garder l'autre fiche"))
	_go = UiKit.button("Fusionner", _apply)
	row.add_child(_go)
	v.add_child(row)
	add_child(v)
	_refresh()


func close() -> void:
	main.close_overlay(self)


func _swap() -> void:
	var t := old_name
	old_name = keep_name
	keep_name = t
	_refresh()


func _refresh() -> void:
	for c in _box.get_children():
		c.queue_free()
	plan = app.merge_plan(old_name, keep_name)
	_box.add_child(UiKit.label("« %s » est reprise dans « %s »." % [old_name, keep_name], true, 17))
	if not plan.ok:
		_box.add_child(UiKit.error("Impossible : " + str(plan.error)))
		_go.disabled = true
		return
	_go.disabled = false
	for s in plan.summary:
		_box.add_child(UiKit.label("• " + str(s)))
	var names := PackedStringArray()
	for w in plan.writes:
		names.append("%s (%s)" % [str(w.rel).get_file().get_basename(), w.label])
	_box.add_child(UiKit.muted("Notes écrites (%d) : %s" % [plan.writes.size(), ", ".join(names)]))
	_box.add_child(UiKit.warn("Conseil : synchronisez le coffre avec Git juste avant, pour pouvoir revenir en arrière."))


func _apply() -> void:
	var r: Dictionary = app.merge_notes(plan)
	if not r.ok:
		_box.add_child(UiKit.error("Fusion interrompue : %s. Notes déjà écrites : %s." % [r.error,
			", ".join(PackedStringArray(r.done)) if not r.done.is_empty() else "aucune"]))
		_go.disabled = true
		return
	close()
	if on_done.is_valid():
		on_done.call(str(plan.keep_rel))
