extends Control
## On-screen controls for phones using the new cartoon assets.
## LEFT  : virtual joystick with JoyStickBG.png base + JoyStick.png knob
## RIGHT : four independent action buttons - Jump, Punch, Grab, Dash

const Cartoon := preload("res://scripts/cartoon_ui.gd")
const UIKit := preload("res://scripts/ui_kit.gd")
const HUD_VIVID_SHADER := preload("res://assets/shaders/hud_vivid.gdshader")

signal jump_pressed
signal push_pressed
signal dash_pressed

const DEAD_ZONE := 0.12
const TOP_RESERVED := 0.14   # top strip reserved for the HUD's native buttons

var enabled := true
var input_exclusion_controls: Array[Control] = []

# Joystick
var _joy_touch := -1
var _joy_center: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO
var _joy_vector: Vector2 = Vector2.ZERO

# Camera drag
var _cam_touch := -1
var _cam_delta: Vector2 = Vector2.ZERO

# Action buttons
var _jump_touch := -1
var _punch_touch := -1
var _grab_touch := -1
var _jump_down := false
var _punch_down := false
var _grab_down := false
var _jump_queued := false
var _punch_queued := false
var _grab_queued := false
var _charge_t := 0.0
var _charge_release := 0.0

# Arm mode (punch vs grab)
var _arm_mode := 0  # 0 = punch, 1 = grab
var _role_ui := 0   # 0 normal, 1 hider (no attack), 2 seeker (instant CATCH)
var _can_switch_mode := true

# Dash
var _dash_touch := -1
var _dash_down := false
var _dash_queued := false
var _dash_cd_frac := 0.0

# Attack cooldown (shared for punch/grab)
var _attack_cd_frac := 0.0

# Swapped layout
var _swapped := false

# Animation

# Textures
var _joy_bg_tex: Texture2D
var _joy_knob_tex: Texture2D
var _jump_tex: Texture2D
var _punch_tex: Texture2D
var _grab_tex: Texture2D
var _dash_tex: Texture2D

# Layout rects
var _joy_bg_rect: Rect2
var _joy_knob_rect: Rect2
var _jump_rect: Rect2
var _punch_rect: Rect2
var _grab_rect: Rect2
var _dash_rect: Rect2

var _jump_center: Vector2
var _punch_center: Vector2
var _grab_center: Vector2
var _dash_center: Vector2

var _joy_radius := 80.0
var _btn_radius := 54.0

# Button size multipliers (relative to _btn_radius)
const BTN_JUMP_MULT := 1.3
const BTN_ACTION_MULT := 1.1
const BTN_DASH_MULT := 0.9


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vivid_material := ShaderMaterial.new()
	vivid_material.shader = HUD_VIVID_SHADER
	material = vivid_material
	add_to_group("touch_controls")

	# Load textures
	_joy_bg_tex = load("res://NewAssets/in_game/JoyStickBG.png")
	_joy_knob_tex = load("res://NewAssets/in_game/JoyStick.png")
	_jump_tex = load("res://NewAssets/in_game/jump.png")
	_punch_tex = load("res://NewAssets/in_game/punch.png")
	_grab_tex = load("res://NewAssets/in_game/grab.png")
	_dash_tex = load("res://NewAssets/in_game/Dash.png")

	resized.connect(_layout)
	SettingsManager.settings_changed.connect(func(_k: String, _v: Variant) -> void: _layout())
	call_deferred("_layout")


func _process(delta: float) -> void:
	# Charge timer for punch/grab
	if (_punch_down or _grab_down) and _role_ui == 0:
		_charge_t += delta
		queue_redraw()


