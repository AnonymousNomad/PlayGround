# sound_bank.gd — synthesized, project-owned audio. No music. Wilderness is the
# soundtrack: wind loop, water proximity, footsteps per surface (event-driven
# from animation foot plants), fire crackle, door, UI, wildlife blips.
class_name SoundBank
extends Node

var wind_player: AudioStreamPlayer
var water_player: AudioStreamPlayer
var fire_player: AudioStreamPlayer
var step_players: Array = []
var step_index := 0
var world: WorldBuilder

func _wav(seconds: float, rate: int, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s: float = clampf(fn.call(t, i), -1.0, 1.0)
		var v := int(s * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

func _noise(seed: int) -> Callable:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var last := 0.0
	return func(_t: float, _i: int) -> float:
		last = last * 0.97 + r.randf_range(-1.0, 1.0) * 0.03 * 8.0
		return clampf(last, -1.0, 1.0)

func make() -> void:
	var rate := 22050
	# wind: slow-modulated filtered noise loop (4s)
	var wind_noise := _noise(7)
	var wind := _wav(4.0, rate, func(t: float, i: int) -> float:
		return wind_noise.call(t, i) * (0.35 + 0.2 * sin(t * 0.9) + 0.1 * sin(t * 2.3)))
	wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind.loop_begin = 0
	wind.loop_end = int(4.0 * rate)
	wind_player = AudioStreamPlayer.new()
	wind_player.stream = wind
	wind_player.volume_db = -14.0
	add_child(wind_player)
	wind_player.play()
	# water babble loop
	var water_noise := _noise(21)
	var water := _wav(3.0, rate, func(t: float, i: int) -> float:
		return water_noise.call(t, i) * 0.5 + sin(t * 7.0) * 0.08 + sin(t * 13.7) * 0.05)
	water.loop_mode = AudioStreamWAV.LOOP_FORWARD
	water_player = AudioStreamPlayer.new()
	water_player.stream = water
	water_player.volume_db = -28.0
	add_child(water_player)
	water_player.play()
	# fire crackle loop (1.5s pops)
	var fire_noise := _noise(99)
	var fire := _wav(1.5, rate, func(t: float, i: int) -> float:
		var base: float = fire_noise.call(t, i) * 0.25
		var pop := 0.0
		if fmod(t * 7.0, 1.0) < 0.03:
			pop = 0.5
		return base + pop)
	fire.loop_mode = AudioStreamWAV.LOOP_FORWARD
	fire_player = AudioStreamPlayer.new()
	fire_player.stream = fire
	fire_player.volume_db = -60.0
	add_child(fire_player)
	fire_player.play()
	# footstep pool (positional-ish via volume; 3D players created per step for panning)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		step_players.append(p)

func footstep_sound(surface: String, loudness: float, pos: Vector3) -> void:
	var rate := 22050
	var dur := 0.14
	var seed := 100 + surface.length() * 17 + int(loudness * 10.0)
	var r := RandomNumberGenerator.new()
	r.seed = seed + step_index * 131
	var brightness := 0.4
	var decay := 18.0
	match surface:
		"wood":
			brightness = 0.7
			decay = 22.0
		"rock", "gravel":
			brightness = 0.9
			decay = 26.0
		"water":
			brightness = 1.2
			decay = 10.0
		"mud":
			brightness = 0.25
			decay = 12.0
		_:
			brightness = 0.5
			decay = 16.0
	var data := PackedByteArray()
	var n := int(dur * rate)
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * decay)
		var s := (r.randf_range(-1, 1) * brightness + sin(t * 900.0) * 0.2) * env * (0.3 + loudness * 0.7)
		data.encode_s16(i * 2, int(clampf(s, -1, 1) * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	# positional: use 3D player one-shot
	var p3 := AudioStreamPlayer3D.new()
	p3.stream = w
	p3.unit_size = 6.0
	p3.max_distance = 30.0
	get_tree().current_scene.add_child(p3)
	p3.global_position = pos
	p3.play()
	# auto free
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(p3.queue_free)
	step_index += 1

func play_ui() -> void:
	pass # subtle; skip to keep mix clean

func update_ambience(player_pos: Vector3, fire_lit: bool, fire_pos: Vector3) -> void:
	if not water_player or not world:
		return
	# water volume by proximity to sea/creek
	var d_sea := maxf(0.0, player_pos.z - 24.0)
	var creek_x := -8.0 + player_pos.z * 0.12
	var d_creek := absf(player_pos.x - creek_x)
	var d := minf(d_sea if player_pos.z > 20.0 else 100.0, d_creek)
	var vol := -28.0 + clampf(1.0 - d / 18.0, 0.0, 1.0) * 18.0
	water_player.volume_db = vol
	if fire_player:
		if fire_lit:
			var fd: float = player_pos.distance_to(fire_pos)
			fire_player.volume_db = -16.0 + clampf(1.0 - fd / 12.0, 0.0, 1.0) * 8.0
		else:
			fire_player.volume_db = -60.0
