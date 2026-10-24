extends SceneTree
## Banc de mesure sans interface (ordinateur) :
##   godot --headless --path . --script res://tools/bench_headless.gd -- <dossier_de_banc> [échelle]
## Le dossier de banc doit être vide (ou un ancien dossier de banc). Échelle 1.0 par défaut.

const Synthetic := preload("res://core/app/synthetic.gd")
const Benchmark := preload("res://core/app/benchmark.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage : -- <dossier_de_banc> [échelle]")
		quit(2)
		return
	var path: String = args[0]
	var scale := float(args[1]) if args.size() > 1 else 1.0
	var problem := Synthetic.check_target(path, "")
	if problem != "":
		print("Banc : " + problem)
		quit(2)
		return
	if not FileAccess.file_exists(path.trim_suffix("/") + "/" + Synthetic.MARKER):
		var g = Synthetic.new()
		var r: Dictionary = g.generate(path, scale)
		print("Génération : %s — %.1f Mo écrits en %d ms" % [JSON.stringify(r.counts), r.bytes / 1048576.0, r.ms])
	var out: Dictionary = Benchmark.run(path, "user://index/banc-headless.sqlite")
	for l in out.lines:
		print(l)
	quit(0 if out.ok else 1)
