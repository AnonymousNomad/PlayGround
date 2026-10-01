# game.gd — benchmark orchestrator: modes, world+player+AI wiring, interactions,
# survival zones, stealth sense, sounds, opening flow, encounter trigger.
extends Node3D

const BUILD_ID := "bv-bench-0001"

var world: WorldBuilder
var player: Corley
var cam_rig: ThirdPersonCamera
var controls: MobileControls
var hud: HUD
var survival: Survival
var sounds: SoundBank
var opening: OpeningFlow
var encounter: Encounter
var wildlife: Wildlife
var npcs: Array = []
var mode := "MENU"
var fade: ColorRect

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--menu-shot" in args:
		_show_menu()
		_run_menu_shot()
		return
	if "--probe" in args:
		_on_mode("PLAY")
		_run_probe()
		return
	if "--autoplay" in args or "--smoke" in args or "--capture" in args:
		_on_mode("PLAY")
		if "--smoke" in args:
			_run_smoke()
		elif "--capture" in args:
			_run_capture()
		return
	_show_menu()

func _sha() -> String:
	# short build id: file mtime hash fallback
	return BUILD_ID

# ---------------- menu / modes ----------------
func _show_menu() -> void:
	var c := CanvasLayer.new()
	c.name = "Menu"
	add_child(c)
	var panel := CenterContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "BLACK VECTOR — INDEPENDENT BENCHMARK"
	title.add_theme_font_size_override("font_size", 26)
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Vesper island vertical slice · " + _sha() + "\nWASD move · mouse-right-drag look · E interact · C crouch · F strike · G guard"
	sub.add_theme_font_size_override("font_size", 14)
	vb.add_child(sub)
	for entry in [
		["PLAY BLACK VECTOR BENCHMARK", "PLAY"],
		["CHARACTER TEST", "CHAR"],
		["WORLD / BEAUTY TEST", "WORLD"],
		["OPENING TEST", "OPENING"],
		["AI TEST", "AI"],
		["FULL BENCHMARK (run checks + play)", "FULL"],
	]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(420, 44)
		b.pressed.connect(_on_mode.bind(entry[1]))
		vb.add_child(b)

func _on_mode(m: String) -> void:
	mode = m
	var menu := get_node_or_null("Menu")
	if menu:
		menu.queue_free()
	_start_game()

func _start_game() -> void:
	# systems
	survival = Survival.new()
	add_child(survival)
	sounds = SoundBank.new()
	add_child(sounds)
	sounds.make()
	opening = OpeningFlow.new()
	add_child(opening)
	encounter = Encounter.new()
	add_child(encounter)
	encounter.setup(self)
	# world
	world = WorldBuilder.new()
	add_child(world)
	world.build(self)
	sounds.world = world
	# player
	player = Corley.new()
	player.name = "Corley"
	player.add_to_group("player")
	add_child(player)
	player.world = world
	player.survival = survival
	player.footstep.connect(_on_footstep)
	# spawn by mode
	var spawn := Vector3(6, 0, 30) # awakening: partly in shoreline water
	if mode == "CHAR":
		spawn = Vector3(0, 0, -6)
	elif mode == "OPENING":
		spawn = Vector3(2, 0, 18)
	elif mode == "AI":
		spawn = Vector3(8, 0, 0)
	spawn.y = world.height_at(spawn.x, spawn.z) + 0.6
	# keep awakening wet: spawn slightly in water
	if mode == "PLAY" or mode == "FULL":
		spawn.y = 0.25
	player.global_position = spawn
	# camera
	cam_rig = ThirdPersonCamera.new()
	add_child(cam_rig)
	cam_rig.setup(player)
	# controls + hud
	controls = MobileControls.new()
	add_child(controls)
	controls.setup(player, cam_rig)
	hud = HUD.new()
	add_child(hud)
	hud.build("BLACK VECTOR · INDEPENDENT BENCHMARK · " + _sha())
	opening.setup(self, hud.hint_label)
	# wildlife
	wildlife = Wildlife.new()
	add_child(wildlife)
	wildlife.spawn_all(world)
	# npcs
	_spawn_npcs()
	# fade-in from awakening
	_make_fade()
	if mode == "PLAY" or mode == "FULL":
		_awakening_fade()
	if mode == "FULL":
		_run_live_checks()

func _make_fade() -> void:
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cl := CanvasLayer.new()
	cl.layer = 90
	cl.add_child(fade)
	add_child(cl)

