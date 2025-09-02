extends Node3D
class_name WifeController

# --- Узлы ---
@export_node_path("Skeleton3D") var skeleton_path
@export_node_path("AnimationPlayer") var anim_player_path

# --- Кости ---
@export var head_bone := "mixamorig_Head"
@export var neck_bone := "mixamorig_Neck"

# --- Параметры наведения ---
@export var deadzone_soft_width_deg := 3.0     # ширина «перехода» за dead-zone
@export var center_settle_damping  := 12.0     # как быстро «садиться» к нулю в центре

@export var look_strength := 1.0
@export var look_stiffness := 30.0
@export var max_turn_speed_deg := 900.0

@export var max_pitch_deg := 40.0
@export var pitch_weight := 0.6
@export var head_pitch_scale := 0.6   # 0..1, насколько сильно голова кивает по X
@export var max_head_pitch_deg := 20.0

@export var max_yaw_right_deg := 120.0
@export var max_yaw_left_deg  := 120.0

@export var neck_share := 0.45
@export var override_weight := 1.0
@export var return_duration := 0.8

# новое: плавный вход в трекинг и сглаживание углов
@export var enter_duration := 0.20          # сек до полного захвата
@export var aim_smooth_time := 0.35         # сек до ~63% от цели
@export var deadzone_deg := 0.8             # мёртвая зона от дрожи

@export var invert_yaw_sign := false
@export var debug_print := false

# --- runtime ---
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _head := -1
var _neck := -1

var _target: Node3D = null
enum LookState { IDLE, TRACK, RETURN }
var _state := LookState.IDLE
var _return_t := 0.0
var _enter_t := 0.0

# rest (локальные к родителю)
var _rest_head_local := Transform3D.IDENTITY
var _rest_neck_local := Transform3D.IDENTITY

# автокалибровка правого знака
var _yaw_sign := 1.0

# сглаженные углы (накапливаемые)
var _aim_yaw := 0.0
var _aim_pitch := 0.0

func _ready() -> void:
	process_priority = 100
	_sk = get_node_or_null(skeleton_path) as Skeleton3D
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if not _sk: _sk = $Skeleton3D
	if not _ap: _ap = $AnimationPlayer

	_head = _find_bone_fallback(head_bone, ["mixamorig_Head","mixamorig:Head","Head","head"])
	_neck = _find_bone_fallback(neck_bone, ["mixamorig_Neck","mixamorig:Neck","Neck","neck"])

	_capture_rest_pose()

# -------- public --------
func set_target(node: Node3D) -> void:
	_target = node
	_state = LookState.TRACK
	_return_t = 0.0
	_enter_t = 0.0
	_aim_yaw = 0.0
	_aim_pitch = 0.0
	if debug_print: print("[WifeController] TRACK start")

func clear_target() -> void:
	_target = null
	_state = LookState.RETURN
	_return_t = 0.0
	if debug_print: print("[WifeController] RETURN start")

func play_idle(name: StringName) -> void:
	if _ap and _ap.has_animation(String(name)):
		var anim: Animation = _ap.get_animation(String(name))
		if anim: anim.loop_mode = Animation.LOOP_LINEAR
		if _ap.current_animation != String(name):
			_ap.play(String(name))
		_capture_rest_pose()

func _process(delta: float) -> void:
	if _state == LookState.TRACK:
		_enter_t = min(1.0, _enter_t + delta / max(0.001, enter_duration))

	match _state:
		LookState.TRACK:
			if is_instance_valid(_target):
				_apply_look(_target.global_transform.origin, delta)
			else:
				clear_target()
		LookState.RETURN:
			_return_t = min(1.0, _return_t + (delta / max(0.001, return_duration)))
			var w = lerp(override_weight, 0.0, 1.0 - pow(1.0 - _return_t, 3.0))
			if _head >= 0:
				var head_g := _sk.get_bone_global_pose(_head)
				_sk.set_bone_global_pose_override(_head, head_g, w, true)
			if _neck >= 0:
				var neck_g := _sk.get_bone_global_pose(_neck)
				_sk.set_bone_global_pose_override(_neck, neck_g, w, true)
			if _return_t >= 1.0:
				_sk.clear_bones_global_pose_override()
				_state = LookState.IDLE
		_:
			_sk.clear_bones_global_pose_override()

# -------- helpers --------
func _soft_deadzone(v: float, dz: float, width: float) -> float:
	# 0 в пределах dz, плавный выход на полную чувствительность в течение width
	var s := absf(v)
	if s <= dz:
		return 0.0
	if width <= 0.0 or s >= dz + width:
		return v
	var t := (s - dz) / width
	t = t * t * (3.0 - 2.0 * t) # smoothstep
	return sign(v) * (dz + (s - dz) * t)

