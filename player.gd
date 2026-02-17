extends CharacterBody3D

# Emitted when the player was hit by a mob.
signal hit
# Emitted when the player earns score from bouncing on mobs
# Emitted when the player earns score from bouncing on mobs
signal score_earned(amount: int)
signal slow_time_toggled(active: bool)

@onready var bounce_sound = $BounceSound
@onready var dash_sound = $DashSound
@onready var hit_sound = $HitSound
@onready var shield_break_sound = $ShieldBreakSound
@onready var explosion_bounce_sound = $ExplosionBounceSound
@onready var jump_sound = $JumpSound

# How fast the player moves in meters per second.
@export var speed = 14
# The downward acceleration when in the air, in meters per second squared.
@export var fall_acceleration = 75
@export var jump_impulse = 20
@export var bounce_impulse = 20
@export var dash_speed = 35 # Speed multiplier during dash
@export var dash_duration = 0.2 # How long the dash lasts in seconds
@export var dash_cooldown = 1.0 # Cooldown time in seconds
# Movement feel parameters
@export var acceleration = 8.0 # How fast player reaches max speed
@export var friction = 12.0 # How fast player stops
@export var air_control = 0.3 # Control while airborne (0.0-1.0)
@export var rotation_speed = 12.0 # How fast player turns
# Camera parameters
@export var base_fov = 75.0
@export var max_fov = 90.0
@export var fov_speed = 5.0
@export var camera_tilt_amount = 0.15
@export var trauma_decay = 2.0
@export var max_shake_offset = 0.3
@export var max_shake_rotation = 0.1
var camera_trauma = 0.0
@export var is_dashing = false
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var dash_direction = Vector3.ZERO
var dash_locked_y = 0.0 # Y position when dash started

# Combo system variables
var combo_count = 0
var combo_timer = 0.0
@export var max_combo_time = 2.0
@export var score_popup_scene: PackedScene

# Powerup States
enum PowerupType {
	DOUBLE_JUMP,
	DASH_UNLOCK,
	DOUBLE_DASH,
	SHIELD,
	SPEED_BOOST,
	SLOW_TIME,
	EXPLOSIVE_LAND,
	REPEL,
	SCORE_MULTIPLIER
}
var can_double_jump = false
var can_dash = false # Default false, unlocked by powerup
var double_dash = false
var has_shield = false
var speed_boost_active = false
var explosive_landing = false
var repel_active = false
var score_multiplier = 1

var jump_count = 0
var powerup_timers = {} # Store timer references
var powerup_bars = {} # Store bar UI references per powerup
var powerup_durations = {} # Store max duration per powerup


var target_velocity = Vector3.ZERO
@onready var camera = get_node_or_null("Camera3D")

var powerup_aura: MeshInstance3D
var powerup_light: OmniLight3D
var powerup_material: StandardMaterial3D

var is_invulnerable = false

func _ready():
	# Get reference to the dash fuel gauge
	update_dash_gauge()
	# Debug camera
	if camera:
		print("Camera found: ", camera.name)
	else:
		print("WARNING: Camera not found!")
	
	_create_aura()