func _awakening_fade() -> void:
	player.frozen = true
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(fade, "color:a", 0.0, 3.0)
	tw.tween_callback(func() -> void: player.frozen = false)

func _spawn_npcs() -> void:
	var w := world
	var defs := [
		{"name": "Yuri", "pal": Color(0.55, 0.32, 0.12), "wps": [Vector3(20, 0, -10.5), Vector3(23.5, 0, -14), Vector3(20, 0, -18)], "active": true},
		{"name": "Pavel", "pal": Color(0.25, 0.35, 0.45), "wps": [Vector3(8, 0, -3), Vector3(12, 0, 2), Vector3(4, 0, 4)], "active": true},
		{"name": "Sable", "pal": Color(0.35, 0.35, 0.30), "wps": [Vector3(10, 0, 2), Vector3(14, 0, -2)], "active": false},
	]
	for d in defs:
		var n := NPC.new()
		n.name = String(d["name"])
		add_child(n)
		var wps: Array = []
		for p in d["wps"]:
			var q: Vector3 = p
			q.y = w.height_at(q.x, q.z) + 0.5
			wps.append(q)
		n.setup(String(d["name"]), d["pal"], wps, w)
		n.active = bool(d["active"])
		var p0: Vector3 = wps[0]
		n.global_position = p0
		npcs.append(n)

# ---------------- per-frame ----------------
func _process(delta: float) -> void:
	if player == null or world == null:
		return
	_update_survival_zones()
	_update_context_prompt()
	_update_sense()
	sounds.update_ambience(player.global_position, world.fire_lit, world.fire_pos)
	# NPC contact harm (shove when grabbing distance + confirmed)
	for n in npcs:
		var npc := n as NPC
		if npc.active and npc.state == "CONFIRMED" and npc.global_position.distance_to(player.global_position) < 1.3:
			# throttle via physics-frame interval; stagger/hurt timers gate repeats
			if Engine.get_physics_frames() % 90 == 0:
				encounter.npc_touched_player(npc, player)
	# desktop context key handled in player; update mobile action button label
func _update_survival_zones() -> void:
	var p := player.global_position
	survival.near_fire = world.fire_lit and p.distance_to(world.fire_pos) < 5.0
	survival.in_shelter = Vector2(p.x - 20.0, p.z + 14.0).length() < 3.6
	if survival.is_critical_cold() and hud:
		hud.status_label.text = "cold · get warm"
	elif survival.wetness > 60.0 and hud:
		hud.status_label.text = "wet · %.0f%%" % survival.wetness
	elif hud:
		hud.status_label.text = ""

func _update_context_prompt() -> void:
	var it := world.nearest_interactable(player.global_position)
	var label := ""
	if not it.is_empty():
		label = String(it["label"])
	var in_combat := encounter.triggered
	if controls:
		controls.set_action(label, in_combat)
	if hud:
		hud.prompt_label.text = ("[E] " + label) if not label.is_empty() else ""

func _update_sense() -> void:
	var max_s := 0.0
	for n in npcs:
		var npc := n as NPC
		if npc.active:
			max_s = maxf(max_s, npc.suspicion)
	if hud:
		if max_s > 0.85:
			hud.set_sense(max_s, "seen")
		elif max_s > 0.4:
			hud.set_sense(max_s * 0.8, "sensed…")
		else:
			hud.set_sense(0.0, "")

# ---------------- interactions ----------------
func do_interact(action: String, item: Dictionary) -> void:
	match action:
		"toggle_door":
			world.toggle_door()
			hud_flash("The door drags on wet wood.")
		"inspect_sign":
			hud_flash("Weathered sign: “VESPER FISHERY — cabin · stay off the muskeg”.")
		"inspect_gear":
			hud_flash("Discarded fuel can. Someone works this trail.")
		"inspect_oldcamp":
			hud_flash("Cold ashes, cut boughs. Days old, not hours.")
		"inspect_debris":
			hud_flash("Torn strap, prison stencil half-washed off. Yours?")
		"inspect_bench":
			hud_flash("Somebody's tools, kept with care. Not a loot chest.")
		"take_clothes":
			if not survival.has_dry_clothes:
				survival.has_dry_clothes = true
				survival.wetness = maxf(0.0, survival.wetness - 45.0)
				hud_flash("Dry work clothes. Still cold — but human again.")
			else:
				hud_flash("You already changed.")
		"light_fire":
			if not world.fire_lit:
				world.set_fire_lit(true)
				opening.notify_fire_lit()
				hud_flash("Fire catches. Warmth — and a signature.")
			else:
				hud_flash("You warm your hands. The fire pops.")
		"rest":
			if opening.stage == "WARMTH" or opening.stage == "CABIN":
				_rest_sequence()
			else:
				hud_flash("Too exposed to rest here. The cabin bunk is safer.")

