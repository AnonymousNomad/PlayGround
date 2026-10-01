# corley.gd — Corley third-person controller: movement, full-body crouch,
# camera-relative analog locomotion, procedural gait animation, footstep events,
# interaction, minimal combat (strike/guard/evade), injury hooks.
class_name Corley
extends CharacterBody3D

signal footstep(side: String, surface: String, loudness: float)
signal posture_changed(crouched: bool)
signal interact_hint(text: String)
signal hurt_taken(amount: float)

const WALK_SPEED := 2.3
const RUN_SPEED := 5.2
const CROUCH_SPEED := 1.15
const BACKPEDAL_MULT := 0.7
const TURN_LERP := 10.0

var bones: Dictionary = {}
var rig: Node3D
var hips_base_y := 0.96
var crouched := false
var crouch_amount := 0.0
var gait_phase := 0.0
var last_step_half := 0 # 0/1 which foot last fired
var anim_state := "IDLE"
var move_input := Vector2.ZERO # x strafe, y forward (from joystick+keys)
var cam_yaw := 0.0
var model_yaw := 0.0
var interact_timer := 0.0
var hurt_timer := 0.0
var guard_held := false
var pain := 0.0 # 0..1 persists, slows slightly
var noise_level := 0.0
var surface := "soil"
var world: Node = null # set by game.gd (world_builder)
var survival: Node = null
var frozen := false # awakening lie-still etc.

var col_stand: CollisionShape3D
var col_crouch: CollisionShape3D
var step_ray: RayCast3D

func _ready() -> void:
	var built: Dictionary = CorleyRig.build(self, "corley")
	bones = built["bones"]
	rig = built["rig"]
	hips_base_y = built["hips_base_y"]
	# collision: standing capsule + crouch capsule
	col_stand = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.66
	col_stand.shape = cap
	col_stand.position = Vector3(0, 0.86, 0)
	add_child(col_stand)
	col_crouch = CollisionShape3D.new()
	var cap2 := CapsuleShape3D.new()
	cap2.radius = 0.30
	cap2.height = 1.10
	col_crouch.shape = cap2
	col_crouch.position = Vector3(0, 0.58, 0)
	col_crouch.disabled = true
	add_child(col_crouch)
	step_ray = RayCast3D.new()
	step_ray.target_position = Vector3(0, -1.6, 0)
	step_ray.position = Vector3(0, 0.4, 0)
	add_child(step_ray)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(45.0)

func set_crouched(v: bool) -> void:
	if v == crouched:
		return
	if not v:
		# overhead clearance check: stand capsule would intersect?
		var params := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.30
		cap.height = 1.66
		params.shape = cap
		var xf := Transform3D(Basis(), global_position + Vector3(0, 0.86, 0))
		params.transform = xf
		params.exclude = [get_rid()]
		var space := get_world_3d().direct_space_state
		var hit: Dictionary = space.get_rest_info(params)
		if not hit.is_empty():
			emit_signal("interact_hint", "No room to stand")
			return
	crouched = v
	col_stand.disabled = v
	col_crouch.disabled = not v
	emit_signal("posture_changed", crouched)

func current_max_speed() -> float:
	var base := RUN_SPEED if _wants_run() else WALK_SPEED
	if crouched:
		base = CROUCH_SPEED
	if pain > 0.5:
		base *= 0.8
	if survival and survival.get("temperature") != null and float(survival.get("temperature")) < 15.0:
		base *= 0.9 # cold stiff
	return base

func _wants_run() -> bool:
	# full joystick deflection or shift key = jog/run
	if Input.is_action_pressed("sprint"):
		return true
	return move_input.length() > 0.92

func _physics_process(delta: float) -> void:
	if frozen:
		velocity = Vector3.ZERO
		_update_gait(delta)
		_update_pose(delta)
		_update_noise()
		return
	else:
		_gather_keyboard()
		var wish := _camera_relative_wish()
		var max_speed := current_max_speed()
		# backward slower
		var fwd_dot := wish.normalized().dot(-global_transform.basis.z) if wish.length() > 0.01 else 1.0
		var spd := max_speed * clampf(move_input.length(), 0.0, 1.0)
		if wish.length() > 0.01 and Vector3(wish.x, 0, wish.z).normalized().dot(_forward_on_ground()) < -0.3:
			spd *= BACKPEDAL_MULT
		var accel := 14.0 if is_on_floor() else 4.0
		velocity.x = move_toward(velocity.x, wish.x * spd, accel * delta) if wish.length() > 0.01 else move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, wish.z * spd, accel * delta) if wish.length() > 0.01 else move_toward(velocity.z, 0.0, 12.0 * delta)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		if velocity.y < 0.0:
			velocity.y = -0.5
	move_and_slide()
	_update_surface()
	_update_gait(delta)
	_update_pose(delta)
	_update_noise()

