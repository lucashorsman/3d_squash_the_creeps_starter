extends CharacterBody3D

# Minimum speed of the mob in meters per second.
@export var min_speed = 10
# Maximum speed of the mob in meters per second.
@export var max_speed = 18
# The downward acceleration when in the air, in meters per second squared.
@export var fall_acceleration = 75

var player: Node3D
var mob_speed: float
func _ready():
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y = velocity.y - (fall_acceleration * delta)
	
	# Hone in on player position
	if player != null:
		if player.is_on_floor():
			var direction = (player.global_position - global_position)
			direction.y = 0
			direction = direction.normalized()
			velocity.x = direction.x * mob_speed
			velocity.z = direction.z * mob_speed
			
			# Make the mob look at the player
			look_at(player.global_position, Vector3.UP)
	
	if (velocity.is_zero_approx()):
		queue_free()
	
	move_and_slide()

# This function will be called from the Main scene.
func initialize(start_position, player_position):
	# Store the player reference
	
	# Set position
	global_position = start_position
	
	# Calculate a random speed
	mob_speed = randi_range(min_speed, max_speed)
	
	# Set initial velocity towards player
	var direction = (player_position - start_position).normalized()
	velocity = direction * mob_speed

func _on_visible_on_screen_notifier_3d_screen_exited():
	queue_free()

func squash():
	queue_free()
