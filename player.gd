extends CharacterBody3D

# Emitted when the player was hit by a mob.
signal hit
# Emitted when the player earns score from bouncing on mobs
signal score_earned(amount: int)

# How fast the player moves in meters per second.
@export var speed = 14
# The downward acceleration when in the air, in meters per second squared.
@export var fall_acceleration = 75
@export var jump_impulse = 20
@export var bounce_impulse = 20
@export var dash_speed = 35  # Speed multiplier during dash
@export var dash_duration = 0.2  # How long the dash lasts in seconds
@export var dash_cooldown = 1.0  # Cooldown time in seconds
# Movement feel parameters
@export var acceleration = 8.0  # How fast player reaches max speed
@export var friction = 12.0  # How fast player stops
@export var air_control = 0.3  # Control while airborne (0.0-1.0)
@export var rotation_speed = 12.0  # How fast player turns
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
var dash_locked_y = 0.0  # Y position when dash started

# Combo system variables
var combo_count = 0
var combo_timer = 0.0
@export var max_combo_time = 2.0
@export var score_popup_scene: PackedScene

var target_velocity = Vector3.ZERO
@onready var bounce_sound = $BounceSound
@onready var dash_sound = $DashSound
@onready var camera = get_node_or_null("Camera3D")

func _ready():
	# Get reference to the dash fuel gauge
	update_dash_gauge()
	# Debug camera
	if camera:
		print("Camera found: ", camera.name)
	else:
		print("WARNING: Camera not found!")

func _physics_process(delta):
	# We create a local variable to store the input direction.
	var direction = Vector3.ZERO
	
	# Update combo timer
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo_count = 0  # Reset combo when timer expires
	
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
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0 and not is_dashing:
		if direction != Vector3.ZERO:
			# Start dash
			is_dashing = true
			dash_timer = dash_duration
			dash_cooldown_timer = dash_cooldown
			dash_direction = direction.normalized()
			dash_locked_y = position.y  # Lock current Y position
			dash_sound.play()
	
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		target_velocity.y = jump_impulse
	
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
		$Pivot.scale = Vector3.ONE		# Disable dash trail particles
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
	
	# Lock Y position during dash (after physics)
	if is_dashing:
		position.y = dash_locked_y
	
	$Pivot.rotation.x = PI / 6 * velocity.y / jump_impulse
	
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
			if Vector3.UP.dot(collision.get_normal()) > 0.1:
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
				# Play bounce sound
				bounce_sound.play()
				print("Bounced on mob! Combo: %d, Score: +%d" % [combo_count, score_value])
				# Cancel dash on bounce to allow vertical movement
				is_dashing = false
				dash_timer = 0.0
				# velocity.y = bounce_impulse
				# Prevent further duplicate calls.
				break
			else:
				# Hit from the side - player dies
				combo_count = 0  # Reset combo on death
				combo_timer = 0.0
				hit.emit()
				set_physics_process(false)  # Stop movement

				$AnimationPlayer.play("death")
				break

func update_dash_gauge():
	# Get reference to the gauge in the main scene
	var gauge = get_node_or_null("/root/Main/UserInterface/DashFuelGauge")
	if gauge:
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

func calculate_score(combo: int) -> int:
	# Exponential scoring: 10, 20, 40, 80, 160...
	# With a cap at 10x multiplier to prevent infinite scaling
	var multiplier = min(pow(2, combo - 1), 10)
	return int(10 * multiplier)

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
	var base_position = Vector3(0, 7.22042, 9)
	
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
