extends Node

signal mouse_sens_changed(value: float)

var mouse_sens := 0.6

func _ready() -> void:
	# читаем сохранённое (если уже писал раньше — ок)
	mouse_sens = float(ProjectSettings.get_setting("input/mouse_sens", 0.6))

func set_mouse_sens(v: float) -> void:
	mouse_sens = clamp(v, 0.05, 5.0)
	ProjectSettings.set_setting("input/mouse_sens", mouse_sens)
	ProjectSettings.save()
	mouse_sens_changed.emit(mouse_sens)
