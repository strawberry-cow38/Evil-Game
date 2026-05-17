extends Node3D

# Destructible glass sheet. Bullet hits route through take_damage(int); when
# HP hits zero (or the player slams into us at sprint speed) we spawn a
# brief shard burst and free ourselves. Two shader variants:
#   - "fancy": refractive Standard PBR + clearcoat + low alpha. Looks great,
#     costs a screen-space refraction sample per pixel.
#   - "cheap": alpha-blended Standard PBR, no refraction, no clearcoat.
# Per-instance tweaks (variant, tint, frosted) flow in via apply_state(),
# matching how the computer station + cctv camera carry per-placement state.

const DEFAULTS: Dictionary = {
	"variant": "fancy",   # "fancy" or "cheap"
	"tint": Color(0.75, 0.88, 0.95, 0.35),
	"frosted": false,
	"hp_max": 60,
}

const SHARD_COUNT := 28
const SHARD_LIFETIME := 1.3
const SHARD_SPEED_MIN := 2.5
const SHARD_SPEED_MAX := 6.5
const SHARD_SIZE_MIN := 0.04
const SHARD_SIZE_MAX := 0.12
const SHATTER_SPRINT_SPEED := 8.0   # CharacterBody3D speed above which a player walking into us breaks the pane

var _state: Dictionary = DEFAULTS.duplicate(true)
var _mi: MeshInstance3D = null
var _body: StaticBody3D = null
var _hp: int = 0
var _shattered: bool = false

func _ready() -> void:
	_rebuild()

func apply_state(state: Dictionary) -> void:
	for k in DEFAULTS.keys():
		if state.has(k):
			_state[k] = state[k]
	_rebuild()

func get_state() -> Dictionary:
	return _state.duplicate(true)

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_mi = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 2.0, 0.04)
	_mi.mesh = bm
	_mi.material_override = _build_material()
	# Glass barely casts shadows in real life — cheaper + better-looking with
	# casting off. Receive is fine.
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 2.0, 0.04)
	cs.shape = bs
	_body.add_child(cs)
	add_child(_body)
	_hp = int(_state.get("hp_max", DEFAULTS["hp_max"]))

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
		# Refraction + clearcoat sells the depth. Refraction needs SCREEN_SPACE
		# textures from the back buffer; cheap variant skips this.
		mat.refraction_enabled = true
		mat.refraction_scale = 0.04 if not frosted else 0.10
		mat.clearcoat_enabled = true
		mat.clearcoat = 1.0
		mat.clearcoat_roughness = 0.05
		mat.rim_enabled = true
		mat.rim = 0.5
	return mat

func take_damage(amount: int, _headshot: bool = false) -> void:
	if _shattered or amount <= 0:
		return
	_hp = max(_hp - amount, 0)
	if _hp <= 0:
		_shatter(global_position, Vector3.UP)

func _physics_process(_delta: float) -> void:
	if _shattered:
		return
	# Cheap broadphase: only check sprinting players nearby. CharacterBody3D
	# doesn't fire a contact signal by itself, so we sweep the body group
	# each tick. With one local player + a handful of glass sheets this is
	# cheaper than wiring an Area3D per pane.
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
		# Reject if player is far or on the wrong side of the pane normal.
		var to_player: Vector3 = cb.global_position - global_position
		if to_player.length() > 1.8:
			continue
		# Local-space check: pane lies in XY, depth on Z. Cull lateral misses.
		var local: Vector3 = global_transform.affine_inverse() * cb.global_position
		if absf(local.z) > 0.6 or absf(local.x) > 1.4 or local.y < -1.4 or local.y > 1.4:
			continue
		_shatter(cb.global_position, -global_transform.basis.z)
		return

func _shatter(world_pos: Vector3, normal: Vector3) -> void:
	if _shattered:
		return
	_shattered = true
	var scene := get_tree().current_scene
	if scene == null:
		queue_free()
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tint: Color = _state.get("tint", DEFAULTS["tint"])
	# Use the glass's tint for the shards but punch alpha so they read.
	var shard_color := Color(tint.r, tint.g, tint.b, 0.85)
	for i in range(SHARD_COUNT):
		var shard := MeshInstance3D.new()
		var sm := BoxMesh.new()
		var s: float = rng.randf_range(SHARD_SIZE_MIN, SHARD_SIZE_MAX)
		sm.size = Vector3(s, s * rng.randf_range(0.6, 1.4), 0.01)
		shard.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = shard_color
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.metallic = 0.0
		smat.roughness = 0.1
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		shard.material_override = smat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(shard)
		var jitter: Vector3 = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.2, 0.2))
		shard.global_position = global_position + jitter
		shard.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var spd: float = rng.randf_range(SHARD_SPEED_MIN, SHARD_SPEED_MAX)
		var dir: Vector3 = (normal + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 0.8), rng.randf_range(-0.6, 0.6))).normalized()
		var end_pos: Vector3 = shard.global_position + dir * spd * SHARD_LIFETIME + Vector3(0, -2.0 * SHARD_LIFETIME * SHARD_LIFETIME, 0)
		var t := shard.create_tween()
		t.set_parallel(true)
		t.tween_property(shard, "global_position", end_pos, SHARD_LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(smat, "albedo_color:a", 0.0, SHARD_LIFETIME).set_trans(Tween.TRANS_LINEAR)
		var rspd: Vector3 = Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		t.tween_property(shard, "rotation", shard.rotation + rspd, SHARD_LIFETIME)
		var shard_ref: WeakRef = weakref(shard)
		t.chain().tween_callback(func():
			var sh: Node = shard_ref.get_ref() as Node
			if sh != null:
				sh.queue_free()
		)
	queue_free()
