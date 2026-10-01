# mobile_controls.gd — LEFT analog joystick, RIGHT drag-to-look, small posture
# icon + single contextual action button. Touch-index ownership so move+look
# work simultaneously. Desktop: WASD + mouse drag + E/C/F keys still work.
class_name MobileControls
extends CanvasLayer

var player: Corley
var camera_rig: ThirdPersonCamera
var move_base: Control
var move_knob: Control
var posture_btn: Button
var action_btn: Button
var strike_btn: Button
var guard_btn: Button
var look_area: Control

var move_touch := -1
var look_touch := -1
var move_center := Vector2.ZERO
var joy_radius := 90.0
var last_look_pos := Vector2.ZERO
var action_visible := false
var action_text := ""

func setup(p: Corley, cam: ThirdPersonCamera) -> void:
	player = p
	camera_rig = cam
	_build_ui()
	set_process_input(true)

func _build_ui() -> void:
	var root := Control.new()
	root.name = "TouchUI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# LEFT joystick base (subtle circle)
	move_base = Control.new()
	move_base.name = "MoveBase"
	move_base.custom_minimum_size = Vector2(190, 190)
	move_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	move_base.position = Vector2(36, -226)
	move_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(move_base)
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(95)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(2)
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_base.add_child(bg)
	move_knob = Control.new()
	move_knob.custom_minimum_size = Vector2(76, 76)
	move_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_base.add_child(move_knob)
	var knob := Panel.new()
	knob.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ksb := StyleBoxFlat.new()
	ksb.bg_color = Color(1, 1, 1, 0.28)
	ksb.set_corner_radius_all(38)
	knob.add_theme_stylebox_override("panel", ksb)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_knob.add_child(knob)
	_reset_knob()
	# RIGHT look area: transparent full-right-half catcher
	look_area = Control.new()
	look_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_area.offset_left = 1280 * 0.35
	look_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(look_area)
	# posture icon button (small circle, bottom-right above actions)
	posture_btn = Button.new()
	posture_btn.text = "🧍" # standing icon; toggles to 🧎-like via text change
	posture_btn.custom_minimum_size = Vector2(64, 64)
	posture_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	posture_btn.position = Vector2(-96, -200)
	posture_btn.focus_mode = Control.FOCUS_NONE
	posture_btn.pressed.connect(_on_posture)
	root.add_child(posture_btn)
	_style_circle_btn(posture_btn)
	# context action button (single, appears with label)
	action_btn = Button.new()
	action_btn.text = "◉"
	action_btn.custom_minimum_size = Vector2(84, 84)
	action_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	action_btn.position = Vector2(-200, -120)
	action_btn.focus_mode = Control.FOCUS_NONE
	action_btn.pressed.connect(_on_action)
	root.add_child(action_btn)
	_style_circle_btn(action_btn)
	action_btn.visible = false
	# strike / guard: tiny icons revealed only during encounter pressure
	strike_btn = Button.new()
	strike_btn.text = "✊"
	strike_btn.custom_minimum_size = Vector2(60, 60)
	strike_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	strike_btn.position = Vector2(-290, -190)
	strike_btn.focus_mode = Control.FOCUS_NONE
	strike_btn.pressed.connect(func() -> void: if player: player.do_strike())
	root.add_child(strike_btn)
	_style_circle_btn(strike_btn)
	strike_btn.visible = false
	guard_btn = Button.new()
	guard_btn.text = "🛡"
	guard_btn.custom_minimum_size = Vector2(60, 60)
	guard_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	guard_btn.position = Vector2(-290, -120)
	guard_btn.focus_mode = Control.FOCUS_NONE
	guard_btn.button_down.connect(func() -> void: if player: player.guard_held = true)
	guard_btn.button_up.connect(func() -> void: if player: player.guard_held = false)
	root.add_child(guard_btn)
	_style_circle_btn(guard_btn)
	guard_btn.visible = false
	if player:
		player.posture_changed.connect(_on_posture_changed)
		player.interact_hint.connect(_on_hint_text)

func _style_circle_btn(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.11, 0.55)
	sb.set_corner_radius_all(32)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.15, 0.25, 0.28, 0.7)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_color_override("font_color", Color(0.92, 0.95, 0.94))

func _reset_knob() -> void:
	move_knob.position = Vector2(57, 57)

func _on_posture() -> void:
	if player:
		player.set_crouched(not player.crouched)

func _on_posture_changed(crouched: bool) -> void:
	posture_btn.text = "⬇" if crouched else "🧍" # icon indicates current posture

func _on_hint_text(_t: String) -> void:
	pass

func _on_action() -> void:
	if player:
		player.try_interact()

func set_action(label: String, combat: bool = false) -> void:
	if label.is_empty():
		action_btn.visible = false
	else:
		action_btn.visible = true
		action_btn.text = "◎" # full label lives in the prompt line; button stays iconic
		action_btn.tooltip_text = label
	strike_btn.visible = combat
	guard_btn.visible = combat

func _input(event: InputEvent) -> void:
	if player == null or camera_rig == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if st.position.x < vp.x * 0.4 and move_touch == -1:
				move_touch = st.index
				move_center = st.position
			elif st.position.x >= vp.x * 0.35 and look_touch == -1:
				look_touch = st.index
				last_look_pos = st.position
		else:
			if st.index == move_touch:
				move_touch = -1
				player.move_input = Vector2.ZERO
				_reset_knob()
			if st.index == look_touch:
				look_touch = -1
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if dr.index == move_touch:
			var d: Vector2 = dr.position - move_center
			if d.length() > joy_radius:
				d = d.normalized() * joy_radius
			move_knob.position = Vector2(57, 57) + d * (57.0 / joy_radius)
			# screen up = forward: invert y
			var v := Vector2(d.x / joy_radius, -d.y / joy_radius)
			player.move_input = v.limit_length(1.0)
		elif dr.index == look_touch:
			var delta: Vector2 = dr.position - last_look_pos
			last_look_pos = dr.position
			camera_rig.add_look(delta.x, delta.y)
	# desktop fallback: mouse drag on right side rotates camera
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		camera_rig.add_look(mm.relative.x * 2.0, mm.relative.y * 2.0)
