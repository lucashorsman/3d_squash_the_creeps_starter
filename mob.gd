extends CharacterBody3D

# === MOB TYPE ===
enum MobType {CHARGER, FLANKER, ORBITER, LURKER}

@export var mob_type: MobType = MobType.CHARGER

# === Base Movement ===
@export var min_speed = 10
@export var max_speed = 18
@export var fall_acceleration = 75

# === Separation ===
@export var min_mob_distance: float = 2.5
@export var separation_force: float = 50.0

# === Charger Settings ===
@export_group("Charger")
@export var charger_turn_speed: float = 1.0
@export var charger_commit_time: float = 1.5 # Seconds before recalculating direction
@export var charger_speed_min: float = 16.0
@export var charger_speed_max: float = 22.0

# === Flanker Settings ===
@export_group("Flanker")
@export var flanker_turn_speed: float = 3.0
@export var flanker_offset_angle: float = 1.2 # ~70 degrees in radians
@export var flanker_recalc_time: float = 2.0
@export var flanker_speed_min: float = 12.0
@export var flanker_speed_max: float = 16.0

# === Orbiter Settings ===
@export_group("Orbiter")
@export var orbiter_turn_speed: float = 5.0
@export var orbiter_radius: float = 10.0
@export var orbiter_shrink_rate: float = 0.5 # Radius shrinks per second
@export var orbiter_min_radius: float = 3.0
@export var orbiter_speed_min: float = 10.0
@export var orbiter_speed_max: float = 14.0

# === Lurker Settings ===
@export_group("Lurker")
@export var lurker_idle_speed: float = 6.0
@export var lurker_charge_speed: float = 20.0
@export var lurker_turn_speed: float = 3.0
@export var lurker_safe_distance: float = 15.0

# === Pack Tactics ===
@export_group("Pack Tactics")
@export var pack_radius: float = 12.0
@export var pack_min_size: int = 3
@export var pack_recalc_time: float = 1.0

# === Archetype Colors ===
@export_group("Visual")
@export var charger_color: Color = Color(1.0, 0.2, 0.2) # Red
@export var flanker_color: Color = Color(1.0, 0.9, 0.2) # Yellow
@export var orbiter_color: Color = Color(0.7, 0.2, 1.0) # Purple
@export var lurker_color: Color = Color(0.2, 0.6, 0.2) # Dark Green

# === Internal State ===
var player: Node3D
var mob_speed: float
var speed_modifier: float = 1.0

# Charger state
var committed_direction: Vector3 = Vector3.ZERO
var commit_timer: float = 0.0

# Flanker state
var flank_side: float = 1.0 # 1 or -1
var flank_recalc_timer: float = 0.0

# Orbiter state
var orbit_angle: float = 0.0
var current_orbit_radius: float = 10.0
var orbit_direction: float = 1.0 # 1 or -1

# Lurker state
var is_charging: bool = false

# Pack state
var pack_recalc_timer_internal: float = 0.0
var pack_assigned_angle: float = 0.0
var is_pack_alpha: bool = false

# Emission light
var type_light: OmniLight3D

func set_speed_modifier(value: float):
	speed_modifier = value

func _ready():
	player = get_tree().get_first_node_in_group("player")
	_setup_type_visual()

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y = velocity.y - (fall_acceleration * delta)
	
	# === SEPARATION (Hard constraint) ===
	_enforce_separation(delta)
	
	# === TYPE-SPECIFIC AI ===
	if player != null:
		match mob_type:
			MobType.CHARGER:
				_ai_charger(delta)
			MobType.FLANKER:
				_ai_flanker(delta)
			MobType.ORBITER:
				_ai_orbiter(delta)
			MobType.LURKER:
				_ai_lurker(delta)
	
	# === PACK TACTICS ===
	pack_recalc_timer_internal -= delta
	if pack_recalc_timer_internal <= 0:
		pack_recalc_timer_internal = pack_recalc_time
		_evaluate_pack()
	
	# Face movement direction
	if velocity.length() > 0.1:
		var look_target = global_position + velocity
		look_target.y = global_position.y
		var target_transform = transform.looking_at(look_target, Vector3.UP)
		transform.basis = transform.basis.slerp(target_transform.basis, 10.0 * delta)
	
	move_and_slide()


