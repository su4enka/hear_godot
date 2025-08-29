extends CanvasLayer



@onready var menu_buttons = $VBoxContainer
@onready var settings := $SettingsMenu
@onready var btn_play := $VBoxContainer/ButtonPlay
@onready var btn_settings := $VBoxContainer/ButtonSettings
@onready var btn_quit := $VBoxContainer/ButtonQuit
@onready var slider := $SettingsMenu/HSliderSensitivity
@onready var lbl := $SettingsMenu/LabelSensitivity
@onready var btn_back := $SettingsMenu/ButtonBackToMenu


# --- dev/test ---
@onready var dev_toggle    := $DevToggle
@onready var dev_panel     := $DevPanel
@onready var spin_day      := $DevPanel/Grid/SpinDay
@onready var spin_ore      := $DevPanel/Grid/SpinOre
@onready var btn_apply_go  := $DevPanel/BtnApplyStart
@onready var btn_apply     := $DevPanel/BtnOnlyApply
@onready var spin_chances   := $DevPanel/Grid/SpinChances
@onready var spin_req       := $DevPanel/Grid/SpinReq
@onready var chk_skip       := $DevPanel/ChkSkipPrologue


const PS_KEY := "player/mouse_sensitivity"
const DEFAULT_SENS := 0.002

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	settings.visible = false
	btn_play.pressed.connect(_on_play)
	btn_settings.pressed.connect(_on_open_settings)
	btn_quit.pressed.connect(_on_quit)
	btn_back.pressed.connect(_on_close_settings)

	# Подсказка: играйте со звуком!
	lbl.text = "Mouse Sensitivity  |  Make the sounds louder 🎧"

	# Подтягиваем сохранённую сенсу
	if not ProjectSettings.has_setting(PS_KEY):
		ProjectSettings.set_setting(PS_KEY, DEFAULT_SENS)
		ProjectSettings.save()
	slider.min_value = 0.001
	slider.max_value = 0.01
	slider.step = 0.001
	slider.value = float(ProjectSettings.get_setting(PS_KEY))
	slider.value_changed.connect(_on_sens_changed)

		# dev/test
	dev_toggle.toggled.connect(func(on):
		dev_panel.visible = on)
	btn_apply_go.pressed.connect(_on_dev_apply_and_start)
	btn_apply.pressed.connect(_on_dev_apply_only)

	# проставим текущие значения для удобства
	spin_day.value = GameManager.current_day
	spin_ore.value = GameManager.total_ore
	spin_chances.value = GameManager.chances_left
	if GameManager.current_day - 1 >= 0 and GameManager.current_day - 1 < GameManager.ore_required_by_day.size():
		spin_req.value = GameManager.ore_required_by_day[GameManager.current_day - 1]
	chk_skip.button_pressed = not GameManager.opening_needs_confirm

func _on_sens_changed(v):
	ProjectSettings.set_setting(PS_KEY, v)
	ProjectSettings.save()

func _on_open_settings():
	menu_buttons.visible = false
	settings.visible = true

func _on_close_settings():
	menu_buttons.visible = true
	settings.visible = false

func _on_quit():
	get_tree().quit()

func _on_play():
	# Старт нового дня и показ интро будет отработан в House через GameManager
	get_tree().change_scene_to_file("res://scenes/Prologue.tscn")
	
	# ---------- DEV / TEST ----------
func _apply_dev_values():
	var d    := int(spin_day.value)
	var ore  := int(spin_ore.value)
	var ch   := int(spin_chances.value)
	var req  := int(spin_req.value)
	var skip = chk_skip.button_pressed

	# День в рамках
	d = clamp(d, 1, GameManager.total_days)
	GameManager.current_day = d

	# Пролог
	GameManager.opening_needs_confirm = not skip

	# Руда (0 = оставить как есть)
	if ore > 0:
		GameManager.total_ore = ore
	GameManager.ore_collected_today = 0

	# Chances left (0 = оставить текущее)
	if ch > 0:
		GameManager.chances_left = ch

	# Норма на день (0 = оставить из массива)
	if req > 0 and d - 1 >= 0 and d - 1 < GameManager.ore_required_by_day.size():
		GameManager.ore_required_by_day[d - 1] = req

	# Сброс флагов
	GameManager.came_from_cave = false
	GameManager.the_game_ended = false

	# Deafness
	GameManager.deafness_level = float(GameManager.current_day - 1) / float(GameManager.total_days - 1)

	# Интро
	GameManager.day_intro.emit("Day %d" % GameManager.current_day)

func _on_dev_apply_only():
	_apply_dev_values()

func _on_dev_apply_and_start():
	_apply_dev_values()
	# Запускаем день «правильно»: чтобы House получил day_started и т.п.
	GameManager.start_new_day()  # сбросит ore_collected_today и отправит сигнал. :contentReference[oaicite:3]{index=3}
	get_tree().change_scene_to_packed(preload("res://scenes/House.tscn"))
