extends Node3D
class_name WifeController

# --- Узлы ---
@export_node_path("Skeleton3D") var skeleton_path
@export_node_path("AnimationPlayer") var anim_player_path

# --- Кости ---
@export var head_bone := "mixamorig_Head"
@export var neck_bone := "mixamorig_Neck"

# --- Параметры наведения ---
@export var look_strength := 1.0
@export var look_stiffness := 30.0
@export var max_turn_speed_deg := 900.0
@export var max_yaw_deg := 90.0       # оставлен для совместимости
@export var max_pitch_deg := 40.0
@export var pitch_weight := 0.6
@export var neck_share := 0.45
@export var override_weight := 1.0
@export var return_duration := 0.8
@export var max_yaw_right_deg := 90.0
@export var max_yaw_left_deg := 140.0
@export var debug_print := false

# --- runtime ---
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _head := -1
var _neck := -1


var _target: Node3D = null
enum { IDLE, TRACK, RETURN }
var _state := IDLE
var _return_t := 0.0

# рейст головы/шеи в осях РОДИТЕЛЯ
var _rest_head_in_parent := Basis.IDENTITY
var _rest_neck_in_parent := Basis.IDENTITY

func _ready() -> void:
	process_priority = 100
	_sk = get_node_or_null(skeleton_path) as Skeleton3D
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if not _sk: _sk = $Skeleton3D
	if not _ap: _ap = $AnimationPlayer

	_head = _find_bone_fallback(head_bone, ["mixamorig_Head","mixamorig:Head","Head","head"])
	_neck = _find_bone_fallback(neck_bone, ["mixamorig_Neck","mixamorig:Neck","Neck","neck"])

	_capture_rest_pose()

func set_target(node: Node3D) -> void:
	_target = node
	# захватываем базу ИЗ ТЕКУЩЕЙ позы
	if _head >= 0:
		var head_g := _sk.get_bone_global_pose(_head)
		var p_idx := _sk.get_bone_parent(_head)
		var p_g := _sk.global_transform
		if p_idx >= 0:
			p_g = _sk.get_bone_global_pose(p_idx)
		_rest_head_in_parent = p_g.basis.inverse() * head_g.basis
	if _neck >= 0:
		var neck_g := _sk.get_bone_global_pose(_neck)
		var np_idx := _sk.get_bone_parent(_neck)
		var np_g := _sk.global_transform
		if np_idx >= 0:
			np_g = _sk.get_bone_global_pose(np_idx)
		_rest_neck_in_parent = np_g.basis.inverse() * neck_g.basis
	_state = TRACK
	_return_t = 0.0
	if debug_print: print("[WifeController] TRACK start")

func clear_target() -> void:
	_target = null
	_state = RETURN
	_return_t = 0.0
	if debug_print: print("[WifeController] RETURN start")

func play_idle(name: StringName) -> void:
	if _ap and _ap.has_animation(String(name)):
		var anim: Animation = _ap.get_animation(String(name))
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
		if _ap.current_animation != String(name):
			_ap.play(String(name))
		_capture_rest_pose()

func _process(delta: float) -> void:
	match _state:
		TRACK:
			if is_instance_valid(_target):
				_apply_look(_target.global_transform.origin, delta)
			else:
				clear_target()
		RETURN:
			_return_t = min(1.0, _return_t + (delta / max(0.001, return_duration)))
			var w := 1.0 - pow(1.0 - _return_t, 3)
			if _head >= 0:
				var head_g := _sk.get_bone_global_pose(_head)
				var weight_now = lerp(override_weight, 0.0, w)
				_sk.set_bone_global_pose_override(_head, head_g, weight_now, true)
				if _neck >= 0:
					var neck_g := _sk.get_bone_global_pose(_neck)
					_sk.set_bone_global_pose_override(_neck, neck_g, weight_now, true)
			if _return_t >= 1.0:
				_sk.clear_bones_global_pose_override()
				_state = IDLE
		_:
			_sk.clear_bones_global_pose_override()

# --- helpers ---
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
	if not is_instance_valid(_sk): return
	if _head >= 0:
		_rest_head_in_parent = _sk.get_bone_rest(_head).basis
	if _neck >= 0:
		_rest_neck_in_parent = _sk.get_bone_rest(_neck).basis

# выбираем «вперёд» у головы в осях РОДИТЕЛЯ (±X/±Y/±Z)
func _choose_rest_forward_in_parent(parent_up: Vector3) -> Vector3:
	var cands: Array[Vector3] = [
		_rest_head_in_parent.x, -_rest_head_in_parent.x,
		_rest_head_in_parent.y, -_rest_head_in_parent.y,
		_rest_head_in_parent.z, -_rest_head_in_parent.z
	]
	var best := cands[0].normalized()
	var best_score := -1e9
	for v in cands:
		var vn := v.normalized()
		# хотим горизонтальнее (меньше проекция на up) и «похоже на вперёд» родителя (-Z)
		var horiz = 1.0 - abs(vn.dot(parent_up))      # 0..1
		var forward_hint := Vector3(0,0,-1).dot(vn)    # -1..1 (в осях РОДИТЕЛЯ!)
		var score = horiz + 0.25 * forward_hint
		if score > best_score:
			best_score = score
			best = vn
	return best