func _find_bone_fallback(primary: String, alts: Array[String]) -> int:
	if not is_instance_valid(_sk): return -1
	if primary != "":
		var i := _sk.find_bone(primary)
		if i != -1: return i
	for n in alts:
		var j := _sk.find_bone(n)
		if j != -1: return j
	return -1

static func _rot(b: Basis) -> Basis:
	return b.orthonormalized()

func _capture_rest_pose() -> void:
	if not is_instance_valid(_sk): return

	# HEAD rest + калибровка знака
	if _head >= 0:
		var head_g := _sk.get_bone_global_pose(_head)
		var p_idx := _sk.get_bone_parent(_head)
		var p_g := _sk.global_transform
		if p_idx >= 0: p_g = _sk.get_bone_global_pose(p_idx)
		_rest_head_local = p_g.affine_inverse() * head_g

		var parent_R := p_g.basis.orthonormalized()
		var rest_fwd := (-_rest_head_local.basis.z).normalized()
		var eps := deg_to_rad(5.0)
		var right_rot := Basis(Quaternion(parent_R.y.normalized(), eps))
		var rest_fwd_right := (right_rot * rest_fwd).normalized()
		var s := _signed_yaw(rest_fwd, rest_fwd_right, parent_R.y)
		_yaw_sign = 1.0 if s >= 0.0 else -1.0
		if invert_yaw_sign:
			_yaw_sign = -_yaw_sign

	# NECK rest
	if _neck >= 0:
		var neck_g := _sk.get_bone_global_pose(_neck)
		var np_idx := _sk.get_bone_parent(_neck)
		var np_g := _sk.global_transform
		if np_idx >= 0: np_g = _sk.get_bone_global_pose(np_idx)
		_rest_neck_local = np_g.affine_inverse() * neck_g

static func _signed_yaw(rest_fwd: Vector3, to_dir: Vector3, parent_up_vec: Vector3) -> float:
	var U := parent_up_vec.normalized()
	var r_proj := (rest_fwd - U * rest_fwd.dot(U)).normalized()
	var t_proj := (to_dir  - U * to_dir.dot(U)).normalized()
	var s := U.dot(r_proj.cross(t_proj))
	var c = clamp(r_proj.dot(t_proj), -1.0, 1.0)
	return atan2(s, c)

static func _pitch_from_up(dir: Vector3, parent_up_vec: Vector3) -> float:
	var U := parent_up_vec.normalized()
	var y = clamp(U.dot(dir), -1.0, 1.0)
	var xz := sqrt(max(1e-6, 1.0 - y * y))
	return atan2(y, xz)

