extends CanvasLayer

const Items = preload("res://items.gd")

@export var player_path: NodePath
@export var weapon_path: NodePath

@onready var _label: Label = $Label
@onready var _ammo_label: Label = $AmmoLabel
@onready var _flash: ColorRect = $LowAmmoFlash
var _player: CharacterBody3D
var _weapon: Node
var _flash_phase := 0.0
# RPM gauge (built lazily in _ready). Background bar + fill bar + redline tick.
var _rpm_bg: ColorRect
var _rpm_fill: ColorRect
var _rpm_redline_tick: ColorRect
const RPM_BAR_W := 220.0
const RPM_BAR_H := 10.0
# Minigun spin-up bar. Shown only when minigun equipped; fill 0→1 tracks
# spin progress, color shifts orange → green at ready.
var _mg_bg: ColorRect
var _mg_fill: ColorRect
var _mg_label: Label
const MG_BAR_W := 180.0
const MG_BAR_H := 12.0

func _ready() -> void:
	if player_path != NodePath():
		_player = get_node(player_path)
	if weapon_path != NodePath():
		_weapon = get_node(weapon_path)
	_build_rpm_gauge()
	_build_minigun_gauge()

func _build_rpm_gauge() -> void:
	# Sits under the FPS/Speed label in the top-left. Hidden by default; shown
	# only while driving.
	_rpm_bg = ColorRect.new()
	_rpm_bg.color = Color(0, 0, 0, 0.55)
	_rpm_bg.position = Vector2(12, 76)
	_rpm_bg.size = Vector2(RPM_BAR_W, RPM_BAR_H)
	_rpm_bg.visible = false
	_rpm_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rpm_bg)
	_rpm_fill = ColorRect.new()
	_rpm_fill.color = Color(0.2, 0.85, 0.25, 1.0)
	_rpm_fill.position = Vector2(0, 0)
	_rpm_fill.size = Vector2(0, RPM_BAR_H)
	_rpm_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rpm_bg.add_child(_rpm_fill)
	# Redline tick — placed once we know the redline ratio per vehicle.
	_rpm_redline_tick = ColorRect.new()
	_rpm_redline_tick.color = Color(1, 0.2, 0.2, 0.9)
	_rpm_redline_tick.size = Vector2(2, RPM_BAR_H)
	_rpm_redline_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rpm_bg.add_child(_rpm_redline_tick)

func _build_minigun_gauge() -> void:
	# Anchored bottom-center above the ammo readout. Hidden unless the
	# minigun is equipped.
	_mg_bg = ColorRect.new()
	_mg_bg.color = Color(0, 0, 0, 0.6)
	_mg_bg.size = Vector2(MG_BAR_W, MG_BAR_H)
	_mg_bg.anchor_left = 0.5
	_mg_bg.anchor_right = 0.5
	_mg_bg.anchor_top = 1.0
	_mg_bg.anchor_bottom = 1.0
	_mg_bg.offset_left = -MG_BAR_W * 0.5
	_mg_bg.offset_right = MG_BAR_W * 0.5
	_mg_bg.offset_top = -110.0
	_mg_bg.offset_bottom = -110.0 + MG_BAR_H
	_mg_bg.visible = false
	_mg_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mg_bg)
	_mg_fill = ColorRect.new()
	_mg_fill.color = Color(1.0, 0.45, 0.1, 1.0)
	_mg_fill.position = Vector2(0, 0)
	_mg_fill.size = Vector2(0, MG_BAR_H)
	_mg_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mg_bg.add_child(_mg_fill)
	_mg_label = Label.new()
	_mg_label.text = "SPIN"
	_mg_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_mg_label.add_theme_font_size_override("font_size", 10)
	_mg_label.position = Vector2(4, -2)
	_mg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mg_bg.add_child(_mg_label)