func _layout() -> void:
	var s := size
	var safe := UIKit.safe_insets(get_viewport())
	# Scale the touch targets with the actual viewport. The HUD may run at a
	# portrait/mobile resolution or in a smaller embedded viewport.
	var ui_scale := minf(1.0, minf(s.x / 1280.0, s.y / 720.0))
	_joy_radius = 100.0 * float(SettingsManager.get_setting("joystick_size")) * ui_scale
	_btn_radius = 68.0 * float(SettingsManager.get_setting("button_size")) * ui_scale
	_swapped = bool(SettingsManager.get_setting("controls_swapped"))

	var left := safe.x
	var top := safe.y
	var usable_w := s.x - safe.x - safe.z
	var usable_h := s.y - safe.y - safe.w

	# Joystick position (left side by default) - FIXED BASE (non-floating)
	var joy_x := left + usable_w * 0.104
	if _swapped:
		joy_x = left + usable_w * 0.896

	_joy_center = Vector2(joy_x, top + usable_h * 0.82)
	var joy_diam := _joy_radius * 2.0
	_joy_bg_rect = Rect2(_joy_center - Vector2(_joy_radius, _joy_radius), Vector2(joy_diam, joy_diam))
	# The source knob has substantial transparent padding, so draw it larger
	# than its nominal texture ratio to make the visible handle usable.
	var knob_r := _joy_radius * 0.85 * 1.25
	_joy_knob_rect = Rect2(Vector2(0, 0), Vector2(knob_r * 2.0, knob_r * 2.0))

	# Four independent actions in a compact 2x2 cluster.
	var jump_r := _btn_radius * BTN_JUMP_MULT
	var action_r := _btn_radius * BTN_ACTION_MULT
	var dash_r := _btn_radius * BTN_DASH_MULT
	var right := left + usable_w
	var jump_x := left + usable_w * (0.925 if not _swapped else 0.075)
	var punch_x := left + usable_w * (0.81 if not _swapped else 0.19)
	var grab_x := left + usable_w * (0.91 if not _swapped else 0.09)
	var dash_x := left + usable_w * (0.77 if not _swapped else 0.23)
	if _swapped:
		jump_x = clampf(jump_x, left + jump_r, right - jump_r)
		punch_x = clampf(punch_x, left + action_r, right - action_r)
		grab_x = clampf(grab_x, left + action_r, right - action_r)
		dash_x = clampf(dash_x, left + dash_r, right - dash_r)

	_jump_center = Vector2(jump_x, top + usable_h * 0.856)
	_punch_center = Vector2(punch_x, top + usable_h * 0.756)
	_grab_center = Vector2(grab_x, top + usable_h * 0.588)

	_jump_rect = Rect2(_jump_center - Vector2(jump_r, jump_r), Vector2(jump_r * 2.0, jump_r * 2.0))
	_punch_rect = Rect2(_punch_center - Vector2(action_r, action_r), Vector2(action_r * 2.0, action_r * 2.0))
	_grab_rect = Rect2(_grab_center - Vector2(action_r, action_r), Vector2(action_r * 2.0, action_r * 2.0))

	# Dash fills the open upper-left spot beside Grab, as the fourth action.
	_dash_center = Vector2(dash_x, top + usable_h * 0.588)
	_dash_rect = Rect2(_dash_center - Vector2(dash_r, dash_r), Vector2(dash_r * 2.0, dash_r * 2.0))

	queue_redraw()


# ---------------------------------------------------------------------------
# Public API used by player_controller.gd

func get_move_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	return _joy_vector


func consume_jump() -> bool:
	var v := _jump_queued
	_jump_queued = false
	return v


func consume_push() -> bool:
	return consume_punch() or consume_grab()


func consume_punch() -> bool:
	var value := _punch_queued
	_punch_queued = false
	return value


func consume_grab() -> bool:
	var value := _grab_queued
	_grab_queued = false
	return value


func consume_charge() -> float:
	var c := _charge_release
	_charge_release = 0.0
	return c


func is_attack_down() -> bool:
	return _punch_down or _grab_down


func get_charge_fraction() -> float:
	if not (_punch_down or _grab_down) or _role_ui != 0:
		return 0.0
	return clampf(_charge_t / 0.85, 0.0, 1.0)


func set_role_ui(role: int) -> void:
	_role_ui = role
	_release_all()
	queue_redraw()


func consume_dash() -> bool:
	var v := _dash_queued
	_dash_queued = false
	return v


func consume_arm_mode() -> bool:
	return false


func consume_mode() -> bool:
	# Backward compatibility alias
	return consume_arm_mode()


func set_status(dash_frac: float, attack_frac: float, arm_mode: int, can_switch_mode := true) -> void:
	var changed := absf(dash_frac - _dash_cd_frac) > 0.01 or absf(attack_frac - _attack_cd_frac) > 0.01 or arm_mode != _arm_mode or can_switch_mode != _can_switch_mode
	_dash_cd_frac = clampf(dash_frac, 0.0, 1.0)
	_attack_cd_frac = clampf(attack_frac, 0.0, 1.0)
	_arm_mode = arm_mode
	_can_switch_mode = can_switch_mode
	if changed:
		queue_redraw()


func flash_denied(which: String) -> void:
	queue_redraw()


func consume_camera_delta() -> Vector2:
	var d := _cam_delta
	_cam_delta = Vector2.ZERO
	return d


func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if not value:
		_release_all()


