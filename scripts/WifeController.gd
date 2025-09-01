extends Node3D
class_name WifeController

# --- Узлы ---
@export_node_path("Skeleton3D") var skeleton_path
@export_node_path("AnimationPlayer") var anim_player_path

# --- Кости ---
@export var head_bone := "mixamorig_Head"
@export var neck_bone := "mixamorig_Neck"

# --- Параметры наведения ---
@export var look_strength := 1.0         # 0..1
@export var look_stiffness := 30.0       # скорость «схватывания» (экспонента)
@export var max_turn_speed_deg := 900.0  # макс. скорость (град/сек)
@export var max_yaw_deg := 90.0          # влево/вправо от базовой позы
@export var max_pitch_deg := 40.0        # вверх/вниз от базовой позы
@export var pitch_weight := 0.6          # 0..1, уменьшить вертикальные кивки
@export var neck_share := 0.45           # доля поворота в шею
@export var override_weight := 1.0       # вес override
@export var return_duration := 0.8       # время мягкого возврата
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
	_capture_rest_pose()
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
		if anim: anim.loop_mode = Animation.LOOP_LINEAR
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
			var w := 1.0 - pow(1.0 - _return_t, 3)   # ease-out
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
		var head_g := _sk.get_bone_global_pose(_head)
		var parent_idx := _sk.get_bone_parent(_head)
		var parent_g := head_g
		if parent_idx >= 0:
			parent_g = _sk.get_bone_global_pose(parent_idx)
		_rest_head_in_parent = parent_g.basis.inverse() * head_g.basis
	if _neck >= 0:
		var neck_g := _sk.get_bone_global_pose(_neck)
		var nparent_idx := _sk.get_bone_parent(_neck)
		var nparent_g := neck_g
		if nparent_idx >= 0:
			nparent_g = _sk.get_bone_global_pose(nparent_idx)
		_rest_neck_in_parent = nparent_g.basis.inverse() * neck_g.basis

func _yaw_pitch_in_parent(dir: Vector3) -> Vector2:
	var x := dir.x
	var z := dir.z
	var y := dir.y
	var yaw := atan2(x, -z)                               # вокруг Y родителя
	var pitch := atan2(y, max(1e-6, sqrt(x * x + z * z))) # вокруг X родителя
	return Vector2(yaw, pitch)

# --- основной трекинг ---
func _apply_look(target: Vector3, delta: float) -> void:
	if _head < 0: return

	# родительские трансформы
	var head_g := _sk.get_bone_global_pose(_head)
	var head_parent_idx := _sk.get_bone_parent(_head)
	var head_parent_g := head_g
	if head_parent_idx >= 0:
		head_parent_g = _sk.get_bone_global_pose(head_parent_idx)

	var neck_parent_g := head_parent_g
	if _neck >= 0:
		var nparent_idx := _sk.get_bone_parent(_neck)
		if nparent_idx >= 0:
			neck_parent_g = _sk.get_bone_global_pose(nparent_idx)

	# направление к цели в осях родителя головы
	var to_parent := head_parent_g.basis.inverse() * (target - head_g.origin)
	var to_dir := to_parent.normalized()

	# углы от рейста
	var rest_fwd := -_rest_head_in_parent.z
	var ang_t := _yaw_pitch_in_parent(to_dir)
	var ang_r := _yaw_pitch_in_parent(rest_fwd)
	var yaw_total := wrapf(ang_t.x - ang_r.x, -PI, PI)
	var pitch_total := wrapf(ang_t.y - ang_r.y, -PI, PI)

	# ослабленная вертикаль + лимиты
	pitch_total *= clamp(pitch_weight, 0.0, 1.0)
	yaw_total = clamp(yaw_total, deg_to_rad(-max_yaw_deg), deg_to_rad(max_yaw_deg))
	pitch_total = clamp(pitch_total, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))

	# раскладываем на шею/голову
	var yaw_neck   := yaw_total * neck_share
	var pitch_neck := pitch_total * neck_share
	var yaw_head   := yaw_total * (1.0 - neck_share)
	var pitch_head := pitch_total * (1.0 - neck_share)

	# целевые базисы в ГЛОБАЛЕ
	var qy_h := Quaternion(head_parent_g.basis.y.normalized(), yaw_head)
	var qx_h := Quaternion(head_parent_g.basis.x.normalized(), -pitch_head)
	var desired_head_basis := head_parent_g.basis * _rest_head_in_parent * Basis(qy_h) * Basis(qx_h)

	var desired_neck_basis := Basis.IDENTITY
	if _neck >= 0:
		var qy_n := Quaternion(neck_parent_g.basis.y.normalized(), yaw_neck)
		var qx_n := Quaternion(neck_parent_g.basis.x.normalized(), -pitch_neck)
		desired_neck_basis = neck_parent_g.basis * _rest_neck_in_parent * Basis(qy_n) * Basis(qx_n)

# ограничение скорости + сглаживание
	var max_step := deg_to_rad(max_turn_speed_deg) * delta

	# --- HEAD ---
	var err_head = abs((head_g.basis.get_rotation_quaternion().inverse()
		* desired_head_basis.get_rotation_quaternion()).get_angle())

	var t_head := 1.0
	if err_head > 1e-4:
		t_head = min(1.0, max_step / err_head)

	var k = clamp(1.0 - exp(-look_stiffness * delta), 0.0, 1.0) * look_strength
	var blend_h = min(t_head, k)

	var head_out := head_g.basis.slerp(desired_head_basis, blend_h)
	_sk.set_bone_global_pose_override(_head, Transform3D(head_out, head_g.origin), override_weight, true)

	# --- NECK ---
	if _neck >= 0:
		var neck_g := _sk.get_bone_global_pose(_neck)
		var err_neck = abs((neck_g.basis.get_rotation_quaternion().inverse()
			* desired_neck_basis.get_rotation_quaternion()).get_angle())

		var t_neck := 1.0
		if err_neck > 1e-4:
			t_neck = min(1.0, max_step / err_neck)

		var blend_n = min(t_neck, k * 0.75)
		var neck_out := neck_g.basis.slerp(desired_neck_basis, blend_n)
		_sk.set_bone_global_pose_override(_neck, Transform3D(neck_out, neck_g.origin), override_weight, true)
