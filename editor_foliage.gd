extends Node3D

# Foliage authoring + runtime. Owns a single MultiMeshInstance3D that
# holds every placed grass billboard. Each instance is a Y-billboarded
# quad with a procedural alpha-blade texture, so density is cheap (one
# draw call regardless of count). Backing data is a plain Array of dicts
# so it round-trips through MapState as JSON without extra glue. Used by
# both the editor (live edit) and main_bootstrap (play scene rebuild).

const BLADE_W: float = 0.6   # billboard quad width (metres)
const BLADE_H: float = 0.7   # billboard quad height
const TEX_SIZE: int = 32     # procedural texture resolution

# Per-instance authored state.
#   { pos: Vector3, scale: float, rot_y: float }
# scale = uniform multiplier on the base quad; rot_y is mostly cosmetic
# (Y-billboards auto-face the camera) but lets us jitter blade-look.
var _instances: Array = []

var _mmi: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null
var _dirty: bool = false

func _ready() -> void:
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = false
	_multimesh.use_custom_data = false
	_multimesh.mesh = _build_blade_mesh()
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _multimesh
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_rebuild_multimesh()

func _process(_delta: float) -> void:
	if _dirty:
		_rebuild_multimesh()
		_dirty = false

func _build_blade_mesh() -> Mesh:
	# Y-billboarded quad shared by every blade. The material's billboard
	# mode handles the camera-facing rotation per frame, so the mesh
	# itself is just a centred upright quad.
	var qm := QuadMesh.new()
	qm.size = Vector2(BLADE_W, BLADE_H)
	# Centre vertically at the half-height so the blade sits ON the
	# terrain hit point with its root at ground level.
	qm.center_offset = Vector3(0, BLADE_H * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _build_blade_texture()
	mat.albedo_color = Color(0.7, 1.0, 0.7, 1.0)  # tint the green texture lighter
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# Make grass slightly emissive so dim lighting doesn't kill the whole
	# carpet visually — bias toward green so it stays grass-coloured.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	qm.material = mat
	return qm

func _build_blade_texture() -> ImageTexture:
	# Three vertical blade silhouettes side-by-side on a 32x32 canvas.
	# Alpha-scissored so the silhouette stays crisp under any rotation.
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(TEX_SIZE):
		for y in range(TEX_SIZE):
			var u: float = float(x) / float(TEX_SIZE - 1)
			var v: float = float(y) / float(TEX_SIZE - 1)
			# Three blade columns with slight curvature; widest at the base.
			# QuadMesh UV has V=0 at the top edge of the quad (tip, away
			# from terrain), V=1 at the bottom (root, on ground), so the
			# thickness/shade gradients are anchored to V=1 = root.
			var blade_centre_a: float = 0.18 + 0.03 * sin(v * PI)
			var blade_centre_b: float = 0.5  + 0.05 * cos(v * PI * 0.8)
			var blade_centre_c: float = 0.82 - 0.03 * sin(v * PI)
			var thickness: float = lerp(0.02, 0.10, v)
			var d_a: float = absf(u - blade_centre_a)
			var d_b: float = absf(u - blade_centre_b)
			var d_c: float = absf(u - blade_centre_c)
			var on: bool = d_a < thickness or d_b < thickness or d_c < thickness
			if on:
				# Darker green at the base, brighter tip — sells depth on
				# packed billboards.
				var shade: float = lerp(0.55, 0.95, 1.0 - v)
				img.set_pixel(x, y, Color(0.25 * shade, 0.65 * shade, 0.20 * shade, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _rebuild_multimesh() -> void:
	_multimesh.instance_count = _instances.size()
	for i in range(_instances.size()):
		var inst: Dictionary = _instances[i]
		var pos: Vector3 = inst.get("pos", Vector3.ZERO)
		var s: float = float(inst.get("scale", 1.0))
		var ry: float = float(inst.get("rot_y", 0.0))
		var t: Transform3D = Transform3D(Basis(Vector3.UP, ry).scaled(Vector3.ONE * s), pos)
		_multimesh.set_instance_transform(i, t)

func add_instance(world_pos: Vector3, scale: float, rot_y: float) -> void:
	_instances.append({"pos": world_pos, "scale": scale, "rot_y": rot_y})
	_dirty = true

func remove_in_radius(world_pos: Vector3, radius: float, shape: String) -> int:
	# Returns number removed. Square uses an L∞ ball; circle uses L2 on
	# the xz plane so vertical foliage on cliffs still drops cleanly.
	var keep: Array = []
	var dropped: int = 0
	var r2: float = radius * radius
	for inst in _instances:
		var p: Vector3 = inst.get("pos", Vector3.ZERO)
		var dx: float = p.x - world_pos.x
		var dz: float = p.z - world_pos.z
		var inside: bool = false
		if shape == "square":
			inside = absf(dx) <= radius and absf(dz) <= radius
		else:
			inside = dx * dx + dz * dz <= r2
		if inside:
			dropped += 1
		else:
			keep.append(inst)
	if dropped > 0:
		_instances = keep
		_dirty = true
	return dropped

func count_in_radius(world_pos: Vector3, radius: float, shape: String) -> int:
	# Used by the spray brush to throttle density without re-scanning the
	# whole list on every tick.
	var hits: int = 0
	var r2: float = radius * radius
	for inst in _instances:
		var p: Vector3 = inst.get("pos", Vector3.ZERO)
		var dx: float = p.x - world_pos.x
		var dz: float = p.z - world_pos.z
		var inside: bool = false
		if shape == "square":
			inside = absf(dx) <= radius and absf(dz) <= radius
		else:
			inside = dx * dx + dz * dz <= r2
		if inside:
			hits += 1
	return hits

func instance_count() -> int:
	return _instances.size()

func clear_all() -> void:
	_instances.clear()
	_dirty = true

func get_state() -> Array:
	# Returns a deep copy so callers can't mutate the live list.
	var out: Array = []
	for inst in _instances:
		out.append({
			"pos":   inst.get("pos", Vector3.ZERO),
			"scale": float(inst.get("scale", 1.0)),
			"rot_y": float(inst.get("rot_y", 0.0)),
		})
	return out

func set_state(state: Array) -> void:
	_instances.clear()
	for inst in state:
		if not inst is Dictionary:
			continue
		_instances.append({
			"pos":   inst.get("pos", Vector3.ZERO),
			"scale": float(inst.get("scale", 1.0)),
			"rot_y": float(inst.get("rot_y", 0.0)),
		})
	_dirty = true
