extends Control

@export var bus_name := "Master"
@export var min_freq := 80.0
@export var max_freq := 8000.0
@export var bands := 24
@export var fall_speed := 6.0

var _inst: AudioEffectSpectrumAnalyzerInstance
var _heights: PackedFloat32Array

func _ready():
	var bus = AudioServer.get_bus_index(bus_name)
	for i in range(AudioServer.get_bus_effect_count(bus)):
		var eff = AudioServer.get_bus_effect(bus, i)
		if eff is AudioEffectSpectrumAnalyzer:
			_inst = AudioServer.get_bus_effect_instance(bus, i)
			break
	_heights.resize(bands)
	set_process(true)

func _process(delta):
	if _inst == null: return
	var h = size.y
	for b in range(bands):
		var t1 = float(b)/bands
		var t2 = float(b+1)/bands
		var f1 = exp(lerp(log(min_freq), log(max_freq), t1))
		var f2 = exp(lerp(log(min_freq), log(max_freq), t2))
		var mag = _inst.get_magnitude_for_frequency_range(f1, f2).length()
		var db = linear_to_db(max(mag, 0.00001))   # -∞..0
		var norm = clamp((db + 60.0) / 60.0, 0.0, 1.0)  # -60..0 → 0..1
		var px = norm * h
		_heights[b] = max(_heights[b] - fall_speed * delta * h, px)
	queue_redraw()

func _draw():
	var w = size.x
	var h = size.y
	var gap = 2.0
	var bw = (w - gap * (bands - 1)) / bands
	for b in range(bands):
		var bar_h = _heights[b]
		if bar_h <= 1.0: continue
		var x = b * (bw + gap)
		draw_rect(Rect2(Vector2(x, h - bar_h), Vector2(bw, bar_h)), Color.WHITE)