func _physics_process(delta):
	# We create a local variable to store the input direction.
	var direction = Vector3.ZERO
	
	# Update combo timer
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo_count = 0 # Reset combo when timer expires
	
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	
	if dash_timer > 0:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
	
	# Update dash fuel gauge
	update_dash_gauge()
	
	# We check for each move input and update the direction accordingly.
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_back"):
		# Notice how we are working with the vector's x and z axes.
		# In 3D, the XZ plane is the ground plane.
		direction.z += 1
	if Input.is_action_pressed("move_forward"):
		direction.z -= 1
	if Input.is_action_just_pressed("dash"):
		# Repel wave works even without dash unlocked
		if repel_active:
			_trigger_repel_wave()
		
		if can_dash and dash_cooldown_timer <= 0 and not is_dashing:
			if direction != Vector3.ZERO:
				# Start dash
				is_dashing = true
				dash_timer = dash_duration
				dash_cooldown_timer = dash_cooldown
				dash_direction = direction.normalized()
				dash_locked_y = position.y # Lock current Y position
				dash_sound.play(0.05)
	
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			target_velocity.y = jump_impulse
			jump_count = 1
			jump_sound.play()
		elif can_double_jump and jump_count < 2:
			target_velocity.y = jump_impulse
			jump_count += 1
			jump_sound.play()
			$AnimationPlayer.play("jump") # Replay jump anim
	
	# Determine movement direction and current speed
	var current_speed = speed
	var movement_direction = direction
	
	if is_dashing:
		current_speed = dash_speed
		movement_direction = dash_direction
		$AnimationPlayer.speed_scale = 8
		# Visual feedback: tint player cyan/blue during dash
		#$Pivot/Character.modulate = Color(0.5, 0.8, 1.5)
		$Pivot.scale = Vector3(1.2, 0.9, 1.2)
		# Enable dash trail particles
		$Pivot/DashTrail.emitting = true
	else:
		# Reset visual effects when not dashing
		#$Pivot/Character.modulate = Color(1, 1, 1)
		$Pivot.scale = Vector3.ONE # Disable dash trail particles
		$Pivot/DashTrail.emitting = false
		
		if direction != Vector3.ZERO:
			direction = direction.normalized()
			movement_direction = direction
			# Smooth rotation instead of instant snap
			var target_basis = Basis.looking_at(direction)
			$Pivot.basis = $Pivot.basis.slerp(target_basis, rotation_speed * delta)
		
	# Apply air control factor
	var control_factor = 1.0 if is_on_floor() else air_control
	
	# Ground Velocity with acceleration
	target_velocity.x = movement_direction.x * current_speed * control_factor
	target_velocity.z = movement_direction.z * current_speed * control_factor

	# Vertical Velocity
	if not is_on_floor() and not is_dashing: # If in the air, fall towards the floor. Literally gravity
		target_velocity.y = target_velocity.y - (fall_acceleration * delta)
	
	# Lock Y position during dash
	if is_dashing:
		target_velocity.y = 0
		
	# Moving the Character with smooth acceleration/deceleration
	if not is_dashing:
		if movement_direction != Vector3.ZERO:
			# Accelerate towards target velocity
			velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
			velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		else:
			# Apply friction when no input
			velocity.x = lerp(velocity.x, 0.0, friction * delta)
			velocity.z = lerp(velocity.z, 0.0, friction * delta)
		# Keep vertical velocity direct
		velocity.y = target_velocity.y
	else:
		# During dash, use direct velocity for tight control
		velocity = target_velocity
	
	move_and_slide()
	
	# Kill Floor check
	if position.y < -20:
		die()
	
	# Lock Y position during dash (after physics)
	if is_dashing:
		position.y = dash_locked_y
	
	$Pivot.rotation.x = PI / 6 * velocity.y / jump_impulse
	
	# Repel Logic

	
	# Speed-based animation - use actual velocity
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if not is_dashing:
		if horizontal_speed > 0.1:
			$AnimationPlayer.speed_scale = 1.0 + (horizontal_speed / speed) * 3.0
		else:
			$AnimationPlayer.speed_scale = 1.0
	
	# Dynamic camera effects
	update_camera(delta, horizontal_speed)
	
	# Iterate through all collisions that occurred this frame
	for index in range(get_slide_collision_count()):
		# We get one of the collisions with the player
		var collision = get_slide_collision(index)
		
		# If the collision is with a mob
		if collision.get_collider() == null:
			continue
		# If the collider is with a group "mob".
		if collision.get_collider().is_in_group("mob"):
			var mob = collision.get_collider()
			# we check that we are hitting it from above.
			if Vector3.UP.dot(collision.get_normal()) > 0.05:
				# Increment combo
				combo_count += 1
				combo_timer = max_combo_time
				
				# Calculate score based on combo
				var score_value = calculate_score(combo_count)
				
				# Spawn floating score text
				spawn_score_popup(mob.global_position, score_value, combo_count)
				
				# Emit score to main scene
				score_earned.emit(score_value)
				
				# Add camera shake based on combo
				camera_trauma = min(camera_trauma + 0.2 + (0.1 * combo_count), 1.0)
				
				# If so, we squash it and bounce.
				mob.squash()
				target_velocity.y = bounce_impulse
				
				if explosive_landing:
					explosion_bounce_sound.play()
					_trigger_explosive_landing()
					target_velocity.y = bounce_impulse * 1.5 # Extra height from explosion
				else:
					bounce_sound.play(0.1)
				
				# Cancel dash on bounce to allow vertical movement
				is_dashing = false
				dash_timer = 0.0
				# velocity.y = bounce_impulse
				# Prevent further duplicate calls.
				break
			else:
				# Hit from the side - player dies or shield protects
				if is_invulnerable:
					break
				
				if has_shield:
					has_shield = false
					_clear_aura()
					shield_break_sound.play()
					# Push mob away
					mob.velocity = (mob.global_position - global_position).normalized() * 30
					print("Shield blocked hit!")
					
					# Grant invulnerability
					is_invulnerable = true
					var timer = get_tree().create_timer(1.0)
					timer.timeout.connect(func(): is_invulnerable = false)
					
					break
				
				die()
				break

