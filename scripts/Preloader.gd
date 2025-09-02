# res://autoload/Preloader.gd
extends Node

# Явно типизируем словарь: имя -> путь
const SCENES: Dictionary[String, String] = {
	"house": "res://scenes/House.tscn",
	"cave":  "res://scenes/Cave.tscn",
}

var _packed: Dictionary[String, PackedScene] = {}
var _instances: Dictionary[String, Node] = {}

func warmup_sync(pack_and_instantiate: bool = false) -> void:
	for k: String in SCENES.keys():
		var ps: PackedScene = load(SCENES[k]) as PackedScene
		if ps:
			_packed[k] = ps
			if pack_and_instantiate:
				var inst: Node = ps.instantiate()
				inst.visible = false
				inst.process_mode = Node.PROCESS_MODE_DISABLED
				get_tree().root.add_child(inst)
				_instances[k] = inst

func preload_async(name: String) -> void:
	if _packed.has(name): return
	if not SCENES.has(name): return
	var path: String = SCENES[name] # ← строго String
	ResourceLoader.load_threaded_request(path, "PackedScene")

func is_loaded(name: String) -> bool:
	return _packed.has(name)

func ensure_loaded(name: String) -> void:
	if _packed.has(name): return
	if not SCENES.has(name): return
	var path: String = SCENES[name]

	var status: int = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var res := ResourceLoader.load_threaded_get(path)
		_packed[name] = res as PackedScene
		return
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		var res2 := ResourceLoader.load_threaded_get(path)
		_packed[name] = res2 as PackedScene
		return
	else:
		var ps: PackedScene = load(path) as PackedScene
		if ps:
			_packed[name] = ps

func get_packed(name: String) -> PackedScene:
	return _packed.get(name, null)

func get_or_make_instance(name: String) -> Node:
	if _instances.has(name):
		return _instances[name]
	var ps: PackedScene = get_packed(name)
	if ps == null: return null
	var inst: Node = ps.instantiate()
	_instances[name] = inst
	return inst

func free_instance(name: String) -> void:
	if not _instances.has(name): return
	var n: Node = _instances[name]
	if is_instance_valid(n):
		n.queue_free()
	_instances.erase(name)
