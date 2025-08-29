extends Node3D

# === Loudness Tuning ===
@export var master_drop_db := -18.0     # сколько dB теряем на Master при полной глухоте (день 15)
@export var warn_base_db := -10.0       # базовая громкость warning (день 1), ДО дистанции
@export var warn_drop_db := -14.0       # сколько dB теряет warning к дню 15 (добавляется к base)
@export var warn_min_db := -48.0        # ограничение снизу на warning (чтоб не падал в -∞)

# (опц.) дистанция: сколько дБ терять, если игрок далеко от входа пути
@export var dist_near := 3.0            # до 3м – «рядом»
@export var dist_far := 6.0             # дальше 6м – «далеко»
@export var dist_near_db := 0.0         # добавка к dB, если рядом
@export var dist_mid_db := -3.0         # средняя дистанция
@export var dist_far_db := -6.0         # далеко

@export var ore_per_node := 1
@export var min_collapse_time := 20.0
@export var max_collapse_time := 30.0
@export var warning_time := 5.0
@export var min_warning_gap := 5.0  # минимум секунд между стартами warning’ов

@export var false_warning_chance := 0.40   # 1 из 4 ложных миганий
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
@onready var ore_label: Label = $CanvasLayer/Control/OreCounter
@onready var walls_container: Node3D = $"Level Assets/Cave/Collapse Walls"

const PATH_PITCH := { "Path1": 1.00, "Path2": 0.92, "Path3": 1.08 } # полутон вниз/вверх
const DEFAULT_PITCH := 1.0

var _next_warning_allowed_at := 0.0
var _kill_scheduled := false

var path_timers := {}
var path_warnings := {}
var player_alive := true
var _warning_light_by_path: Dictionary = {}   # path -> Light3D

func _ready():
	if Engine.has_singleton("Rumble"):
		Rumble.enter_context("cave")
	randomize()
	GameManager.day_started.connect(_on_day_started)
	exit_trigger.body_entered.connect(_on_exit_triggered)
	_setup_day()
	if not GameManager.ore_collected.is_connected(_on_ore_added):
		GameManager.ore_collected.connect(_on_ore_added)
	_refresh_ore_ui()  # показать стартовые значения при входе в пещеру

func _compute_master_db() -> float:
	# deafness_level 0..1 (пересчитывается в GameManager по дню)
	# 0 → 0 dB, 1 → master_drop_db (например -18 dB)
	return lerp(0.0, master_drop_db, GameManager.deafness_level)

func _compute_warning_db(path: Path3D) -> float:
	# День → громкость warning: на 1-м дне warn_base_db, на 15-м warn_base_db + warn_drop_db
	var warn_day_db = warn_base_db + lerp(0.0, warn_drop_db, GameManager.deafness_level)

	# Дистанция до входа пути → доп. поправка
	var d := _closest_distance_to_path(player.global_position, path)
	var dist_db := dist_near_db
	if d > dist_far:
		dist_db = dist_far_db
	elif d > dist_near:
		dist_db = dist_mid_db

	var total = warn_day_db + dist_db
	return max(total, warn_min_db)  # не тише, чем warn_min_db

func _setup_day():
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, _compute_master_db())
	
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
	var warning_timer := Timer.new()
	warning_timer.one_shot = true
	warning_timer.wait_time = randf_range(min_collapse_time, max_collapse_time) - warning_time
	warning_timer.timeout.connect(func():
		# --- разруливаем глобальный зазор между предупреждениями ---
		var now := Time.get_ticks_msec() / 1000.0
		if now < _next_warning_allowed_at:
			var wait_more := _next_warning_allowed_at - now
			await get_tree().create_timer(wait_more).timeout
		# старт этого предупреждения «занимает окно»
		_next_warning_allowed_at = (Time.get_ticks_msec() / 1000.0) + min_warning_gap

		# реальный варнинг (с лампой/пылью/звуком)
		_play_warning_fx(path, true)
		await get_tree().create_timer(warning_time).timeout
		_do_path_collapse(path)
	)
	add_child(warning_timer)

	# Ложное мигание без звука и обвала (иногда)
	if randf() < false_warning_chance:
		var false_timer := Timer.new()
		false_timer.one_shot = true
		false_timer.wait_time = max(0.8, warning_timer.wait_time * randf_range(0.35, 0.8))
		false_timer.timeout.connect(func():
			var old := flicker_time
			flicker_time = max(0.4, old * 0.7)
			_play_warning_fx(path, false)  # без звука
			flicker_time = old
		)
		add_child(false_timer)
		false_timer.start()


	warning_timer.start()
	
	var fx := _get_path_fx_multi(path)
	for l in fx.lights:
		# запустить в фоне; если хочешь, можешь не ждать
		_start_idle_flicker(l)

