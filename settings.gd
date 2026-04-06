extends VBoxContainer

var player = null
@onready var volume_slider = $VolumeSlider 
@export var bus_name: String = "Master"
var bus_index: int

func on_ready():
	bus_index = AudioServer.get_bus_index(bus_name)
	if is_instance_valid(volume_slider):
		volume_slider.min_value = 0.001
		volume_slider.max_value = 1.0
		volume_slider.value = 0.5
		_on_volume_value_changed(volume_slider.value)

func _on_back_pressed() -> void:
	GameEvents.request_back_to_pause.emit()
	self.hide()

func _on_window_mode_pressed() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_volume_value_changed(value: float) -> void:
	var volume_db = linear_to_db(value)
	AudioServer.set_bus_volume_db(bus_index, volume_db)	

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			_on_show()

func _on_show():
	if is_instance_valid(volume_slider):
		_on_volume_value_changed(volume_slider.value)
