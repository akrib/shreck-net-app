extends RefCounted
## Outils communs aux tests.

var runner: Object


func ok(cond: bool, msg: String) -> void:
	runner.check(cond, msg)


func eq(a: Variant, b: Variant, msg: String) -> void:
	var same: bool = typeof(a) == typeof(b) and a == b
	runner.check(same, "%s — obtenu %s (%s), attendu %s (%s)" % [msg, var_to_str(a), type_string(typeof(a)),
		var_to_str(b), type_string(typeof(b))])


## Dossier temporaire vide (chemin absolu).
func temp_dir(name: String) -> String:
	var p := OS.get_user_data_dir() + "/tests_tmp/" + name
	remove_tree(p)
	DirAccess.make_dir_recursive_absolute(p)
	return p


func remove_tree(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	var d := DirAccess.open(p)
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(p + "/" + f)
	for sub in d.get_directories():
		remove_tree(p + "/" + sub)
	DirAccess.remove_absolute(p)


func copy_tree(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	d.include_hidden = true
	for f in d.get_files():
		if f == ".gdignore":
			continue
		var bytes := FileAccess.get_file_as_bytes(src + "/" + f)
		var out := FileAccess.open(dst + "/" + f, FileAccess.WRITE)
		out.store_buffer(bytes)
		out.close()
	for sub in d.get_directories():
		copy_tree(src + "/" + sub, dst + "/" + sub)


func write_file(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func example_vault() -> String:
	return ProjectSettings.globalize_path("res://tests/fixtures/coffre-exemple")
