extends Node3D
class_name WifeController

# --- Узлы ---
@export_node_path("Skeleton3D") var skeleton_path
@export_node_path("AnimationPlayer") var anim_player_path

# --- Имена костей (с твоими фолбэками) ---
@export var head_bone := "mixamorig_Head"
@export var neck_bone := "mixamorig_Neck"

# --- Параметры взгляда ---
@export var look_duration := 1.6             # если пользуешься таймером для одной реплики
@export var look_strength := 1.0             # 0..1
@export var look_stiffness := 26.0           # скорость «схватывания» (экспонента)
@export var max_turn_speed_deg := 1000.0     # град/сек (лимит по скорости)
@export var max_yaw_deg := 100.0             # влево/вправо (АБСОЛЮТНЫЙ лимит от рейста)
@export var max_pitch_deg := 75.0            # вверх/вниз (АБСОЛЮТНЫЙ лимит от рейста)
@export var neck_share := 0.45               # доля поворота, уходящая в шею
@export var override_weight := 1.0           # вес override 0..1
@export var return_duration := 0.55          # плавный возврат после конца диалога

@export var lock_snap_deg := 10.0

var _prev_err_yaw := 999.0
var _prev_err_pitch := 999.0

# --- Фиксация при наведении ---
@export var deadzone_deg := 4.0              # в эту точность «считаем, что смотрит» → фикс
@export var lock_on_reach := true            # фиксировать позу, когда попали в deadzone
@export var breakout_deg := 25.0             # если цель ушла дальше этого порога — снимаем фикс

# --- Лёгкий автотрекинг (по умолчанию выкл) ---
@export var auto_track_enabled := false
@export var auto_fov_deg := 140.0
@export var auto_dist_min := 0.2
@export var auto_dist_max := 8.0

@export var debug_print := false

# --- Внутренние поля ---
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _head := -1
var _neck := -1

var _look_left := 0.0
var _look_target: Node3D = null    # целимся в Camera3D игрока
var _auto_target: Node3D = null
var _find_target_cooldown := 0.0

enum LookState { IDLE, TRACK, RETURN }
var _state := LookState.IDLE
var _return_t := 0.0
var _active_weight := 1.0

# база/«рейст» головы в осях родителя (захватываем при старте диалога/айдля)
var _rest_in_parent := Basis.IDENTITY

# лок «дошли — держим»:
var _lock_active := false
var _locked_head_basis := Basis.IDENTITY  # глобальная базис-поза головы для фикса

func _ready() -> void:
	process_priority = 100  # применяемся после анимаций

	_sk = get_node_or_null(skeleton_path) as Skeleton3D
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if not _sk: _sk = $Skeleton3D
	if not _ap: _ap = $AnimationPlayer

	_head = _find_bone_fallback(head_bone, ["mixamorig_Head","mixamorig:Head","Head","head"])
	_neck = _find_bone_fallback(neck_bone, ["mixamorig_Neck","mixamorig:Neck","Neck","neck"])

	if debug_print:
		print("[WifeController] head=", _head, "(", _bone_name(_head), ") neck=", _neck, "(", _bone_name(_neck), ")")

	_capture_rest_pose() # базовая поза для абсолютных лимитов
	_try_find_player_camera(true)

# --- Вспомогалки костей ---
func _bone_name(i: int) -> String:
	if not is_instance_valid(_sk) or i < 0: return "<none>"
	return _sk.get_bone_name(i)

func _find_bone_fallback(primary: String, alts: Array[String]) -> int:
	if not is_instance_valid(_sk): return -1
	if primary != "":
		var i := _sk.find_bone(primary)
		if i != -1: return i
	for n in alts:
		var j := _sk.find_bone(n)
		if j != -1: return j
	return -1

