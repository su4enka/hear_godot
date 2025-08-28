extends Node

@export var total_days := 15
@export var ore_required := 100
@export var early_exit_day := 5

var current_day := 1
var total_ore := 0
var daily_ore_required := 5
var ore_collected_today := 0
var deafness_level := 0.0
var the_game_ended := false

signal day_started(day_number:int)
signal day_ended(day_number:int, ore_collected:int)
signal game_ended(ending_type:String)
signal ore_collected(amount:int)

func start_new_day():
	if the_game_ended:
		return
	ore_collected_today = 0
	deafness_level = float(current_day - 1) / float(total_days - 1)
	day_started.emit(current_day)

func end_day(_ore_collected:int):
	# Проверяем норму дня
	if ore_collected_today < daily_ore_required:
		end_game("bad")
		return

	# Завершили день
	day_ended.emit(current_day, ore_collected_today)
	current_day += 1

	# Проверяем конец игры
	if current_day > total_days:
		if total_ore >= ore_required:
			end_game("good")
		else:
			end_game("bad")
		return

	# Опция “уехать” после 5-го дня можно оставить на уровне House/Cave UI,
	# не проверяй здесь клавиатуру — менеджер без ввода

	# Стартуем следующий
	start_new_day()

func end_game(ending_type:String):
	print("bad ending")
	the_game_ended = true
	game_ended.emit(ending_type)
