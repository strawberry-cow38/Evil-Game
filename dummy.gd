extends StaticBody3D

# Training dummy. Soaks bullets, spits floating damage numbers.
# Auto-respawns HP after a few seconds with no hits so you can keep shooting.

const MAX_HP := 500
const REGEN_DELAY := 3.0
const REGEN_RATE := 250.0       # hp/sec once regen starts
const POPUP_LIFETIME := 1.0
const POPUP_RISE := 1.4         # m it floats up over its lifetime
const POPUP_DRIFT := 0.6        # m random horiz drift

var _hp: int = MAX_HP
var _last_hit_time: float = -1000.0
var _rng := RandomNumberGenerator.new()
var _hp_label: Label3D

func _ready() -> void:
	_rng.randomize()
	_hp_label = Label3D.new()
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.fixed_size = false
	_hp_label.font_size = 96
	_hp_label.outline_size = 12
	_hp_label.modulate = Color(1, 1, 1)
	_hp_label.outline_modulate = Color(0, 0, 0)
	_hp_label.position = Vector3(0, 2.2, 0)
	add_child(_hp_label)
	_refresh_hp_label()

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _hp < MAX_HP and now - _last_hit_time >= REGEN_DELAY:
		var regenned: float = float(_hp) + REGEN_RATE * delta
		_hp = min(int(regenned), MAX_HP)
		_refresh_hp_label()

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	_hp = max(_hp - amount, 0)
	_last_hit_time = Time.get_ticks_msec() / 1000.0
	_refresh_hp_label()
	_spawn_popup(amount)

func _refresh_hp_label() -> void:
	if _hp_label == null:
		return
	_hp_label.text = "%d / %d" % [_hp, MAX_HP]
	var ratio: float = float(_hp) / float(MAX_HP)
	_hp_label.modulate = Color(1.0, 0.4 + 0.6 * ratio, 0.4 + 0.6 * ratio)

func _spawn_popup(amount: int) -> void:
	var lbl := Label3D.new()
	lbl.text = str(amount)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = false
	lbl.font_size = 72
	lbl.outline_size = 10
	lbl.modulate = _damage_color(amount)
	lbl.outline_modulate = Color(0, 0, 0)
	# Spawn near hit zone with a little jitter so multi-shot pops don't overlap.
	var jx: float = _rng.randf_range(-0.35, 0.35)
	var jy: float = _rng.randf_range(0.6, 1.6)
	var jz: float = _rng.randf_range(-0.35, 0.35)
	lbl.position = Vector3(jx, jy, jz)
	add_child(lbl)
	var dx: float = _rng.randf_range(-POPUP_DRIFT, POPUP_DRIFT)
	var dz: float = _rng.randf_range(-POPUP_DRIFT, POPUP_DRIFT)
	var end_pos: Vector3 = lbl.position + Vector3(dx, POPUP_RISE, dz)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position", end_pos, POPUP_LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, POPUP_LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

func _damage_color(amount: int) -> Color:
	# Yellow → orange → red as damage gets juicier.
	if amount >= 50:
		return Color(1.0, 0.35, 0.25)
	if amount >= 35:
		return Color(1.0, 0.65, 0.20)
	return Color(1.0, 0.95, 0.40)
