extends Node

@export var house_stream: AudioStream
@export var cave_stream: AudioStream

# твики
@export var fade_in_sec: float = 2.0
@export var fade_out_sec: float = 0.8
@export var base_min_db: float = -60.0  # день 1 (почти тишина)
@export var base_max_db: float = -12.0  # день 15 (ощутимо)
@export var curve_pow: float = 0.7      # форма роста (1.0 линейно; <1 быстрее растёт)

# лёгкая дыхалка громкости (LFO)
@export var wobble_db: float = 1.5
@export var wobble_sec: float = 4.0

var _player: AudioStreamPlayer
var _current_ctx := ""
var _tween: Tween
var _wobble_on := true

func _ready():
	_player = AudioStreamPlayer.new()
	_player.bus = "Rumble"
	_player.volume_db = -80.0
	_player.autoplay = false
	add_child(_player)
	# обновляться при старте каждого дня
	if Engine.has_singleton("GameManager"):
		GameManager.day_started.connect(_on_day_started)

	_start_wobble()

func _on_day_started(_d):
	_update_target_db(true)

func enter_context(ctx: String) -> void:
	if _current_ctx == ctx and _player.stream:
		_update_target_db(true)
		return

	_current_ctx = ctx
	var next: AudioStream = null
	if ctx == "house":
		next = house_stream
	elif ctx == "cave":
		next = cave_stream

	if next != null:
		_player.stream = next
		if not _player.playing:
			_player.play()
	else:
		# нет стима — просто выключаемся
		_fade_to(-80.0, fade_out_sec)
		return

	_update_target_db(false)

func _update_target_db(smooth: bool):
	var target := _compute_target_db()
	_fade_to(target, fade_in_sec if smooth else 0.1)

func _compute_target_db() -> float:
	# deafness_level 0..1 → растущая громкость с кривой
	var t := pow(GameManager.deafness_level, curve_pow)
	var db = lerp(base_min_db, base_max_db, t)

	# частичная компенсация общего «оглушения» Master (если ты его делаешь)
	# например, вернём половину просадки: (см. CaveManager._compute_master_db)
	var master_drop = lerp(0.0, -18.0, GameManager.deafness_level)  # подгони под свой master_drop_db
	db -= master_drop * 0.5

	return clamp(db, -80.0, 6.0)

func _fade_to(db: float, sec: float):
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_player, "volume_db", db, max(0.0, sec))

func _start_wobble():
	if not _wobble_on: return
	await get_tree().process_frame
	while true:
		var a := _player.volume_db
		var up := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		up.tween_property(_player, "volume_db", a + wobble_db, wobble_sec * 0.5)
		await up.finished
		var down := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		down.tween_property(_player, "volume_db", a, wobble_sec * 0.5)
		await down.finished
