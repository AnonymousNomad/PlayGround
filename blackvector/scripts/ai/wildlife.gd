# wildlife.gd — ONE credible species pair (fox + hare): independent wander,
# terrain following, graze pauses, flee from noise/movement. NOT enemies.
class_name Wildlife
extends Node3D

var world: WorldBuilder
var animals: Array = [] # {node, kind, pos, yaw, speed, state, timer, home}

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _build_quadruped(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Animal_" + kind
	var is_fox := kind == "fox"
	var body_mat := _mat(Color(0.62, 0.38, 0.20) if is_fox else Color(0.55, 0.52, 0.47))
	var dark := _mat(Color(0.25, 0.18, 0.12) if is_fox else Color(0.35, 0.33, 0.30))
	var body := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.22 if is_fox else 0.14
	bs.height = (0.44 if is_fox else 0.28)
	body.mesh = bs
	body.material_override = body_mat
	body.scale = Vector3(1.0, 0.85, 1.7 if is_fox else 1.4)
	body.position = Vector3(0, 0.32 if is_fox else 0.22, 0)
	root.add_child(body)
	# head
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.12 if is_fox else 0.08
	hs.height = 0.24 if is_fox else 0.16
	head.mesh = hs
	head.material_override = body_mat
	head.position = Vector3(0, 0.48 if is_fox else 0.34, 0.38 if is_fox else 0.24)
	root.add_child(head)
	# snout
	var sn := MeshInstance3D.new()
	var snm := PrismMesh.new()
	snm.size = Vector3(0.08, 0.08, 0.14)
	sn.mesh = snm
	sn.material_override = dark
	sn.position = Vector3(0, 0.44 if is_fox else 0.31, 0.52 if is_fox else 0.34)
	root.add_child(sn)
	# ears
	for sx in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var em := PrismMesh.new()
		em.size = Vector3(0.05, 0.12 if is_fox else 0.16, 0.04)
		ear.mesh = em
		ear.material_override = dark
		ear.position = Vector3(sx * 0.07, 0.60 if is_fox else 0.46, 0.34 if is_fox else 0.22)
		root.add_child(ear)
	# tail (fox bushy)
	var tail := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.09 if is_fox else 0.05
	tm.height = 0.3 if is_fox else 0.12
	tail.mesh = tm
	tail.material_override = _mat(Color(0.55, 0.33, 0.18) if is_fox else Color(0.6, 0.58, 0.55))
	tail.position = Vector3(0, 0.36 if is_fox else 0.24, -0.42 if is_fox else -0.22)
	tail.rotation.x = -0.7
	root.add_child(tail)
	root.set_meta("tail", tail)
	# legs
	var legs := []
	for lx in [-0.12, 0.12]:
		for lz in [-0.18, 0.22]:
			var leg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.035 if is_fox else 0.025
			cm.bottom_radius = 0.025 if is_fox else 0.02
			cm.height = 0.3 if is_fox else 0.2
			leg.mesh = cm
			leg.material_override = dark
			var sc := 1.0
			leg.position = Vector3(lx * (1.4 if is_fox else 1.2), 0.15 if is_fox else 0.10, lz)
			root.add_child(leg)
			legs.append(leg)
	root.set_meta("legs", legs)
	root.set_meta("kind", kind)
	return root

func spawn_all(w: WorldBuilder) -> void:
	world = w
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# fox near woods edge, hare near clearing
	var defs := [
		{"kind": "fox", "at": Vector3(-12, 0, -4)},
		{"kind": "hare", "at": Vector3(3, 0, -2)},
		{"kind": "hare", "at": Vector3(-5, 0, 8)},
	]
	for d in defs:
		var n := _build_quadruped(String(d["kind"]))
		var p: Vector3 = d["at"]
		p.y = world.height_at(p.x, p.z)
		n.position = p
		add_child(n)
		animals.append({"node": n, "kind": String(d["kind"]), "yaw": rng.randf() * TAU, "speed": 0.0, "state": "graze", "timer": rng.randf_range(1, 3), "phase": rng.randf() * TAU, "home": p})

func _process(delta: float) -> void:
	if world == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for a in animals:
		var n: Node3D = a["node"]
		a["timer"] = float(a["timer"]) - delta
		a["phase"] = float(a["phase"]) + delta * (4.0 + float(a["speed"]) * 3.0)
		var to_player := 100.0
		var player_noise := 0.0
		if player:
			to_player = n.global_position.distance_to(player.global_position)
			if "noise_level" in player:
				player_noise = float(player.get("noise_level"))
		# flee if close or loud
		var flee_r := 9.0 if a["kind"] == "fox" else 7.0
		if player_noise > 0.7:
			flee_r += 4.0
		if to_player < flee_r and a["state"] != "flee":
			a["state"] = "flee"
			a["timer"] = 2.5
		match String(a["state"]):
			"graze":
				a["speed"] = 0.0
				if float(a["timer"]) <= 0.0:
					a["state"] = "wander"
					a["timer"] = randf_range(3, 7)
					a["yaw"] = float(a["yaw"]) + randf_range(-1.2, 1.2)
			"wander":
				a["speed"] = 0.8 if a["kind"] == "fox" else 1.0
				if float(a["timer"]) <= 0.0:
					a["state"] = "graze"
					a["timer"] = randf_range(2, 5)
					a["speed"] = 0.0
			"flee":
				a["speed"] = 4.5 if a["kind"] == "fox" else 4.0
				if player:
					var away: Vector3 = (n.global_position - player.global_position)
					away.y = 0
					if away.length() > 0.01:
						a["yaw"] = lerp_angle(float(a["yaw"]), atan2(away.x, away.z), 6.0 * delta)
				if float(a["timer"]) <= 0.0:
					a["state"] = "graze"
					a["timer"] = 2.0
		# steer home loosely when wandering
		if String(a["state"]) == "wander" and n.global_position.distance_to(a["home"]) > 25.0:
			var want: Vector3 = (a["home"] - n.global_position)
			a["yaw"] = lerp_angle(float(a["yaw"]), atan2(want.x, want.z), 1.5 * delta)
		# move
		var sp := float(a["speed"])
		if sp > 0.01:
			var dir := Vector3(sin(float(a["yaw"])), 0, cos(float(a["yaw"])))
			var np: Vector3 = n.global_position + dir * sp * delta
			# keep out of water/cabin
			var ny := world.height_at(np.x, np.z)
			if ny > 0.3:
				np.y = ny
				n.global_position = np
			else:
				a["yaw"] = float(a["yaw"]) + 2.2 * delta
		else:
			n.global_position.y = world.height_at(n.global_position.x, n.global_position.z)
		n.rotation.y = float(a["yaw"])
		# leg scamper + tail wag
		var legs: Array = n.get_meta("legs")
		for i in legs.size():
			(legs[i] as MeshInstance3D).position.y = (0.15 if a["kind"] == "fox" else 0.10) + sin(float(a["phase"]) + float(i) * PI * 0.5) * 0.05 * clampf(sp, 0.0, 1.5)
		var tail: MeshInstance3D = n.get_meta("tail") as MeshInstance3D
		if tail:
			tail.rotation.y = sin(float(a["phase"]) * 0.5) * 0.3
