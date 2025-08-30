extends CharacterBody3D

const OUTLINE_SHADER_PATH := "res://shaders/outline.gdshader"
var last_outlined: MeshInstance3D = null

@export var speed := 5.0

var _last_talk_time := 0.0
const TALK_COOLDOWN := 0.2

const BOB_FREQ = 2.0
const BOB_AMP = 0.08
var t_bob = 0.0
var camera_base_pos: Vector3

var mouse_sensitivity := 0.002
const PS_KEY := "player/mouse_sensitivity"

var paused = false

@export var interact_action := "interact"
@onready var interact_ray := $Camera3D/InteractRay
@onready var interact_hint: Label = $"../CanvasLayer/Control/InteractHint"
@onready var camera_3d: Camera3D = $Camera3D


# farol дживение
@onready var farol = $Camera3D/Farol
var farol_base_pos: Vector3
var farol_base_rot: Vector3

# сверху рядом с остальными export
@export var farol_enabled := true
@export var farol_bob_amp := 0.6      # насколько повторять твой headbob (0..1)
@export var farol_sway_rot := 6.0     # градусы наклона при шаге/повороте
@export var farol_lag := 12.0         # сглаживание (чем больше — быстрее догоняет)
@export var farol_damp := 0.85        # демпфирование сглаживания
var _mouse_dx := 0.0                  # для «рывка» при повороте мыши
var _farol_inited := false


var can_move := true

func _ready():
	
	if interact_ray:
		interact_ray.collide_with_areas = true
		interact_ray.collide_with_bodies = true
	
	camera_base_pos = camera_3d.transform.origin
	if is_instance_valid(farol):
		# 1) сохранить позу из инспектора как базовую
		farol_base_pos = farol.position      # локальная позиция под камерой
		farol_base_rot = farol.rotation      # локальные эйлеры

		# 2) включить/выключить видимость по флагу
		farol.visible = farol_enabled

		# 3) заставить первый тик встать ровно в target (без интерпа)
		_farol_inited = false
		_mouse_dx = 0.0
	
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if ProjectSettings.has_setting(PS_KEY):
		mouse_sensitivity = float(ProjectSettings.get_setting(PS_KEY))
	if interact_ray:
		interact_ray.collide_with_areas = true

func _process(_delta: float) -> void:
	_update_interact_hint()
	
	if last_outlined and last_outlined.material_overlay is ShaderMaterial:
		last_outlined.material_overlay.set_shader_parameter("camera_world_pos", camera_3d.global_position)


func _get_interactable_from_hit(hit: Object) -> Node:
	var n := hit as Node
	while n:
		if n.has_method("try_mine"): return n      # руда
		if n.is_in_group("wife") or n.has_method("talk"): return n  # жена/НПС
		if n.is_in_group("bed"): return n                    # кровать
		if n.is_in_group("exit"): return n
		n = n.get_parent()
	return null

func _update_interact_hint() -> void:
	if not interact_hint or not interact_ray:
		return

	interact_ray.force_raycast_update()
	var text := ""
	var new_outline: MeshInstance3D = null

	if interact_ray.is_colliding():
		var hit = interact_ray.get_collider()
		if hit:
			var target := _get_interactable_from_hit(hit)

			if target:
				if target.has_method("try_mine"):
					text = "Press E to dig"
				elif target.is_in_group("wife") or target.has_method("talk"):
					text = "Press E to speak"
				elif target.is_in_group("bed"):
					text = "Press E to sleep"
				elif target.is_in_group("exit"):
					text = "Press E to leave"

			# стало: меш ищем около самого target (это фильтрует дом и всё лишнее)
			if target:
				var mesh := _find_mesh_for_target(target)
				if mesh:
					new_outline = mesh

	# выключить у прошлого
	if last_outlined and last_outlined != new_outline:
		_set_outline(last_outlined, false)

	# включить у нового
	if new_outline:
		_set_outline(new_outline, true)

	last_outlined = new_outline

	interact_hint.text = text
	interact_hint.visible = text != ""

func _find_mesh_ancestor(n: Node) -> MeshInstance3D:
	# Поднимаемся по родителям до ближайшего меша
	var cur := n
	while cur:
		if cur is MeshInstance3D:
			return cur
		cur = cur.get_parent()
	return null