func _capture_rest_pose() -> void:
	if _head < 0 or not is_instance_valid(_sk): return
	var head_g := _sk.get_bone_global_pose(_head)
	var parent_idx := _sk.get_bone_parent(_head)
	var parent_g := head_g
	if parent_idx >= 0:
		parent_g = _sk.get_bone_global_pose(parent_idx)
	_rest_in_parent = parent_g.basis.inverse() * head_g.basis
	# сбрасываем лок при смене «рейста»
	_lock_active = false

# --- Публичные методы управления анимацией/взглядом ---
func play_idle(name: StringName) -> void:
	if _ap and _ap.has_animation(String(name)):
		var anim: Animation = _ap.get_animation(String(name))
		if anim: anim.loop_mode = Animation.LOOP_LINEAR
		if _ap.current_animation != String(name):
			_ap.play(String(name))
		# после смены анимации заново фиксируем базу
		_capture_rest_pose()
	elif debug_print:
		push_warning("[WifeController] idle '%s' not found" % name)

# старый короткий вызов (если хочешь оставить таймерный вариант)
func look_at_node(node: Node3D, duration: float = -1.0) -> void:
	_look_target = node
	_state = LookState.TRACK
	_look_left = duration if duration > 0.0 else look_duration
	_return_t = 0.0
	_active_weight = override_weight
	_capture_rest_pose()
	_lock_active = false
	_prev_err_yaw = 999.0
	_prev_err_pitch = 999.0

# основной протокол под диалоги:
func begin_dialogue(target_cam: Node3D) -> void:
	_look_target = target_cam
	_state = LookState.TRACK
	_look_left = 0.0
	_return_t = 0.0
	_active_weight = override_weight
	_capture_rest_pose()
	_lock_active = false
	_prev_err_yaw = 999.0
	_prev_err_pitch = 999.0
	if debug_print:
		print("[WifeController] begin_dialogue -> TRACK")

func pulse_line(seconds: float) -> void:
	# вызывать на каждую новую реплику
	_look_left = max(_look_left, seconds)

func end_dialogue() -> void:
	# немедленно прекращаем трекинг и мягко отпускаем позу
	_look_target = null
	_look_left = 0.0
	_state = LookState.RETURN
	_return_t = 0.0
	_active_weight = override_weight
	_lock_active = false
	if debug_print:
		print("[WifeController] end_dialogue -> RETURN")

# доп. сервис:
func set_auto_target(node: Node3D) -> void:
	_auto_target = node

# --- Основной апдейт ---
func _process(delta: float) -> void:
	# авто-поиск камеры при включённом автотрекинге
	if auto_track_enabled and not is_instance_valid(_auto_target):
		_find_target_cooldown -= delta
		if _find_target_cooldown <= 0.0:
			_try_find_player_camera(false)
			_find_target_cooldown = 1.0

	var did_look := false

	match _state:
		LookState.TRACK:
			if is_instance_valid(_look_target):
				if _look_left > 0.0:
					_look_left -= delta
				_apply_look(_look_target.global_transform.origin, delta)
				did_look = true
				if _look_left <= 0.0 and not auto_track_enabled:
					_state = LookState.RETURN
					_return_t = 0.0
					_active_weight = override_weight
					_lock_active = false
			else:
				_state = LookState.RETURN
				_return_t = 0.0
				_active_weight = override_weight
				_lock_active = false

		LookState.RETURN:
			# прогресс возврата 0..1
			_return_t = min(1.0, _return_t + (delta / max(0.001, return_duration)))
			# ease-out cubic: быстро стартуем, плавно затухаем
			var w := 1.0 - pow(1.0 - _return_t, 3)

			if _head >= 0 and is_instance_valid(_sk):
				var head_g := _sk.get_bone_global_pose(_head)
				var weight_now = lerp(override_weight, 0.0, w)
				_sk.set_bone_global_pose_override(_head, head_g, weight_now, true)
				if _neck >= 0:
					var neck_g := _sk.get_bone_global_pose(_neck)
					_sk.set_bone_global_pose_override(_neck, neck_g, weight_now, true)

			if _return_t >= 1.0:
				_sk.clear_bones_global_pose_override()
				_state = LookState.IDLE
				_lock_active = false
				if debug_print:
					print("[WifeController] RETURN -> IDLE")


		LookState.IDLE:
			if auto_track_enabled and is_instance_valid(_auto_target):
				var tgt := _auto_target.global_transform.origin
				if _target_in_fov_and_range(tgt):
					_apply_look(tgt, delta)
					did_look = true

	if not did_look and _state == LookState.IDLE and is_instance_valid(_sk):
		_sk.clear_bones_global_pose_override()

