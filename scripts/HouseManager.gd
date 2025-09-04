extends Node3D


@export var wife_spawn_scale := Vector3(1.5, 1.5, 1.5)
@export_node_path("Node3D") var wife_root_path
@export_node_path("Node") var spawn_container_path

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $DirectionalLight3D

@onready var wife_root := get_node(wife_root_path) as Node3D
@onready var wife_ctrl := wife_root.get_node_or_null("WifeController") as WifeController
@onready var spawn_container := get_node(spawn_container_path)

@export var day_sky_horizon  := Color(0.66, 0.67, 0.69)
@export var day_ground_horizon := Color(0.66, 0.67, 0.69)
@export var night_sky_horizon := Color(0.03, 0.05, 0.10)
@export var night_ground_horizon := Color(0.02, 0.03, 0.05)
@export var day_sun_energy := 1.0
@export var night_sun_energy := 0.08


@onready var player = $Player
@onready var camera_3d: Camera3D = $Player/Camera3D

@onready var spawn_bed: Node3D  = $Spawns/SpawnBed
@onready var spawn_door: Node3D = $Spawns/SpawnDoor
var _spawn_done := false

@onready var shower_knobs: StaticBody3D = $ShowerKnobs
@onready var toilet_area: Area3D = $Toilet/Area3D
@onready var shower_area: Area3D = $ShowerKnobs/Area3D
@onready var bed_area = $Bed/Area3D
@onready var exit_trigger = $Door/ExitTrigger
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

var _suppress_cancel_leave2 := false
var _suppress_cancel_leave1 := false

var _pee_busy := false
var _shower_busy := false




func _ready():
	if is_instance_valid(wife_root):
		wife_ctrl = _find_wife_controller(wife_root)
	print("[House] wife_ctrl is WifeController:", wife_ctrl is WifeController)

# Выберем точку в зависимости от фазы
	var phase := WifeSpawnPoint.Phase.AFTER_CAVE if GameManager.came_from_cave else WifeSpawnPoint.Phase.MORNING
	_place_wife_for_phase(phase)

# При старте нового дня — снова рандомим точку для утра
	GameManager.day_started.connect(func(_d):
		_place_wife_for_phase(WifeSpawnPoint.Phase.MORNING))


	# СПАВН: если пришли из пещеры — у двери, иначе — у кровати
	if GameManager.came_from_cave or GameManager.came_from_street:
		_place_player(spawn_door)
		GameManager.came_from_street = false
	else:
		_place_player(spawn_bed)
	
	# чтобы следующий заход в дом считался «обычным»
	_spawn_done = true
	GameManager.day_started.connect(_on_day_started)
	
	# День при чистом старте, ночь — если вернулись из пещеры
	_apply_outdoor(not GameManager.came_from_cave)
	
	Rumble.enter_context("house")
	
	if not wife_area.is_in_group("wife"):
		wife_area.add_to_group("wife")
	if not bed_area.is_in_group("bed"):
		bed_area.add_to_group("bed")
	if not exit_trigger.is_in_group("exit"):
		exit_trigger.add_to_group("exit")
	if not shower_area.is_in_group("shower"):
		shower_area.add_to_group("shower")
	if not toilet_area.is_in_group("toilet"):
		toilet_area.add_to_group("toilet")
	
		# Подключаемся к сигналам от автолоада
	GameManager.day_intro.connect(_on_day_intro)
	if day_intro_label:
		day_intro_label.visible = false
	# Показать баннер ТОЛЬКО на самом первом старте игры
# (не при входе с улицы/из пещеры)
	if GameManager.intro_queued and not GameManager.came_from_cave and not GameManager.came_from_street:
		GameManager.intro_queued = false
		await get_tree().process_frame
		_on_day_intro("Day %d" % GameManager.current_day)
	GameManager.day_ended.connect(_on_day_ended)
	

	# ТРИГГЕРЫ
	leave_dialog.confirmed.connect(_on_leave_dialog_confirmed)
	leave_dialog.canceled.connect(_on_leave_dialog_canceled)
	leave_dialog2.confirmed.connect(_on_leave_dialog2_confirmed)
	leave_dialog2.canceled.connect(_on_leave_dialog2_canceled)
	leave_dialog2.close_requested.connect(_on_leave_dialog2_close)
	
	# Безопасная инициализация интро-оверлея — на случай если сигнал пролетел до подключения

	_update_ui()
	
	
	# ГАРАНТИЯ ПОКАЗА интро в House:
	# если Menu уже вызвало GameManager.start_new_day() ДО смены сцены,
	# сигнал мог уйти раньше — покажем вручную текущий день.
	if GameManager.just_returned_home:
		var lm := get_node_or_null("HouseLights") # путь до узла с HouseLights.gd
		if lm:
			lm.lights_on_arrival()
		GameManager.just_returned_home = false  # «съели» маркер
		
func _find_wife_controller(root: Node) -> WifeController:
	if root == null:
		return null
	if root is WifeController:
		return root
	for child in root.get_children():
		var found := _find_wife_controller(child)
		if found:
			return found
	return null