func _release_all() -> void:
	_joy_touch = -1
	_cam_touch = -1
	_jump_touch = -1
	_punch_touch = -1
	_grab_touch = -1
	_dash_touch = -1
	_dash_down = false
	_dash_queued = false
	_jump_down = false
	_punch_down = false
	_grab_down = false
	_charge_t = 0.0
	_joy_vector = Vector2.ZERO
	_cam_delta = Vector2.ZERO
	_jump_queued = false
	_punch_queued = false
	_grab_queued = false
	queue_redraw()


# ---------------------------------------------------------------------------
# Touch handling

func _input(event: InputEvent) -> void:
	if not enabled or not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_began(event.index, event.position)
		else:
			_touch_ended(event.index)
	elif event is InputEventScreenDrag:
		_touch_moved(event.index, event.position, event.relative)


func _touch_began(idx: int, pos: Vector2) -> void:
	for control in input_exclusion_controls:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(pos):
			return
	if pos.y < size.y * TOP_RESERVED:
		return # HUD strip: let other buttons handle it

	# Check buttons from top to bottom (priority order)
	var jump_r := _btn_radius * BTN_JUMP_MULT
	var action_r := _btn_radius * BTN_ACTION_MULT
	var dash_r := _btn_radius * BTN_DASH_MULT
	if pos.distance_to(_jump_center) <= jump_r * 1.2:
		_jump_touch = idx
		_jump_down = true
		_jump_queued = true
		jump_pressed.emit()
		_consume()
	elif pos.distance_to(_punch_center) <= action_r * 1.2 and _role_ui != 1:
		_punch_touch = idx
		_punch_down = true
		_punch_queued = _role_ui == 2 # hide-and-seek catch is instant
		_charge_t = 0.0
		push_pressed.emit()
		_consume()
	elif pos.distance_to(_grab_center) <= action_r * 1.2 and _role_ui != 1:
		_grab_touch = idx
		_grab_down = true
		_grab_queued = _role_ui == 2 # hide-and-seek catch is instant
		_charge_t = 0.0
		push_pressed.emit()
		_consume()
	elif pos.distance_to(_dash_center) <= dash_r * 1.2:
		_dash_touch = idx
		_dash_down = true
		_dash_queued = true
		_consume()
	elif _is_joystick_side(pos) and _joy_touch == -1:
		_joy_touch = idx
		# Fixed base: _joy_center stays at its layout position
		# Knob starts at center and moves toward touch
		var offset: Vector2 = pos - _joy_center
		var max_r: float = _joy_radius * 0.6
		if offset.length() > max_r:
			offset = offset.normalized() * max_r
		_joy_pos = _joy_center + offset
		var v: Vector2 = offset / max_r
		var l: float = v.length()
		if l < DEAD_ZONE:
			v = Vector2.ZERO
		else:
			v = v.normalized() * ((l - DEAD_ZONE) / (1.0 - DEAD_ZONE))
			v *= float(SettingsManager.get_setting("joystick_sensitivity"))
			if v.length() > 1.0:
				v = v.normalized()
		_joy_vector = v
		_consume()
	elif _cam_touch == -1:
		_cam_touch = idx
		_consume()
	queue_redraw()


func _touch_moved(idx: int, pos: Vector2, relative: Vector2) -> void:
	if idx == _joy_touch:
		var offset: Vector2 = pos - _joy_center
		var max_r: float = _joy_radius * 0.6
		# Clamp knob position to base radius (non-floating joystick)
		if offset.length() > max_r:
			offset = offset.normalized() * max_r
		_joy_pos = _joy_center + offset
		var v: Vector2 = offset / max_r
		var l: float = v.length()
		if l < DEAD_ZONE:
			v = Vector2.ZERO
		else:
			v = v.normalized() * ((l - DEAD_ZONE) / (1.0 - DEAD_ZONE))
			v *= float(SettingsManager.get_setting("joystick_sensitivity"))
			if v.length() > 1.0:
				v = v.normalized()
		_joy_vector = v
		_consume()
		queue_redraw()
	elif idx == _cam_touch:
		_cam_delta += relative
		_consume()


func _touch_ended(idx: int) -> void:
	if idx == _joy_touch:
		_joy_touch = -1
		_joy_vector = Vector2.ZERO
	elif idx == _cam_touch:
		_cam_touch = -1
	elif idx == _jump_touch:
		_jump_touch = -1
		_jump_down = false
	elif idx == _punch_touch:
		_punch_touch = -1
		if _punch_down and _role_ui == 0:
			_punch_queued = true
			_charge_release = clampf(_charge_t / 0.85, 0.0, 1.0)
		_punch_down = false
		_charge_t = 0.0
	elif idx == _grab_touch:
		_grab_touch = -1
		if _grab_down and _role_ui == 0:
			_grab_queued = true
			_charge_release = clampf(_charge_t / 0.85, 0.0, 1.0)
		_grab_down = false
		_charge_t = 0.0
	elif idx == _dash_touch:
		_dash_touch = -1
		_dash_down = false
	queue_redraw()


