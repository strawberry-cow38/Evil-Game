extends Node3D

# Destructible glass sheet. Bullet hits route through take_damage(int); when
# HP hits zero (or a sprinting player slams into us) we hide the pane and
# spawn a kinematic shard burst that arcs to the floor under gravity.
#
# Two shader variants:
#   - "fancy": refractive Standard PBR + clearcoat + low alpha. Looks great,
#     costs a screen-space refraction sample per pixel.
#   - "cheap": alpha-blended Standard PBR, no refraction, no clearcoat.
#
# Per-instance state (variant, tint, frosted) flows in via apply_state().
# Destructible toggle lives on the editor-side per-box flag and reaches us
# via the parent's "destructible" meta stamped by main_bootstrap.

const DEFAULTS: Dictionary = {
	"variant": "fancy",
	"tint": Color(0.75, 0.88, 0.95, 0.35),
	"frosted": false,
}

const SHARD_COUNT := 32
const SHARD_LIFETIME := 1.6
const SHARD_SIZE_MIN := 0.04
const SHARD_SIZE_MAX := 0.14
const SHARD_GRAVITY := 9.8
const SHARD_OUT_SPEED_MIN := 1.2
const SHARD_OUT_SPEED_MAX := 3.4
const SHARD_LATERAL := 1.4
const SHARD_UP_BIAS := 0.6      # max initial upward kick (still beaten by gravity)
const SHATTER_SPRINT_SPEED := 8.0

var _state: Dictionary = DEFAULTS.duplicate(true)
var _mi: MeshInstance3D = null
var _body: StaticBody3D = null
var _shape: CollisionShape3D = null
var _hp: int = 0
var _shattered: bool = false
# Active shard sim state. Each entry: {mi, mat, vel, rot_vel, age}.
var _shards: Array = []

func _ready() -> void:
	_rebuild()
	# Tag the holder so bullet-impact classifier doesn't read us as flesh
	# just because we expose take_damage. Stays in sync if apply_state runs
	# a rebuild later.
	set_meta("impact_material", "glass")

func apply_state(state: Dictionary) -> void:
	for k in DEFAULTS.keys():
		if state.has(k):
			_state[k] = state[k]
	_rebuild()

func get_state() -> Dictionary:
	return _state.duplicate(true)

func _rebuild() -> void:
	_shards.clear()
	_shattered = false
	for c in get_children():
		c.queue_free()
	_mi = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 2.0, 0.04)
	_mi.mesh = bm
	_mi.material_override = _build_material()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_body = StaticBody3D.new()
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 2.0, 0.04)
	_shape.shape = bs
	_body.add_child(_shape)
	add_child(_body)
	_hp = int(get_meta("hp_max", 60)) if has_meta("hp_max") else 60
	set_process(false)

func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tint: Color = _state.get("tint", DEFAULTS["tint"])
	var frosted: bool = bool(_state.get("frosted", false))
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.0
	mat.roughness = 0.05 if not frosted else 0.55
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if String(_state.get("variant", "fancy")) == "fancy":
		mat.refraction_enabled = true
		mat.refraction_scale = 0.04 if not frosted else 0.10
		mat.clearcoat_enabled = true
		mat.clearcoat = 1.0
		mat.clearcoat_roughness = 0.05
		mat.rim_enabled = true
		mat.rim = 0.5
	return mat

func _is_destructible() -> bool:
	# Stamped by main_bootstrap from the editor box's flag. Default true if
	# missing so legacy maps still let glass shatter (destructible-by-default).
	if has_meta("destructible"):
		return bool(get_meta("destructible"))
	return true

func take_damage(amount: int, _headshot: bool = false) -> void:
	if _shattered or amount <= 0 or not _is_destructible():
		return
	_hp = max(_hp - amount, 0)
	if _hp <= 0:
		_shatter(global_position, -global_transform.basis.z)

func _physics_process(_delta: float) -> void:
	if _shattered or not _is_destructible():
		return
	# Cheap broadphase: only check sprinting players nearby. CharacterBody3D
	# doesn't fire a contact signal by itself, so we sweep the group each tick.
	var tree := get_tree()
	if tree == null:
		return
	for p in tree.get_nodes_in_group("player"):
		if not (p is CharacterBody3D) or not is_instance_valid(p):
			continue
		var cb: CharacterBody3D = p
		var hsp: float = Vector2(cb.velocity.x, cb.velocity.z).length()
		if hsp < SHATTER_SPRINT_SPEED:
			continue
		var to_player: Vector3 = cb.global_position - global_position
		if to_player.length() > 1.8:
			continue
		var local: Vector3 = global_transform.affine_inverse() * cb.global_position
		if absf(local.z) > 0.6 or absf(local.x) > 1.4 or local.y < -1.4 or local.y > 1.4:
			continue
		_shatter(cb.global_position, -global_transform.basis.z)
		return

