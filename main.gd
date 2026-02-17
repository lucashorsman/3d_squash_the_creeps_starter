extends Node

@export var mob_scene: PackedScene
@export var min_spawn_distance = 7.0
@export var max_spawn_distance = 50.0
@export var hoop_scene: PackedScene
@export var powerup_pickup_scene: PackedScene = preload("res://powerup_pickup.tscn")
@export var powerup_ui_scene: PackedScene = preload("res://powerup_ui.tscn")
@export var game_over_scene: PackedScene = preload("res://game_over_screen.tscn")
@export var max_powerups_on_field: int = 5

var score = 0
var high_score = 0
var time_elapsed = 0.0
var powerup_ui
var mob_speed_multiplier = 1.0

func _ready():
	high_score = load_high_score()
	$Player.hit.connect(_on_player_hit)
	$Player.score_earned.connect(_on_player_score_earned)
	
	# Instantiate Powerup UI
	powerup_ui = powerup_ui_scene.instantiate()
	add_child(powerup_ui)
	powerup_ui.selected.connect(_on_powerup_selected)
	
	$FadeOverlay/ColorRect.color.a = 1.0
	var tween = create_tween()
	tween.tween_property($FadeOverlay/ColorRect, "color:a", 0.0, 1.0)
	tween.tween_callback($FadeOverlay.queue_free)
	
	# Start Powerup Timer
	var powerup_timer = Timer.new()
	powerup_timer.wait_time = 3
	powerup_timer.autostart = true
	powerup_timer.timeout.connect(_on_powerup_timer_timeout)
	add_child(powerup_timer)

func _process(delta):
	# Update time
	time_elapsed += delta

func _on_hoop_timer_timeout():
		var hoop = hoop_scene.instantiate()


func _on_mob_timer_timeout():
	# Create a new instance of the Mob scene.
	var mob = mob_scene.instantiate()

	# Choose random location on ground
	var player_position = $Player.position
	var spawn_position = Vector3.ZERO
	var attempts = 0
	var max_attempts = 20
	
	while attempts < max_attempts:
		# Random X/Z within ground bounds (approx +/- 90 for safety)
		spawn_position.x = randf_range(-90.0, 90.0)
		spawn_position.z = randf_range(-90.0, 90.0)
		spawn_position.y = 1 # Ensure spawn position is on ground
		
		# Check distance to player (only X and Z, ignore Y)
		var distance = Vector2(spawn_position.x - player_position.x, spawn_position.z - player_position.z).length()
		
		if distance >= min_spawn_distance  and distance <= max_spawn_distance:
			break
		
		attempts += 1
	
	# Select mob type based on difficulty scaling
	var selected_type = _pick_mob_type()
	mob.initialize(spawn_position, player_position, selected_type)
	mob.set_speed_modifier(mob_speed_multiplier)

	# Spawn the mob by adding it to the Main scene.
	add_child(mob)

func _on_player_score_earned(amount: int):
	# Add the combo score to the total
	score += amount
	$UserInterface/ScoreLabel.text = str(score)
	
	# Update combo display
	var combo_count = $Player.combo_count
	if combo_count > 1:
		$UserInterface/ComboLabel.text = "COMBO x%d" % combo_count
		$UserInterface/ComboLabel.visible = true
	else:
		$UserInterface/ComboLabel.visible = false

func _on_score_timer_timeout():
	score += 1
	$UserInterface/ScoreLabel.text = str(score)
	

