extends Area3D
@export_node_path("Node3D") var wife_root_path
@export var exit_grace_time := 0.15  # сек, анти-дребезг выхода

var _wife: WifeController
var _player: Node3D = null
var _lost_t := 0.0

func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	# body_exited можно не подключать — будем сами проверять в _physics_process

	var root := get_node_or_null(wife_root_path) as Node3D
	_wife = _find_wife_controller(root)
	if _wife == null:
		push_warning("[LookArea] WifeController not found from wife_root_path")

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	# есть ли игрок в перекрытиях сейчас?
	var in_now := false
	for b in get_overlapping_bodies():
		if b == _player:
			in_now = true
			break
	if in_now:
		_lost_t = 0.0
	else:
		_lost_t += delta
		if _lost_t >= exit_grace_time:
			_lost_t = 0.0
			if _wife:
				_wife.clear_target()
			_player = null

func _on_body_entered(b: Node) -> void:
	# на входе просто запоминаем игрока и ставим цель
	if b.is_in_group("player"):
		_player = b
		_lost_t = 0.0
		if _wife:
			var cam := b.get_node_or_null("Camera3D") as Node3D
			if cam:
				_wife.set_target(cam)

func _find_wife_controller(root: Node) -> WifeController:
	if root == null:
		return null
	if root is WifeController:
		return root
	for c in root.get_children():
		var w := _find_wife_controller(c)
		if w:
			return w
	return null