# =============================================
# SEPARATION
# =============================================
func _enforce_separation(_delta):
	var mobs = get_tree().get_nodes_in_group("mob")
	for other in mobs:
		if other == self or not is_instance_valid(other):
			continue
		var to_self = global_position - other.global_position
		to_self.y = 0
		var dist = to_self.length()
		if dist < min_mob_distance and dist > 0.01:
			# Hard push away
			var push = to_self.normalized() * separation_force * (min_mob_distance - dist)
			velocity.x += push.x
			velocity.z += push.z


# =============================================
# CHARGER AI
# =============================================
func _ai_charger(delta):
	commit_timer -= delta
	
	if commit_timer <= 0:
		# Recalculate committed direction
		if player != null:
			committed_direction = (player.global_position - global_position)
			committed_direction.y = 0
			committed_direction = committed_direction.normalized()
		commit_timer = charger_commit_time
	
	# Rush in committed direction with very low steering
	var target_vel = committed_direction * mob_speed * speed_modifier
	velocity.x = lerp(velocity.x, target_vel.x, charger_turn_speed * delta)
	velocity.z = lerp(velocity.z, target_vel.z, charger_turn_speed * delta)


# =============================================
# FLANKER AI
# =============================================
func _ai_flanker(delta):
	flank_recalc_timer -= delta
	if flank_recalc_timer <= 0:
		flank_recalc_timer = flanker_recalc_time
		# Randomly pick left or right
		flank_side = [-1.0, 1.0].pick_random()
	
	if player == null:
		return
	
	# Calculate offset target position (to the side of the player)
	var to_player = (player.global_position - global_position)
	to_player.y = 0
	to_player = to_player.normalized()
	
	# Rotate direction to approach from the side
	var offset_dir = to_player.rotated(Vector3.UP, flanker_offset_angle * flank_side)
	
	# When close enough, switch to direct approach
	var dist_to_player = global_position.distance_to(player.global_position)
	var blend = clamp(1.0 - (dist_to_player / 8.0), 0.0, 1.0)
	var final_dir = offset_dir.lerp(to_player, blend).normalized()
	
	var target_vel = final_dir * mob_speed * speed_modifier
	velocity.x = lerp(velocity.x, target_vel.x, flanker_turn_speed * delta)
	velocity.z = lerp(velocity.z, target_vel.z, flanker_turn_speed * delta)


# =============================================
# ORBITER AI
# =============================================
func _ai_orbiter(delta):
	if player == null:
		return
	
	# Shrink orbit radius over time
	current_orbit_radius = max(current_orbit_radius - orbiter_shrink_rate * delta, orbiter_min_radius)
	
	# Calculate orbit position
	orbit_angle += orbit_direction * (mob_speed * speed_modifier / current_orbit_radius) * delta * 0.3
	
	var target_pos = player.global_position + Vector3(
		cos(orbit_angle) * current_orbit_radius,
		0,
		sin(orbit_angle) * current_orbit_radius
	)
	
	var direction = (target_pos - global_position)
	direction.y = 0
	direction = direction.normalized()
	
	var target_vel = direction * mob_speed * speed_modifier
	velocity.x = lerp(velocity.x, target_vel.x, orbiter_turn_speed * delta)
	velocity.z = lerp(velocity.z, target_vel.z, orbiter_turn_speed * delta)


# =============================================
# LURKER AI
# =============================================
func _ai_lurker(delta):
	if player == null:
		return
	
	var dist = global_position.distance_to(player.global_position)
	
	# Check if player is mid-air
	if not player.is_on_floor():
		is_charging = true
	
	if is_charging:
		# Full charge at the player
		var direction = (player.global_position - global_position)
		direction.y = 0
		direction = direction.normalized()
		
		var charge_vel = direction * lurker_charge_speed * speed_modifier
		velocity.x = lerp(velocity.x, charge_vel.x, lurker_turn_speed * delta)
		velocity.z = lerp(velocity.z, charge_vel.z, lurker_turn_speed * delta)
		
		# Stop charging if close to player and player is grounded
		if dist < 5.0 and player.is_on_floor():
			is_charging = false
	else:
		# Idle: maintain distance. If too close, back away. If too far, drift closer.
		var direction = (player.global_position - global_position)
		direction.y = 0
		direction = direction.normalized()
		
		if dist < lurker_safe_distance - 3.0:
			# Too close, back away
			var target_vel = - direction * lurker_idle_speed * speed_modifier
			velocity.x = lerp(velocity.x, target_vel.x, lurker_turn_speed * delta)
			velocity.z = lerp(velocity.z, target_vel.z, lurker_turn_speed * delta)
		elif dist > lurker_safe_distance + 3.0:
			# Too far, drift closer
			var target_vel = direction * lurker_idle_speed * speed_modifier
			velocity.x = lerp(velocity.x, target_vel.x, lurker_turn_speed * delta)
			velocity.z = lerp(velocity.z, target_vel.z, lurker_turn_speed * delta)
		else:
			# Comfortable distance, strafe sideways
			var strafe = direction.rotated(Vector3.UP, PI / 2.0)
			var target_vel = strafe * lurker_idle_speed * 0.5 * speed_modifier
			velocity.x = lerp(velocity.x, target_vel.x, lurker_turn_speed * delta)
			velocity.z = lerp(velocity.z, target_vel.z, lurker_turn_speed * delta)


