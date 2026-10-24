extends SceneTree
## Lance les tests sans interface :
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- flat_yaml   (filtre)
## Code de sortie : 0 si tout passe, 1 sinon.

var passed := 0
var failed := 0
var current := ""


func _init() -> void:
	var filtre := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filtre = args[0]
	print("== Tests Nosferatu Intelligence — Godot %s — %s ==" % [Engine.get_version_info().string, OS.get_name()])
	var files := Array(DirAccess.get_files_at("res://tests"))
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		if filtre != "" and not f.contains(filtre):
			continue
		var script: Script = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			failed += 1
			print("ÉCHEC %s : script illisible (erreur de syntaxe ?)" % f)
			continue
		var t = script.new()
		t.runner = self
		var before := failed
		var n := 0
		for m in t.get_method_list():
			if str(m.name).begins_with("test_"):
				current = "%s::%s" % [f.get_basename(), m.name]
				if OS.get_environment("NOSF_TRACE") != "":
					printerr("→ " + current)
				n += 1
				var avant := passed + failed
				t.call(m.name)
				if passed + failed == avant:
					check(false, "aucune vérification exécutée (erreur de script ?)")
		if t.has_method("cleanup"):
			t.cleanup()
		print("%s %s (%d tests)" % ["OK  " if failed == before else "ÉCHEC", f, n])
	print("== %d vérifications réussies, %d échecs ==" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  ✗ %s : %s" % [current, msg])
