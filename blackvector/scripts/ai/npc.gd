# npc.gd — 2-3 human workers with independent routines + perception states:
# UNAWARE -> NOTICED -> SUSPICIOUS -> INVESTIGATING -> CONFIRMED -> LOST -> RETURN.
# They NEVER default-follow Corley. Investigation expires.
class_name NPC
extends CharacterBody3D

const WALK := 1.6
var npc_name := "Worker"
var bones: Dictionary = {}
var world: WorldBuilder
var waypoints: Array = [] # Vector3 list loop
var wp_index := 0
var wait_timer := 0.0
var state := "UNAWARE" # perception
var suspicion := 0.0
var investigate_pos := Vector3.ZERO
var investigate_timer := 0.0
var lost_timer := 0.0
var stagger_timer := 0.0
var gait_phase := 0.0
var hips_base := 0.96
var active := true # encounter gating: NPC3 dormant until morning
var label := ""

func setup(nm: String, palette: Color, wps: Array, w: WorldBuilder) -> void:
	npc_name = nm
	world = w
	waypoints = wps
	set_meta("palette", palette)
	var built: Dictionary = CorleyRig.build(self, "worker")
	bones = built["bones"]
	hips_base = built["hips_base_y"]
	# collision
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.66
	cs.shape = cap
	cs.position = Vector3(0, 0.86, 0)
	add_child(cs)
	add_to_group("npc")

func _physics_process(delta: float) -> void:
	if not active:
		return
	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 10 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10 * delta)
	else:
		_update_routine(delta)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = -0.5 if velocity.y < 0 else velocity.y
	move_and_slide()
	_update_perception(delta)
	_update_pose(delta)

func _update_routine(delta: float) -> void:
	if state == "INVESTIGATING" or state == "CONFIRMED":
		_move_toward_point(investigate_pos, WALK * 1.3, delta)
		if global_position.distance_to(investigate_pos) < 1.2:
			if state == "INVESTIGATING":
				# look around then give up (expires)
				investigate_timer -= delta
				velocity.x = move_toward(velocity.x, 0.0, 8 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 8 * delta)
				rotation.y += delta * 1.2
				if investigate_timer <= 0.0:
					_set_state("LOST")
		return
	if state == "SUSPICIOUS":
		# pause and stare toward stimulus
		velocity.x = move_toward(velocity.x, 0.0, 8 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8 * delta)
		var d: Vector3 = investigate_pos - global_position
		if d.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z) + PI, 4 * delta)
		return
	# routine waypoints
	if waypoints.is_empty():
		return
	if wait_timer > 0.0:
		wait_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 8 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8 * delta)
		return
	var target: Vector3 = waypoints[wp_index]
	if global_position.distance_to(target) < 1.4:
		# perform simple activity pause
		wait_timer = randf_range(2.0, 5.0)
		wp_index = (wp_index + 1) % waypoints.size()
		return
	_move_toward_point(target, WALK, delta)

func _move_toward_point(target: Vector3, speed: float, delta: float) -> void:
	var d: Vector3 = target - global_position
	d.y = 0
	if d.length() < 0.05:
		return
	var dir := d.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z) + PI * 0.0 + atan2(dir.x, dir.z), 5 * delta)

func _set_state(s: String) -> void:
	state = s
	if s == "INVESTIGATING":
		investigate_timer = 9.0
	elif s == "LOST":
		lost_timer = 4.0
	elif s == "UNAWARE":
		suspicion = 0.0

