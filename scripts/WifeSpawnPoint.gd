extends Marker3D
class_name WifeSpawnPoint

enum Phase { MORNING, AFTER_CAVE, ANY }

@export var phase: Phase = Phase.ANY         # когда можно выбрать эту точку
@export var idle: StringName = &"sitting_idle" # имя анимации (луп)
@export_range(0.0, 10.0, 0.1) var weight := 1.0 # шанс выпадения
@export var look_at_on_interact := true         # разрешить поворот головы при E
