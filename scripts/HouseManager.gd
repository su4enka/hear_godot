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

func _ready():
	GameManager.day_intro.connect(_on_day_intro)
	GameManager.day_started.connect(_on_day_started)
	GameManager.day_ended.connect(_on_day_ended)
	exit_trigger.body_entered.connect(_on_exit_triggered)
	bed_area.body_entered.connect(_on_bed_entered)
	leave_dialog.confirmed.connect(_on_leave_confirmed) # кнопка OK = уехать
	_update_ui()

func _on_day_intro(text:String):
	day_intro_label.text = text
	fade_rect.modulate.a = 0.0
	day_intro_label.visible = true
	var t := create_tween()
	t.tween_property(fade_rect, "modulate:a", 0.8, 0.4)
	await t.finished
	await get_tree().create_timer(0.8).timeout
	var t2 := create_tween()
	t2.tween_property(fade_rect, "modulate:a", 0.0, 0.4)
	await t2.finished
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
	day_label.text = "Day: %d/%d" % [GameManager.current_day, GameManager.total_days]
	ore_label.text = "Ore: %d / need %d (total %d)" % [GameManager.ore_collected_today, GameManager.get_required_today(), GameManager.total_ore]
