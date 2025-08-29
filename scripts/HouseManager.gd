extends Node3D

@onready var player = $Player
@onready var bed_area = $Bed/Area3D
@onready var exit_trigger = $ExitTrigger
@onready var day_label = $CanvasLayer/Control/DayCounter
@onready var ore_label = $CanvasLayer/Control/OreCounter
@onready var leave_dialog: ConfirmationDialog = $CanvasLayer/LeaveDialog
@onready var leave_dialog2: ConfirmationDialog = $CanvasLayer/LeaveDialog2

@onready var wife_area: Area3D = $Wife/Area3D
@onready var subtitle: Label = $CanvasLayer/Subtitles
@onready var hint_label: Label = $CanvasLayer/Control/HintLabel
@onready var fade_rect: ColorRect = $OverlayLayer/DayIntro/Fade
@onready var day_intro_label: Label = $OverlayLayer/DayIntro/Label

var _subtitle_tween: Tween
var _subtitle_task_running := false
var _advance_requested := false
var _skip_armed := false

func _ready():
	
	
	if not wife_area.is_in_group("wife"):
		wife_area.add_to_group("wife")
	if not bed_area.is_in_group("bed"):
		bed_area.add_to_group("bed")
	if not exit_trigger.is_in_group("exit"):
		exit_trigger.add_to_group("exit")
	
		# Подключаемся к сигналам от автолоада
	GameManager.day_intro.connect(_on_day_intro)
	GameManager.day_started.connect(_on_day_started)
	GameManager.day_ended.connect(_on_day_ended)

	# ТРИГГЕРЫ
	leave_dialog.confirmed.connect(_on_leave_dialog_confirmed)
	leave_dialog.canceled.connect(_on_leave_dialog_canceled)
	leave_dialog2.confirmed.connect(_on_leave_dialog2_confirmed)
	leave_dialog2.canceled.connect(_on_leave_dialog2_canceled)

	# Безопасная инициализация интро-оверлея — на случай если сигнал пролетел до подключения
	if day_intro_label:
		day_intro_label.visible = false

	_update_ui()

	# ГАРАНТИЯ ПОКАЗА интро в House:
	# если Menu уже вызвало GameManager.start_new_day() ДО смены сцены,
	# сигнал мог уйти раньше — покажем вручную текущий день.
	if not GameManager.came_from_cave:
		_on_day_intro("Day %d" % GameManager.current_day)

func request_wife_talk() -> void:
	if _subtitle_task_running:
		_advance_requested = true
		return
	_show_wife_line()

func _skip_actions_down() -> bool:
	return Input.is_action_pressed("ui_accept") \
		or Input.is_action_pressed("interact") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _skip_down() -> bool:
	return Input.is_action_pressed("ui_accept") \
		or Input.is_action_pressed("interact") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _arm_skip() -> void:
	var tree := get_tree()
	while _skip_down():
		await tree.process_frame
		if not is_inside_tree(): return
	_skip_armed = true

func _subtitle_time_for(text: String) -> float:
	var t := 2.5 + text.length() * 0.04
	return clamp(t, 2.5, 6.5)


func _action_is_pressed() -> bool:
	return Input.is_action_just_pressed("interact") \
		or Input.is_action_just_pressed("ui_accept") \
		or Input.is_action_just_pressed("ui_select") \
		or Input.is_action_just_pressed("ui_cancel") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _subtitle_wait_for_skip_or_timeout(timeout: float) -> void:
	var tree := get_tree()
	var t := 0.0
	while t < timeout:
		await tree.process_frame
		if not is_inside_tree(): return
		t += get_process_delta_time()
		if Input.is_action_just_pressed("ui_accept") \
		or Input.is_action_just_pressed("interact") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			break

