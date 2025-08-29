extends CanvasLayer

@onready var control = $Control
@onready var resume_btn = $Control/VBoxContainer/ButtonResume
@onready var settings_btn = $Control/VBoxContainer/ButtonSettings
@onready var quit_btn = $Control/VBoxContainer/ButtonQuit
@onready var settings_menu = $SettingsMenu
@onready var sens_slider = $SettingsMenu/HSliderSensitivity
@onready var back_to_menu_btn = $SettingsMenu/ButtonBackToMenu


func _ready():
	visible = false
	settings_menu.visible = false
	resume_btn.pressed.connect(_on_resume)
	settings_btn.pressed.connect(_on_settings)
	back_to_menu_btn.pressed.connect(_on_back_to_menu)
	quit_btn.pressed.connect(_on_quit)
	sens_slider.value = ProjectSettings.get_setting("player/mouse_sensitivity", 0.0025)
	sens_slider.value_changed.connect(_on_sens_changed)

func toggle():
	if visible:
		_resume_game()
	else:
		_pause_game()

func _pause_game():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	control.visible = true
	visible = true
	Engine.time_scale = 0
	settings_menu.visible = false

func _resume_game():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	visible = false
	Engine.time_scale = 1

func _on_resume():
	_resume_game()

func _on_settings():
	settings_menu.visible = true
	control.visible = false

func _on_back_to_menu():
	settings_menu.visible = false
	control.visible = true

func _on_quit():
	Engine.time_scale = 1
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _on_sens_changed(value: float):
	ProjectSettings.set_setting("player/mouse_sensitivity", value)
	ProjectSettings.save()