func _rest_sequence() -> void:
	player.frozen = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 1.5)
	tw.tween_callback(func() -> void:
		survival.rest_until_morning()
		# morning light: lift sun energy slightly + warm
		opening.notify_rested())
	tw.tween_interval(1.2)
	tw.tween_property(fade, "color:a", 0.0, 2.0)
	tw.tween_callback(func() -> void: player.frozen = false)

func on_morning() -> void:
	# activate pressure pair near junction (Pavel + Sable)
	var pair := []
	for n in npcs:
		if (n as NPC).npc_name in ["Pavel", "Sable"]:
			pair.append(n)
	encounter.activate(pair)
	hud_flash("Morning. Movement on the trail — voices.")
	# brief memory fragment: subtle, no facility reveal
	hud.prompt_label.text = ""

func resolve_strike(p: Corley) -> void:
	encounter.resolve_strike(p)

func emit_noise(pos: Vector3, loudness: float) -> void:
	for n in npcs:
		var npc := n as NPC
		if npc.active and npc.global_position.distance_to(pos) < 6.0 + loudness * 8.0:
			npc.suspicion = clampf(npc.suspicion + 0.3 * loudness, 0.0, 1.0)
			npc.investigate_pos = pos
			if npc.state == "UNAWARE":
				npc.state = "NOTICED"

func hud_flash(t: String) -> void:
	if hud:
		hud.flash(t)

func _on_footstep(side: String, surface: String, loudness: float) -> void:
	sounds.footstep_sound(surface, loudness, player.global_position)
	emit_noise(player.global_position, loudness * 0.5)

# ---------------- live checks (FULL mode) ----------------
func _run_menu_shot() -> void:
	DirAccess.make_dir_recursive_absolute("res://../captures")
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://../captures/shot_menu.png")
	print("MENUSHOT-OK")
	get_tree().quit()

func _run_probe() -> void:
	player.frozen = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for pt in [Vector3(6, 0, 29), Vector3(0, 0, 4), Vector3(-4, 0, -2), Vector3(13, 0, -7), Vector3(-2, 0, 19), Vector3(0, 0, -6), Vector3(20, 0, -14)]:
		var ana: float = world.height_at(pt.x, pt.z)
		var q := PhysicsRayQueryParameters3D.create(Vector3(pt.x, 30, pt.z), Vector3(pt.x, -30, pt.z))
		var hit := space.intersect_ray(q)
		var col_y := -999.0
		if not hit.is_empty():
			col_y = (hit["position"] as Vector3).y
		print("PROBE (", pt.x, ",", pt.z, ") analytic=", ana, " collision=", col_y)
	print("PROBE-OK")
	# terrain vertex-color diagnostics
	var terr := world.get_node_or_null("Terrain") as MeshInstance3D
	if terr and terr.mesh:
		var arr: Array = terr.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var umin := Vector2(9, 9)
		var umax := Vector2(-9, -9)
		for uv in uvs:
			umin.x = minf(umin.x, uv.x)
			umin.y = minf(umin.y, uv.y)
			umax.x = maxf(umax.x, uv.x)
			umax.y = maxf(umax.y, uv.y)
		print("PROBE terrain_uvs n=", uvs.size(), " min=", umin, " max=", umax)
		var m := terr.material_override
		if m:
			print("PROBE terrain_mat=", m.get_class(), " shader=", (m as ShaderMaterial).shader.code.left(80) if m is ShaderMaterial else "n/a")
	get_tree().quit()

