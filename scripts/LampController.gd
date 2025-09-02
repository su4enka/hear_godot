extends Node3D
class_name LampController

@export_node_path("MeshInstance3D") var bulb_mesh_path
@export var emissive_surface := 1
@export_node_path("OmniLight3D") var light_path

# Визуальные параметры
@export var on_albedo := Color(1.0, 0.95, 0.55)
@export var off_albedo := Color(0.02, 0.02, 0.02)
@export var on_emission := Color(1.0, 0.95, 0.65)
@export var on_energy := 2.0
@export var off_energy := 0.0
@export var mat_energy_scale := 1.0

# База яркости (0.5..1.0 от on_energy)
@export var base_energy_rand := Vector2(0.5, 1.0)
@export var randomize_each_turn_on := false

# Фликер (бесконечный цикл)
@export var flicker_on_start := false
@export var flicker_amp := 0.35                         # глубина просадки (0..1)
@export var flicker_zero_chance := 0.08                 # шанс «в ноль»
@export var flicker_change_range := Vector2(0.08, 0.25) # период смены цели (сек)
@export var flicker_speed := 1.0                        # множитель частоты (>1=чаще)
@export var flicker_interp_up := 10.0                   # скорость возврата к базе
@export var flicker_interp_down := 6.0                  # скорость провала

@export var debug_flicker := false

# Группы/состояния
@export var start_enabled := false
@export var auto_register_in_group := true

var _enabled := false
var _flicker := false
var _bulb: MeshInstance3D
var _light: OmniLight3D
var _mat: StandardMaterial3D

var _base_energy := 1.0
var _cur_energy := 0.0
var _target_energy := 0.0
var _time_left := 0.0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if auto_register_in_group:
		add_to_group("lamps")

	# важно: всегда тикаем, даже под паузой/оверлеем
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

	_rng.randomize()

	_bulb = get_node_or_null(bulb_mesh_path) as MeshInstance3D
	_light = get_node_or_null(light_path) as OmniLight3D
	_mat = _get_or_make_unique_material(_bulb, emissive_surface)

	_base_energy = on_energy * _rng.randf_range(base_energy_rand.x, base_energy_rand.y)
	_cur_energy = 0.0
	_target_energy = _base_energy
	_time_left = 0.0

	if start_enabled:
		turn_on(flicker_on_start)
	else:
		turn_off()

# ---------- API ----------
func turn_on(with_flicker := true) -> void:
	if randomize_each_turn_on:
		_base_energy = on_energy * _rng.randf_range(base_energy_rand.x, base_energy_rand.y)

	_enabled = true
	_flicker = with_flicker

	_cur_energy = _base_energy
	_target_energy = _base_energy
	_time_left = 0.0
	_apply_energy(_cur_energy)
	if debug_flicker: print("[Lamp] ON base=%.3f flicker=%s" % [_base_energy, str(_flicker)])

func turn_off() -> void:
	_enabled = false
	_flicker = false
	_cur_energy = 0.0
	_target_energy = 0.0
	_apply_energy(0.0)
	_set_light_energy(off_energy)
	_set_mat_state(false, off_albedo, Color.BLACK, 0.0)
	if debug_flicker: print("[Lamp] OFF")

func start_flicker() -> void:
	_flicker = true
	_time_left = 0.0
	if debug_flicker: print("[Lamp] start_flicker")

func stop_flicker() -> void:
	_flicker = false
	_target_energy = _base_energy
	if debug_flicker: print("[Lamp] stop_flicker → settle to base")

func is_flickering() -> bool:
	return _flicker

# ---------- процесс ----------
func _process(delta: float) -> void:
	if not _enabled:
		return

	# 1) Переодическая смена цели
	if _flicker:
		_time_left -= delta * max(0.05, flicker_speed)
		if _time_left <= 0.0:
			var drop := _rng.randf_range(0.0, flicker_amp)
			var new_target := _base_energy * (1.0 - drop)
			if _rng.randf() < flicker_zero_chance:
				new_target = 0.0
			_target_energy = new_target
			_time_left = _rng.randf_range(flicker_change_range.x, flicker_change_range.y)
			if debug_flicker: print("[Lamp] target=%.3f, next in %.2fs" % [_target_energy, _time_left])
	else:
		_target_energy = _base_energy

	# 2) Плавное догоняние цели
	var going_down := _target_energy < _cur_energy
	var rate := (flicker_interp_down if going_down else flicker_interp_up)
	var alpha := 1.0 - exp(-rate * delta)
	_cur_energy = lerp(_cur_energy, _target_energy, alpha)

	# 3) Применяем
	_apply_energy(_cur_energy)

# ---------- утилиты ----------
func _apply_energy(value: float) -> void:
	_set_light_energy(value)
	if _mat:
		var on := value > 0.03
		_mat.emission_enabled = on
		_mat.albedo_color = on_albedo if on else off_albedo
		_mat.emission = on_emission
		_mat.emission_energy_multiplier = value * mat_energy_scale

func _set_light_energy(e: float) -> void:
	if _light:
		_light.light_energy = e

func _set_mat_state(on: bool, albedo: Color, emission_col: Color, emission_energy: float) -> void:
	if not _mat: return
	_mat.albedo_color = albedo
	_mat.emission_enabled = on
	_mat.emission = emission_col
	_mat.emission_energy_multiplier = emission_energy

func _get_or_make_unique_material(mi: MeshInstance3D, surface_idx: int) -> StandardMaterial3D:
	if not mi or not mi.mesh: return null
	var m: Material = mi.get_surface_override_material(surface_idx)
	if m == null: m = mi.mesh.surface_get_material(surface_idx)
	if m == null: return null
	var unique := m.duplicate(true)
	unique.resource_local_to_scene = true
	mi.set_surface_override_material(surface_idx, unique)
	return unique as StandardMaterial3D
