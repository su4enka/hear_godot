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
	
	resume_btn.focus_mode = Control.FOCUS_ALL
	settings_btn.focus_mode = Control.FOCUS_ALL
	quit_btn.focus_mode = Control.FOCUS_ALL
	back_to_menu_btn.focus_mode = Control.FOCUS_ALL
	resume_btn.grab_focus()
	
func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return

	if settings_menu.visible:
		back_to_menu_btn.grab_focus()
		if ev.is_action_pressed("ui_accept"):
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			_on_back_to_menu()
			resume_btn.grab_focus()
		return

	if ev.is_action_pressed("ui_down"):
		_cycle_focus(+1)
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
	elif ev.is_action_pressed("ui_up"):
		_cycle_focus(-1)
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
	elif ev.is_action_pressed("ui_accept"):
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()

		var owner: Control = null
		if vp != null:
			owner = vp.gui_get_focus_owner()
		if owner is BaseButton:
			(owner as BaseButton).emit_signal("pressed")

func _cycle_focus(dir: int) -> void:
	var order: Array[BaseButton] = [resume_btn, settings_btn, quit_btn]
	var f := get_viewport().gui_get_focus_owner()
	var i = max(order.find(f), 0)
	var n = (i + dir + order.size()) % order.size()
	order[n].grab_focus()

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
	# применить «на лету»
	var player := get_tree().current_scene.get_node_or_null("Player")
	if player != null:
		# в твоём игроке это публичное поле HousePlayer.mouse_sensitivity
		player.mouse_sensitivity = float(value)