func _pitch_for_path(path: Node) -> float:
	return PATH_PITCH.get(path.name, DEFAULT_PITCH)

func _cutoff_by_distance(dist: float) -> float:
	# ближний — ясный (6кГц), дальний — глуше (1.2–2.5 кГц)
	if dist < 6.0:
		return 6000.0
	elif dist < 12.0:
		return 2500.0
	else:
		return 1200.0

func _get_wall_for_path(path: Node) -> Node3D:
	# 1) если есть отдельный контейнер стен (твоя текущая схема)
	if walls_container:
		var name := "%s Collapse Wall" % path.name
		var wall = walls_container.get_node_or_null(name)
		if wall:
			return wall as Node3D
	# 2) запасной вариант — если стену положишь прямо внутрь Path
	return path.get_node_or_null("CollapseWall") as Node3D

func _do_path_collapse(path: Path3D) -> void:
	if not player_alive:
		return

	var path3d := path as Path3D
	var will_kill := false

	# 1) решаем, убивает ли
	if path3d and path3d.curve:
		var closest := _closest_distance_to_path(player.global_position, path3d)
		if closest < 2.0:
			will_kill = true

	# 2) СНАЧАЛА роняем стену – всегда
	var wall := _get_wall_for_path(path)
	if wall:
		var start := wall.global_position
		var end := start + Vector3(0, -2.5, 0)
		var tw := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(wall, "global_position", end, 0.5)

	# 3) Смерть планируем таймером, не блокируя и без return
	if will_kill and not _kill_scheduled:
		_kill_scheduled = true
		var t := get_tree().create_timer(3.0)  # задержка перед смертью
		t.timeout.connect(func():
			_kill_player()
			_kill_scheduled = false   # на всякий, если вернёшься в пещеру тем же инстансом
		)

func _get_path_fx_multi(path: Node3D) -> Dictionary:
	var lights: Array[Light3D] = []
	var dusts: Array[CPUParticles3D] = []

	for child in path.get_children():
		if child is Light3D and String(child.name).begins_with("WarningLight"):
			lights.append(child)
		elif child is CPUParticles3D and String(child.name).begins_with("Dust"):
			dusts.append(child)

	# бэкап на случай единичных имён без чисел
	var one_light := path.get_node_or_null("WarningLight")
	if one_light and one_light is Light3D and not lights.has(one_light):
		lights.append(one_light)

	var one_dust := path.get_node_or_null("Dust")
	if one_dust and one_dust is CPUParticles3D and not dusts.has(one_dust):
		dusts.append(one_dust)

	return {"lights": lights, "dusts": dusts}

func _choose_warning_light_for_path(path: Node3D, lights: Array[Light3D]) -> Light3D:
	# 1) Явно помеченная лампа
	for l in lights:
		if String(l.name).to_lower().contains("entrance"):
			return l
	# 2) Ближайшая к началу кривой/path origin
	var best = null
	var best_d := INF
	for l in lights:
		var d := l.global_position.distance_to(path.global_position)
		if d < best_d:
			best_d = d
			best = l
	return best

func _get_warning_light(path: Node3D, lights: Array[Light3D]) -> Light3D:
	if _warning_light_by_path.has(path):
		var cached = _warning_light_by_path[path]
		if is_instance_valid(cached):
			return cached
	var picked := _choose_warning_light_for_path(path, lights)
	_warning_light_by_path[path] = picked
	return picked

func _pick_fake_light(path: Node3D, lights: Array[Light3D], real: Light3D) -> Light3D:
	var pool: Array[Light3D] = []
	for l in lights:
		if l != real:
			pool.append(l)
	if pool.is_empty():
		return real
	return pool[randi() % pool.size()]

func _ensure_base_energy(l: Light3D):
	if not l.has_meta("base_energy"):
		l.set_meta("base_energy", l.light_energy)