func _process(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var speed := 0.0
	var driving := false
	var rpm := 0.0
	var redline := 1.0
	var gear_label := "N"
	var rev_limited := false
	var engine_on := true
	var start_progress := -1.0
	if _player:
		# When seated as driver the player's own velocity is forced to zero, so
		# fall through to the vehicle's linear_velocity for the readout.
		if _player.has_method("is_in_vehicle") and _player.is_in_vehicle():
			var veh: Node = _player.get_vehicle()
			if veh is RigidBody3D:
				driving = true
				var vv: Vector3 = (veh as RigidBody3D).linear_velocity
				speed = Vector2(vv.x, vv.z).length()
				if veh.has_method("get_rpm"):
					rpm = veh.get_rpm()
				if veh.has_method("get_redline"):
					redline = veh.get_redline()
				if veh.has_method("get_gear_label"):
					gear_label = veh.get_gear_label()
				if veh.has_method("is_rev_limited"):
					rev_limited = veh.is_rev_limited()
				if veh.has_method("is_engine_on"):
					engine_on = veh.is_engine_on()
				if veh.has_method("get_start_progress"):
					start_progress = veh.get_start_progress()
		else:
			var v := _player.velocity
			speed = Vector2(v.x, v.z).length()
	if driving:
		var status: String = ""
		if not engine_on:
			if start_progress >= 0.0:
				status = "  CRANKING %d%%" % int(round(start_progress * 100.0))
			else:
				status = "  ENGINE OFF (hold N to start)"
		elif rev_limited:
			status = "  REV LIMIT"
		_label.text = "FPS: %d\nSpeed: %.2f m/s  (driving)\nRPM: %d / %d   Gear: %s%s" % [
			fps, speed, int(round(rpm)), int(round(redline)), gear_label, status
		]
		_update_rpm_gauge(rpm, redline, rev_limited)
	else:
		_label.text = "FPS: %d\nSpeed: %.2f m/s" % [fps, speed]
		if _rpm_bg != null:
			_rpm_bg.visible = false

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
		# Show the ammo-type line only on weapons that can chamber more than one
		# cartridge — prevents clutter on single-ammo guns and keeps the label
		# inside its anchor box.
		var compat: Array = _weapon.get_compatible_ammo_ids() if _weapon.has_method("get_compatible_ammo_ids") else []
		var ammo_id: String = _weapon.get_selected_ammo() if _weapon.has_method("get_selected_ammo") else ""
		var ammo_line: String = ""
		if compat.size() > 1 and ammo_id != "":
			ammo_line = "\n%s" % Items.item_name(ammo_id)
		if reloading:
			var bar_len := 10
			var filled := int(round(prog * bar_len))
			var bar := "[" + "=".repeat(filled) + " ".repeat(bar_len - filled) + "]"
			_ammo_label.text = "%s  [%s]\n%d / %d   (%d)  %s%s" % [name, mode, ammo, mag, reserve, bar, ammo_line]
		else:
			_ammo_label.text = "%s  [%s]\n%d / %d   (%d)%s" % [name, mode, ammo, mag, reserve, ammo_line]
		_update_low_ammo_flash(delta, ammo, mag, reloading)
	_update_minigun_gauge()

func _update_minigun_gauge() -> void:
	if _mg_bg == null:
		return
	var show: bool = _weapon != null and _weapon.has_method("is_minigun_equipped") and _weapon.is_minigun_equipped()
	_mg_bg.visible = show
	if not show:
		return
	var spin: float = _weapon.get_minigun_spin() if _weapon.has_method("get_minigun_spin") else 0.0
	spin = clampf(spin, 0.0, 1.0)
	_mg_fill.size.x = MG_BAR_W * spin
	# Orange while spinning, flips green at full spin (ready to fire).
	if spin >= 1.0:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0)
		_mg_fill.color = Color(0.2, 0.9, 0.3).lerp(Color(0.6, 1.0, 0.6), pulse * 0.4)
		_mg_label.text = "READY"
	else:
		_mg_fill.color = Color(1.0, 0.45, 0.1).lerp(Color(1.0, 0.85, 0.2), spin)
		_mg_label.text = "SPIN %d%%" % int(round(spin * 100.0))

func _update_rpm_gauge(rpm: float, redline: float, rev_limited: bool) -> void:
	if _rpm_bg == null:
		return
	_rpm_bg.visible = true
	# Gauge fills 0..(redline * 1.05) so the redline tick sits at ~95% of the bar.
	var max_rpm: float = redline * 1.05
	var ratio: float = clampf(rpm / max_rpm, 0.0, 1.0)
	_rpm_fill.size.x = RPM_BAR_W * ratio
	# Color fade green→yellow→red as RPM approaches redline.
	var t: float = clampf(rpm / redline, 0.0, 1.2)
	var col: Color
	if t < 0.7:
		col = Color(0.2, 0.85, 0.25)
	elif t < 0.95:
		var k: float = (t - 0.7) / 0.25
		col = Color(0.2 + 0.7 * k, 0.85 - 0.15 * k, 0.25 - 0.20 * k)
	else:
		col = Color(0.95, 0.2, 0.15)
	if rev_limited:
		# Pulse the bar so the limiter is unmissable.
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 50.0)
		col = col.lerp(Color(1, 1, 0.3), pulse * 0.6)
	_rpm_fill.color = col
	_rpm_redline_tick.position.x = RPM_BAR_W * (redline / max_rpm)

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