func _gather_keyboard() -> void:
	# merged with joystick: joystick sets move_input directly; keys add
	var k := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		k.y += 1.0
	if Input.is_action_pressed("move_back"):
		k.y -= 1.0
	if Input.is_action_pressed("move_left"):
		k.x -= 1.0
	if Input.is_action_pressed("move_right"):
		k.x += 1.0
	if k.length() > 0.01:
		move_input = k.limit_length(1.0)
	# actions edge
	if Input.is_action_just_pressed("crouch"):
		set_crouched(not crouched)
	if Input.is_action_just_pressed("interact"):
		try_interact()
	if Input.is_action_just_pressed("strike"):
		do_strike()
	guard_held = Input.is_action_pressed("guard")

func _camera_relative_wish() -> Vector3:
	var f := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var r := Vector3(f.z, 0, -f.x) * -1.0 # right = f cross up? compute properly
	# forward (-Z rotated by yaw), right (+X rotated)
	f = Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	r = Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var wish: Vector3 = r * move_input.x + f * move_input.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	# never push vertically from pitch: y forced 0 (pitch handled by camera only)
	wish.y = 0.0
	return wish

func _forward_on_ground() -> Vector3:
	var b := global_transform.basis
	return Vector3(-b.z.x, 0, -b.z.z).normalized()

func _update_surface() -> void:
	if world and world.has_method("ground_surface_at"):
		surface = world.ground_surface_at(global_position)
	else:
		surface = "soil"

