extends Node3D

# UI Nodes
@onready var color_rect = $CanvasLayer/ColorRect
@onready var line1 = $CanvasLayer/ColorRect/VBoxContainer/Line1
@onready var line2 = $CanvasLayer/ColorRect/VBoxContainer/Line2
@onready var line3 = $CanvasLayer/ColorRect/VBoxContainer/Line3
@onready var controls_container = $CanvasLayer/ColorRect/VBoxContainer/ControlsContainer
@onready var title_label = $TitleLabel3D
@onready var instruction_label = $InstructionLabel3D

# Control Icons
@onready var key_w = $CanvasLayer/ColorRect/VBoxContainer/ControlsContainer/WASDGrid/KeyW
@onready var key_a = $CanvasLayer/ColorRect/VBoxContainer/ControlsContainer/WASDGrid/KeyA
@onready var key_s = $CanvasLayer/ColorRect/VBoxContainer/ControlsContainer/WASDGrid/KeyS
@onready var key_d = $CanvasLayer/ColorRect/VBoxContainer/ControlsContainer/WASDGrid/KeyD
@onready var key_space = $CanvasLayer/ColorRect/VBoxContainer/ControlsContainer/SpaceKey
@onready var key_shift = $CanvasLayer/ColorRect/VBoxContainer/ControlsContainer/ShiftKey

# 3D Nodes
@onready var mob = $CutsceneMob
@onready var angel = $angel
@onready var player = $CutscenePlayer
@onready var world_env = $WorldEnvironment

# Textures (Filled)
var tex_w_filled = preload("res://art/keyboard_w.png")
var tex_a_filled = preload("res://art/keyboard_a.png")
var tex_s_filled = preload("res://art/keyboard_s.png")
var tex_d_filled = preload("res://art/keyboard_d.png")
var tex_space_filled = preload("res://art/keyboard_space.png")

# Textures (Outline)
var tex_w_out = preload("res://art/keyboard_w_outline.png")
var tex_a_out = preload("res://art/keyboard_a_outline.png")
var tex_s_out = preload("res://art/keyboard_s_outline.png")
var tex_d_out = preload("res://art/keyboard_d_outline.png")
var tex_space_out = preload("res://art/keyboard_space_outline.png")
var tex_shift_filled = preload("res://art/keyboard_shift.png")
var tex_shift_out = preload("res://art/keyboard_shift_outline.png")

var is_cutscene_playing = false