func _ensure_overlay_unique(mi: MeshInstance3D) -> ShaderMaterial:
	# Гарантируем уникальный ShaderMaterial в material_overlay
	var mat := mi.material_overlay
	if mat == null:
		var sh := load(OUTLINE_SHADER_PATH) as Shader
		if sh == null:
			push_error("Outline shader not found at: %s" % OUTLINE_SHADER_PATH)
			return null
		mat = ShaderMaterial.new()
		mat.shader = sh
		mi.material_overlay = mat
	else:
		# если общий ресурс — сделаем локальным для сцены/инстанса
		if not mat.resource_local_to_scene:
			mat = mat.duplicate(true)
			mat.resource_local_to_scene = true
			mi.material_overlay = mat
	return mat as ShaderMaterial

func _set_outline(mi: MeshInstance3D, on: bool) -> void:
	if mi == null: return
	var sm := _get_outline_material(mi)
	if sm == null:
		return
	# здесь уже точно наш шейдер → можно безопасно ставить параметры
	sm.set_shader_parameter("outline_enabled", on)
	sm.set_shader_parameter("camera_world_pos", camera_3d.global_position)

func _find_mesh_descendant(root: Node, max_depth: int = 8) -> MeshInstance3D:
	var q: Array = [root]
	var depth: Dictionary = {root: 0}
	while q.size() > 0:
		var n: Node = q.pop_front()
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			return n
		var d := int(depth.get(n, 0))
		if d >= max_depth:
			continue
		for c in n.get_children():
			q.append(c)
			depth[c] = d + 1
	return null

func _find_mesh_for_target(target: Node) -> MeshInstance3D:
	# поднимаемся до 3 предков, на каждом ищем вниз
	var cur := target
	var hops := 0
	while cur and hops < 3:
		var m := _find_mesh_descendant(cur, 10)
		if m: return m
		cur = cur.get_parent()
		hops += 1
	return null

func _shader_has_param(mat: ShaderMaterial, pname: String) -> bool:
	# в Godot 4 get_shader_parameter() кидает ошибку, если параметра нет — проверим по списку uniforms
	if mat.shader == null: return false
	for u in mat.shader.get_uniform_list():
		if String(u.name) == pname:
			return true
	return false

func _is_outline_shader(sm: ShaderMaterial) -> bool:
	if sm == null: 
		return false
	if sm.shader == null:
		return false
	# Сравниваем по ресурсу шейдера (быстро и без ошибок)
	if sm.shader == preload(OUTLINE_SHADER_PATH):
		return true
	# На случай дубликатов/копий — сверим путь
	return String(sm.shader.resource_path) == OUTLINE_SHADER_PATH

func _walk_next_pass(m: Material) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var cur := m
	var safety := 0
	while cur and safety < 16:
		if cur is ShaderMaterial:
			out.append(cur)
		cur = cur.next_pass
		safety += 1
	return out

func _get_outline_material(mi: MeshInstance3D) -> ShaderMaterial:
	# 1) Overlay
	if mi.material_overlay is ShaderMaterial:
		var sm := mi.material_overlay as ShaderMaterial
		if _is_outline_shader(sm):
			return sm
		for sm2 in _walk_next_pass(sm):
			if _is_outline_shader(sm2):
				return sm2

	# 2) material_override
	if mi.material_override is ShaderMaterial:
		var mo := mi.material_override as ShaderMaterial
		if _is_outline_shader(mo):
			return mo
		for sm3 in _walk_next_pass(mo):
			if _is_outline_shader(sm3):
				return sm3

	# 3) surface-материалы
	if mi.mesh:
		var sc := mi.mesh.get_surface_count()
		for i in sc:
			var m := mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			if m:
				if m is ShaderMaterial and _is_outline_shader(m):
					return m
				for sm4 in _walk_next_pass(m):
					if _is_outline_shader(sm4):
						return sm4
	return null

func _find_mesh_nearby(hit: Node, target: Node) -> MeshInstance3D:
	# 1) вверх по предкам от collider’а
	var m := _find_mesh_ancestor(hit)
	if m: return m
	# 2) вниз по таргету (твоя логика интеракции)
	if target:
		m = _find_mesh_descendant(target)
		if m: return m
	# 3) вверх от collider’а, на каждом уровне пробуем спуститься вниз
	var cur := hit
	var hops := 0
	while cur and hops < 6:
		m = _find_mesh_descendant(cur)
		if m: return m
		cur = cur.get_parent()
		hops += 1
	return null

