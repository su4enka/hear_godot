extends Node3D
class_name WifeController

@export_node_path("Skeleton3D") var skeleton_path
@export_node_path("AnimationPlayer") var anim_player_path
@export var head_bone := "mixamorig_Head"
@export var neck_bone := "mixamorig_Neck"
@export var look_duration := 1.6
@export var look_strength := 0.7
@export var max_yaw_deg := 60.0
@export var max_pitch_deg := 35.0
@export var interaction_radius: float = 2.3

var _sk: Skeleton3D
var _ap: AnimationPlayer
var _head := -1
var _neck := -1
var _look_left := 0.0
var _look_target: Node3D

func _ready():
	_sk = get_node_or_null(skeleton_path) as Skeleton3D
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if not _sk: _sk = $Skeleton3D
	if not _ap: _ap = $AnimationPlayer
	_head = _sk.find_bone(head_bone)
	_neck = _sk.find_bone(neck_bone)

func play_idle(name: StringName) -> void:
	if _ap and _ap.has_animation(String(name)):
		var anim: Animation = _ap.get_animation(String(name))
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
		_ap.play(String(name))

func look_at_node(node: Node3D, duration: float = -1.0) -> void:
	_look_target = node
	_look_left = duration if duration > 0.0 else look_duration

func _process(delta: float) -> void:
	if _look_left > 0.0 and is_instance_valid(_look_target):
		_look_left -= delta
		_apply_look(_look_target.global_transform.origin, delta)
	else:
		_sk.clear_bones_global_pose_override()

func _apply_look(target: Vector3, delta: float) -> void:
	if _head < 0:
		return
	# дистанционный порог
	var dist := global_transform.origin.distance_to(target)
	if dist > interaction_radius:
		return

	var k = clamp(1.0 - pow(0.85, 12.0 * delta), 0.0, 1.0) * look_strength

	# HEAD
	var head_pose: Transform3D = _sk.get_bone_global_pose(_head)
	var head_look: Transform3D = head_pose.looking_at(target, Vector3.UP)
	var head_out: Transform3D = head_pose.interpolate_with(head_look, k)
	_sk.set_bone_global_pose_override(_head, head_out, 1.0, true)

	# NECK (мягче)
	if _neck >= 0:
		var neck_pose: Transform3D = _sk.get_bone_global_pose(_neck)
		var neck_look: Transform3D = neck_pose.looking_at(target, Vector3.UP)
		var neck_out: Transform3D = neck_pose.interpolate_with(neck_look, k * 0.6)
		_sk.set_bone_global_pose_override(_neck, neck_out, 1.0, true)
