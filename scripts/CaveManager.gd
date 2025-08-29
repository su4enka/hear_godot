extends Node3D

@export var ore_per_node := 1
@export var min_collapse_time := 30.0
@export var max_collapse_time := 60.0
@export var warning_time := 5.0

@export var false_warning_chance := 0.25   # 1 из 4 ложных миганий
@export var flicker_time := 1.2            # сколько секунд мигает лампа перед обвалом
@export var flicker_interval := 0.12       # как часто переключаем свет
@export var dust_time := 1.5               # сколько секунд летят пылинки
@onready var collapse_warning = $CollapseWarning
@onready var player = $Player
@onready var ore_container = $OreContainer
@onready var paths_container = $PathsContainer
@onready var deafness_bar = $CanvasLayer/Control/DeafnessIndicator
@onready var death_screen = $DeathScreen
@onready var exit_trigger = $ExitTrigger

var path_timers := {}
var path_warnings := {}
var player_alive := true

func _ready():
	randomize()
	GameManager.day_started.connect(_on_day_started)
	exit_trigger.body_entered.connect(_on_exit_triggered)
	_setup_day()
	
func _setup_day():
	var db := -18.0 * GameManager.deafness_level
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, db)
	
	# Clear previous day
	for child in ore_container.get_children():
		child.queue_free()
	
	# Clear old timers
	for timer in path_timers.values():
		timer.queue_free()
	for timer in path_warnings.values():
		timer.queue_free()
	path_timers.clear()
	path_warnings.clear()
	
	player_alive = true
	death_screen.visible = false
	
	# Hide all paths initially
	var all_paths: Array = paths_container.get_children()
	for p in all_paths:
		if p is Node3D:
			p.visible = false
			# если ты красишь путь цветом — сделай это на меше внутри пути,
			# но оставлю как было у тебя, если работает:
			if "modulate" in p:
				p.modulate = Color.WHITE
	
	# Select 2-3 random paths
	all_paths.shuffle()
	var path_count := randi_range(2, 3)
	var active_paths = []
	
	for i in range(min(path_count, all_paths.size())):
		var p: Path3D = all_paths[i]
		active_paths.append(p)
		p.visible = true
		_setup_path_collapse(p)

	_spawn_ore_nodes(active_paths)
	
	# Update UI
	deafness_bar.value = GameManager.deafness_level * 100.0
	$CanvasLayer/Control/DayCounter.text = "Day: %d" % GameManager.current_day
	$CanvasLayer/Control/OreCounter.text = "Ore: %d/%d" % [
	GameManager.ore_collected_today,
	GameManager.get_required_today()
]
	
func _setup_path_collapse(path: Path3D):
# Таймер настоящего обвала
	var collapse_timer = Timer.new()
	collapse_timer.wait_time = randf_range(min_collapse_time, max_collapse_time)
	collapse_timer.one_shot = true
	collapse_timer.timeout.connect(_on_path_collapse.bind(path))
	add_child(collapse_timer)
	path_timers[path] = collapse_timer

	# Таймер предупреждения перед обвалом (свет+пыль+звук)
	var warning_timer = Timer.new()
	warning_timer.wait_time = max(0.05, collapse_timer.wait_time - warning_time)
	warning_timer.one_shot = true
	warning_timer.timeout.connect(func():
		# визуал+звук
		_play_warning_fx(path, true)
		# старый коллбек на звук у тебя тоже был — если нужно оставь:
		_on_path_warning(path)
	)
	add_child(warning_timer)
	path_warnings[path] = warning_timer

	# Иногда запускаем "ложное" мигание ЗАРАНЕЕ без звука и без обвала
	if randf() < false_warning_chance:
		var false_timer := Timer.new()
		# пусть срабатывает где-то в первой трети времени до настоящего варнинга
		false_timer.wait_time = warning_timer.wait_time * randf_range(0.2, 0.5)
		false_timer.one_shot = true
		false_timer.timeout.connect(func():
			_play_warning_fx(path, false))  # визуально, но без collapse и без SFX
		add_child(false_timer)
		false_timer.start()
	
	warning_timer.start()
	collapse_timer.start()

