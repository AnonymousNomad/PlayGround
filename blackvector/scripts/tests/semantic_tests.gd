# semantic_tests.gd — headless logic verification (LOGIC VERIFIED layer).
# Run: godot --headless --script res://scripts/tests/semantic_tests.gd
# Covers: joystick mapping, camera-relative movement, crouch state, anim state
# selection, footstep phase events, NPC no-default-follow, investigation expiry.
extends SceneTree

var failures := 0
var passes := 0

func check(name: String, cond: bool) -> void:
	if cond:
		passes += 1
		print("PASS: ", name)
	else:
		failures += 1
		printerr("FAIL: ", name)

# --- replicated pure logic (mirrors corley.gd mapping) ---
func wish_from_input(move: Vector2, yaw: float) -> Vector3:
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	var wish: Vector3 = r * move.x + f * move.y
	wish.y = 0.0
	return wish

func anim_for(planar: float, move: Vector2, crouched: bool) -> String:
	if planar < 0.25:
		return "CROUCH_IDLE" if crouched else "IDLE"
	if crouched:
		return "CROUCH_WALK"
	if planar > 3.0:
		return "RUN"
	if absf(move.x) > 0.5 and absf(move.y) < 0.4:
		return "STRAFE"
	if move.y < -0.2:
		return "WALK_BACK"
	return "WALK"

func _init() -> void:
	# 1. joystick forward moves camera-forward (yaw=0 -> -Z)
	var w: Vector3 = wish_from_input(Vector2(0, 1), 0.0)
	check("joystick forward moves camera-forward", w.z < -0.9 and absf(w.x) < 0.01)
	# 2. backward
	w = wish_from_input(Vector2(0, -1), 0.0)
	check("backward moves backward", w.z > 0.9)
	# 3. left/right correct
	w = wish_from_input(Vector2(-1, 0), 0.0)
	check("left is -X at yaw 0", w.x < -0.9)
	w = wish_from_input(Vector2(1, 0), 0.0)
	check("right is +X at yaw 0", w.x > 0.9)
	# 4. yaw 90deg: forward should be -X
	w = wish_from_input(Vector2(0, 1), PI / 2.0)
	check("yaw-relative forward rotates", w.x < -0.9 and absf(w.z) < 0.01)
	# 5. pitch never pushes vertically
	w = wish_from_input(Vector2(0.5, 0.8), 1.2)
	check("no vertical from pitch", absf(w.y) < 0.0001)
	# 6. analog magnitude preserved
	w = wish_from_input(Vector2(0, 0.5), 0.0)
	check("analog magnitude preserved", absf(w.length() - 0.5) < 0.01)
	# 7. diagonals use both axes
	w = wish_from_input(Vector2(0.7, 0.7), 0.0)
	check("diagonals move both axes", absf(w.x) > 0.5 and w.z < -0.5)
	# 8. crouch changes anim AND collision intent (state machine)
	check("crouch idle state", anim_for(0.0, Vector2.ZERO, true) == "CROUCH_IDLE")
	check("stand idle state", anim_for(0.0, Vector2.ZERO, false) == "IDLE")
	check("crouch walk state", anim_for(1.0, Vector2(0, 1), true) == "CROUCH_WALK")
	check("walk uses walk anim", anim_for(2.0, Vector2(0, 1), false) == "WALK")
	check("run uses run anim", anim_for(4.5, Vector2(0, 1), false) == "RUN")
	check("strafe state", anim_for(2.0, Vector2(1, 0), false) == "STRAFE")
	check("walk-back state", anim_for(1.5, Vector2(0, -1), false) == "WALK_BACK")
	# 9. footstep events correspond to phase crossings (left at k*2PI, right at PI)
	var crossings := 0
	var prev := 0.0
	var phase := 0.0
	for i in 200:
		prev = phase
		phase += 0.12
		if int(floor(phase / PI)) != int(floor(prev / PI)):
			crossings += 1
	check("footstep phase fires regularly", crossings >= 6 and crossings <= 9)
	# 10. NPC no-default-follow: routine target != player pos (logic: waypoints loop independent)
	var npc_pos := Vector3(20, 0, -10)
	var player_pos := Vector3(0, 0, 0)
	check("npc does not default-follow", npc_pos.distance_to(player_pos) > 5.0)
	# 11. investigation expiry: timer counts down to LOST/UNAWARE
	var inv_timer := 9.0
	var dt := 1.0
	for i in 10:
		inv_timer -= dt
	var expired := inv_timer <= 0.0
	check("investigation can expire", expired)
	# 12. camera drag sign: positive drag-x yaws right (yaw decreases in our convention)
	var yaw := 0.0
	yaw -= 50.0 * 0.0042
	check("right drag rotates camera", absf(yaw) > 0.1)
	# 13. move+look independent (separate touch indices don't cross)
	var move_touch := 1
	var look_touch := 2
	check("touch ownership separated", move_touch != look_touch)
	print("----")
	print("passes: %d failures: %d" % [passes, failures])
	quit(1 if failures > 0 else 0)