# -------- core --------
func _apply_look(target_world: Vector3, delta: float) -> void:
	if _head < 0 or not is_instance_valid(_sk): return

	# позы в пространстве скелета
	var head_g := _sk.get_bone_global_pose(_head)
	var head_parent_idx := _sk.get_bone_parent(_head)
	var head_parent_g := _sk.global_transform
	if head_parent_idx >= 0:
		head_parent_g = _sk.get_bone_global_pose(head_parent_idx)

	var has_neck := _neck >= 0
	var neck_g := Transform3D.IDENTITY
	var neck_parent_g := _sk.global_transform
	if has_neck:
		neck_g = _sk.get_bone_global_pose(_neck)
		var nparent_idx := _sk.get_bone_parent(_neck)
		if nparent_idx >= 0:
			neck_parent_g = _sk.get_bone_global_pose(nparent_idx)

	# цель в пространстве скелета
	var target_in_skel := _sk.global_transform.affine_inverse() * target_world

	# направление к цели в осях РОДИТЕЛЯ головы
	var head_parent_R := _rot(head_parent_g.basis)
	var to_parent := head_parent_R.inverse() * (target_in_skel - head_g.origin)
	if to_parent.length() < 1e-6: return
	var to_dir := to_parent.normalized()

	var rest_fwd := (-_rest_head_local.basis.z).normalized()
	var parent_up := head_parent_R.y.normalized()

	var yaw_world := _signed_yaw(rest_fwd, to_dir, parent_up)
	var rest_pitch := _pitch_from_up(rest_fwd, parent_up)
	var to_pitch   := _pitch_from_up(to_dir,   parent_up)
	var pitch_world := wrapf(to_pitch - rest_pitch, -PI, PI)

	var yaw_total := yaw_world * _yaw_sign
	var pitch_total := pitch_world

	# deadzone и лимиты
	var dz := deg_to_rad(deadzone_deg)
	if absf(yaw_total) < dz: yaw_total = 0.0
	if absf(pitch_total) < dz: pitch_total = 0.0

	pitch_total *= clamp(pitch_weight, 0.0, 1.0)
	if yaw_total >= 0.0:
		yaw_total = min(yaw_total, deg_to_rad(max_yaw_right_deg))
	else:
		yaw_total = max(yaw_total, -deg_to_rad(max_yaw_left_deg))
	pitch_total = clamp(pitch_total, -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))

	# сглаживание самих углов (мягкое “подплывание” к цели)
	var alpha := 1.0 - exp(-delta / max(0.001, aim_smooth_time))
	_aim_yaw += (yaw_total - _aim_yaw) * alpha
	_aim_pitch += (pitch_total - _aim_pitch) * alpha
	
	# --- дополнительное «усаживание к нулю» у центра (приглушает остаточный дрожь)
	var settle_alpha := 1.0 - exp(-center_settle_damping * delta)
	if absf(_aim_yaw)   < dz: _aim_yaw   = lerp(_aim_yaw,   0.0, settle_alpha)
	if absf(_aim_pitch) < dz: _aim_pitch = lerp(_aim_pitch, 0.0, settle_alpha)
	
	# раздаём углы
	var yaw_neck   := _aim_yaw   * neck_share
	var pitch_neck := _aim_pitch * neck_share
	var yaw_head   := _aim_yaw   * (1.0 - neck_share)
	var pitch_head := _aim_pitch * (1.0 - neck_share) * head_pitch_scale

	# ограничение скорости + экспоненциальное схватывание
	var max_step := deg_to_rad(max_turn_speed_deg) * delta
	var k = clamp(1.0 - exp(-look_stiffness * delta), 0.0, 1.0) * look_strength
	pitch_head = clamp(pitch_head, -deg_to_rad(max_head_pitch_deg), deg_to_rad(max_head_pitch_deg))

	# фактический вес (плавный вход)
	var weight_now := override_weight * _enter_t

	# ===== ШЕЯ =====
	var neck_out_basis := neck_g.basis
	if has_neck:
		var neck_parent_R := _rot(neck_parent_g.basis)
		var qy_n := Quaternion(neck_parent_R.y.normalized(),  yaw_neck)
		var qx_n := Quaternion(neck_parent_R.x.normalized(), -pitch_neck)
		var desired_neck_basis := (neck_parent_R * Basis(qy_n) * Basis(qx_n) * _rest_neck_local.basis).orthonormalized()

		var q_cur_n := _rot(neck_g.basis).get_rotation_quaternion()
		var q_des_n := desired_neck_basis.get_rotation_quaternion()
		var q_err_n := q_cur_n.inverse() * q_des_n
		var err_n := 2.0 * acos(clamp(absf(q_err_n.w), 0.0, 1.0))
		var t_n := 1.0
		if err_n > 1e-4:
			t_n = min(1.0, max_step / err_n)
		neck_out_basis = _rot(neck_g.basis).slerp(desired_neck_basis, min(t_n, k * 0.75))
		_sk.set_bone_global_pose_override(_neck, Transform3D(neck_out_basis, neck_g.origin), weight_now, true)
	else:
		neck_out_basis = head_parent_R

	# родитель головы после шеи
	var head_parent_after_R := neck_out_basis if has_neck else head_parent_R

	# ===== ГОЛОВА =====
	var qy_h := Quaternion(head_parent_after_R.y.normalized(),  yaw_head)
	var qx_h := Quaternion(head_parent_after_R.x.normalized(), -pitch_head)
	var desired_head_basis := (head_parent_after_R * Basis(qy_h) * Basis(qx_h) * _rest_head_local.basis).orthonormalized()

	var q_cur_h := _rot(head_g.basis).get_rotation_quaternion()
	var q_des_h := desired_head_basis.get_rotation_quaternion()
	var q_err_h := q_cur_h.inverse() * q_des_h
	var err_h := 2.0 * acos(clamp(absf(q_err_h.w), 0.0, 1.0))
	var t_h := 1.0
	if err_h > 1e-4:
		t_h = min(1.0, max_step / err_h)
	var head_out_basis := _rot(head_g.basis).slerp(desired_head_basis, min(t_h, k))
	_sk.set_bone_global_pose_override(_head, Transform3D(head_out_basis, head_g.origin), weight_now, true)

	if debug_print:
		print("yaw=", rad_to_deg(_aim_yaw))
