extends StaticBody3D

# Training dummy. Soaks bullets, spits floating damage numbers.
# Auto-respawns HP after a few seconds with no hits so you can keep shooting.
# Tunables (hp_max, regen_*, enemy, xp_reward, drop_table_id) are vars so
# editor-spawned actors can override them per spawn before _ready().

signal died(drop_table_id: String, xp_reward: int)

const HEADSHOT_MULT := 1.5
const POPUP_LIFETIME := 1.0
const POPUP_RISE := 1.4
const POPUP_DRIFT := 0.6

var hp_max: int = 500
var regen_delay: float = 3.0
var regen_rate: float = 250.0
var enemy: bool = false
var xp_reward: int = 0
var drop_table_id: String = ""

var _hp: int = 0
var _last_hit_time: float = -1000.0
var _dead: bool = false
var _rng := RandomNumberGenerator.new()
var _hp_label: Label3D

func _ready() -> void:
	_rng.randomize()
	_hp = hp_max
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
	if _dead:
		return
	if regen_rate <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _hp < hp_max and now - _last_hit_time >= regen_delay:
		var regenned: float = float(_hp) + regen_rate * delta
		_hp = min(int(regenned), hp_max)
		_refresh_hp_label()

func take_damage(amount: int, headshot: bool = false) -> void:
	if amount <= 0 or _dead:
		return
	var dealt: int = amount
	if headshot:
		dealt = int(round(float(amount) * HEADSHOT_MULT))
	_hp = max(_hp - dealt, 0)
	_last_hit_time = Time.get_ticks_msec() / 1000.0
	_refresh_hp_label()
	_spawn_popup(dealt, headshot)
	if _hp <= 0:
		_die()

func _die() -> void:
	_dead = true
	emit_signal("died", drop_table_id, xp_reward)
	queue_free()

func _refresh_hp_label() -> void:
	if _hp_label == null:
		return
	_hp_label.text = "%d / %d" % [_hp, hp_max]
	var ratio: float = float(_hp) / float(hp_max)
	_hp_label.modulate = Color(1.0, 0.4 + 0.6 * ratio, 0.4 + 0.6 * ratio)

func _spawn_popup(amount: int, headshot: bool = false) -> void:
	var lbl := Label3D.new()
	lbl.text = str(amount)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = false
	lbl.font_size = 96 if headshot else 72
	lbl.outline_size = 12 if headshot else 10
	lbl.modulate = Color(1.0, 0.95, 0.20) if headshot else _damage_color(amount)
	lbl.outline_modulate = Color(0, 0, 0)
	var jx: float = _rng.randf_range(-0.35, 0.35)
	var jy: float = _rng.randf_range(1.4, 1.9) if headshot else _rng.randf_range(0.6, 1.6)
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
	if amount >= 50:
		return Color(1.0, 0.35, 0.25)
	if amount >= 35:
		return Color(1.0, 0.65, 0.20)
	return Color(1.0, 0.95, 0.40)
