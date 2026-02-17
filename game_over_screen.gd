extends Control

signal restart_game

@onready var score_label = $Panel/ScoreLabel
@onready var high_score_label = $Panel/HighScoreLabel
@onready var restart_button = $Panel/RestartButton

func _ready():
	restart_button.pressed.connect(_on_restart_pressed)
	hide()

func set_scores(score: int, high_score: int):
	score_label.text = "Score: %d" % score
	high_score_label.text = "High Score: %d" % high_score
	restart_button.grab_focus()

func _on_restart_pressed():
	restart_game.emit()
