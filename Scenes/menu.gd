extends CanvasLayer


func _ready():
	get_viewport().size_changed.connect(_on_size_changed)

func _on_size_changed():
	var new_size = get_viewport().size
	if has_node("UI/HitRect"):
		$Background.size = new_size
