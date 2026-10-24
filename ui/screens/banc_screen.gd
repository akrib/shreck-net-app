extends VBoxContainer
## Écran « Banc » : génère un jeu de données synthétique dans un dossier
## SÉPARÉ du coffre, puis mesure les performances sur cet appareil.

const UiKit := preload("res://ui/ui_kit.gd")

const VOLUMES := [["Réduit (10 %) — environ 800 notes", 0.1], ["Moyen (50 %) — environ 4 000 notes", 0.5],
	["Complet (100 %) — environ 8 000 notes, 32 000 éléments", 1.0]]

var app: Node
var main: Control
var _path: LineEdit
var _volume: OptionButton
var _out: TextEdit


func setup(p_app: Node, p_main: Control) -> void:
	app = p_app
	main = p_main
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	add_child(UiKit.heading("Banc de performance"))
	add_child(UiKit.muted("Écrit un jeu de données fictif au format v1 dans un dossier vide et séparé (jamais dans votre coffre), puis mesure : indexation complète, resynchronisation, enregistrement, recherche, mémoire. Les durées sont mesurées sur cet appareil."))
	_path = UiKit.line_edit("Dossier de banc (vide)", app.bench_path())
	add_child(_path)
	_volume = OptionButton.new()
	_volume.custom_minimum_size.y = UiKit.TOUCH
	for v in VOLUMES:
		_volume.add_item(v[0])
	_volume.selected = 2
	add_child(_volume)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_child(UiKit.button("Générer le jeu de données", _generate))
	row.add_child(UiKit.button("Mesurer", _run))
	row.add_child(UiKit.button("Copier les résultats", func(): DisplayServer.clipboard_set(_out.text)))
	add_child(row)
	_out = UiKit.report_box(260)
	add_child(_out)


func _generate() -> void:
	_out.text = "Génération en cours…"
	if not app.start_bench_generate(_path.text.strip_edges(), VOLUMES[_volume.selected][1]):
		_out.text = "Impossible : " + app.journal[app.journal.size() - 1]


func _run() -> void:
	_out.text = "Mesures en cours…"
	if not app.start_bench_run(_path.text.strip_edges()):
		_out.text = "Impossible : " + app.journal[app.journal.size() - 1]


func on_job_finished(job: String, result: Dictionary) -> void:
	if job == "génération du banc":
		if result.has("counts"):
			_out.text = "Jeu de données écrit : %s\n%.1f Mo en %d ms.\nAppuyez sur « Mesurer »." % [
				JSON.stringify(result.counts), result.bytes / 1048576.0, result.ms]
	elif job == "mesures":
		_out.text = "\n".join(result.get("lines", PackedStringArray(["(aucun résultat)"])))
