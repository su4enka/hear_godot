extends Node

@export var total_days := 15
@export var early_exit_day := 5
@export var ore_required_total := 100

# Нормы по дням (можешь подправить числа)
var ore_required_by_day := [2,2,2,3,3, 4,4,5,5,6, 6,6,6,6,6]

var current_day := 1
var total_ore := 0
var ore_collected_today := 0
var chances_left := 2                 # два «прокола» по норме
var deafness_level := 0.0             # 0..1, растёт к 15 дню
var the_game_ended := false

var opening_needs_confirm := true

var just_returned_home := false
var came_from_cave := false

var early_used := false

signal day_started(day_number:int)
signal day_ended(day_number:int, ore_collected:int)
signal game_ended(ending_type:String)         # "good","bad","early","death"
signal ore_collected(amount:int)
signal wife_line(text:String)                 # для реплик жены
signal day_intro(text:String)                 # для «День N» и пролога

var wife_lines := {
	1: [
		"We'll manage. I believe in you.",
		"The bed still smells of the city. We'll get used to this place."
	],
	2: [
		"Be careful today. I heard the cave creak last night.",
		"I'll keep the stove going. Come back warm."
	],
	3: [
		"I think your hearing has gotten worse… Watch the lamps in the cave.",
		"If you can’t hear, look. Stones speak with dust."
	],
	4: [
		"Don't rush every rock, listen first.",
		"The cave feels heavier each morning.",
		"Even the lamp flickers differently today."
	],
	5: [
		"If you hate it, we can leave. No shame in choosing life.",
		"Five days in… Does the ringing ever stop?"
	],
	6: [
		"The dust last night made me cough. Be careful.",
		"If you can't hear, then look — the cave shows signs.",
		"I dreamt of falling stones. Don't make it real."
	],
	7: [
		"The dust last night made me cough. Be careful.",
		"If you can't hear, then look — the cave shows signs.",
		"I dreamt of falling stones. Don't make it real."
	],
	8: [
		"I made soup. It's thin, but hot. Come back for it, alright?",
	],
	9: [
		"You don't answer the kettle anymore. I'll tap three times when I speak.",
	],
	10: [
		"Ten days… you barely answer anymore.",
		"I keep talking even if you can't hear me.",
		"The neighbors say the cave eats voices."
	],
	11: [
		"I counted again. We're close — but at what cost?",
		"Don't let the cave steal your name.",
		"Even whispers echo louder than you do now."
	],
	12: [
		"If dust falls, promise me you’ll run.",
		"Each path looks like the last. Don't get lost.",
		"Sometimes the cave warns, sometimes it lies."
	],
	13: [
		"Our bags are packed — for leaving or for ending.",
		"One more day, I tell myself.",
		"Even the walls in this house creak like the cave."
	],
	14: [
		"Tomorrow you will finally rest.",
		"I'll wait at the door, as always.",
		"The night feels like the cave is already here."
	],
	15: [
		"Last day. I'll listen for the door."
	]
}

var last_wife_line: String = ""


func _ready():
	_emit_day_intro()

func get_wife_line() -> String:
	var day_lines:Array = wife_lines.get(current_day, [])
	var pool:Array = day_lines.duplicate()

	# Контекст — мало руды сегодня
	if ore_collected_today < get_required_today() and ore_collected_today > 0:
		pool.append_array([
			"That's not enough for today… try another path?",
			"I can stretch dinner, but not forever."
		])

	# Контекст — закончились/тают шансы
	if chances_left <= 0:
		pool.append("We can’t afford another short day.")
	elif chances_left == 1:
		pool.append("Only one chance left before we lose the house.")
	elif chances_left == 2 and current_day > 1:
		pool.append("Two chances remain. Use them wisely.")

	# Контекст — глухота растёт
	if deafness_level > 0.6:
		pool.append("You don’t hear me anymore. So look at me: come back safe.")
	elif deafness_level > 0.3:
		pool.append("If you miss the sound, watch the lamps and dust.")

	# Контекст — после 5 дня подсказываем про «уехать»
	if current_day >= early_exit_day:
		pool.append("We can still leave. The door isn't locked.")

	if pool.is_empty():
		return "..."

	if last_wife_line != "" and pool.size() > 1:
		var tries := 6
		var pick = pool[randi() % pool.size()]
		while pick == last_wife_line and tries > 0:
			pick = pool[randi() % pool.size()]
			tries -= 1
		last_wife_line = pick
		return pick
	else:
		var pick2 = pool[randi() % pool.size()]
		last_wife_line = pick2
		return pick2

func _emit_day_intro():
	var intro := "Day %d" % current_day
	day_intro.emit(intro)

func get_required_today() -> int:
	var idx = clamp(current_day-1, 0, ore_required_by_day.size()-1)
	return ore_required_by_day[idx]

func start_new_day():
	if the_game_ended:
		return
	came_from_cave = false 
	ore_collected_today = 0
	deafness_level = float(current_day - 1) / float(total_days - 1)
	_emit_day_intro()
	day_started.emit(current_day)

func reset_state() -> void:
	current_day = 1
	total_ore = 0
	ore_collected_today = 0
	chances_left = 2
	
	early_used = false
	the_game_ended = false
	opening_needs_confirm = true
	came_from_cave = false
	deafness_level = 0.0
	last_wife_line = ""

	## если есть ещё временные таймеры/словарики
	#path_timers.clear()
	#path_warnings.clear()

func add_ore(n:=1):
	ore_collected_today += n
	total_ore += n
	ore_collected.emit(n)

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

func go_home_from_cave():
	came_from_cave = true
	get_tree().change_scene_to_file("res://scenes/TrailerPark.tscn")
