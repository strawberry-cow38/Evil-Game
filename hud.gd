extends CanvasLayer

@export var player_path: NodePath
@onready var _label: Label = $Label
var _player: CharacterBody3D

func _ready() -> void:
	if player_path != NodePath():
		_player = get_node(player_path)

func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var speed := 0.0
	if _player:
		var v := _player.velocity
		speed = Vector2(v.x, v.z).length()
	_label.text = "FPS: %d\nSpeed: %.2f m/s" % [fps, speed]
