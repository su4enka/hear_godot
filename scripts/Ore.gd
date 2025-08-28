extends Area3D
@export var hits_min := 2
@export var hits_max := 3
@export var ore_amount := 1
var hits_left := 2

func _ready():
	hits_left = randi_range(hits_min, hits_max)
	# отключаем автосбор при входе:
	if is_connected("body_entered", Callable(self, "_on_body_entered")):
		disconnect("body_entered", Callable(self, "_on_body_entered"))

func try_mine():
	hits_left -= 1
	if hits_left <= 0:
		GameManager.add_ore(ore_amount)
		queue_free()
