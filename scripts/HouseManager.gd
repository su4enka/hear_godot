extends Node3D

@onready var player = $Player
@onready var bed_area = $Bed/Area3D
@onready var exit_trigger = $ExitTrigger
@onready var day_label = $CanvasLayer/Control/DayCounter
@onready var ore_label = $CanvasLayer/Control/OreCounter
@onready var leave_dialog: ConfirmationDialog = $CanvasLayer/LeaveDialog
@onready var wife_area: Area3D = $Wife/Area3D
@onready var subtitle: Label = $CanvasLayer/Subtitles
@onready var hint_label: Label = $CanvasLayer/Control/HintLabel
@onready var fade_rect: ColorRect = $OverlayLayer/DayIntro/Fade
@onready var day_intro_label: Label = $OverlayLayer/DayIntro/Label

func _ready():
		# Подключаемся к сигналам от автолоада
	GameManager.day_intro.connect(_on_day_intro)
	GameManager.day_started.connect(_on_day_started)
	GameManager.day_ended.connect(_on_day_ended)

	# ТРИГГЕРЫ
	exit_trigger.body_entered.connect(_on_exit_triggered)
	bed_area.body_entered.connect(_on_bed_entered)
	# <-- переносим из _on_day_intro, чтобы не плодить подключения
	wife_area.body_entered.connect(_on_wife_entered)

	# Безопасная инициализация интро-оверлея — на случай если сигнал пролетел до подключения
	if day_intro_label:
		day_intro_label.visible = false

	_update_ui()

	# ГАРАНТИЯ ПОКАЗА интро в House:
	# если Menu уже вызвало GameManager.start_new_day() ДО смены сцены,
	# сигнал мог уйти раньше — покажем вручную текущий день.
	if not GameManager.came_from_cave:
		_on_day_intro("Day %d" % GameManager.current_day)

func _action_is_pressed() -> bool:
	return Input.is_action_just_pressed("interact") \
		or Input.is_action_just_pressed("ui_accept") \
		or Input.is_action_just_pressed("ui_select") \
		or Input.is_action_just_pressed("ui_cancel") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _wait_for_skip() -> void:
	while true:
		await get_tree().process_frame
		if _action_is_pressed():
			return

func _set_fade_alpha(a: float) -> void:
	var c = fade_rect.color
	c.a = a
	fade_rect.color = c

func _on_day_intro(text:String):
	day_intro_label.text = text
	day_intro_label.visible = true
	_set_fade_alpha(0.0)

	if GameManager.needs_opening_confirm():
		if player: player.can_move = false
		var t := create_tween()
		t.tween_method(_set_fade_alpha, 0.0, 0.85, 0.30)
		await t.finished
		await _wait_for_skip()
		GameManager.opening_needs_confirm = false
		var t2 := create_tween()
		t2.tween_method(_set_fade_alpha, 0.85, 0.0, 0.30)
		await t2.finished
		day_intro_label.visible = false
		if player: player.can_move = true
		return

	var t3 := create_tween()
	t3.tween_method(_set_fade_alpha, 0.0, 0.85, 0.18)
	await t3.finished
	await get_tree().create_timer(3.0).timeout
	var t4 := create_tween()
	t4.tween_method(_set_fade_alpha, 0.85, 0.0, 0.28)
	await t4.finished
	day_intro_label.visible = false

func _on_wife_entered(body):
	if body == player:
		subtitle.text = GameManager.get_wife_line()
		subtitle.visible = true
		await get_tree().create_timer(2.5).timeout
		subtitle.visible = false

func _on_bed_entered(body):
	if body == player:
		GameManager.end_day()

func _on_exit_triggered(body):
	if body == player:
		if GameManager.came_from_cave:
			# показать короткую подсказку и не пускать
			var lbl := $CanvasLayer/Control/HintLabel if has_node($"CanvasLayer/Control/HintLabel".get_path()) else $CanvasLayer/Subtitles
			if lbl:
				lbl.text = "You need to rest"
				lbl.visible = true
				await get_tree().create_timer(2.0).timeout
				lbl.visible = false
			return
		get_tree().change_scene_to_packed(preload("res://scenes/Cave.tscn"))

func _on_leave_confirmed():
	GameManager.end_game("early")

func _on_day_started(_d):
	player.global_position = Vector3(0, 1, 0)
	player.can_move = true
	_update_ui()

func _on_day_ended(_d, _ore):
	player.can_move = false
	_update_ui()

func _update_ui():
	var need_today := GameManager.get_required_today()
	day_label.text = "Day: %d/%d" % [GameManager.current_day, GameManager.total_days]
	ore_label.text = "Ore: %d/%d" % [GameManager.total_ore, GameManager.ore_required_total]

	if hint_label:
		hint_label.text = "We need %d ore today. There are %d chances left before poverty." % [
			need_today, GameManager.chances_left
		]