func _on_player_hit():
	# Stop spawning new enemies
	$MobTimer.stop()
	$ScoreTimer.stop()
	
	# Show "Game Over" text immediately
	var label = Label.new()
	label.text = ""
	label.label_settings = LabelSettings.new()
	label.label_settings.font_size = 64
	label.label_settings.font_color = Color(0.8, 0, 0)
	label.label_settings.outline_size = 8
	label.label_settings.outline_color = Color.BLACK
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchors_preset = Control.PRESET_CENTER
	$UserInterface.add_child(label)
	
	# Disable player control
	$Player.set_physics_process(false)
	
	# Freeze all existing enemies
	for mob in get_tree().get_nodes_in_group("mob"):
		mob.set_physics_process(false)
	
	await get_tree().create_timer(1.8).timeout # Match animation length
	print("Game Over! Final Score: ", score)
	
	# Check High Score
	if score > high_score:
		high_score = score
		save_high_score(high_score)
	
	# Show Game Over Screen
	var game_over = game_over_scene.instantiate()
	add_child(game_over)
	game_over.set_scores(score, high_score)
	game_over.show()
	game_over.restart_game.connect(_on_restart_game)
	
	# Enable mouse processing for UI
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_restart_game():
	get_tree().paused = false
	get_tree().reload_current_scene()

func save_high_score(new_score):
	var file = FileAccess.open("user://highscore.save", FileAccess.WRITE)
	if file:
		file.store_32(new_score)

func load_high_score() -> int:
	if FileAccess.file_exists("user://highscore.save"):
		var file = FileAccess.open("user://highscore.save", FileAccess.READ)
		if file:
			return file.get_32()
	return 0

func _on_powerup_timer_timeout():
	# Cap powerups on the field
	var current_pickups = get_tree().get_nodes_in_group("powerup_pickups")
	if current_pickups.size() >= max_powerups_on_field:
		return
	
	# Spawn powerup pickup
	# Try to find a spawn location that isn't too close to existing pickups
	## Spawns a power-up at a random position, ensuring it doesn't spawn too close to existing pickups.
	## Generates random coordinates within the play area and checks distance against all current pickups.
	## If a pickup is found within 15 units, the loop retries with a new random position.
	## Otherwise, the pickup is placed at the generated spawn position.
	var spawn_pos = Vector3.ZERO
	var pickup = powerup_pickup_scene.instantiate()
	var max_attempts = 50
	var attempts = 0
	
	while attempts < max_attempts:
		print("Finding spawn position for powerup...")
		spawn_pos = Vector3(randf_range(-90, 90), 1, randf_range(-90, 90))
		var valid_position = true
		
		for pickup1 in current_pickups:
			var dist = Vector2(spawn_pos.x - pickup1.position.x, spawn_pos.z - pickup1.position.z).length()
			if dist < 15.0:
				valid_position = false
				break # Too close to this pickup, try again
		
		if valid_position:
			break # Found a good position!
		
		attempts += 1
			
	pickup.add_to_group("powerup_pickups")
	pickup.position = spawn_pos
	add_child(pickup)
	pickup.picked_up.connect(_on_powerup_picked_up)

func _on_powerup_picked_up():
	# Play coin sound (survives pause)
	var sound = AudioStreamPlayer.new()
	sound.stream = preload("res://art/sound/pickupCoin.wav")
	sound.volume_db = -5.0
	sound.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sound)
	sound.play()
	sound.finished.connect(sound.queue_free)
	
	get_tree().paused = true
	powerup_ui.show_options()

func _on_powerup_selected(type):
	$Player.apply_powerup(type)
	get_tree().paused = false

func _on_player_slow_time_toggled(active: bool):
	mob_speed_multiplier = 0.5 if active else 1.0
	get_tree().call_group("mob", "set_speed_modifier", mob_speed_multiplier)

func _pick_mob_type() -> int:
	# Difficulty scaling: weighted random mob type based on time
	# MobType enum: CHARGER=0, FLANKER=1, ORBITER=2, LURKER=3
	var weights: Array[float]
	
	if time_elapsed < 30.0:
		weights = [80.0, 20.0, 0.0, 0.0]
	elif time_elapsed < 60.0:
		weights = [50.0, 30.0, 20.0, 0.0]
	elif time_elapsed < 90.0:
		weights = [30.0, 25.0, 25.0, 20.0]
	else:
		weights = [20.0, 30.0, 25.0, 25.0]
	
	# Weighted random selection
	var total = 0.0
	for w in weights:
		total += w
	
	var roll = randf() * total
	var cumulative = 0.0
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			return i
	
	return 0 # Default: Charger