func _apply_outdoor(is_day: bool) -> void:
	if world_env and world_env.environment and world_env.environment.sky:
		var mat := world_env.environment.sky.sky_material
		if mat is ProceduralSkyMaterial:
			var psm := mat as ProceduralSkyMaterial
			if is_day:
				psm.sky_horizon_color    = day_sky_horizon
				psm.ground_horizon_color = day_ground_horizon
			else:
				psm.sky_horizon_color    = night_sky_horizon
				psm.ground_horizon_color = night_ground_horizon
	if sun:
		sun.light_energy = day_sun_energy if is_day else night_sun_energy

func _pick_weighted(points: Array[WifeSpawnPoint]) -> WifeSpawnPoint:
	var sum := 0.0
	for p in points: sum += p.weight
	var r = randf() * max(sum, 0.0001)
	for p in points:
		r -= p.weight
		if r <= 0.0: return p
	return points.back()

func _place_wife_for_phase(phase: int) -> void:

	if not is_instance_valid(spawn_container) or not is_instance_valid(wife_root): return

	var candidates: Array[WifeSpawnPoint] = []
	for c in spawn_container.get_children():
		if c is WifeSpawnPoint:
			var sp := c as WifeSpawnPoint
			if sp.phase == phase or sp.phase == WifeSpawnPoint.Phase.ANY:
				candidates.append(sp)

	if candidates.is_empty(): return

	var point := _pick_weighted(candidates)
	wife_root.global_transform = point.global_transform
	wife_root.scale = wife_spawn_scale
	if wife_ctrl:
		wife_ctrl.play_idle(point.idle)
	# сохраним флаг — можно ли крутить голову на этой позе
	wife_root.set_meta("wife_look_enabled", point.look_at_on_interact)



func _place_player(marker: Node3D) -> void:
	if not marker or not player: return
	# переносим позицию и ориентацию игрока 1-в-1 как у маркера
	player.global_transform = marker.global_transform
	player.velocity = Vector3.ZERO
	player.call_deferred("reset_physics_interpolation") # опционально, если дёргается кадр

func request_wife_talk() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
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

	# длительность самой реплики (без фейдов)
	var show_dur := _subtitle_time_for(line)


	_subtitle_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_subtitle_tween.tween_property(subtitle, "modulate:a", 1.0, 0.12)
	await _subtitle_tween.finished
	if not is_inside_tree(): return

	await _arm_skip()
	if not is_inside_tree(): return

	var t := 0.0
	while t < show_dur and not _advance_requested:
		await get_tree().process_frame
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
	var lm := get_node_or_null("HouseLights")
	lm.lights_off()

func request_exit() -> void:
	_cancel_subtitle_task()

	# диалог дня 7 — без изменений
	if GameManager.current_day == 7 \
		and not GameManager.early_used \
		and not GameManager.came_from_cave:
		leave_dialog.title = "Leave or Stay?"
		leave_dialog.dialog_text = "You can leave the cave life now. Will you stay home?"
		leave_dialog.popup_centered()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	# если уже были в пещере сегодня — не выпускаем из дома
	if GameManager.came_from_cave:
		var lbl := hint_label if hint_label else subtitle
		if lbl:
			lbl.text = "You need to rest"
			lbl.visible = true
			await get_tree().create_timer(2.0).timeout
			lbl.visible = false
		return

	# раньше тут было: GameManager.came_from_cave = true и переход в Cave
	# теперь выходим наружу — в трейлер-парк
	#get_tree().change_scene_to_file("res://scenes/TrailerPark.tscn")
	get_tree().change_scene_to_file("res://scenes/TrailerPark.tscn")



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
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameManager.early_used = true
	GameManager.end_game("early")

func _on_leave_dialog2_confirmed():
	# Leave = early ending
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameManager.early_used = true
	GameManager.end_game("early")


func _on_leave_dialog2_canceled():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if GameManager.came_from_cave:
		return  # уже были в пещере сегодня — никуда не идём
	get_tree().change_scene_to_file("res://scenes/Cave.tscn")

func _on_leave_dialog2_close():
	_suppress_cancel_leave2 = true
	leave_dialog2.hide()
	await get_tree().process_frame # дождаться, чтобы canceled пришёл после
	_suppress_cancel_leave2 = false

func _on_leave_confirmed():
	GameManager.end_game("early")

func _on_day_started(_d):
	
	
	
		# новый день после сна/кнопки Play — всегда у кровати
	_place_player(spawn_bed)
	
	player.can_move = true
	_update_ui()
	_apply_outdoor(true)

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

func request_pee() -> void:
	if _pee_busy:
		return
	_pee_busy = true

	var p: GPUParticles3D = camera_3d.get_node_or_null("PeeParticles")
	if p:
		p.emitting = true
	await get_tree().create_timer(3.0).timeout
	if p:
		p.emitting = false

	_pee_busy = false
	
func request_shower() -> void:
	if _shower_busy: return
	_shower_busy = true

	var p: GPUParticles3D = shower_knobs.get_node_or_null("ShowerParticles")
	if p:
		p.emitting = true
	await get_tree().create_timer(3.0).timeout
	if p:
		p.emitting = false

	_shower_busy = false