func can_see_player(player: Node3D) -> Dictionary:
	# returns {visible, distance, angle_ok, cover}
	var res := {"visible": false, "distance": 100.0, "cover": 0.0}
	if player == null:
		return res
	var to: Vector3 = player.global_position + Vector3(0, 1.2, 0) - (global_position + Vector3(0, 1.5, 0))
	var dist := to.length()
	res["distance"] = dist
	if dist > 26.0:
		return res
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var dir := to.normalized()
	var ang := rad_to_deg(acos(clampf(fwd.dot(Vector3(dir.x, 0, dir.z).normalized()), -1, 1))) if Vector2(dir.x, dir.z).length() > 0.01 else 0.0
	if dist > 4.0 and ang > 65.0:
		return res # outside vision cone (close proximity always sensed)
	# line of sight raycast
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.55, 0), player.global_position + Vector3(0, 1.0, 0))
	q.exclude = [get_rid(), (player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return res
	# cover: crouched + slow in vegetation reduces effective visibility
	var cover := 0.0
	if "crouched" in player and bool(player.get("crouched")):
		cover += 0.45
	if "noise_level" in player and float(player.get("noise_level")) < 0.2:
		cover += 0.2
	res["cover"] = cover
	res["visible"] = true
	return res

func _update_perception(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or stagger_timer > 0.0:
		return
	# LOST counts down then return to routine
	if state == "LOST":
		lost_timer -= delta
		if lost_timer <= 0.0:
			_set_state("UNAWARE")
		return
	var see := can_see_player(player)
	var hear_r := 3.0
	if "noise_level" in player:
		hear_r = 2.5 + float(player.get("noise_level")) * 11.0
	var dist: float = player.global_position.distance_to(global_position)
	var heard := dist < hear_r and float(player.get("noise_level")) > 0.45
	var stimulus := 0.0
	if bool(see["visible"]):
		var closeness := clampf(1.0 - float(see["distance"]) / 26.0, 0.1, 1.0)
		stimulus = closeness * (1.0 - float(see["cover"]) * 0.8)
		# movement speed factor
		if "noise_level" in player:
			stimulus *= 0.6 + float(player.get("noise_level")) * 0.8
		# crouched still far = weak
		if dist > 14.0 and "crouched" in player and bool(player.get("crouched")):
			stimulus *= 0.35
	elif heard:
		stimulus = 0.45
		investigate_pos = player.global_position
	if stimulus > 0.02:
		suspicion = clampf(suspicion + stimulus * delta * 1.6, 0.0, 1.0)
		investigate_pos = player.global_position
	else:
		suspicion = clampf(suspicion - delta * 0.12, 0.0, 1.0)
	# state transitions (no permanent follow)
	if suspicion > 0.85:
		if state != "CONFIRMED" and state != "INVESTIGATING":
			_set_state("INVESTIGATING")
		if dist < 3.0:
			state = "CONFIRMED" # close: confront/shout, not follow-forever
			investigate_pos = player.global_position
	elif suspicion > 0.35:
		if state == "UNAWARE":
			state = "NOTICED"
	elif suspicion <= 0.2 and (state == "NOTICED" or state == "SUSPICIOUS"):
		_set_state("UNAWARE")
	if state == "NOTICED" and suspicion > 0.5:
		state = "SUSPICIOUS"
	if state == "CONFIRMED":
		# lost contact if unseen + quiet for a while
		if not bool(see["visible"]) and not heard:
			lost_timer += delta
			if lost_timer > 5.0:
				_set_state("LOST")
				lost_timer = 0.0
		else:
			lost_timer = 0.0
			investigate_pos = player.global_position

func apply_stagger(from: Node3D) -> void:
	stagger_timer = 1.6
	suspicion = 1.0
	state = "CONFIRMED"
	if from != null:
		investigate_pos = from.global_position
	else:
		investigate_pos = global_position

func _update_pose(delta: float) -> void:
	if bones.is_empty():
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	gait_phase += (planar / 0.75 * PI) * delta if planar > 0.2 else 0.0
	var ph := gait_phase
	var sp := clampf(planar / 3.0, 0.0, 1.0)
	var hips: Node3D = bones["hips"]
	hips.position.y = hips_base + sin(ph * 2.0) * 0.025 * sp
	for s in ["L", "R"]:
		var off := 0.0 if s == "L" else PI
		(bones["thigh_" + s] as Node3D).rotation.x = sin(ph + off) * 0.55 * sp
		(bones["knee_" + s] as Node3D).rotation.x = (0.2 + 0.8 * maxf(0.0, sin(ph + off + 0.9))) * sp
		(bones["ankle_" + s] as Node3D).rotation.x = 0.05 * sp
	for s in ["L", "R"]:
		var off2 := PI if s == "L" else 0.0
		(bones["shoulder_" + s] as Node3D).rotation.x = sin(ph + off2) * 0.4 * sp
		(bones["elbow_" + s] as Node3D).rotation.x = -0.3 - 0.3 * sp
	if stagger_timer > 0.0:
		(bones["spine"] as Node3D).rotation.x = -0.5 * (stagger_timer)
		(bones["head"] as Node3D).rotation.x = 0.3
	else:
		(bones["spine"] as Node3D).rotation.x = lerpf((bones["spine"] as Node3D).rotation.x, 0.0, 5 * delta)
