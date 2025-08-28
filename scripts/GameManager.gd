extends Node

@export var total_days := 15
@export var early_exit_day := 5
@export var ore_required_total := 100

# Нормы по дням (можешь подправить числа)
var ore_required_by_day := [1,2,2,3,3, 4,4,5,5,6, 6,7,7,8,8]

var current_day := 1
var total_ore := 0
var ore_collected_today := 0
var chances_left := 2                 # два «прокола» по норме
var deafness_level := 0.0             # 0..1, растёт к 15 дню
var the_game_ended := false

var opening_needs_confirm := true

signal day_started(day_number:int)
signal day_ended(day_number:int, ore_collected:int)
signal game_ended(ending_type:String)         # "good","bad","early","death"
signal ore_collected(amount:int)
signal wife_line(text:String)                 # для реплик жены
signal day_intro(text:String)                 # для «День N» и пролога

var wife_lines := {
	1: ["We'll manage. I believe in you."],
	2: ["Be careful today. There's some noise in the cave..."],
	3: ["I think your hearing has gotten worse?"],
	5: ["If you hate it, we can leave."],
	11: ["There's not much left..."]
}

func get_wife_line() -> String:
	var lines:Array = wife_lines.get(current_day, [])
	if lines.is_empty(): return "..."
	return lines[randi() % lines.size()]

func _ready():
	_emit_day_intro()

func _emit_day_intro():
	var intro := "Day %d" % current_day
	day_intro.emit(intro)

func get_required_today() -> int:
	var idx = clamp(current_day-1, 0, ore_required_by_day.size()-1)
	return ore_required_by_day[idx]

func start_new_day():
	if the_game_ended:
		return
	ore_collected_today = 0
	deafness_level = float(current_day - 1) / float(total_days - 1)
	_emit_day_intro()
	day_started.emit(current_day)

func add_ore(n:=1):
	ore_collected_today += n
	total_ore += n
	ore_collected.emit(n)

func needs_opening_confirm() -> bool:
	return current_day == 1 and opening_needs_confirm

func end_day():
	# Проверяем норму
	if ore_collected_today < get_required_today():
		chances_left -= 1
		if chances_left < 0:
			end_game("bad")
			return
		# иначе разрешаем спать, но без списания шанса здесь — уже списали выше

	day_ended.emit(current_day, ore_collected_today)
	current_day += 1

	# Проверяем конец игры
	if current_day > total_days:
		if total_ore >= ore_required_total:
			end_game("good")
		else:
			end_game("bad")
		return

	start_new_day()

func end_game(kind:String):
	the_game_ended = true
	game_ended.emit(kind)
