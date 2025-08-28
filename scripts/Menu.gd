extends CanvasLayer

@onready var settings_menu = $SettingsMenu
@onready var v_box_container = $VBoxContainer




# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	settings_menu.hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_settings_pressed() -> void:
	settings_menu.show()
	v_box_container.hide()


func _on_button_back_to_menu_pressed() -> void:
	settings_menu.hide()
	v_box_container.show()


func _on_button_quit_pressed() -> void:
	get_tree().quit()
