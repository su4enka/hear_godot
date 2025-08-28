extends Node

@export var total_days := 15
@export var ore_required := 100
@export var early_exit_day := 5

var current_day := 1
var total_ore := 0
var daily_ore_required := 5
var ore_collected_today := 0
var deafness_level := 0.0  # 0.0 to 1.0
var the_game_ended := false

signal day_started(day_number)
signal day_ended(day_number, ore_collected)
signal game_ended(ending_type)
signal ore_collected(amount)

func start_new_day():
	if game_ended:
		return
	ore_collected_today = 0
	deafness_level = float(current_day - 1) / float(total_days - 1)
	day_started.emit(current_day)
	
func end_day(ore_collected: int):
	if ore_collected_today < daily_ore_required:
		end_game("bad")
		print("bad")
		return
	else:
		start_new_day()		
		day_ended.emit(current_day, ore_collected_today)
		current_day += 1
	
	if current_day > total_days:
		if total_ore >= ore_required:
			end_game("good")
		else:
			end_game("bad")
			print("bad")
	elif current_day > early_exit_day and Input.is_action_just_pressed("ui_cancel"):
		end_game("early")
		print("early")
		
func end_game(ending_type: String):
	the_game_ended = true
	game_ended.emit(ending_type)
