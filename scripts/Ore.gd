extends Area3D
signal collected(amount)
@export var ore_amount := 1

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("player"):
		collected.emit(ore_amount)
		queue_free()
