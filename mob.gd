extends CharacterBody3D

# Minimum speed of the mob in meters per second.
@export var min_speed = 10
# Maximum speed of the mob in meters per second.
@export var max_speed = 18
# The downward acceleration when in the air, in meters per second squared.
@export var fall_acceleration = 75

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y = velocity.y - (fall_acceleration * delta)
	
	move_and_slide()

# This function will be called from the Main scene.
func initialize(start_position, player_position):
	# We position the mob and turn it so that it looks at the player.
	# Set Y to ground level (ground is at -4, add 1 for mob height)
	start_position.y = -3
	look_at_from_position(start_position, player_position, Vector3.UP)
	# Rotate this mob randomly within range of -45 and +45 degrees,
	# so that it doesn't move directly towards the player.
	rotate_y(randf_range(-PI / 4, PI / 4))

	# We calculate a random speed (integer)
	var random_speed = randi_range(min_speed, max_speed)
	# We calculate a forward velocity that represents the speed.
	velocity = Vector3.FORWARD * random_speed
	# We then rotate the velocity vector based on the mob's Y rotation
	# in order to move in the direction the mob is looking.
	velocity = velocity.rotated(Vector3.UP, rotation.y)

func _on_visible_on_screen_notifier_3d_screen_exited():
	queue_free()

func squash():
	queue_free()
