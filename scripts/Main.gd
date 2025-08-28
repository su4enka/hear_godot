extends Node

func _ready():
	
	GameManager.start_new_day()
	get_tree().change_scene_to_packed(preload("res://scenes/House.tscn"))