func _get_path_fx(path: Node3D) -> Dictionary:
	var light := path.get_node_or_null("WarningLight")
	var dust := path.get_node_or_null("Dust")
	return {"light": light, "dust": dust}

func _play_warning_fx(path: Node3D, with_sound: bool):
	var fx := _get_path_fx(path)
	var light = fx.light
	var dust = fx.dust

	# звук с учётом глухоты
	if with_sound and collapse_warning:
		collapse_warning.global_position = path.global_position
		collapse_warning.volume_db = -20.0 + (GameManager.deafness_level * 30.0)
		collapse_warning.play()

	# пыль
	if dust and dust is CPUParticles3D:
		dust.emitting = true
		await get_tree().create_timer(dust_time).timeout
		dust.emitting = false

	# мигание лампы
	if light and light is Light3D:
		light.visible = true
		var t := 0.0
		while t < flicker_time:
			light.visible = not light.visible
			await get_tree().create_timer(flicker_interval).timeout
			t += flicker_interval
		light.visible = false

func _spawn_ore_nodes(active_paths: Array):
	# Spawn ore along active paths
	for path in active_paths:
		var path3d := path as Path3D
		if path3d == null or path3d.curve == null:
			continue

		var curve: Curve3D = path3d.curve
		var length := curve.get_baked_length()
		if length <= 0.0:
			continue

		for i in range(3):
			var ore: Node3D = preload("res://scenes/Ore.tscn").instantiate()
			var progress := float(i + 1) / 4.0
			var dist := progress * length
			var pos_local: Vector3 = curve.sample_baked(dist)
			var pos_global: Vector3 = path3d.to_global(pos_local)
			ore.global_position = pos_global + Vector3(0, 0.5, 0)
			ore_container.add_child(ore)
			if ore.has_signal("collected") and not ore.collected.is_connected(_on_ore_collected):
				ore.collected.connect(_on_ore_collected)
	
func _on_day_started(day):
	_setup_day()
	
func _on_ore_collected(amount):
	GameManager.ore_collected_today += amount
	GameManager.total_ore += amount
	$CanvasLayer/Control/OreCounter.text = "Ore: %d/%d" % [
	GameManager.ore_collected_today,
	GameManager.get_required_today()
]
	
func _on_path_warning(path: Path3D):
	# Play warning sound for this specific path
	collapse_warning.global_position = path.global_position
	collapse_warning.volume_db = -20 + (GameManager.deafness_level * 30)
	collapse_warning.play()
	
	
func _on_path_collapse(path: Path3D):
	if not player_alive:
		return
	var path3d := path as Path3D
	if path3d == null or path3d.curve == null:
		return

	var closest_dist := _closest_distance_to_path(player.global_position, path3d)
	if closest_dist < 2.0:
		_kill_player()
	else:
		if "modulate" in path:
			path.modulate = Color.DARK_GRAY

func _closest_distance_to_path(point: Vector3, path: Path3D) -> float:
	var curve: Curve3D = path.curve
	# лучше использовать baked длину + выборку по дистанции
	var length := curve.get_baked_length()
	if length <= 0.0:
		return point.distance_to(path.global_position)

	var samples := 40 # чем больше, тем точнее и чуть дороже
	var best := INF
	for i in range(samples + 1):
		var t := float(i) / float(samples)              # 0..1
		var dist := t * length                          # дистанция вдоль кривой
		var local := curve.sample_baked(dist)           # точка в ЛОКАЛЬНЫХ координатах пути
		var world := path.to_global(local)              # переводим в глобальные
		var d := point.distance_to(world)
		if d < best:
			best = d
	return best

func _kill_player():
	player_alive = false
	death_screen.visible = true
	
	# Wait 2 seconds then game over
	await get_tree().create_timer(2.0).timeout
	GameManager.end_game("bad")

func _on_exit_triggered(body):
	if body.is_in_group("player"):
		GameManager.came_from_cave = true
		get_tree().change_scene_to_file("res://scenes/House.tscn")
