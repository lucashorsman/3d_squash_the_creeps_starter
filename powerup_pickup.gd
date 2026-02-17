extends Area3D

signal picked_up

@export var despawn_time: float = 20.0

var lifetime: float = 0.0

func _ready():
	body_entered.connect(_on_body_entered)

func _process(delta):
	# Rotate the angel
	rotate_y(2.0 * delta)
	
	# Despawn timer
	lifetime += delta
	if lifetime >= despawn_time:
		queue_free()
		return

func _on_body_entered(body):
	if body.is_in_group("player"):
		picked_up.emit()
		queue_free()