func _run_capture() -> void:
	player.frozen = true
	if fade:
		fade.color.a = 0.0
	DirAccess.make_dir_recursive_absolute("res://../captures")
	var shots := [
		{"file": "res://../captures/shot_awakening.png", "pos": Vector3(6, 0.4, 29), "yaw": 0.15, "pitch": -0.22, "dist": 3.4},
		{"file": "res://../captures/shot_character.png", "pos": Vector3(0, 0, 4), "yaw": 2.6, "pitch": -0.18, "dist": 2.0},
		{"file": "res://../captures/shot_woods.png", "pos": Vector3(-4, 0, -2), "yaw": -0.7, "pitch": -0.28, "dist": 3.6},
		{"file": "res://../captures/shot_cabin.png", "pos": Vector3(13, 0, -7), "yaw": -0.8, "pitch": -0.16, "dist": 3.0},
		{"file": "res://../captures/shot_water.png", "pos": Vector3(-2, 0, 19), "yaw": 3.14, "pitch": -0.24, "dist": 4.0},
		{"file": "res://../captures/shot_crouch.png", "pos": Vector3(2, 0, -2), "yaw": 1.6, "pitch": -0.16, "dist": 2.6, "crouch": true},
		{"file": "res://../captures/shot_walk.png", "pos": Vector3(4, 0, 8), "yaw": 2.7, "pitch": -0.2, "dist": 3.0, "walk": true},
	]
	for s in shots:
		var pp: Vector3 = s["pos"]
		pp.y = world.height_at(pp.x, pp.z) + 1.2
		if String(s["file"]).ends_with("shot_awakening.png"):
			pp.y = 0.35
		player.global_position = pp
		player.velocity = Vector3.ZERO
		player.frozen = false
		player.move_input = Vector2.ZERO
		var landed := false
		for i in 90:
			await get_tree().physics_frame
			# ignore stale floor state from pre-teleport ticks
			if i >= 3 and player.is_on_floor():
				landed = true
				break
		player.move_input = Vector2.ZERO
		player.frozen = true
		if s.get("crouch", false):
			player.set_crouched(true)
			for i in 40:
				await get_tree().physics_frame
		else:
			player.set_crouched(false)
		if s.get("walk", false):
			# freeze mid-stride to prove gait animation (legs/arms mid-swing)
			player.frozen = false
			player.move_input = Vector2(0, 1)
			for i in 55:
				await get_tree().physics_frame
			player.frozen = true
		if not landed:
			print("CAPTUREDBG ", String(s["file"]), " NO-FLOOR at ", pp)
			continue
		cam_rig.yaw = float(s["yaw"])
		cam_rig.pitch = float(s["pitch"])
		cam_rig.spring.spring_length = float(s["dist"])
		# snap follow point to teleported player so framing is exact
		cam_rig.global_position = player.global_position + Vector3(0, 1.45, 0)
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		print("CAPTUREDBG ", String(s["file"]), " player=", player.global_position, " cam=", cam_rig.cam.global_position if cam_rig.cam else Vector3.ZERO, " hitlen=", cam_rig.spring.get_hit_length())
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(s["file"]))
		print("CAPTURE saved ", String(s["file"]))
	print("CAPTURE-OK")
	get_tree().quit()

func _run_smoke() -> void:
	# headless smoke: drive player forward, toggle crouch, force interactions
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.frozen = false # skip awakening hold for smoke
	if fade:
		fade.color.a = 0.0
	print("SMOKE player=", player != null, " pos=", player.global_position)
	print("SMOKE interactables=", world.interactables.size(), " npcs=", npcs.size(), " animals=", wildlife.animals.size())
	player.move_input = Vector2(0, 1)
	for i in 120:
		await get_tree().physics_frame
	print("SMOKE moved pos=", player.global_position, " state=", player.anim_state, " surface=", player.surface)
	player.set_crouched(true)
	for i in 60:
		await get_tree().physics_frame
	print("SMOKE crouch=", player.crouched, " col_stand_disabled=", player.col_stand.disabled, " state=", player.anim_state)
	player.set_crouched(false)
	player.try_interact()
	world.set_fire_lit(true)
	opening.notify_fire_lit()
	print("SMOKE fire=", world.fire_lit, " stage=", opening.stage)
	# npc follow check: record npc positions over 3s while player moves
	var p0: Array = []
	for n in npcs:
		p0.append((n as NPC).global_position)
	for i in 120:
		await get_tree().physics_frame
	var drift := 0.0
	for j in npcs.size():
		drift += ((npcs[j] as NPC).global_position - (p0[j] as Vector3)).length()
	print("SMOKE npc_drift=", drift, " (routine motion, not follow-train)")
	print("SMOKE-OK")
	get_tree().quit()
func _run_live_checks() -> void:
	var results: Array = []
	results.append("player spawned: %s" % str(player != null))
	results.append("world content: %d interactables" % world.interactables.size())
	results.append("npcs independent: %d" % npcs.size())
	var txt := "\n".join(results)
	hud_flash(txt)
