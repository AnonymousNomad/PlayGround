# hud.gd — minimal HUD: version line, hint, context prompt, subtle survival cues,
# faint detection sense. No meters wall, no minimap, no GPS.
class_name HUD
extends CanvasLayer

var version_label: Label
var hint_label: Label
var prompt_label: Label
var sense_label: Label
var status_label: Label
var flash_label: Label
var menu: Control

func build(version_text: String) -> void:
	version_label = Label.new()
	version_label.text = version_text
	version_label.add_theme_font_size_override("font_size", 13)
	version_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	version_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	version_label.position = Vector2(10, 8)
	add_child(version_label)
	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 17)
	hint_label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.94, 1))
	hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hint_label.add_theme_constant_override("shadow_offset_x", 1)
	hint_label.add_theme_constant_override("shadow_offset_y", 2)
	hint_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(0, 64)
	add_child(hint_label)
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-120, -150)
	add_child(prompt_label)
	sense_label = Label.new()
	sense_label.text = ""
	sense_label.add_theme_font_size_override("font_size", 15)
	sense_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5, 0.0))
	sense_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sense_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sense_label.position = Vector2(0, 40)
	add_child(sense_label)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.9, 0.75))
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_label.position = Vector2(12, -34)
	add_child(status_label)
	flash_label = Label.new()
	flash_label.add_theme_font_size_override("font_size", 18)
	flash_label.add_theme_color_override("font_color", Color(1, 1, 1, 0))
	flash_label.set_anchors_preset(Control.PRESET_CENTER)
	flash_label.position = Vector2(-200, -20)
	add_child(flash_label)

func flash(t: String) -> void:
	flash_label.text = t
	flash_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(flash_label, "modulate:a", 0.0, 1.2)

func set_sense(a: float, txt: String) -> void:
	sense_label.text = txt
	sense_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5, clampf(a, 0.0, 1.0)))
