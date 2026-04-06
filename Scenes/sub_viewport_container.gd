extends SubViewportContainer

func _ready():
	$SubViewport.size = size

func _process(_delta):
	if $SubViewport.size != Vector2i(size):
		$SubViewport.size = Vector2i(size)
