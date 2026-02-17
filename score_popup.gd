extends Node3D

var score_value: int = 0
var combo_count: int = 0

func initialize(pos: Vector3, score: int, combo: int):
	global_position = pos + Vector3(0, 1.0, 0)
	score_value = score
	combo_count = combo
	
	var label = $Label3D
	var animation_player = $AnimationPlayer
	
	# Set the score text with combo indicator
	if combo_count > 1:
		label.text = "+%d (x%d COMBO!)" % [score_value, combo_count]
	else:
		label.text = "+%d" % score_value
	
	# Set color based on combo level
	if combo_count >= 5:
		label.modulate = Color(1.0, 0.2, 1.0) # Purple for high combos
		label.outline_modulate = Color(0.5, 0.0, 0.5)
		label.font_size = 24
	elif combo_count >= 3:
		label.modulate = Color(1.0, 0.3, 0.0) # Red-orange for medium combos
		label.outline_modulate = Color(0.5, 0.1, 0.0)
		label.font_size = 22
	elif combo_count >= 2:
		label.modulate = Color(1.0, 0.7, 0.0) # Orange for small combos
		label.outline_modulate = Color(0.5, 0.3, 0.0)
		label.font_size = 20
	else:
		label.modulate = Color(1.0, 1.0, 0.5) # Yellow for single hits
		label.outline_modulate = Color(0.5, 0.5, 0.0)
		label.font_size = 16
	
	# Start the animation
	animation_player.play("float_and_fade")

func _on_animation_player_animation_finished(anim_name):
	queue_free()
