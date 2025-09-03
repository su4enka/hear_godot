extends Node3D
class_name TrailerParkManager

# — окружение —
@onready var world_env: WorldEnvironment     = $WorldEnvironment
@onready var sun: DirectionalLight3D         = $DirectionalLight3D

# — спавны игрока —
@onready var player: Node3D                  = $Player
@onready var camera_3d: Camera3D             = $Player/Camera3D
@onready var spawn_door: Node3D              = $Spawns/SpawnDoor   # «вышел из дома»
@onready var spawn_bus: Node3D               = $Spawns/SpawnBus    # «приехал из пещеры (автобус)»

# — интеракции —
@onready var bus_trigger: Area3D             = $Bus/ExitTrigger
@onready var door_trigger: Area3D            = $HouseDoor/ExitTrigger
@onready var hint_label: Label               = $CanvasLayer/Control/HintLabel

# День/ночь как в доме
@export var day_sky_horizon  := Color(0.66, 0.67, 0.69)
@export var day_ground_horizon := Color(0.66, 0.67, 0.69)
@export var night_sky_horizon := Color(0.03, 0.05, 0.10)
@export var night_ground_horizon := Color(0.02, 0.03, 0.05)
@export var day_sun_energy := 1.0
@export var night_sun_energy := 0.08

func _ready() -> void:
	# чтобы игрок мог "видеть" оба триггера как exit — и мы решим, что именно
	if not bus_trigger.is_in_group("exit"):
		bus_trigger.add_to_group("exit")
	if not door_trigger.is_in_group("exit"):
		door_trigger.add_to_group("exit")

	# Спавн: если пришли из пещеры — возле автобуса, иначе — у двери дома
	if GameManager.came_from_cave:
		_place_player(spawn_bus)
	else:
		_place_player(spawn_door)

	# День/ночь: после пещеры — ночь, иначе — день
	_apply_outdoor(not GameManager.came_from_cave)

	# фоновый гул (если пользуешься)
	Rumble.enter_context("house")  # можно завести отдельный "park", если нужно

func _place_player(marker: Node3D) -> void:
	if not marker or not player: return
	player.global_transform = marker.global_transform
	if "velocity" in player: player.velocity = Vector3.ZERO

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

func _show_hint(text: String, secs := 2.0) -> void:
	if hint_label:
		hint_label.text = text
		hint_label.visible = true
		await get_tree().create_timer(secs).timeout
		if is_instance_valid(hint_label):
			hint_label.visible = false

# Важно: Player зовёт request_exit() на корневом узле сцены, когда видит группу "exit".
# Мы сами определим, это автобус или дверь.
func request_exit() -> void:
	var ray: RayCast3D = player.get_node_or_null("Camera3D/InteractRay")
	if not ray:
		return
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var hit := ray.get_collider()
	var n: Node = hit

	var hit_bus := false
	var hit_door := false
	while n:
		if n == bus_trigger or n.is_in_group("bus"):
			hit_bus = true
		if n == door_trigger or n.is_in_group("house_door"):
			hit_door = true
		n = n.get_parent()

	# 1) Автобус -> Пещера (только если ещё НЕ были в пещере сегодня)
	if hit_bus:
		if GameManager.came_from_cave:
			await _show_hint("You need to rest", 2.0)
			return
		GameManager.came_from_cave = true   # помечаем, что сегодня уже поехали
		get_tree().change_scene_to_file("res://scenes/Cave.tscn")
		return

	# 2) Дверь -> Дом
	if hit_door:
		# Если возвращаемся после пещеры — попросим Дом включить «приехали домой»
		if GameManager.came_from_cave:
			GameManager.just_returned_home = true
		get_tree().change_scene_to_file("res://scenes/House.tscn")
		return
