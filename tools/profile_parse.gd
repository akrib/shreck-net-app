extends SceneTree
## Mesure séparément lecture, analyse YAML, analyse du corps (outil de développement).
##   godot --headless --path . --script res://tools/profile_parse.gd -- <dossier>

const RepoAccess := preload("res://core/storage/repo_access.gd")
const NoteDocument := preload("res://core/format/note_document.gd")
const StructuredLines := preload("res://core/format/structured_lines.gd")
const IndexStore := preload("res://core/index/index_store.gd")


func _init() -> void:
	var repo = RepoAccess.new(OS.get_cmdline_user_args()[0])
	var lst: Dictionary = repo.list_files()
	var t_read := 0
	var t_hash := 0
	var t_doc := 0
	var t_body := 0
	var t_prep := 0
	for rel in lst.md:
		var t0 := Time.get_ticks_usec()
		var rb: Dictionary = repo.read_bytes(rel)
		var t1 := Time.get_ticks_usec()
		RepoAccess.hash_bytes(rb.bytes)
		var t2 := Time.get_ticks_usec()
		var doc = NoteDocument.from_bytes(rb.bytes)
		var t3 := Time.get_ticks_usec()
		var parsed := StructuredLines.parse_body(doc.body, doc.body_first_line)
		var t4 := Time.get_ticks_usec()
		IndexStore.prepare(rel, doc, parsed, false)
		t_prep += Time.get_ticks_usec() - t4
		t_read += t1 - t0
		t_hash += t2 - t1
		t_doc += t3 - t2
		t_body += t4 - t3
	print("%d fichiers — lecture %d ms, empreinte %d ms, frontmatter %d ms, corps %d ms, lignes d'index %d ms" % [
		lst.md.size(), t_read / 1000, t_hash / 1000, t_doc / 1000, t_body / 1000, t_prep / 1000])
	quit()
