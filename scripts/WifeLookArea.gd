extends Area3D
@export_node_path("Node3D") var wife_root_path

var _wife: WifeController

func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var root := get_node_or_null(wife_root_path) as Node3D
	if root:
		_wife = root.get_node_or_null("WifeController") as WifeController
	if _wife == null:
		push_warning("[WifeLookArea] WifeController not found. Set wife_root_path to the Wife root.")

func _on_body_entered(b: Node) -> void:
	if _wife and b.is_in_group("player"):
		var cam := b.get_node_or_null("Camera3D") as Node3D
		if cam:
			_wife.set_target(cam)

func _on_body_exited(b: Node) -> void:
	if _wife and b.is_in_group("player"):
		_wife.clear_target()