func die():
	combo_count = 0 # Reset combo on death
	combo_timer = 0.0
	hit_sound.play()
	hit.emit()
	set_physics_process(false) # Stop movement
	$AnimationPlayer.play("death")

func update_dash_gauge():
	# Get reference to the gauge in the main scene
	var gauge = get_node_or_null("/root/Main/UserInterface/DashFuelGauge")
	if gauge:
		if not can_dash:
			gauge.visible = false
			# return # REMOVED RETURN to allow powerup bar update
		else:
			gauge.visible = true
			
		if is_dashing:
			# During dash, show dash_timer progress (depletes quickly)
			gauge.value = (dash_timer / dash_duration) * 110.0
		elif dash_cooldown_timer > 0:
			# During cooldown, show recovery progress
			gauge.value = (1.0 - (dash_cooldown_timer / dash_cooldown)) * 90.0
		else:
			# Fully ready
			gauge.value = 100.0
		
		# Change color based on whether dash is ready
		if gauge.value >= 100.0:
			# Green when full (dash ready)
			gauge.add_theme_color_override("fill_color", Color(0.0, 1.0, 0.0))
		else:
			# Red when not full (dash not ready)
			gauge.add_theme_color_override("fill_color", Color(1.0, 0.0, 0.0))

	# Update all Powerup Bars
	for pname in powerup_bars.keys():
		var bar = powerup_bars[pname]
		if powerup_timers.has(pname) and is_instance_valid(bar):
			bar.max_value = powerup_durations[pname]
			bar.value = powerup_timers[pname].time_left
		elif is_instance_valid(bar):
			bar.queue_free()
			powerup_bars.erase(pname)
			powerup_durations.erase(pname)
			_reposition_powerup_bars()

func calculate_score(combo: int) -> int:
	# Exponential scoring: 10, 20, 40, 80, 160...
	# With a cap at 10x multiplier to prevent infinite scaling
	var multiplier = min(pow(2, combo - 1), 10)
	return int(10 * multiplier * score_multiplier)

func spawn_score_popup(position: Vector3, score: int, combo: int):
	if score_popup_scene:
		var popup = score_popup_scene.instantiate()
		get_tree().root.add_child(popup)
		popup.initialize(position, score, combo)

func update_camera(delta: float, horizontal_speed: float):
	if not camera:
		return
	
	# 1. Speed-based FOV
	# var speed_ratio = horizontal_speed / speed
	# var target_fov = base_fov + (max_fov - base_fov) * speed_ratio
	# if is_dashing:
	# 	target_fov = 95.0
	# camera.fov = lerp(camera.fov, target_fov, fov_speed * delta)
	
	# # Base camera position (from scene)
	var base_position = camera.position
	
	# 2. Camera shake
	var shake_offset = Vector3.ZERO
	if camera_trauma > 0:
		camera_trauma = max(camera_trauma - trauma_decay * delta, 0)
		var shake_amount = camera_trauma * camera_trauma
		shake_offset = Vector3(
			randf_range(-max_shake_offset, max_shake_offset) * shake_amount,
			randf_range(-max_shake_offset, max_shake_offset) * shake_amount,
			0
		)
		var shake_rotation = randf_range(-max_shake_rotation, max_shake_rotation) * shake_amount
		camera.rotation.z = shake_rotation
	else:
		if abs(camera.rotation.z) > 0.001:
			camera.rotation.z = lerp(camera.rotation.z, 0.0, 10.0 * delta)
	
	# 3. Camera tilt on turns (only when not shaking much)
	if camera_trauma <= 0.1:
		var turn_input = 0.0
		if Input.is_action_pressed("move_right"):
			turn_input += 1.0
		if Input.is_action_pressed("move_left"):
			turn_input -= 1.0
		var target_tilt = turn_input * camera_tilt_amount
		camera.rotation.z = lerp(camera.rotation.z, target_tilt, 5.0 * delta)
	
	# Apply shake offset to position
	camera.position = base_position + shake_offset