func _update_gait(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var stride := 0.75 if planar < 3.0 else 1.15
	if crouched:
		stride = 0.55
	var target_freq := planar / stride * PI # rad/s so feet match speed
	if planar < 0.25:
		# settle phase toward nearest foot-neutral to avoid sliding
		gait_phase = lerp_angle(gait_phase, roundf(gait_phase / PI) * PI, minf(1.0, 8.0 * delta))
	else:
		var prev := gait_phase
		gait_phase += target_freq * delta
		# footstep events at phase crossings: left at 0, right at PI
		var prev_half := int(floor(prev / PI))
		var now_half := int(floor(gait_phase / PI))
		if now_half != prev_half:
			var side := "L" if now_half % 2 == 0 else "R"
			var loud := clampf(planar / RUN_SPEED, 0.2, 1.0)
			if crouched:
				loud *= 0.35
			emit_signal("footstep", side, surface, loud)
	# anim state
	if hurt_timer > 0.0:
		anim_state = "HURT"
	elif interact_timer > 0.0:
		anim_state = "INTERACT"
	elif planar < 0.25:
		anim_state = "CROUCH_IDLE" if crouched else "IDLE"
	else:
		var running := planar > 3.0
		if crouched:
			anim_state = "CROUCH_WALK"
		elif running:
			anim_state = "RUN"
		else:
			# strafe variants for test semantics: still walk family
			if absf(move_input.x) > 0.5 and absf(move_input.y) < 0.4:
				anim_state = "STRAFE"
			elif move_input.y < -0.2:
				anim_state = "WALK_BACK"
			else:
				anim_state = "WALK"
	interact_timer = maxf(0.0, interact_timer - delta)
	hurt_timer = maxf(0.0, hurt_timer - delta)
	# face movement
	if planar > 0.4:
		var want := atan2(-velocity.x, -velocity.z)
		model_yaw = lerp_angle(model_yaw, want, minf(1.0, TURN_LERP * delta))
		rotation.y = model_yaw
	# crouch blend
	crouch_amount = move_toward(crouch_amount, 1.0 if crouched else 0.0, 5.0 * delta)

func _update_noise() -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	noise_level = clampf(planar / RUN_SPEED, 0.0, 1.0)
	if crouched:
		noise_level *= 0.3
	if surface == "water":
		noise_level = minf(1.0, noise_level + 0.25)
	elif surface == "wood":
		noise_level = minf(1.0, noise_level + 0.1)

func _update_pose(delta: float) -> void:
	if bones.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var planar := Vector2(velocity.x, velocity.z).length()
	var speed_n := clampf(planar / RUN_SPEED, 0.0, 1.0)
	var ph := gait_phase
	var c := crouch_amount
	var hips: Node3D = bones["hips"]
	hips.position.y = lerpf(hips_base_y, 0.62, c) + sin(ph * 2.0) * 0.028 * speed_n - c * 0.02
	hips.position.x = sin(t * 0.9) * 0.012 * (1.0 - speed_n)
	var spine: Node3D = bones["spine"]
	spine.rotation.x = c * 0.38 + speed_n * 0.12
	spine.rotation.y = sin(ph) * 0.06 * speed_n
	var chest: Node3D = bones["chest"]
	chest.rotation.x = c * 0.12 - speed_n * 0.06 + sin(t * 1.4) * 0.012
	chest.rotation.y = -sin(ph) * 0.09 * speed_n
	var head: Node3D = bones["head"]
	head.rotation.x = -c * 0.28 - speed_n * 0.05 + (0.02 * sin(t * 0.7))
	# legs: swing + crouch bend
	var swing := 0.62 * speed_n + 0.08 * c
	# when idle keep slight bend
	for s in ["L", "R"]:
		var off := 0.0 if s == "L" else PI
		var thigh: Node3D = bones["thigh_" + s]
		var knee: Node3D = bones["knee_" + s]
		var ankle: Node3D = bones["ankle_" + s]
		var sw: float = sin(ph + off) * swing
		thigh.rotation.x = sw - c * 1.05 - speed_n * 0.08
		# knee bends most when leg is back->forward passing; plus deep crouch flex
		var knee_bend: float = c * 1.9 + (0.25 + 0.85 * maxf(0.0, sin(ph + off + 0.9))) * speed_n + (0.08 if planar < 0.25 else 0.0) + c * 0.15
		knee.rotation.x = knee_bend
		ankle.rotation.x = -thigh.rotation.x * 0.55 - knee_bend * 0.35 + c * 0.35
	# strafe lean
	var lean := clampf(move_input.x, -1.0, 1.0) * 0.12
	hips.rotation.z = -lean * 0.6
	spine.rotation.z = -lean * 0.4
	# arms: opposite swing, strafe abduction, crouch guard slightly forward
	for s in ["L", "R"]:
		var off2 := PI if s == "L" else 0.0
		var sh: Node3D = bones["shoulder_" + s]
		var up: Node3D = bones["upper_" + s]
		var el: Node3D = bones["elbow_" + s]
		var arm_sw: float = sin(ph + off2) * (0.5 * speed_n)
		sh.rotation.x = -arm_sw + c * -0.35
		sh.rotation.z = (0.10 if s == "L" else -0.10) + lean * 0.5
		up.rotation.x = sh.rotation.x
		el.rotation.x = -0.25 - 0.35 * speed_n - c * 0.5 - maxf(0.0, -arm_sw) * 0.4
	# interact reach overrides right arm
	if interact_timer > 0.0:
		var k := interact_timer / 0.7
		var sh_r: Node3D = bones["shoulder_R"]
		sh_r.rotation.x = -1.25 * k
		var el_r: Node3D = bones["elbow_R"]
		el_r.rotation.x = -0.3 * k
	# hurt flinch
	if hurt_timer > 0.0:
		var hk := hurt_timer / 0.6
		spine.rotation.x -= 0.5 * hk
		head.rotation.x += 0.4 * hk
	# guard pose
	if guard_held:
		for s in ["L", "R"]:
			var sh2: Node3D = bones["shoulder_" + s]
			sh2.rotation.x = -0.9
			var el2: Node3D = bones["elbow_" + s]
			el2.rotation.x = -1.1

func try_interact() -> void:
	if interact_timer > 0.0 or hurt_timer > 0.0:
		return
	if world and world.has_method("try_player_interact"):
		var did: bool = world.try_player_interact(self)
		if did:
			interact_timer = 0.7

func do_strike() -> void:
	if interact_timer > 0.0 or hurt_timer > 0.0:
		return
	interact_timer = 0.55
	# loud noise + ask world to resolve strike vs NPCs
	if world and world.has_method("player_strike"):
		world.player_strike(self)

func apply_hurt(amount: float) -> void:
	var final := amount * (0.35 if guard_held else 1.0)
	pain = clampf(pain + final * 0.5, 0.0, 1.0)
	hurt_timer = 0.6
	emit_signal("hurt_taken", final)
