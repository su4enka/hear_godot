extends Node

func _ready():
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.start_new_day()
	get_tree().change_scene_to_packed(preload("res://scenes/House.tscn"))

func _on_game_ended(kind:String):
	var map := {
		"bad": "res://scenes/Ending_Bad.tscn",
		"death": "res://scenes/Ending_Bad.tscn",
		"early": "res://scenes/Ending_Early.tscn",
		"good": "res://scenes/Ending_Good.tscn"
	}
	get_tree().change_scene_to_file(map.get(kind, "res://scenes/Ending_Bad.tscn"))