func apply_powerup(type: int):
	print("Applying Powerup: ", type)
	match type:
		PowerupType.DOUBLE_JUMP:
			can_double_jump = true
			_set_aura_color(Color.DEEP_SKY_BLUE)
			_start_powerup_timer("double_jump", 15.0, func():
				can_double_jump = false
				_clear_aura()
			)
		PowerupType.DASH_UNLOCK:
			can_dash = true
			# Permanent unlock, maybe just a brief flash?
			_set_aura_color(Color.YELLOW)
			# Create a timer just to clear the aura
			var timer = get_tree().create_timer(1.0)
			timer.timeout.connect(func(): _clear_aura())
			
		PowerupType.DOUBLE_DASH:
			double_dash = true
			dash_cooldown = 0.3 # Fast cooldown
			_set_aura_color(Color.ORANGE_RED)
			_start_powerup_timer("double_dash", 15.0, func():
				double_dash = false
				dash_cooldown = 1.0 # Reset to default
				_clear_aura()
			)
		PowerupType.SHIELD:
			has_shield = true
			_set_aura_color(Color.CYAN)
		PowerupType.SPEED_BOOST:
			speed_boost_active = true
			speed = 24 # Base 14 -> 24
			_set_aura_color(Color.GREEN_YELLOW)
			_start_powerup_timer("speed_boost", 15.0, func():
				speed_boost_active = false
				speed = 14
				_clear_aura()
			)
		PowerupType.REPEL:
			repel_active = true
			_set_aura_color(Color.MAGENTA)
			# No immediate area creation, only triggers on dash
			_start_powerup_timer("repel", 15.0, func():
				repel_active = false
				_clear_aura()
			)
		PowerupType.EXPLOSIVE_LAND:
			explosive_landing = true
			_set_aura_color(Color.ORANGE)
			_start_powerup_timer("explosive", 20.0, func():
				explosive_landing = false
				_clear_aura()
			)
		PowerupType.SCORE_MULTIPLIER:
			score_multiplier = 2
			_set_aura_color(Color.GOLD)
			_start_powerup_timer("score_mult", 15.0, func():
				score_multiplier = 1
				_clear_aura()
			)
		PowerupType.SLOW_TIME:
			# Signal main to slow mobs
			slow_time_toggled.emit(true)
			_set_aura_color(Color.CORNFLOWER_BLUE)
			_start_powerup_timer("slow_time", 10.0, func():
				slow_time_toggled.emit(false)
				_clear_aura()
			)


func _start_powerup_timer(name: String, duration: float, callback: Callable):
	powerup_durations[name] = duration
	
	if powerup_timers.has(name):
		powerup_timers[name].start(duration)
	else:
		var timer = Timer.new()
		timer.wait_time = duration
		timer.one_shot = true
		timer.autostart = true
		add_child(timer)
		timer.timeout.connect(func():
			callback.call()
			timer.queue_free()
			powerup_timers.erase(name)
			if powerup_bars.has(name) and is_instance_valid(powerup_bars[name]):
				powerup_bars[name].queue_free()
				powerup_bars.erase(name)
				powerup_durations.erase(name)
				_reposition_powerup_bars()
		)
		timer.start()
		powerup_timers[name] = timer
	
	# Create a bar for this powerup
	_create_powerup_bar(name)

