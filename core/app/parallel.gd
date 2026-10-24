extends RefCounted
## Traitement en parallèle sur les cœurs du processeur (WorkerThreadPool).
## Sur Android, Godot fait passer chaque accès fichier par Java : les dates de
## modification se parallélisent bien ; l'ouverture et la lecture des fichiers,
## elles, sont sérialisées par un verrou côté Java (le gain vient alors de
## l'analyse, faite en parallèle).
##
## Règle : `fn` ne doit ni toucher à SQLite ni à l'interface ; elle lit et
## calcule, et renvoie un résultat. L'ordre des résultats est celui des entrées.

static func workers() -> int:
	return clampi(OS.get_processor_count(), 1, 8)


static func map(items: Array, fn: Callable, n_workers := -1) -> Array:
	var n := items.size()
	if n == 0:
		return []
	var k := clampi(workers() if n_workers < 1 else n_workers, 1, n)
	if k == 1:
		var seq := []
		for it in items:
			seq.append(fn.call(it))
		return seq
	# Petits paquets distribués à la demande : sur les téléphones, les cœurs
	# n'ont pas tous la même vitesse ; un découpage en k parts égales ferait
	# attendre les cœurs rapides.
	var parts := mini(n, k * 6)
	var chunks := []
	chunks.resize(parts)
	var mutex := Mutex.new()
	var task := func(ti: int) -> void:
		var start := ti * n / parts
		var end := (ti + 1) * n / parts
		var local := []
		for i in range(start, end):
			local.append(fn.call(items[i]))
		mutex.lock()
		chunks[ti] = local
		mutex.unlock()
	var gid := WorkerThreadPool.add_group_task(task, parts, k, true, "nosferatu")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var out := []
	for c in chunks:
		out.append_array(c)
	return out