func _start_idle_flicker(l: Light3D) -> void:
	_ensure_base_energy(l)
	l.set_meta("idle_on", true)
	await _idle_flicker_loop(l)

func _idle_flicker_loop(l: Light3D) -> void:
	while is_instance_valid(l) and l.get_meta("idle_on", false):
		# если варнинговый фликер активен – подождать
		if l.get_meta("warning_running", false):
			await get_tree().create_timer(0.05).timeout
			continue

		var base := float(l.get_meta("base_energy"))
		var delta := randf_range(0.08, 0.28)    # сила шумка
		var up_dur := randf_range(0.12, 0.35)
		var down_dur := randf_range(0.12, 0.35)
		var wait_dur := randf_range(0.4, 1.6)

		var tw := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(l, "light_energy", base + delta, up_dur)
		tw.tween_property(l, "light_energy", base, down_dur)
		await tw.finished

		await get_tree().create_timer(wait_dur).timeout

func _play_warning_fx(path: Node3D, with_sound: bool) -> void:
	var fx := _get_path_fx_multi(path)
	var lights: Array = fx.lights
	var dusts: Array = fx.dusts
	
# --- ЗВУК ---
	if with_sound and collapse_warning and collapse_warning.stream:
		var p := AudioStreamPlayer3D.new()
		p.stream = collapse_warning.stream
		var path3d := path as Path3D
		p.global_position = _sound_position_for_path(path3d)
		p.bus = "Warning"

		# новая единая формула
		p.volume_db = _compute_warning_db(path3d)

		# остальное как у тебя (pitch, cutoff, unit_size и т.п.)
		p.pitch_scale = _pitch_for_path(path) * randf_range(0.98, 1.02)

		# по желанию можешь оставить/подкрутить фильтр по дистанции
		var d := _closest_distance_to_path(player.global_position, path3d)
		if d > dist_far:
			p.attenuation_filter_cutoff_hz = 1200.0
		elif d > dist_near:
			p.attenuation_filter_cutoff_hz = 2500.0
		else:
			p.attenuation_filter_cutoff_hz = 5000.0

		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()

	# пыль – всем Dust* под путём
	for d in dusts:
		d.emitting = true
	await get_tree().create_timer(dust_time).timeout
	for d in dusts:
		d.emitting = false

	# лампы
	if lights.size() == 0:
		return

	# реальный варнинг → мигает одна «входная»
	if with_sound:
		var real_light: Light3D = _get_warning_light(path, lights)
		if real_light:
			_ensure_base_energy(real_light)
			real_light.set_meta("warning_running", true)  # пауза idle
			var t := 0.0
			# начинаем с включения
			real_light.visible = true
			while t < flicker_time:
				real_light.visible = not real_light.visible
				await get_tree().create_timer(flicker_interval).timeout
				t += flicker_interval
			# по окончании — оставить выключенной
			real_light.visible = false
			real_light.set_meta("warning_running", false)
	else:
		# ложный варнинг → мигает ДРУГАЯ лампа, и возвращаем исходное состояние
		var real_light := _get_warning_light(path, lights)
		var fake_light := _pick_fake_light(path, lights, real_light)
		if fake_light:
			_ensure_base_energy(fake_light)
			var was_vis := fake_light.visible
			fake_light.set_meta("warning_running", true)
			var t := 0.0
			# начинаем с текущего состояния
			while t < max(0.3, flicker_time):  # длительность может отличаться
				fake_light.visible = not fake_light.visible
				await get_tree().create_timer(flicker_interval).timeout
				t += flicker_interval
			# ВАЖНО: вернуть как было (не оставлять тухлой)
			fake_light.visible = was_vis
			fake_light.set_meta("warning_running", false)

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
	_do_path_collapse(path)

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

func _on_ore_added(_amount:int) -> void:
	_refresh_ore_ui()

func _sound_position_for_path(path: Path3D) -> Vector3:
	if path.curve and path.curve.get_baked_length() > 0:
		var dist = min(3.0, path.curve.get_baked_length() * 0.15) # 3м или 15% пути
		var pos_local := path.curve.sample_baked(dist)
		return path.to_global(pos_local)
	return path.global_position

func _refresh_ore_ui() -> void:
	if not ore_label:
		return
	ore_label.text = "Ore: %d/%d" % [
		GameManager.ore_collected_today,
		GameManager.get_required_today()
	]

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
