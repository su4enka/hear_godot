extends Area3D

@export var hits_min := 2
@export var hits_max := 3
@export var ore_amount := 1
@export var shake_pos := 0.06   # сила смещения (метры)
@export var shake_rot := 4.0    # сила поворота (в градусах)
@onready var visual: MeshInstance3D = $Visual
@onready var hit_sfx: AudioStreamPlayer3D = $HitSfx
@onready var hit_dust: CPUParticles3D = $HitDust

var hits_left := 2

func _ready():
	hits_left = randi_range(hits_min, hits_max)
	# если был автосбор по body_entered — отключаем (теперь копаем на Е)
	if is_connected("body_entered", Callable(self, "_on_body_entered")):
		disconnect("body_entered", Callable(self, "_on_body_entered"))
	add_to_group("ore") # удобнее для подсказки

func try_mine():
	if hit_sfx: hit_sfx.play()
	if hit_dust:
		hit_dust.emitting = true
		await get_tree().create_timer(0.15).timeout
		hit_dust.emitting = false
	if hits_left > 1:
		_shake_once()
	hits_left -= 1
	if hits_left <= 0:
		_break_and_collect()

func _break_and_collect():
	# тут можно проиграть звук/частицы
	GameManager.add_ore(ore_amount)
	queue_free()

func _shake_once():
	var node = visual if visual else self

	var orig_t = node.transform
	var off := Vector3(
		randf_range(-shake_pos, shake_pos),
		randf_range(-shake_pos * 0.6, shake_pos * 0.6),
		randf_range(-shake_pos, shake_pos)
	)

	var deg := deg_to_rad(shake_rot)
	var rot_off := Vector3(
		randf_range(-deg, deg),
		randf_range(-deg, deg),
		0.0
	)

	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "transform",
		Transform3D(Basis().rotated(Vector3(1,0,0), rot_off.x)
			.rotated(Vector3(0,1,0), rot_off.y),
			orig_t.origin + off),
		0.06)
	t.tween_property(node, "transform", orig_t, 0.09)
