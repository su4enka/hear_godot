extends Node

func _ready():
	# Initialize game manager
	var game_manager = Node.new()
	game_manager = preload("res://scripts/GameManager.gd").new()
	add_child(game_manager)
	
	# Start the game
	game_manager.start_new_day()
	
	# Load house scene
	var house_scene = preload("res://scenes/House.tscn")
	get_tree().change_scene_to_packed(house_scene)