func _show_wife_line() -> void:
	_subtitle_task_running = true
	_advance_requested = false
	_skip_armed = false

	if _subtitle_tween and _subtitle_tween.is_running():
		_subtitle_tween.kill()

	var line := GameManager.get_wife_line()
	subtitle.text = line
	subtitle.modulate.a = 0.0
	subtitle.visible = true

	_subtitle_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_subtitle_tween.tween_property(subtitle, "modulate:a", 1.0, 0.12)
	await _subtitle_tween.finished
	if not is_inside_tree(): return

	await _arm_skip()
	if not is_inside_tree(): return

	var dur := _subtitle_time_for(line)
	var tree := get_tree()
	var t := 0.0
	while t < dur and not _advance_requested:
		await tree.process_frame
		if not is_inside_tree(): return
		t += get_process_delta_time()
		if _skip_armed and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact")):
			break

	if _subtitle_tween and _subtitle_tween.is_running():
		_subtitle_tween.kill()
	_subtitle_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_subtitle_tween.tween_property(subtitle, "modulate:a", 0.0, 0.15)
	await _subtitle_tween.finished
	if is_instance_valid(subtitle):
		subtitle.visible = false

	_subtitle_task_running = false
	if _advance_requested and is_inside_tree():
		_show_wife_line()

func _wait_for_skip() -> void:
	while true:
		await get_tree().process_frame
		if _action_is_pressed():
			return

func _cancel_subtitle_task():
	_advance_requested = false
	_subtitle_task_running = false
	if _subtitle_tween and _subtitle_tween.is_running():
		_subtitle_tween.kill()
	if is_instance_valid(subtitle):
		subtitle.visible = false
		subtitle.modulate.a = 0.0

func _set_fade_alpha(a: float) -> void:
	var c = fade_rect.color
	c.a = a
	fade_rect.color = c

func _on_day_intro(text:String):
	day_intro_label.text = text
	day_intro_label.visible = true
	_set_fade_alpha(0.0)

	var t3 := create_tween()
	t3.tween_method(_set_fade_alpha, 0.0, 0.85, 0.18)
	await t3.finished
	await get_tree().create_timer(3.0).timeout
	var t4 := create_tween()
	t4.tween_method(_set_fade_alpha, 0.85, 0.0, 0.28)
	await t4.finished
	day_intro_label.visible = false

func request_sleep() -> void:
	GameManager.end_day()

func request_exit() -> void:
	_cancel_subtitle_task()
	
	if GameManager.current_day == 7 and not GameManager.early_used:
		leave_dialog.title = "Leave or Stay?"
		leave_dialog.dialog_text = "You can leave the cave life now. Will you stay home?"
		leave_dialog.popup_centered()
		return

	if GameManager.came_from_cave:
		var lbl := hint_label if hint_label else subtitle
		if lbl:
			lbl.text = "You need to rest"
			lbl.visible = true
			await get_tree().create_timer(2.0).timeout
			lbl.visible = false
		return

	get_tree().change_scene_to_packed(preload("res://scenes/Cave.tscn"))

func _exit_tree():
	_cancel_subtitle_task()

func _on_leave_dialog_canceled():
	# Continue = идти в пещеру
	leave_dialog2.title = "Are you sure"
	leave_dialog2.dialog_text = "Will you continue taking the risk in the cave?"
	leave_dialog2.popup_centered()
	return

func _on_leave_dialog_confirmed():
	# It's not worth it = early ending
	GameManager.early_used = true
	GameManager.end_game("early")

func _on_leave_dialog2_confirmed():
	# Leave = early ending
	GameManager.early_used = true
	GameManager.end_game("early")

func _on_leave_dialog2_canceled():
	# Continue = идти в пещеру
	get_tree().change_scene_to_file("res://scenes/Cave.tscn")

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
	ore_label.text = "Ore: %d/%d" % [GameManager.ore_collected_today, need_today]

	if GameManager.came_from_cave:
		hint_label.text = "You need to rest. Come back tomorrow."
	else:
		hint_label.text = "We need %d ore today. Chances before poverty: %d." % [
			need_today, GameManager.chances_left
		]
