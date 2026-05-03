extends CanvasLayer

@export var player_path: NodePath
@export var weapon_path: NodePath

@onready var _label: Label = $Label
@onready var _ammo_label: Label = $AmmoLabel
var _player: CharacterBody3D
var _weapon: Node

func _ready() -> void:
	if player_path != NodePath():
		_player = get_node(player_path)
	if weapon_path != NodePath():
		_weapon = get_node(weapon_path)

func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var speed := 0.0
	if _player:
		var v := _player.velocity
		speed = Vector2(v.x, v.z).length()
	_label.text = "FPS: %d\nSpeed: %.2f m/s" % [fps, speed]

	if _weapon and _ammo_label:
		var name: String = _weapon.get_weapon_name() if _weapon.has_method("get_weapon_name") else ""
		var mode: String = _weapon.get_fire_mode_name() if _weapon.has_method("get_fire_mode_name") else ""
		var ammo: int = _weapon.get_ammo() if _weapon.has_method("get_ammo") else 0
		var mag: int = _weapon.get_mag_size() if _weapon.has_method("get_mag_size") else 0
		_ammo_label.text = "%s  [%s]\n%d / %d" % [name, mode, ammo, mag]