func _create_powerup_bar(pname: String):
	var ui = get_node_or_null("/root/Main/UserInterface")
	if not ui:
		return
	
	# Remove existing bar for this powerup if it exists
	if powerup_bars.has(pname) and is_instance_valid(powerup_bars[pname]):
		powerup_bars[pname].queue_free()
		powerup_bars.erase(pname)
	
	var bar = ProgressBar.new()
	bar.show_percentage = false
	bar.step = 0.1
	bar.custom_minimum_size = Vector2(100, 15)
	bar.size = Vector2(100, 15)
	
	# Style: dark background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.53)
	bg_style.corner_radius_top_left = 180
	bg_style.corner_radius_bottom_right = 180
	bar.add_theme_stylebox_override("background", bg_style)
	
	# Style: colored fill based on powerup aura
	var fill_style = StyleBoxFlat.new()
	if powerup_light and powerup_light.visible:
		fill_style.bg_color = powerup_light.light_color
	else:
		fill_style.bg_color = Color(0.08, 0.47, 0.73)
	fill_style.corner_radius_top_left = 180
	fill_style.corner_radius_bottom_right = 180
	bar.add_theme_stylebox_override("fill", fill_style)
	
	# Position using anchors (bottom-right area, like dash gauge)
	bar.layout_mode = 1 # Anchors mode
	bar.anchors_preset = 7 # Bottom center
	bar.anchor_left = 0.5
	bar.anchor_top = 1.0
	bar.anchor_right = 0.5
	bar.anchor_bottom = 1.0
	bar.grow_horizontal = 2
	bar.grow_vertical = 0
	bar.scale = Vector2(1.575, 1.575)
	
	ui.add_child(bar)
	powerup_bars[pname] = bar
	_reposition_powerup_bars()

func _reposition_powerup_bars():
	# Stack bars vertically below the dash gauge area
	var base_top = -360.0
	var bar_height = 22.0 # spacing between bars
	var i = 0
	for pname in powerup_bars.keys():
		var bar = powerup_bars[pname]
		if is_instance_valid(bar):
			bar.offset_left = 367.0
			bar.offset_right = 467.0
			bar.offset_top = base_top - (i * bar_height)
			bar.offset_bottom = bar.offset_top + 15.0
			i += 1

func _trigger_repel_wave():
	var repel_area = Area3D.new()
	var shape = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 15.0 # Larger radius for wave
	repel_area.add_child(shape)
	add_child(repel_area)
	repel_area.collision_mask = 2 # Mobs
	
	# Wait one frame for physics to register overlaps
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	for body in repel_area.get_overlapping_bodies():
		if body.is_in_group("mob"):
			var push_dir = (body.global_position - global_position).normalized()
			# Add upward force too for effect
			push_dir.y = 0.5
			push_dir = push_dir.normalized()
			body.velocity = push_dir * 40
	
	repel_area.queue_free()

func _trigger_explosive_landing():
	# Visual feedback (could add particles later)
	print("BOOM! Explosive Landing!")
	
	var explosion_area = Area3D.new()
	var shape = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 15.0 # Wide radius
	explosion_area.add_child(shape)
	add_child(explosion_area)
	explosion_area.collision_mask = 2 # Mobs
	
	# Wait one frame for physics to register overlaps
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	for body in explosion_area.get_overlapping_bodies():
		if body.is_in_group("mob"):
			# Check if mob is already squashed/disabled to avoid double counting
			if body.get_node("CollisionShape3D").disabled:
				continue
				
			# Squash them!
			body.squash()
			
			# Award score based on CURRENT combo (do not increment combo)
			var score_value = calculate_score(combo_count)
			spawn_score_popup(body.global_position, score_value, combo_count)
			score_earned.emit(score_value)
			
			# Launch them away
			var push_dir = (body.global_position - global_position).normalized()
			body.velocity = push_dir * 50
	
	explosion_area.queue_free()


func _create_aura():
	## Create MeshInstance for Aura
	#powerup_aura = MeshInstance3D.new()
	#var sphere = SphereMesh.new()
	#sphere.radius = 1.0
	#sphere.height = 2.0
	#powerup_aura.mesh = sphere
	#
	## Create Material
	#powerup_material = StandardMaterial3D.new()
	#powerup_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	#powerup_material.albedo_color = Color(1, 1, 1, 0.2)
	#powerup_material.emission_enabled = true
	#powerup_material.emission_energy_multiplier = 2.0
	#powerup_aura.material_override = powerup_material
	#
	#powerup_aura.visible = false
	#$Pivot.add_child(powerup_aura)
	#
	# Create Light
	powerup_light = OmniLight3D.new()
	powerup_light.omni_range = 5.0
	powerup_light.light_energy = 2.0
	powerup_light.visible = false
	$Pivot.add_child(powerup_light)

func _set_aura_color(color: Color):
	#powerup_aura.visible = true
	powerup_light.visible = true
	#powerup_material.albedo_color = Color(color.r, color.g, color.b, 0.2)
	#powerup_material.emission = color
	powerup_light.light_color = color

func _clear_aura():
	#powerup_aura.visible = false
	powerup_light.visible = false