func _shatter(_world_pos: Vector3, normal: Vector3) -> void:
	if _shattered:
		return
	_shattered = true
	# Hide the intact pane + disable its collider; keep the node alive so we
	# can drive the shard sim from _process. queue_free runs after shards die.
	if _mi != null:
		_mi.visible = false
	if _shape != null:
		_shape.disabled = true
	set_physics_process(false)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tint: Color = _state.get("tint", DEFAULTS["tint"])
	# Shard colour: mostly white-blue with a hint of tint. Pure tint reads as
	# coloured plastic; muting it sells the broken-glass look.
	var base_rgb := Color(0.88, 0.94, 1.0).lerp(Color(tint.r, tint.g, tint.b), 0.35)
	var base_a: float = clamp(tint.a + 0.4, 0.6, 0.95)
	# Sample pane normal vector; flatten to horizontal so shards don't all
	# rocket skyward when the pane stands upright with normal pointing up.
	var n: Vector3 = normal
	if n.length_squared() < 0.001:
		n = -global_transform.basis.z
	n = n.normalized()
	for i in range(SHARD_COUNT):
		var shard := MeshInstance3D.new()
		var sx: float = rng.randf_range(SHARD_SIZE_MIN, SHARD_SIZE_MAX)
		var sy: float = sx * rng.randf_range(0.5, 1.7)
		var sm := BoxMesh.new()
		sm.size = Vector3(sx, sy, 0.006)
		shard.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(base_rgb.r, base_rgb.g, base_rgb.b, base_a)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.metallic = 0.1
		smat.roughness = 0.15
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		smat.rim_enabled = true
		smat.rim = 0.6
		shard.material_override = smat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shard)
		# Spawn slightly off the pane face on the side facing the impact.
		var local_off := Vector3(
			rng.randf_range(-0.95, 0.95),
			rng.randf_range(-0.95, 0.95),
			rng.randf_range(0.0, 0.04)
		)
		shard.global_position = global_position + global_transform.basis.x * local_off.x \
			+ global_transform.basis.y * local_off.y \
			+ n * local_off.z
		shard.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		# Initial velocity: forward along impact normal + lateral jitter + small upward kick.
		# Upward kick is capped so gravity dominates within ~0.2s.
		var out_speed: float = rng.randf_range(SHARD_OUT_SPEED_MIN, SHARD_OUT_SPEED_MAX)
		var vel: Vector3 = n * out_speed
		vel += global_transform.basis.x * rng.randf_range(-SHARD_LATERAL, SHARD_LATERAL)
		vel += global_transform.basis.y * rng.randf_range(-SHARD_LATERAL * 0.7, SHARD_LATERAL * 0.7)
		vel.y += rng.randf_range(0.0, SHARD_UP_BIAS)
		var rot_vel := Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
		_shards.append({"mi": shard, "mat": smat, "vel": vel, "rot_vel": rot_vel, "age": 0.0, "base_a": base_a})
	set_process(true)

func _process(delta: float) -> void:
	if not _shattered:
		return
	var any_alive: bool = false
	for s in _shards:
		var mi: MeshInstance3D = s.get("mi")
		if mi == null or not is_instance_valid(mi):
			continue
		s.age += delta
		if s.age >= SHARD_LIFETIME:
			mi.queue_free()
			s.mi = null
			continue
		any_alive = true
		s.vel.y -= SHARD_GRAVITY * delta
		mi.global_position += s.vel * delta
		mi.rotation += s.rot_vel * delta
		var t: float = s.age / SHARD_LIFETIME
		# Hold full alpha most of the lifetime, fade the last 40%.
		var fade_start := 0.6
		var a_mul: float = 1.0 if t < fade_start else (1.0 - (t - fade_start) / (1.0 - fade_start))
		var mat: StandardMaterial3D = s.get("mat")
		if mat != null:
			var c: Color = mat.albedo_color
			c.a = s.base_a * a_mul
			mat.albedo_color = c
	if not any_alive:
		queue_free()
