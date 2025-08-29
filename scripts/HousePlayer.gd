extends CharacterBody3D

@export var speed := 5.0

var mouse_sensitivity := 0.002
const PS_KEY := "player/mouse_sensitivity"

@export var interact_action := "interact"
@onready var interact_ray := $Camera3D/InteractRay
@onready var interact_hint: Label = $"../CanvasLayer/Control/InteractHint"


var can_move := true

func _ready():
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if ProjectSettings.has_setting(PS_KEY):
		mouse_sensitivity = float(ProjectSettings.get_setting(PS_KEY))

func _process(_delta: float) -> void:
	_update_interact_hint()

func _update_interact_hint() -> void:
	if not is_instance_valid(interact_hint):
		return
	var show := false
	if interact_ray and interact_ray.is_colliding():
		var hit = interact_ray.get_collider()
		# считаем рудой всё, что в группе "ore" или имеет метод try_mine()
		if (hit and (hit.is_in_group("ore") or hit.has_method("try_mine"))):
			show = true
	if show:
		interact_hint.text = "Press E to dig"
		interact_hint.visible = true
	else:
		interact_hint.visible = false


func _input(event):
	if event is InputEventMouseMotion and can_move:
		rotate_y(-event.relative.x * mouse_sensitivity)
		$Camera3D.rotate_x(-event.relative.y * mouse_sensitivity)
		$Camera3D.rotation.x = clamp($Camera3D.rotation.x, -PI/2, PI/2)
		
	if event.is_action_pressed("interact") and can_move:
		_try_interact()

func _try_interact():
	if not interact_ray.is_colliding(): return
	var hit = interact_ray.get_collider()
	if hit and hit.has_method("try_mine"):
		hit.try_mine()

func _physics_process(delta):
	if not can_move:
		return
		
	var direction = Vector3.ZERO
	
	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		direction += transform.basis.z
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		direction += transform.basis.x
		
	direction = direction.normalized()
	velocity = direction * speed
	move_and_slide()