func _yaw_pitch_from_dir_parent(dir_parent: Vector3) -> Vector2:
	var x := dir_parent.x
	var z := dir_parent.z
	var y := dir_parent.y
	var yaw := atan2(x, -z)                               # вокруг Y родителя
	var pitch := atan2(y, max(1e-6, sqrt(x * x + z * z))) # вокруг X родителя
	return Vector2(yaw, pitch)

# --- основной трекинг ---
func _apply_look(target: Vector3, delta: float) -> void:
	if _head < 0 or not is_instance_valid(_sk):
		return

	# трансформы
	var head_g := _sk.get_bone_global_pose(_head)
	var head_parent_idx := _sk.get_bone_parent(_head)
	var head_parent_g := _sk.global_transform
	if head_parent_idx >= 0:
		head_parent_g = _sk.get_bone_global_pose(head_parent_idx)

	# цель в осях РОДИТЕЛЯ головы
	var to_parent: Vector3 = head_parent_g.basis.inverse() * (target - head_g.origin)
	if to_parent.length() < 1e-6:
		return
	var to_dir := to_parent.normalized()

	# «вперёд» из рейста — автоматически выбранная ось
	var parent_up := head_parent_g.basis.y.normalized()
	var rest_fwd := _choose_rest_forward_in_parent(parent_up)   # в осях РОДИТЕЛЯ

	# yaw/pitch целевое и базовое
	var ang_rest := _yaw_pitch_from_dir_parent(rest_fwd)
	var ang_des  := _yaw_pitch_from_dir_parent(to_dir)

	var yaw_total := wrapf(ang_des.x - ang_rest.x, -PI, PI)
	var pitch_total := wrapf(ang_des.y - ang_rest.y, -PI, PI)

	# вес и лимиты
	pitch_total *= clamp(pitch_weight, 0.0, 1.0)

	var yaw_r := deg_to_rad(max_yaw_right_deg)
	var yaw_l := deg_to_rad(max_yaw_left_deg)
	if yaw_total >= 0.0:
		if yaw_total > yaw_r:
			yaw_total = yaw_r
	else:
		if yaw_total < -yaw_l:
			yaw_total = -yaw_l

	pitch_total = clamp(pitch_total, -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))

	# делим на шею/голову
	var yaw_neck := yaw_total * neck_share
	var pitch_neck := pitch_total * neck_share
	var yaw_head := yaw_total * (1.0 - neck_share)
	var pitch_head := pitch_total * (1.0 - neck_share)

	# целевые базисы в ГЛОБАЛЕ (вращаем вокруг осей РОДИТЕЛЯ)
	var qy_h := Quaternion(head_parent_g.basis.y.normalized(),  yaw_head)
	var qx_h := Quaternion(head_parent_g.basis.x.normalized(), -pitch_head)
	var desired_head_global := head_parent_g.basis * _rest_head_in_parent * Basis(qy_h) * Basis(qx_h)

	var desired_neck_global := Basis.IDENTITY
	if _neck >= 0:
		var nparent_idx := _sk.get_bone_parent(_neck)
		var neck_parent_g := _sk.global_transform
		if nparent_idx >= 0:
			neck_parent_g = _sk.get_bone_global_pose(nparent_idx)
		var qy_n := Quaternion(neck_parent_g.basis.y.normalized(),  yaw_neck)
		var qx_n := Quaternion(neck_parent_g.basis.x.normalized(), -pitch_neck)
		desired_neck_global = neck_parent_g.basis * _rest_neck_in_parent * Basis(qy_n) * Basis(qx_n)

	# ограничение скорости + сглаживание
	var max_step := deg_to_rad(max_turn_speed_deg) * delta
	var k = clamp(1.0 - exp(-look_stiffness * delta), 0.0, 1.0) * look_strength

	# голова — угол между кватернионами
	var q_cur_h: Quaternion = head_g.basis.get_rotation_quaternion()
	var q_des_h: Quaternion = desired_head_global.get_rotation_quaternion()
	var q_err_h: Quaternion = q_cur_h.inverse() * q_des_h
	var err_h: float = 2.0 * acos(clamp(absf(q_err_h.w), 0.0, 1.0))
	var t_h: float = 1.0
	if err_h > 1e-4:
		t_h = min(1.0, max_step / err_h)
	var head_out := head_g.basis.slerp(desired_head_global, min(t_h, k))
	_sk.set_bone_global_pose_override(_head, Transform3D(head_out, head_g.origin), override_weight, true)

	# шея
	if _neck >= 0:
		var neck_g2 := _sk.get_bone_global_pose(_neck)
		var q_cur_n: Quaternion = neck_g2.basis.get_rotation_quaternion()
		var q_des_n: Quaternion = desired_neck_global.get_rotation_quaternion()
		var q_err_n: Quaternion = q_cur_n.inverse() * q_des_n
		var err_n: float = 2.0 * acos(clamp(absf(q_err_n.w), 0.0, 1.0))
		var t_n: float = 1.0
		if err_n > 1e-4:
			t_n = min(1.0, max_step / err_n)
		var neck_out := neck_g2.basis.slerp(desired_neck_global, min(t_n, k * 0.75))
		_sk.set_bone_global_pose_override(_neck, Transform3D(neck_out, neck_g2.origin), override_weight, true)

	# отладка
	if debug_print:
		print("yaw=", rad_to_deg(yaw_total))
