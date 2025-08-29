extends CanvasLayer

@export var kind: String = "bad"  # "bad", "early", "good"
@onready var root := self
var idx := 0
var slides: Array[String] = []
var ended := false

func _ready():
	# Фон и базовый UI на лету, чтобы сцены можно было не трогать
	var layer := Control.new()
	layer.name = "UI"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.anchor_left = 0; layer.anchor_top = 0
	layer.anchor_right = 1; layer.anchor_bottom = 1
	add_child(layer)

	var bg := ColorRect.new()
	bg.name = "BG"
	bg.color = Color(0,0,0,0.9)
	bg.anchor_left = 0; bg.anchor_top = 0
	bg.anchor_right = 1; bg.anchor_bottom = 1
	layer.add_child(bg)

	var title := Label.new()
	title.name = "Title"
	title.text = kind.capitalize() + " Ending"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.anchor_left = 0.1; title.anchor_right = 0.9
	title.anchor_top = 0.05; title.anchor_bottom = 0.2
	layer.add_child(title)

	var body := RichTextLabel.new()
	body.name = "Body"
	body.bbcode_enabled = true
	body.scroll_active = false
	body.fit_content = true
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.anchor_left = 0.1; body.anchor_right = 0.9
	body.anchor_top = 0.22; body.anchor_bottom = 0.8
	layer.add_child(body)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Press [Enter]/[Space] to continue • [R] restart • [Esc] menu"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.1; hint.anchor_right = 0.9
	hint.anchor_top = 0.85; hint.anchor_bottom = 0.92
	layer.add_child(hint)

	# Тексты по концовкам
	slides = _slides_for(kind)
	_show_current()

func _slides_for(k:String) -> Array[String]:
	match k:
		"good":
			return [
				"[b]Fifteen days[/b]. The cave fell silent before the last dawn.",
				"You carried enough ore to buy time — and a train ticket.",
				"Your hearing won’t return, but the house keeps its warmth.\nTogether, you start over."
			]
		"early":
			return [
				"You left on day five.",
				"It wasn’t wealth, but it was choice. The ringing in your ears\ngot quieter on the road.",
				"Some caves are worth leaving behind."
			]
		_:
			return [
				"The rocks sealed the path. The warning came — too quiet.",
				"The house will empty. Debt listens better than you could.",
				"Not all echoes return."
			]

func _show_current():
	var body: RichTextLabel = get_node("UI/Body")
	body.clear()
	body.append_text(slides[idx])

func _input(ev):
	if ended: return
	if ev.is_action_pressed("ui_accept") or ev.is_action_pressed("ui_select") or ev.is_action_pressed("interact") or (ev is InputEventKey and (ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER)):
		_next()
	elif ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_R:
			_restart()
		elif ev.keycode == KEY_ESCAPE:
			_to_menu()

func _next():
	idx += 1
	if idx >= slides.size():
		ended = true
		_to_menu()
	else:
		_show_current()

func _restart():
	# начать новую игру сразу из дома
	GameManager.the_game_ended = false
	GameManager.current_day = 1
	GameManager.total_ore = 0
	GameManager.ore_collected_today = 0
	GameManager.chances_left = 2
	GameManager.opening_needs_confirm = true
	get_tree().change_scene_to_file("res://scenes/House.tscn")

func _to_menu():
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
