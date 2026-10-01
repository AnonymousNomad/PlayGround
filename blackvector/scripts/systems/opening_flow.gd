# opening_flow.gd — locked order: AWAKENING -> SHORELINE -> EXPOSURE -> WOODS ->
# HUMAN TRACE -> CABIN -> WARMTH -> FIRST REST -> MORNING/FREEDOM.
# Minimal contextual hints; no exposition dump; memory fragments subtle.
class_name OpeningFlow
extends Node

var stage := "AWAKENING"
var game = null
var hint_label: Label
var hint_timer := 0.0
var rest_done := false
var morning := false

func setup(g, hud_hint: Label) -> void:
	game = g
	hint_label = hud_hint
	_show_hint("Cold. Water. Shore. — move.", 6.0)

func _show_hint(t: String, dur: float = 5.0) -> void:
	if hint_label:
		hint_label.text = t
		hint_label.modulate.a = 1.0
	hint_timer = dur

func _process(delta: float) -> void:
	if hint_timer > 0.0:
		hint_timer -= delta
		if hint_timer <= 0.0 and hint_label:
			var tw := create_tween()
			tw.tween_property(hint_label, "modulate:a", 0.0, 1.0)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or game == null:
		return
	var p: Vector3 = player.global_position
	match stage:
		"AWAKENING":
			if p.z < 27.0 or Vector2(player.velocity.x, player.velocity.z).length() > 0.5:
				stage = "SHORELINE"
				_show_hint("Get out of the water. Get warm.", 6.0)
		"SHORELINE":
			if p.z < 22.0:
				stage = "EXPOSURE"
				_show_hint("You are soaked and cold. Head inland — treeline.", 6.0)
		"EXPOSURE":
			if p.z < 12.0:
				stage = "WOODS"
				_show_hint("Follow the ground: trail, blazes, old use.", 6.0)
		"WOODS":
			if Vector2(p.x - 4.0, p.z - 10.0).length() < 5.0:
				stage = "TRACE"
				_show_hint("Someone uses this place. Look around.", 6.0)
		"TRACE":
			if Vector2(p.x - 20.0, p.z + 14.0).length() < 9.0:
				stage = "CABIN"
				_show_hint("Shelter. Dry clothes. Fire. Rest.", 7.0)
		"CABIN":
			pass # WARMTH via fire event
		"WARMTH":
			pass # REST via rest event
		"REST":
			pass
		"MORNING":
			pass

func notify_fire_lit() -> void:
	if stage == "CABIN":
		stage = "WARMTH"
		_show_hint("Warmth. Stay a little. Then rest.", 6.0)

func notify_rested() -> void:
	rest_done = true
	morning = true
	stage = "MORNING"
	_show_hint("Morning. You feel steadier — not healed. Explore.", 7.0)
	if game and game.has_method("on_morning"):
		game.on_morning()