# =============================================
# PACK TACTICS
# =============================================
func _evaluate_pack():
	if player == null:
		return
	
	var nearby_mobs = []
	var mobs = get_tree().get_nodes_in_group("mob")
	for m in mobs:
		if not is_instance_valid(m):
			continue
		if m.global_position.distance_to(global_position) < pack_radius:
			nearby_mobs.append(m)
	
	if nearby_mobs.size() < pack_min_size:
		is_pack_alpha = false
		return
	
	# Find closest mob to player = alpha
	var closest_dist = INF
	var alpha = null
	for m in nearby_mobs:
		var d = m.global_position.distance_to(player.global_position)
		if d < closest_dist:
			closest_dist = d
			alpha = m
	
	is_pack_alpha = (alpha == self)
	
	if not is_pack_alpha:
		# Assign spread angle
		var non_alpha = nearby_mobs.filter(func(m): return m != alpha)
		var my_index = non_alpha.find(self)
		if my_index >= 0 and non_alpha.size() > 0:
			# Distribute angles around the player
			var angle_step = TAU / (non_alpha.size() + 1)
			pack_assigned_angle = angle_step * (my_index + 1)
			
			# Override target: approach from assigned angle
			var target_pos = player.global_position + Vector3(
				cos(pack_assigned_angle) * 5.0,
				0,
				sin(pack_assigned_angle) * 5.0
			)
			
			var direction = (target_pos - global_position)
			direction.y = 0
			if direction.length() > 0.1:
				committed_direction = direction.normalized()


# =============================================
# VISUAL SETUP
# =============================================
func _setup_type_visual():
	var color: Color
	match mob_type:
		MobType.CHARGER:
			color = charger_color
		MobType.FLANKER:
			color = flanker_color
		MobType.ORBITER:
			color = orbiter_color
		MobType.LURKER:
			color = lurker_color
	
	# Create a colored light for visual distinction
	type_light = OmniLight3D.new()
	type_light.light_color = color
	type_light.light_energy = 1.5
	type_light.omni_range = 3.0
	type_light.position = Vector3(0, 1.5, 0)
	add_child(type_light)


# =============================================
# INITIALIZATION
# =============================================
func initialize(start_position, player_position, type: MobType = MobType.CHARGER):
	global_position = start_position
	mob_type = type
	
	# Set speed based on type
	match mob_type:
		MobType.CHARGER:
			mob_speed = randf_range(charger_speed_min, charger_speed_max)
		MobType.FLANKER:
			mob_speed = randf_range(flanker_speed_min, flanker_speed_max)
		MobType.ORBITER:
			mob_speed = randf_range(orbiter_speed_min, orbiter_speed_max)
			current_orbit_radius = orbiter_radius
			orbit_angle = randf_range(0, TAU)
			orbit_direction = [-1.0, 1.0].pick_random()
		MobType.LURKER:
			mob_speed = lurker_idle_speed
	
	# Set initial velocity towards player
	var direction = (player_position - start_position).normalized()
	velocity = direction * mob_speed
	
	# Randomize some timers so mobs don't sync up
	commit_timer = randf_range(0, charger_commit_time)
	flank_recalc_timer = randf_range(0, flanker_recalc_time)
	pack_recalc_timer_internal = randf_range(0, pack_recalc_time)
	
	# Setup visual after type is set
	_setup_type_visual()


func _on_visible_on_screen_notifier_3d_screen_exited():
	# Only despawn if very far from the player
	if player and global_position.distance_to(player.global_position) > 120.0:
		queue_free()

func squash():
	$AnimationPlayer.play("squash")
	$CollisionShape3D.disabled = true
	set_physics_process(false)