# --- Трекинг цели/геометрия ---
func _try_find_player_camera(first_time: bool) -> void:
	var scene := get_tree().current_scene
	if scene:
		var cam: Camera3D = scene.get_node_or_null("Player/Camera3D") as Camera3D
		if is_instance_valid(cam):
			_auto_target = cam
			if debug_print: print("[WifeController] auto target = Player/Camera3D")
			return
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if is_instance_valid(pl):
		var cam2 := pl.get_node_or_null("Camera3D") as Camera3D
		if is_instance_valid(cam2):
			_auto_target = cam2
			if debug_print: print("[WifeController] auto target = group(player)/Camera3D")
			return
	if first_time and debug_print:
		print("[WifeController] no player camera found yet")

func _target_in_fov_and_range(target: Vector3) -> bool:
	if _head < 0: return false
	var head_g := _sk.get_bone_global_pose(_head)
	var to := target - head_g.origin
	var dist := to.length()
	if dist < auto_dist_min or dist > auto_dist_max:
		return false
	var fwd := -head_g.basis.z.normalized()
	var ang := rad_to_deg(acos(clamp(fwd.dot(to.normalized()), -1.0, 1.0)))
	return ang <= auto_fov_deg * 0.5

func _yaw_pitch_in_parent(dir: Vector3) -> Vector2:
	# Возвращает (yaw, pitch) для вектора dir, выраженного в осях РОДИТЕЛЯ
	# yaw вокруг оси Y родителя, pitch вокруг оси X родителя.
	var x := dir.x
	var z := dir.z
	var y := dir.y
	var yaw := atan2(x, -z)                                   # [-pi..pi]
	var pitch := atan2(y, max(1e-6, sqrt(x * x + z * z)))     # [-pi..pi]
	return Vector2(yaw, pitch)
	
# --- Взгляд: абсолютные лимиты от рейста + deadzone-lock ---
func _apply_look(target: Vector3, delta: float) -> void:
	if _head < 0 or not is_instance_valid(_sk):
		return

	var head_g: Transform3D = _sk.get_bone_global_pose(_head)
	var head_parent_idx := _sk.get_bone_parent(_head)
	var parent_g := head_g
	if head_parent_idx >= 0:
		parent_g = _sk.get_bone_global_pose(head_parent_idx)

	# 1) Направление к цели в осях РОДИТЕЛЯ
	var to_parent: Vector3 = parent_g.basis.inverse() * (target - head_g.origin)
	var to_dir := to_parent.normalized()

	# 2) «Рейст-вперёд» головы в осях родителя и углы
	var rest_fwd := -_rest_in_parent.z
	var ang_t := _yaw_pitch_in_parent(to_dir)   # (yaw_t, pitch_t)
	var ang_r := _yaw_pitch_in_parent(rest_fwd) # (yaw_r, pitch_r)

	# Δуглы ОТ РЕЙСТА с нормализацией знака
	var yaw_total := wrapf(ang_t.x - ang_r.x, -PI, PI)
	var pitch_total := wrapf(ang_t.y - ang_r.y, -PI, PI)

	# 3) Абсолютные лимиты
	yaw_total   = clamp(yaw_total,   deg_to_rad(-max_yaw_deg),   deg_to_rad(max_yaw_deg))
	pitch_total = clamp(pitch_total, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))

	# 4) Целевая поза головы = родитель * рейст * yaw * pitch
	var q_y := Quaternion(parent_g.basis.y.normalized(), yaw_total)
	var q_p := Quaternion(parent_g.basis.x.normalized(), -pitch_total)
	var desired_head_basis_global := parent_g.basis * _rest_in_parent * Basis(q_y) * Basis(q_p)

