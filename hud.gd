extends CanvasLayer

@export var player_path: NodePath
@export var weapon_path: NodePath

@onready var _label: Label = $Label
@onready var _ammo_label: Label = $AmmoLabel
@onready var _flash: ColorRect = $LowAmmoFlash
var _player: CharacterBody3D
var _weapon: Node
var _flash_phase := 0.0

func _ready() -> void:
	if player_path != NodePath():
		_player = get_node(player_path)
	if weapon_path != NodePath():
		_weapon = get_node(weapon_path)

func _process(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var speed := 0.0
	if _player:
		var v := _player.velocity
		speed = Vector2(v.x, v.z).length()
	_label.text = "FPS: %d\nSpeed: %.2f m/s" % [fps, speed]

	if _weapon and _ammo_label:
		var equipped: bool = not _weapon.has_method("is_equipped") or _weapon.is_equipped()
		if not equipped:
			_ammo_label.text = "Unarmed\n— / —"
			_update_low_ammo_flash(delta, 1, 1, false)
			return
		var name: String = _weapon.get_weapon_name() if _weapon.has_method("get_weapon_name") else ""
		var mode: String = _weapon.get_fire_mode_name() if _weapon.has_method("get_fire_mode_name") else ""
		var ammo: int = _weapon.get_ammo() if _weapon.has_method("get_ammo") else 0
		var mag: int = _weapon.get_mag_size() if _weapon.has_method("get_mag_size") else 0
		var reserve: int = _weapon.get_reserve_ammo() if _weapon.has_method("get_reserve_ammo") else 0
		var reloading: bool = _weapon.has_method("is_reloading") and _weapon.is_reloading()
		var prog: float = _weapon.get_reload_progress() if _weapon.has_method("get_reload_progress") else 0.0
		if reloading:
			var bar_len := 10
			var filled := int(round(prog * bar_len))
			var bar := "[" + "=".repeat(filled) + " ".repeat(bar_len - filled) + "]"
			_ammo_label.text = "%s  [%s]\n%d / %d   (%d)  %s" % [name, mode, ammo, mag, reserve, bar]
		else:
			_ammo_label.text = "%s  [%s]\n%d / %d   (%d)" % [name, mode, ammo, mag, reserve]
		_update_low_ammo_flash(delta, ammo, mag, reloading)

func _update_low_ammo_flash(delta: float, ammo: int, mag: int, reloading: bool) -> void:
	if _flash == null:
		return
	var ratio: float = (float(ammo) / float(mag)) if mag > 0 else 1.0
	var intensity := 0.0
	var freq := 3.0

	if reloading:
		# Sustain a bright urgent flash through the reload window.
		intensity = 0.40
		freq = 8.0
	elif ratio <= 0.5:
		if ratio > 0.25:
			# 50% → 25%: warm-up flash, modest peak.
			var t: float = (0.5 - ratio) / 0.25
			intensity = lerpf(0.06, 0.18, t)
			freq = lerpf(3.0, 4.5, t)
		else:
			# Below 25%: each missing round ramps both alpha and frequency.
			# 0.25 → ~0.20 alpha, 5 Hz; 0.0 → ~0.45 alpha, 9 Hz.
			var t2: float = clampf((0.25 - ratio) / 0.25, 0.0, 1.0)
			intensity = lerpf(0.20, 0.45, t2)
			freq = lerpf(5.0, 9.0, t2)
	else:
		intensity = 0.0

	if intensity <= 0.0:
		_flash.color.a = 0.0
		return

	_flash_phase += delta * freq
	var pulse: float = sin(_flash_phase * TAU) * 0.5 + 0.5  # 0..1
	_flash.color.a = intensity * pulse
