extends Node3D
## Optional standalone tutorial. Uses the production player and touch controls;
## progress only follows actual movement and accepted jump/attack actions.
const PlayerScene := preload("res://scenes/player.tscn")
const Scenery := preload("res://scripts/scenery.gd")

var player: Node = null
var step := 0
var _start_position := Vector3.ZERO

@onready var touch_controls: Control = $TutorialUI/TouchControls
@onready var _message: Label = $TutorialUI/Margin/Row/MessagePanel/Message
@onready var _exit_button: Button = $TutorialUI/Margin/Row/ExitTutorial

func _ready() -> void:
	# Apply the new cartoon theme to the UI.
	var cartoon := preload("res://scripts/cartoon_ui.gd")
	var ui_theme := cartoon.theme()
	$TutorialUI/TouchControls.theme = ui_theme
	$TutorialUI/Margin.theme = ui_theme

	_build_world()
	touch_controls.input_exclusion_controls.append(_exit_button)
	_exit_button.pressed.connect(_exit_tutorial)
	player = PlayerScene.instantiate()
	player.setup(1, SaveManager.player_name, SaveManager.color_index, false)
	player.position = Vector3(0, 0.8, 0)
	add_child(player)
	player.face_direction(Vector3(0, 0, -1))
	player.jump_performed.connect(_on_jump)
	player.attack_performed.connect(_on_attack)
	_start_position = player.global_position
	_show_step()

func _build_world() -> void:
	var preset := int(SettingsManager.get_setting("graphics_preset"))
	Scenery.build_environment(self, bool(SettingsManager.get_setting("shadows")), preset)

func _physics_process(_delta: float) -> void:
	if step == 0 and is_instance_valid(player):
		var displacement: Vector3 = player.global_position - _start_position
		displacement.y = 0
		if displacement.length() >= 2.0:
			step = 1
			_show_step()

func _on_jump() -> void:
	if step == 1:
		step = 2
		_show_step()

func _on_attack() -> void:
	if step == 2:
		step = 3
		_show_step()

func _show_step() -> void:
	var keys := ["tutorial_move", "tutorial_jump", "tutorial_attack", "tutorial_complete"]
	_message.text = GameManager.t(keys[clampi(step, 0, 3)])

func _exit_tutorial() -> void:
	GameManager.go_to_main_menu()
