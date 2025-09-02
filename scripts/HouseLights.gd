# HouseLights.gd
extends Node

@export var off_chance := 0.12          # часть ламп останутся полностью выключенными
@export var flicker_chance := 0.28      # часть ламп немного померцают
@export var settle_after_flicker := 0.0 # через сколько секунд прекратить мерцание и стабилизировать

func lights_on_arrival() -> void:
	var lamps := get_tree().get_nodes_in_group("lamps")
	for l in lamps:
		if l is LampController:
			if randf() < off_chance:
				l.turn_off()
			else:
				var do_flicker := randf() < flicker_chance
				l.turn_on(do_flicker)
				if do_flicker and settle_after_flicker > 0.0:
					# через N секунд остановим мерцание
					var t := get_tree().create_timer(randf_range(1.2, settle_after_flicker))
					t.timeout.connect(func():
						if is_instance_valid(l):
							l.stop_flicker()
					)

func lights_off() -> void:
	if !GameManager.the_game_ended:
		for l in get_tree().get_nodes_in_group("lamps"):
			if l is LampController:
				l.turn_off()
