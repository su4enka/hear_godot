extends Node3D

@onready var player = $Player
@onready var bed_area = $Bed/Area3D
@onready var exit_trigger = $ExitTrigger
@onready var day_label = $CanvasLayer/Control/DayCounter
@onready var ore_label = $CanvasLayer/Control/OreCounter
@onready var leave_dialog: ConfirmationDialog = $CanvasLayer/LeaveDialog
@onready var fade_rect := $CanvasLayer/DayIntro/Fade
@onready var day_intro_label := $CanvasLayer/DayIntro/Label
@onready var wife_area: Area3D = $Wife/Area3D
@onready var subtitle: Label = $CanvasLayer/Subtitles
@onready var hint_label: Label = $CanvasLayer/Control/HintLabel

func _ready():
	GameManager.day_intro.connect(_on_day_intro)
	GameManager.day_started.connect(_on_day_started)
	GameManager.day_ended.connect(_on_day_ended)
	exit_trigger.body_entered.connect(_on_exit_triggered)
	bed_area.body_entered.connect(_on_bed_entered)
	leave_dialog.confirmed.connect(_on_leave_confirmed) # кнопка OK = уехать
	_update_ui()

func _action_is_pressed() -> bool:
	# какие действия считаем "пропуском"
	return Input.is_action_just_pressed("interact") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _wait_for_skip() -> void:
	# ждём, пока игрок нажмёт любую "кнопку подтверждения"
	while true:
		await get_tree().process_frame
		if _action_is_pressed():
			return

func _on_day_intro(text:String):
	day_intro_label.text = text
	fade_rect.modulate.a = 0.0
	day_intro_label.visible = true
	# Пролог: держим экран до нажатия кнопки, затем плавно скрываем
	if GameManager.needs_opening_confirm():
		# (Опционально) заблокировать движение игрока на время пролога:
		if player: player.can_move = false
	
		# плавно затемняем фон и показываем надпись
		var t := create_tween()
		t.tween_property(fade_rect, "modulate:a", 0.85, 0.35)
		await t.finished
	
		# ждём подтверждения от игрока
		await _wait_for_skip()
	
		# снимаем флаг, чтобы больше не ждать подтверждения
		GameManager.opening_needs_confirm = false
	
		# скрываем пролог
		var t2 := create_tween()
		t2.tween_property(fade_rect, "modulate:a", 0.0, 0.35)
		await t2.finished
		day_intro_label.visible = false
	
		# (Опционально) вернуть управление
		if player: player.can_move = true
		return
	
	# Обычное "Day N": авто-показ ~3 сек и скрытие без интеракции
	var t3 := create_tween()
	t3.tween_property(fade_rect, "modulate:a", 0.85, 0.2)
	await t3.finished
	
	await get_tree().create_timer(3.0).timeout
	
	var t4 := create_tween()
	t4.tween_property(fade_rect, "modulate:a", 0.0, 0.3)
	await t4.finished
	day_intro_label.visible = false
	
	wife_area.body_entered.connect(func(b):
		if b == player:
			subtitle.text = GameManager.get_wife_line()
			subtitle.visible = true
			await get_tree().create_timer(2.5).timeout
			subtitle.visible = false)

func _on_bed_entered(body):
	if body == player:
		GameManager.end_day()

func _on_exit_triggered(body):
	if body == player:
		if GameManager.current_day >= GameManager.early_exit_day:
			leave_dialog.title = "Leave the town?"
			leave_dialog.dialog_text = "You can leave now. Do you want to leave?"
			leave_dialog.popup_centered()
		else:
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
