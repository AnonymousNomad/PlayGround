# encounter.gd — ONE small human-pressure situation after morning rest.
# Two workers check the trail junction; player may avoid/observe/sneak/confront.
# No OPTION A/B/C UI. Combat human-scale: strike staggers, guard reduces harm,
# contact injures (pain persists), noise alerts.
class_name Encounter
extends Node

var game = null
var triggered := false
var resolved := false
var pressure_npcs: Array = []

func setup(g) -> void:
	game = g

func activate(npcs: Array) -> void:
	# enable dormant patrol pair near trail junction (10,2)
	triggered = true
	pressure_npcs = npcs
	for n in npcs:
		(n as NPC).active = true

func resolve_strike(player: Corley) -> void:
	if not triggered or resolved:
		_check_opportunistic_hit(player)
		return
	for n in pressure_npcs:
		var npc := n as NPC
		if npc and npc.global_position.distance_to(player.global_position) < 2.2:
			npc.apply_stagger(player)
			# confrontation has costs: noise + pain risk if other NPC close
			for m in pressure_npcs:
				var other := m as NPC
				if other != npc and other.global_position.distance_to(player.global_position) < 6.0:
					(player as Corley).apply_hurt(0.35)
					break
			# after a solid hit, NPCs lose interest faster (they back off, work resumes)
			resolved = true
			if game and game.has_method("hud_flash"):
				game.hud_flash("They back off. The woods are loud now.")
			return
	_check_opportunistic_hit(player)

func _check_opportunistic_hit(player: Node3D) -> void:
	# striking wildlife/NPCs outside encounter still makes noise
	if game and game.has_method("emit_noise"):
		game.emit_noise(player.global_position, 1.0)

func npc_touched_player(npc: NPC, player: Corley) -> void:
	# shove/grab: pain + noise, no HP pool
	if player.guard_held:
		player.apply_hurt(0.15)
	else:
		player.apply_hurt(0.4)
	if game and game.has_method("emit_noise"):
		game.emit_noise(player.global_position, 1.0)
