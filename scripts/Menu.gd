extends CanvasLayer

@onready var menu_buttons = $VBoxContainer
@onready var settings := $SettingsMenu
@onready var btn_play := $VBoxContainer/ButtonPlay
@onready var btn_settings := $VBoxContainer/ButtonSettings
@onready var btn_quit := $VBoxContainer/ButtonQuit
@onready var slider := $SettingsMenu/HSliderSensitivity
@onready var lbl := $SettingsMenu/LabelSensitivity
@onready var btn_back := $SettingsMenu/ButtonBackToMenu

const PS_KEY := "player/mouse_sensitivity"
const DEFAULT_SENS := 0.002

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	settings.visible = false
	btn_play.pressed.connect(_on_play)
	btn_settings.pressed.connect(_on_open_settings)
	btn_quit.pressed.connect(_on_quit)
	btn_back.pressed.connect(_on_close_settings)

	# Подсказка: играйте со звуком!
	lbl.text = "Mouse Sensitivity  |  Make the sounds louder 🎧"

	# Подтягиваем сохранённую сенсу
	if not ProjectSettings.has_setting(PS_KEY):
		ProjectSettings.set_setting(PS_KEY, DEFAULT_SENS)
		ProjectSettings.save()
	slider.min_value = 0.001
	slider.max_value = 0.01
	slider.step = 0.001
	slider.value = float(ProjectSettings.get_setting(PS_KEY))
	slider.value_changed.connect(_on_sens_changed)

func _on_sens_changed(v):
	ProjectSettings.set_setting(PS_KEY, v)
	ProjectSettings.save()

func _on_open_settings():
	menu_buttons.visible = false
	settings.visible = true

func _on_close_settings():
	menu_buttons.visible = true
	settings.visible = false

func _on_quit():
	get_tree().quit()

func _on_play():
	# Старт нового дня и показ интро будет отработан в House через GameManager
	get_tree().change_scene_to_file("res://scenes/Prologue.tscn")
