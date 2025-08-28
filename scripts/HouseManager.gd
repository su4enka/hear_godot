extends Node3D

@onready var player = $Player
@onready var wife = $Wife
@onready var bed_area = $Bed/Area3D
@onready var exit_trigger = $ExitTrigger
@onready var day_label = $CanvasLayer/Control/DayCounter
@onready var ore_label = $CanvasLayer/Control/OreCounter

func _ready():
	GameManager.day_started.connect(_on_day_started)
	GameManager.day_ended.connect(_on_day_ended)
	exit_trigger.body_entered.connect(_on_exit_triggered)
	_update_ui()
	
func _on_day_started(day):
	player.global_position = Vector3(0, 1, 0)
	player.can_move = true
	_update_ui()
	
func _on_day_ended(day, ore):
	player.can_move = false
	_update_ui()
	
func _on_exit_triggered(body):
	if body == player:
		_enter_cave()

func _on_bed_entered(body):
	if body == player:
		GameManager.end_day(GameManager.ore_collected_today)

func _enter_cave():
	var cave_scene = preload("res://scenes/Cave.tscn")
	get_tree().change_scene_to_packed(cave_scene)
	
func _update_ui():
	day_label.text = "Day: %d/%d" % [GameManager.current_day, GameManager.total_days]
	ore_label.text = "Ore: %d/%d" % [GameManager.total_ore, GameManager.ore_required]