# 5) deadzone / lock-on (устойчивый)

# --- deadzone / lock-on (устойчивый + пересечение нуля) ---

	var head_in_parent := parent_g.basis.inverse() * head_g.basis
	var desired_in_parent := parent_g.basis.inverse() * desired_head_basis_global

	# Текущие углы головы ОТ РЕЙСТА (в осях родителя)
	var cur_fwd := -head_in_parent.z
	ang_r = _yaw_pitch_in_parent(-_rest_in_parent.z)   # углы рейста
	var ang_c := _yaw_pitch_in_parent(cur_fwd)              # углы текущей головы
	var yaw_cur_rel := wrapf(ang_c.x - ang_r.x, -PI, PI)
	var pitch_cur_rel := wrapf(ang_c.y - ang_r.y, -PI, PI)

	# Ошибки до цели (в радианах)
	var err_yaw := wrapf(yaw_total - yaw_cur_rel, -PI, PI)
	var err_pitch := wrapf(pitch_total - pitch_cur_rel, -PI, PI)

	var dead_r := deg_to_rad(deadzone_deg)
	var snap_r := deg_to_rad(lock_snap_deg)

	if _lock_active:
		# угол между ЗАФИКСИРОВАННОЙ позой и НОВОЙ целью — критерий "срыва"
		var locked_in_parent := parent_g.basis.inverse() * _locked_head_basis
		var q_lock := locked_in_parent.get_rotation_quaternion()
		var q_des  := desired_in_parent.get_rotation_quaternion()
		var diff_locked_to_target_deg := rad_to_deg(abs((q_lock.inverse() * q_des).get_angle()))
		if diff_locked_to_target_deg > breakout_deg:
			_lock_active = false
		else:
			desired_head_basis_global = _locked_head_basis
	else:
		# ВХОД в лок: либо вошли в deadzone, либо пересекли 0 с малой ошибкой (снэп)
		var crossed_zero := (err_yaw * _prev_err_yaw <= 0.0 and abs(err_yaw) <= snap_r) \
			or (err_pitch * _prev_err_pitch <= 0.0 and abs(err_pitch) <= snap_r)

		if lock_on_reach and ((abs(err_yaw) <= dead_r and abs(err_pitch) <= dead_r) or crossed_zero):
			_lock_active = true
			_locked_head_basis = desired_head_basis_global

	# обновим прошлые ошибки для детектора пересечения нуля
	_prev_err_yaw = err_yaw
	_prev_err_pitch = err_pitch


	# 6) Ограничение скорости + сглаживание
	var max_step := deg_to_rad(max_turn_speed_deg) * delta
	var total_err = abs((head_g.basis.get_rotation_quaternion().inverse() * desired_head_basis_global.get_rotation_quaternion()).get_angle())
	var t := 1.0
	if total_err > 1e-4:
		t = min(1.0, max_step / total_err)

	var k = clamp(1.0 - exp(-look_stiffness * delta), 0.0, 1.0) * look_strength
	var blend = min(t, k)

	# 7) Применяем
	var head_out := head_g.basis.slerp(desired_head_basis_global, blend)
	_sk.set_bone_global_pose_override(_head, Transform3D(head_out, head_g.origin), override_weight, true)

	if _neck >= 0:
		var neck_g := _sk.get_bone_global_pose(_neck)
		var neck_out := neck_g.basis.slerp(desired_head_basis_global, blend * 0.65 * neck_share * 1.7)
		_sk.set_bone_global_pose_override(_neck, Transform3D(neck_out, neck_g.origin), override_weight, true)