func _is_joystick_side(pos: Vector2) -> bool:
	var left_side := pos.x < size.x * 0.45
	return left_side != _swapped


func _consume() -> void:
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Drawing

func _draw() -> void:
	var op_j := float(SettingsManager.get_setting("joystick_opacity"))
	var op_b := float(SettingsManager.get_setting("button_opacity"))

	# Draw joystick background
	if _joy_bg_tex != null:
		draw_texture_rect(_joy_bg_tex, _joy_bg_rect, false, Color(1, 1, 1, op_j))

	# Draw joystick knob (moves with finger)
	var knob_pos := _joy_center if _joy_touch == -1 else _joy_pos
	var knob_rect := Rect2(knob_pos - _joy_knob_rect.size * 0.5, _joy_knob_rect.size)
	if _joy_knob_tex != null:
		draw_texture_rect(_joy_knob_tex, knob_rect, false, Color(1, 1, 1, op_j))

	# Jump button
	_draw_action_button(_jump_rect, _jump_tex, _jump_down, op_b)

	# The four touch actions are always visible; Punch and Grab are distinct.
	if _role_ui != 1:
		_draw_action_button(_punch_rect, _punch_tex, _punch_down, op_b, _attack_cd_frac)
		if _punch_down and _role_ui == 0:
			# Charge ring
			var f := clampf(_charge_t / 0.85, 0.0, 1.0)
			var ring_color := Color(1.0, 1.0 - 0.7 * f, 0.2, 0.95)
			var action_r := _btn_radius * BTN_ACTION_MULT
			draw_arc(_punch_center, action_r * 1.22, -PI * 0.5, -PI * 0.5 + TAU * f, 40, ring_color, 7.0, true)

	if _role_ui != 1:
		_draw_action_button(_grab_rect, _grab_tex, _grab_down, op_b, _attack_cd_frac)
		if _grab_down and _role_ui == 0:
			var f := clampf(_charge_t / 0.85, 0.0, 1.0)
			var ring_color := Color(1.0, 1.0 - 0.7 * f, 0.2, 0.95)
			var action_r := _btn_radius * BTN_ACTION_MULT
			draw_arc(_grab_center, action_r * 1.22, -PI * 0.5, -PI * 0.5 + TAU * f, 40, ring_color, 7.0, true)

	# Dash button
	var dash_color := Color(1.0, 0.75, 0.15) if _dash_cd_frac <= 0.0 else Color(0.55, 0.5, 0.4)
	_draw_action_button(_dash_rect, _dash_tex, _dash_down, op_b, _dash_cd_frac, dash_color)


func _draw_action_button(rect: Rect2, texture: Texture2D, down: bool, opacity: float, cooldown: float = 0.0, base_color: Color = Color(1, 1, 1, 1)) -> void:
	var scale := 0.9 if down else 1.0
	var draw_rect := Rect2(rect.position + rect.size * (1.0 - scale) * 0.5, rect.size * scale)
	if texture != null:
		# These assets already contain the complete button artwork; drawing the
		# old circle underneath and shrinking the art into it caused the offset,
		# double-ring appearance. Fit without distorting their source aspect.
		var tex_size := Vector2(texture.get_size())
		var fit := minf(draw_rect.size.x / tex_size.x, draw_rect.size.y / tex_size.y)
		var fitted_size := tex_size * fit
		var fitted_rect := Rect2(draw_rect.get_center() - fitted_size * 0.5, fitted_size)
		draw_texture_rect(texture, fitted_rect, false, Color(1, 1, 1, opacity))
	else:
		var shadow_rect := Rect2(draw_rect.position + Vector2(0, 4), draw_rect.size)
		draw_circle(shadow_rect.get_center(), shadow_rect.size.x * 0.5, Color(0, 0, 0, 0.25 * opacity))
		draw_circle(draw_rect.get_center(), draw_rect.size.x * 0.5, Color(base_color.r, base_color.g, base_color.b, (1.0 if down else 0.8) * opacity))
		draw_arc(draw_rect.get_center(), draw_rect.size.x * 0.5, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * opacity), 3.0, true)

	# Cooldown ring
	if cooldown > 0.0:
		var r := draw_rect.size.x * 0.5
		draw_arc(draw_rect.position + draw_rect.size * 0.5, r * 0.5, -PI * 0.5, -PI * 0.5 + TAU * cooldown, 32, Color(0, 0, 0, 0.6 * opacity), r, true)