func _ready():
	# Initial Setup: Hide models
	mob.scale = Vector3.ZERO
	angel.scale = Vector3.ZERO
	player.scale = Vector3.ZERO
	
	# Initial Setup: Hide Controls
	controls_container.modulate.a = 0.0
	
	# Pop up title text
	title_label.scale = Vector3.ZERO
	instruction_label.scale = Vector3.ZERO
	
	var pop_tween = create_tween()
	pop_tween.tween_property(title_label, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(instruction_label, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	# Prevent Mob from deleting itself
	mob.set_physics_process(false)
	# Disable player physics
	player.set_physics_process(false)
	# Hide Dash Trail
	var trail = player.get_node_or_null("Pivot/DashTrail")
	if trail:
		trail.visible = false

func _input(event):
	if event.is_action_pressed("ui_accept") and not is_cutscene_playing:
		start_cutscene()

func _process(_delta):
	# Gentle oscillating Y rotation on title
	if title_label.visible and title_label.scale.length() > 0.1:
		var t = Time.get_ticks_msec() / 1000.0 * 0.8
		title_label.rotation.y = sin(t) * deg_to_rad(8.0)
		# Oscillate UV1 scale 1 → 3 → 1 in sync
		var uv_val = 1.0 + 2.0 * abs(sin(t))
		var mat = title_label.get_surface_override_material(0)
		if mat:
			mat.uv1_scale = Vector3(uv_val, uv_val, uv_val)

func start_cutscene():
	is_cutscene_playing = true
	var tween = create_tween()
	
	# 1. Dim the Sky and Fade Visuals
	var text_tween = create_tween().set_parallel(true)
	text_tween.tween_property(title_label, "scale", Vector3.ZERO, 1.0).set_ease(Tween.EASE_IN)
	text_tween.tween_property(instruction_label, "scale", Vector3.ZERO, 1.0).set_ease(Tween.EASE_IN)
	text_tween.tween_property(world_env.environment, "background_energy_multiplier", 0.05, 1.0)
	
	tween.tween_interval(1.0)
	
	# 2. Line 1: "the creeps will not stop" + Mob Appears
	tween.tween_callback(func(): _animate_pop_up(mob, Vector3(-45, 0, 0), true))
	tween.tween_property(line1, "modulate:a", 1.0, 1.0)
	tween.tween_interval(2.0)
	tween.tween_property(line1, "modulate:a", 0.0, 0.5)
	
	# 3. Line 2: "defend your home" + Player + Controls
	tween.tween_callback(func():
		var line2_in = create_tween().set_parallel(true)
		line2_in.tween_property(line2, "modulate:a", 1.0, 1.0)
		line2_in.tween_property(controls_container, "modulate:a", 1.0, 1.0)
		# Flash WASD Sequence
		_flash_wasd_sequence()
	)
	
	tween.tween_interval(1.0) # Wait for text to read
	
	# Player Appears
	tween.tween_callback(func(): _animate_pop_up(player, Vector3.ZERO, false))
	tween.tween_interval(0.5)
	
	# Player Jump Sequence + Space Flash
	tween.tween_callback(func():
		_flash_key(key_space, tex_space_filled, tex_space_out)
		_flash_key(key_shift, tex_shift_filled, tex_shift_out)
		_animate_jump_attack()
	)
	
	tween.tween_interval(1.5)
	
	# Fade out Player, Line 2, and Controls
	tween.tween_callback(func():
		var fade_p_tween = create_tween().set_parallel(true)
		fade_p_tween.tween_property(player, "scale", Vector3.ZERO, 0.5).set_ease(Tween.EASE_IN)
		fade_p_tween.tween_property(line2, "modulate:a", 0.0, 0.5)
		fade_p_tween.tween_property(controls_container, "modulate:a", 0.0, 0.5)
	)
	tween.tween_interval(0.5)
	
	# 4. Line 3: "diamonds are blessings" + Angel
	tween.tween_callback(func(): _animate_pop_up(angel, Vector3.ZERO, true))
	tween.tween_property(line3, "modulate:a", 1.0, 1.0)
	tween.tween_interval(2.5)
	
	# 5. Transition to Main Scene
	tween.tween_callback(change_scene)

func _flash_key(node: TextureRect, filled: Texture2D, outline: Texture2D):
	if not node: return
	var tween = create_tween()
	# Switch to filled
	tween.tween_callback(func(): node.texture = filled)
	# Small scale bump
	tween.tween_property(node, "scale", Vector3(1.2, 1.2, 1), 0.1)
	tween.tween_interval(0.2)
	# Reset
	tween.tween_callback(func(): node.texture = outline)
	tween.tween_property(node, "scale", Vector3.ONE, 0.1)

func _flash_wasd_sequence():
	var tween = create_tween()
	# W
	tween.tween_callback(func(): _flash_key(key_w, tex_w_filled, tex_w_out))
	tween.tween_interval(0.3)
	# A
	tween.tween_callback(func(): _flash_key(key_a, tex_a_filled, tex_a_out))
	tween.tween_interval(0.3)
	# S
	tween.tween_callback(func(): _flash_key(key_s, tex_s_filled, tex_s_out))
	tween.tween_interval(0.3)
	# D
	tween.tween_callback(func(): _flash_key(key_d, tex_d_filled, tex_d_out))

func _animate_pop_up(node: Node3D, extra_rotation: Vector3, should_spin: bool = true):
	if is_instance_valid(node):
		var tween = create_tween()
		tween.tween_property(node, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		
		if should_spin:
			if extra_rotation != Vector3.ZERO:
				var tilt_tween = create_tween()
				tilt_tween.tween_property(node, "rotation_degrees:x", node.rotation_degrees.x + extra_rotation.x, 2.0)
			
			var spin_tween = create_tween().set_loops()
			spin_tween.tween_property(node, "rotation_degrees:y", node.rotation_degrees.y + 360, 4.0).as_relative()

func _animate_jump_attack():
	if not is_instance_valid(player) or not is_instance_valid(mob):
		return
		
	var jump_tween = create_tween()
	var start_pos = player.position
	var target_pos = mob.position
	var peak_height = 2.0
	
	var apex_pos = start_pos.lerp(target_pos, 0.5)
	apex_pos.y += peak_height
	
	jump_tween.tween_property(player, "position", apex_pos, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	jump_tween.tween_property(player, "position", target_pos, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	jump_tween.tween_callback(func():
		if is_instance_valid(mob):
			mob.squash()
		var bounce_pos = target_pos
		bounce_pos.y += 1.5
		bounce_pos.x += 1.0
		var bounce_tween = create_tween()
		bounce_tween.tween_property(player, "position", bounce_pos, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)

func change_scene():
	get_tree().change_scene_to_file("res://main.tscn")
