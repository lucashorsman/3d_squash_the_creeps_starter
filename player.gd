extends CharacterBody3D

# Emitted when the player was hit by a mob.
signal hit

# How fast the player moves in meters per second.
@export var speed = 14
# The downward acceleration when in the air, in meters per second squared.
@export var fall_acceleration = 75
@export var jump_impulse = 20
@export var bounce_impulse = 16
@export var dash_speed = 30  # Speed multiplier during dash
@export var dash_duration = 0.2  # How long the dash lasts in seconds
@export var dash_cooldown = 1.0  # Cooldown time in seconds
@export var is_dashing = false
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var dash_direction = Vector3.ZERO
var dash_locked_y = 0.0  # Y position when dash started

var target_velocity = Vector3.ZERO

func _ready():
	# Get reference to the dash fuel gauge
	update_dash_gauge()

func _physics_process(delta):
	# We create a local variable to store the input direction.
	var direction = Vector3.ZERO
	
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
			# Setting the basis property will affect the rotation of the node.
			$Pivot.basis = Basis.looking_at(direction)
			$AnimationPlayer.speed_scale = 4
		else:
			$AnimationPlayer.speed_scale = 1		
	# Ground Velocity
	target_velocity.x = movement_direction.x * current_speed
	target_velocity.z = movement_direction.z * current_speed

	# Vertical Velocity
	if not is_on_floor() and not is_dashing: # If in the air, fall towards the floor. Literally gravity
		target_velocity.y = target_velocity.y - (fall_acceleration * delta)
	
	# Lock Y position during dash
	if is_dashing:
		target_velocity.y = 0
		
	# Moving the Character
	velocity = target_velocity
	move_and_slide()
	
	# Lock Y position during dash (after physics)
	if is_dashing:
		position.y = dash_locked_y
	
	$Pivot.rotation.x = PI / 6 * velocity.y / jump_impulse
	
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
				# If so, we squash it and bounce.
				mob.squash()
				target_velocity.y = bounce_impulse
				# Cancel dash on bounce to allow vertical movement
				is_dashing = false
				dash_timer = 0.0
				# velocity.y = bounce_impulse
				# Prevent further duplicate calls.
				break
			else:
				# Hit from the side - player dies
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
