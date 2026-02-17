extends CanvasLayer

signal selected(powerup_type)

# Updated Enum based on user request
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

var powerup_names = {
	PowerupType.DOUBLE_JUMP: "Double Jump\n(15s)",
	PowerupType.DASH_UNLOCK: "Unlock Dash\n(15s)",
	PowerupType.DOUBLE_DASH: "Double Dash\n(15s)",
	PowerupType.SHIELD: "Shield\n(1 Hit)",
	PowerupType.SPEED_BOOST: "Speed Boost\n(15s)",
	PowerupType.SLOW_TIME: "Slow Mobs\n(10s)",
	PowerupType.EXPLOSIVE_LAND: "Explosive Land\n(20s)",
	PowerupType.REPEL: "Repel Aura\n(15s)",
	PowerupType.SCORE_MULTIPLIER: "2x Score\n(15s)"
}

@onready var btn1 = %Option1
@onready var btn2 = %Option2

var type1
var type2

func _ready():
	btn1.pressed.connect(func(): _on_selected(type1))
	btn2.pressed.connect(func(): _on_selected(type2))

func show_options():
	show()
	# Pick 2 unique random types
	var keys = PowerupType.values()
	
	# Check player state to filter options
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if not player.can_dash:
			keys.erase(PowerupType.DOUBLE_DASH)
		else:
			keys.erase(PowerupType.DASH_UNLOCK)
	
	type1 = keys.pick_random()
	type2 = keys.pick_random()
	
	while type2 == type1:
		type2 = keys.pick_random()
	
	btn1.text = powerup_names[type1]
	btn2.text = powerup_names[type2]
	
	# Focus first button for controller support
	btn1.grab_focus()

func _on_selected(type):
	selected.emit(type)
	hide()
