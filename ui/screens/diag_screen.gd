extends VBoxContainer
## Écran « Diagnostic » : synchronisation, vérification complète,
## reconstruction de l'index, problèmes détectés, rapport à copier.

const UiKit := preload("res://ui/ui_kit.gd")

var app: Node
var main: Control
var _report: TextEdit
var _extra := ""


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	for b in [
		UiKit.button("Resynchroniser", func(): app.start_sync(), "Détecte les changements faits ailleurs"),
		UiKit.button("Vérifier", _verify, "Relit chaque fichier et compare l'index à une reconstruction complète"),
		UiKit.button("Reconstruire l'index", _rebuild, "Supprime l'index et le refait depuis les notes"),
		UiKit.button("Copier le rapport", _copy),
	]:
		buttons.add_child(b)
	add_child(buttons)
	add_child(UiKit.muted("Supprimer l'index ne touche à aucune note : il se reconstruit entièrement depuis le dossier du coffre."))
	_report = UiKit.report_box(300)
	add_child(_report)


func on_show() -> void:
	_refresh()


func on_job_finished(job: String, result: Dictionary) -> void:
	if job == "vérification":
		var t := PackedStringArray()
		t.append("== Vérification (%d ms) ==" % result.get("ms", 0))
		t.append("Fichiers relus : %d" % result.get("checked", 0))
		t.append("Empreinte différente de l'index : %d %s" % [result.get("hash_mismatch", []).size(), str(result.get("hash_mismatch", []).slice(0, 10))])
		t.append("Absents de l'index : %d · absents du disque : %d" % [result.get("missing_in_index", []).size(), result.get("missing_on_disk", []).size()])
		t.append("Reconstruction complète identique à l'index : %s" % ("OUI ✓" if result.get("rebuild_identical", false) else "NON ✗"))
		_extra = "\n".join(t)
	if is_inside_tree():
		_refresh()


func _verify() -> void:
	_extra = "Vérification en cours…"
	app.start_verify()
	_refresh()


func _rebuild() -> void:
	_extra = "Reconstruction en cours…"
	app.start_rebuild()
	_refresh()


func _refresh() -> void:
	var t: String = app.diagnostic_text()
	if _extra != "":
		t += "\n\n" + _extra
	if app.index != null:
		var probs: Array = app.index.problems(150)
		t += "\n\n== Problèmes (%d affichés) ==" % probs.size()
		for p in probs:
			t += "\n%s  %s:%d  %s" % [p.level, p.path, p.line, p.message]
		var broken: Array = app.index.broken_links(60)
		t += "\n\n== Liens cassés (%d affichés) ==" % broken.size()
		for b in broken:
			t += "\n%s:%d  [[%s]]" % [b.path, b.line, b.target]
	_report.text = t


func _copy() -> void:
	DisplayServer.clipboard_set(_report.text)
	app._log("Rapport copié dans le presse-papiers.")
