extends Node

@export var mob_scene: PackedScene
@export var min_spawn_distance = 5.0

var score = 0

func _ready():
	$Player.hit.connect(_on_player_hit)
	

func _on_mob_timer_timeout():
	# Create a new instance of the Mob scene.
	var mob = mob_scene.instantiate()

	# Choose a random location on the SpawnPath.
	var mob_spawn_location = $SpawnPath/SpawnLocation
	var player_position = $Player.position
	
	# Keep trying random positions until we find one far enough from the player
	var spawn_position
	var attempts = 0
	var max_attempts = 20
	
	while attempts < max_attempts:
		mob_spawn_location.progress_ratio = randf()
		spawn_position = mob_spawn_location.position
		spawn_position.y = -3 # Ensure spawn position is on ground
		
		# Check distance to player (only X and Z, ignore Y)
		var distance = Vector2(spawn_position.x - player_position.x, spawn_position.z - player_position.z).length()
		
		if distance >= min_spawn_distance:
			break
		
		attempts += 1
	
	mob.initialize(spawn_position, player_position)

	# Spawn the mob by adding it to the Main scene.
	add_child(mob)

func _on_score_timer_timeout():
	score += 1
	print("Score: ", score)

func _on_player_hit():
	print("Game Over! Final Score: ", score)
	get_tree().reload_current_scene()