func _input(event):
	
	
	if event is InputEventMouseMotion and can_move and Engine.time_scale != 0:
		rotate_y(-event.relative.x * mouse_sensitivity)
		$Camera3D.rotate_x(-event.relative.y * mouse_sensitivity)
		$Camera3D.rotation.x = clamp($Camera3D.rotation.x, -PI/2, PI/2)
		_mouse_dx += event.relative.x
		
	if event.is_action_pressed("interact") and can_move and Engine.time_scale != 0:
		_try_interact()
	
	if event.is_action_pressed("ui_cancel"): # по умолчанию Esc
		var pause_menu = get_tree().current_scene.get_node_or_null("PauseMenu")
		if pause_menu:
			pause_menu.toggle()

func _try_interact():
	if not interact_ray: return
	interact_ray.force_raycast_update()
	if not interact_ray.is_colliding(): return
	var hit = interact_ray.get_collider()
	if hit == null: return
	var target := _get_interactable_from_hit(hit)
	if target == null: return
	
	if interact_ray and interact_ray.is_colliding():
		if hit and (hit.is_in_group("wife") or hit.has_method("talk")):
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_talk_time < TALK_COOLDOWN:
				return
			_last_talk_time = now
			var house := get_parent()
			if house and house.has_method("request_wife_talk"):
				house.call("request_wife_talk")
			return

# выход
	if target.is_in_group("exit"):
		var house := get_parent()
		if house and house.has_method("request_exit"):
			house.call("request_exit")
		return

# кровать
	if target.is_in_group("bed"):
		var house := get_parent()
		if house and house.has_method("request_sleep"):
			house.call("request_sleep")
		return

		# Руда
	if target.has_method("try_mine"):
		# безопасный вызов (если руда удалится внутри try_mine)
		target.call_deferred("try_mine")
		return

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
	
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera_3d.transform.origin = camera_base_pos + _headbob(t_bob)
	
	_update_farol(delta, direction)
	
	move_and_slide()

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	
	return pos

func _update_farol(delta: float, dir: Vector3) -> void:
	if not is_instance_valid(farol) or not farol_enabled or not farol.visible:
		return

	# --- 1) позиционный кач (локально под камерой) ---
	var bob := _headbob(t_bob) * farol_bob_amp
	var target_pos: Vector3 = farol_base_pos + bob

	# --- 2) углы: pitch/roll от шага, yaw от «рывка» мыши ---
	var move_factor = clamp(velocity.length() / max(0.001, speed), 0.0, 1.0)
	var step := sin(t_bob * BOB_FREQ * 2.0)

	var pitch := deg_to_rad(farol_sway_rot * 0.8 * move_factor * step)
	var roll  := deg_to_rad(-farol_sway_rot * 0.6 * move_factor * step)
	var yaw   := deg_to_rad(clamp(_mouse_dx * 0.25, -farol_sway_rot, farol_sway_rot))

	var target_rot := Vector3(
		farol_base_rot.x + pitch,
		farol_base_rot.y + yaw,
		farol_base_rot.z + roll
	)

	# --- 3) первый тик — жёстко ставим таргет, чтобы не «улетал» ---
	if not _farol_inited:
		farol.position = target_pos
		farol.rotation = target_rot
		_farol_inited = true
		_mouse_dx = 0.0
		return

	# --- 4) плавное догоняние (без interpolate_with) ---
	var alpha = clamp(1.0 - pow(farol_damp, farol_lag * delta), 0.0, 1.0)

	# позиция
	farol.position = farol.position.lerp(target_pos, alpha)

	# углы — по осям через lerp_angle (устойчиво к 2π)
	var cur = farol.rotation
	cur.x = lerp_angle(cur.x, target_rot.x, alpha)
	cur.y = lerp_angle(cur.y, target_rot.y, alpha)
	cur.z = lerp_angle(cur.z, target_rot.z, alpha)
	farol.rotation = cur

	# --- 5) спад «рывка» мыши ---
	_mouse_dx = move_toward(_mouse_dx, 0.0, 10.0 * delta)
