extends Area3D

func _on_body_entered(body: Node3D):
	if body.name == 'Player':
		print('Player entered area')

func _on_body_exited(body: Node3D):
	if body.name == 'Player':
		print('Player exited area')
