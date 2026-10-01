# survival.gd — grounded, restrained: wetness / temperature-exposure /
# fatigue-exertion / pain-injury. No universal HP bar. HUD shows subtle cues only.
class_name Survival
extends Node

var wetness := 100.0 # starts soaked (awakening in water)
var temperature := 32.0 # perceived warmth 0..100; low = hypothermia risk
var fatigue := 10.0
var pain := 0.0
var has_dry_clothes := false
var near_fire := false
var in_shelter := false
var time_of_day := 0.35 # 0..1 (morning-ish cool daylight; rest advances)

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var moving := false
	var running := false
	if player and "noise_level" in player:
		moving = Vector2(player.velocity.x, player.velocity.z).length() > 0.5
		running = Vector2(player.velocity.x, player.velocity.z).length() > 3.2
	# wetness: dries slowly, fast near fire/shelter; rain none in slice
	var dry_rate := 1.2
	if near_fire:
		dry_rate = 14.0
	elif in_shelter:
		dry_rate = 5.0
	if has_dry_clothes:
		dry_rate *= 1.6
	wetness = clampf(wetness - dry_rate * delta, 0.0, 100.0)
	# temperature: cold when wet/exposed, warm near fire/shelter/morning
	var target := 55.0
	if near_fire:
		target = 85.0
	elif in_shelter:
		target = 62.0
	target -= wetness * 0.35
	if time_of_day < 0.5:
		target -= 6.0 # early chill
	temperature = lerpf(temperature, target, minf(1.0, 0.08 * delta))
	# fatigue: rises with exertion/time, rest resets
	fatigue = clampf(fatigue + delta * (0.25 + (1.4 if running else 0.35 if moving else 0.12)), 0.0, 100.0)
	if near_fire and not moving:
		fatigue = maxf(0.0, fatigue - delta * 2.0)
	if player and "pain" in player:
		pain = float(player.get("pain")) * 100.0

func exertion_factor() -> float:
	return clampf(fatigue / 100.0, 0.0, 1.0)

func is_critical_cold() -> bool:
	return temperature < 18.0

func rest_until_morning() -> void:
	wetness = maxf(0.0, wetness - 60.0)
	fatigue = 5.0
	temperature = 65.0
	time_of_day = 0.62
