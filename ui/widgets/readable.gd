extends Container
## Colonne de lecture : en plein écran, des lignes de 1 800 pixels se lisent
## mal. Ce conteneur limite la largeur de son contenu et le centre ; sur un
## écran plus étroit, le contenu prend simplement toute la largeur.

var max_width := 1100.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var w := minf(size.x, max_width)
		var x := floorf((size.x - w) / 2.0)
		for c in get_children():
			if c is Control and (c as Control).visible:
				fit_child_in_rect(c, Rect2(x, 0, w, size.y))


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and (c as Control).visible:
			m = m.max((c as Control).get_combined_minimum_size())
	m.x = minf(m.x, max_width)
	return m
