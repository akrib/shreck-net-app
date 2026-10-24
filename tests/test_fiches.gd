extends "res://tests/base.gd"
## Liste des fiches : cases du tableau (libellés, liens, valeur par défaut tue),
## clés de tri (âge dans l'ordre de la liste), types datés du plus récent,
## propriétés lues en une fois.

const FichesScreen := preload("res://ui/screens/fiches_screen.gd")
const AppService := preload("res://core/app/app_service.gd")
const Scanner := preload("res://core/sync/scanner.gd")


func test_cases_et_tri() -> void:
	var p := {"clan": "Nosferatu", "rang": "ancilla", "domaine": "[[Grenoble]]", "statut": "actif", "secte": ["Camarilla", "Anarchs"]}
	eq(FichesScreen.cell("personnage", "rang", p), "Ancilla", "libellé de la liste")
	eq(FichesScreen.cell("personnage", "domaine", p), "Grenoble", "nom du lien")
	eq(FichesScreen.cell("personnage", "statut", p), "", "« actif » n'est pas répété")
	eq(FichesScreen.cell("personnage", "statut", {"statut": "mort_finale"}), "Mort finale", "les exceptions ressortent")
	eq(FichesScreen.cell("personnage", "secte", p), "Camarilla, Anarchs", "valeurs multiples")
	eq(FichesScreen.cell("source", "fiabilite", {"fiabilite": "B"}), "B", "fiabilité : la lettre seule")
	ok(FichesScreen.sort_key("personnage", "rang", {"rang": "ancien"}) < FichesScreen.sort_key("personnage", "rang", {"rang": "nouveau_ne"}),
		"tri par âge dans l'ordre de la liste, pas alphabétique")
	eq(FichesScreen.sort_key("personnage", "rang", {}), "", "case vide : clé vide (rangée en bas)")
	eq(FichesScreen.detail("faveur", {"niveau": "mineure", "debiteur": "[[A]]", "creancier": "[[B]]", "statut": "active"}),
		"Mineure · A → B", "résumé d'une faveur")
	eq(FichesScreen.detail("source", {"nature": "forum", "fiabilite": "B"}), "Forum · fiabilité B", "résumé d'une source")


func test_ordre_et_proprietes() -> void:
	AppService.settings_file = "user://tests_tmp/reglages-fiches.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppService.settings_file))
	var root := temp_dir("coffre-fiches")
	write_file(root + "/Sources/Notes/2025-03 Ancienne.md", "---\ntype: source\nid: src-f1c00001\nschema: 1\nnature: note\nfiabilite: C\n---\n")
	write_file(root + "/Sources/Notes/2026-01-05 Récente.md", "---\ntype: source\nid: src-f1c00002\nschema: 1\nnature: forum\nfiabilite: B\n---\n")
	write_file(root + "/Sources/Notes/Édits.md", "---\ntype: source\nid: src-f1c00003\nschema: 1\nnature: document\nfiabilite: A\n---\n")
	write_file(root + "/Personnages/Récente.md", "---\ntype: personnage\nid: per-f1c00004\nschema: 1\n---\n# Récente\n")
	var app: Node = AppService.new()
	app.background_jobs = false
	app.set_repo_path(root)
	var db: String = app.db_path()
	app.index.close()
	preload("res://core/index/index_store.gd").delete_files(db)
	app._open_read_index()
	Scanner.new(app.repo, app.index).scan()
	var names: Array = app.index.list_by_type("source", 10, true).map(func(r): return str(r.name))
	eq(names, ["2026-01-05 Récente", "2025-03 Ancienne", "Édits"], "datées du plus récent, puis les autres")
	var paths: Array = app.index.list_by_type("source", 10).map(func(r): return str(r.path))
	var props: Dictionary = app.index.props_for(paths, ["fiabilite", "nature"])
	eq(str(props["Sources/Notes/Édits.md"].fiabilite), "A", "propriétés lues en une fois")
	eq(props.size(), 3, "une entrée par note")
	var found: Array = app.index.search("recente", 10)
	eq(str(found[0].name), "Récente", "recherche : le nom exact d'abord, avant les noms qui le contiennent")
	eq(found.size(), 2, "recherche : les deux notes qui contiennent le mot")
	app.index.close()
	app.free()


func test_tableau_triable() -> void:
	var t: Tree = preload("res://ui/widgets/sort_table.gd").new()
	t.setup([{"key": "name", "title": "Nom"}, {"key": "n", "title": "Nombre", "numeric": true}])
	t.set_rows([{"path": "a", "cells": {"name": "Éloi", "n": "2"}}, {"path": "b", "cells": {"name": "Abel", "n": "10"}},
		{"path": "c", "cells": {"name": "Zoé", "n": ""}}])
	var order := func() -> Array:
		return t.get_root().get_children().map(func(it): return it.get_text(0))
	eq(order.call(), ["Éloi", "Abel", "Zoé"], "sans tri : l'ordre donné")
	t.sort_by(1)
	eq(order.call(), ["Abel", "Éloi", "Zoé"], "un nombre se trie par valeur, le plus grand d'abord, les cases vides en bas")
	t.sort_by(1)
	eq(order.call(), ["Éloi", "Abel", "Zoé"], "second appui : ordre inversé, les cases vides toujours en bas")
	t.sort_by(0)
	eq(order.call(), ["Abel", "Éloi", "Zoé"], "les noms sans tenir compte des accents")
	t.free()
