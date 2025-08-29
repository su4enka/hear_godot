extends CanvasLayer

var slides := [
	"[b]We moved for work.[/b]\nA cave outside the town. Fifteen days to make enough.",
	"The house is small. Warm, when the oven breathes.\nThe cave is colder, and it listens.",
	"She said: 'We’ll leave if it breaks you.'\nI said: 'It won’t.'",
]

var idx := 0
var ended := false

func _ready():
	_build_ui()
	_show()

func _build_ui():
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
	title.text = "Prologue"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.anchor_left = 0.1; title.anchor_right = 0.9
	title.anchor_top = 0.05; title.anchor_bottom = 0.18
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
	hint.text = "Press [Enter]/[Space]/[E] to continue • [Esc] skip"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.1; hint.anchor_right = 0.9
	hint.anchor_top = 0.85; hint.anchor_bottom = 0.92
	layer.add_child(hint)

func _show():
	var body: RichTextLabel = get_node("UI/Body")
	body.clear()
	body.append_text(slides[idx])

func _input(ev):
	if ended: return
	if _is_skip(ev):
		_next()
	elif ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		_finish_and_start()

func _is_skip(ev: InputEvent) -> bool:
	# Actions (ui_accept / ui_select / interact)
	if (ev.is_action_pressed("ui_accept")
		or ev.is_action_pressed("ui_select")
		or ev.is_action_pressed("interact")):
		# не реагируем на автоповтор клавиши
		if ev is InputEventKey and ev.echo:
			return false
		return true

	# Прямые клавиши (если они не входят в эти действия)
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER:
			return true

	return false

func _next():
	idx += 1
	if idx >= slides.size():
		_finish_and_start()
	else:
		_show()

func _finish_and_start():
	ended = true
	# Чистый старт новой игры и автоскрытие Day 1
	GameManager.reset_state()
	GameManager.opening_needs_confirm = false   # Day 1 не ждёт нажатия
	GameManager.start_new_day()
	get_tree().change_scene_to_file("res://scenes/House.tscn")
