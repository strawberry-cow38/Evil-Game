extends Node3D

# Foliage authoring + runtime. Owns one MultiMeshInstance3D per preset so
# each variant (different blade height + tint) keeps its own batched draw
# call. Per-instance state is { preset, pos, scale, rot_y } and round-trips
# through MapState as plain JSON. Used by both the editor and
# main_bootstrap.

const TEX_SIZE: int = 32
const GRASS_SHADER := preload("res://grass.gdshader")
const DEFAULT_PRESET: String = "short_green"

# Preset table. Each preset is one MultiMesh bucket — same shader/texture
# but its own quad height + tint uniform. Tints picked to read against the
# terrain paint colours (grass = green, dirt = dry/brown, sand = pale).
const PRESETS: Array = [
	{"id": "short_green", "label": "Short Green", "height": 0.4, "width": 0.6, "tint": Color(0.26, 0.68, 0.21, 1.0)},
	{"id": "long_green",  "label": "Long Green",  "height": 0.7, "width": 0.6, "tint": Color(0.26, 0.68, 0.21, 1.0)},
	{"id": "short_brown", "label": "Short Brown", "height": 0.4, "width": 0.6, "tint": Color(0.55, 0.40, 0.18, 1.0)},
	{"id": "long_brown",  "label": "Long Brown",  "height": 0.7, "width": 0.6, "tint": Color(0.55, 0.40, 0.18, 1.0)},
	{"id": "short_sand",  "label": "Short Sand",  "height": 0.4, "width": 0.6, "tint": Color(0.80, 0.72, 0.45, 1.0)},
	{"id": "long_sand",   "label": "Long Sand",   "height": 0.7, "width": 0.6, "tint": Color(0.80, 0.72, 0.45, 1.0)},
]

# Per-instance state keyed by preset id:
#   _instances[preset_id] = [ { pos: Vector3, scale: float, rot_y: float }, ... ]
var _instances: Dictionary = {}
var _mmis: Dictionary = {}
var _multimeshes: Dictionary = {}
var _materials: Dictionary = {}
var _dirty: bool = false

# Shared procedural blade texture (height comes from the mesh, not the
# texture, so one bitmap fits every preset).
var _shared_blade_tex: ImageTexture = null

var _wind_dir: Vector2 = Vector2(1.0, 0.0)
var _wind_min: float = 0.04
var _wind_max: float = 0.18
var _wind_speed: float = 1.8

func _ready() -> void:
	_shared_blade_tex = _build_blade_texture()
	for p in PRESETS:
		_init_preset(p)
	_rebuild_all()

func _process(_delta: float) -> void:
	if _dirty:
		_rebuild_all()
		_dirty = false

func _init_preset(p: Dictionary) -> void:
	var pid: String = String(p.id)
	_instances[pid] = []
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	mm.mesh = _build_blade_mesh(p)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_multimeshes[pid] = mm
	_mmis[pid] = mmi

func _build_blade_mesh(p: Dictionary) -> Mesh:
	var w: float = float(p.width)
	var h: float = float(p.height)
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	qm.center_offset = Vector3(0, h * 0.5, 0)
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("albedo_tex", _shared_blade_tex)
	mat.set_shader_parameter("albedo_tint", p.tint)
	mat.set_shader_parameter("alpha_scissor", 0.5)
	_materials[String(p.id)] = mat
	_apply_wind_uniforms_to(mat)
	qm.material = mat
	return qm

func _build_blade_texture() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(TEX_SIZE):
		for y in range(TEX_SIZE):
			var u: float = float(x) / float(TEX_SIZE - 1)
			var v: float = float(y) / float(TEX_SIZE - 1)
			# QuadMesh UV V=0 = top edge (tip), V=1 = bottom (root).
			var blade_centre_a: float = 0.18 + 0.03 * sin(v * PI)
			var blade_centre_b: float = 0.5  + 0.05 * cos(v * PI * 0.8)
			var blade_centre_c: float = 0.82 - 0.03 * sin(v * PI)
			var thickness: float = lerp(0.02, 0.10, v)
			var d_a: float = absf(u - blade_centre_a)
			var d_b: float = absf(u - blade_centre_b)
			var d_c: float = absf(u - blade_centre_c)
			var on: bool = d_a < thickness or d_b < thickness or d_c < thickness
			if on:
				# Grayscale silhouette — the shader multiplies by the preset
				# tint, so baking colour into the bitmap here would lock every
				# preset to green. Shade still rolls darker→tip to sell depth.
				var shade: float = lerp(0.55, 0.95, 1.0 - v)
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _rebuild_all() -> void:
	for pid in _instances.keys():
		var mm: MultiMesh = _multimeshes[pid]
		var list: Array = _instances[pid]
		mm.instance_count = list.size()
		for i in range(list.size()):
			var inst: Dictionary = list[i]
			var pos: Vector3 = inst.get("pos", Vector3.ZERO)
			var s: float = float(inst.get("scale", 1.0))
			var ry: float = float(inst.get("rot_y", 0.0))
			var t: Transform3D = Transform3D(Basis(Vector3.UP, ry).scaled(Vector3.ONE * s), pos)
			mm.set_instance_transform(i, t)

func _resolve_preset(preset_id: String) -> String:
	# Unknown preset ids fall back to the default so a stale save can still
	# load without dropping instances.
	if _instances.has(preset_id):
		return preset_id
	return DEFAULT_PRESET

func get_preset_height(preset_id: String) -> float:
	for p in PRESETS:
		if String(p.id) == preset_id:
			return float(p.height)
	return float(PRESETS[0].height)

func get_preset_tint(preset_id: String) -> Color:
	for p in PRESETS:
		if String(p.id) == preset_id:
			return p.tint
	return Color.WHITE

func add_instance(preset_id: String, world_pos: Vector3, scale: float, rot_y: float) -> void:
	var pid: String = _resolve_preset(preset_id)
	_instances[pid].append({"pos": world_pos, "scale": scale, "rot_y": rot_y})
	_dirty = true

func remove_in_radius(world_pos: Vector3, radius: float, shape: String) -> int:
	# Cross-preset removal: brush erases every variant within the footprint.
	var dropped: int = 0
	var r2: float = radius * radius
	for pid in _instances.keys():
		var keep: Array = []
		for inst in _instances[pid]:
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
		if keep.size() != _instances[pid].size():
			_instances[pid] = keep
			_dirty = true
	return dropped

func count_in_radius(world_pos: Vector3, radius: float, shape: String) -> int:
	var hits: int = 0
	var r2: float = radius * radius
	for pid in _instances.keys():
		for inst in _instances[pid]:
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
	var total: int = 0
	for pid in _instances.keys():
		total += (_instances[pid] as Array).size()
	return total

func clear_all() -> void:
	for pid in _instances.keys():
		_instances[pid] = []
	_dirty = true

func get_state() -> Array:
	# Flattened list — one dict per instance with preset id, so loaders can
	# restore each into the right bucket without knowing about MultiMeshes.
	var out: Array = []
	for pid in _instances.keys():
		for inst in _instances[pid]:
			out.append({
				"preset": pid,
				"pos":   inst.get("pos", Vector3.ZERO),
				"scale": float(inst.get("scale", 1.0)),
				"rot_y": float(inst.get("rot_y", 0.0)),
			})
	return out

func set_state(state: Array) -> void:
	for pid in _instances.keys():
		_instances[pid] = []
	for inst in state:
		if not inst is Dictionary:
			continue
		var pid: String = _resolve_preset(String(inst.get("preset", DEFAULT_PRESET)))
		_instances[pid].append({
			"pos":   inst.get("pos", Vector3.ZERO),
			"scale": float(inst.get("scale", 1.0)),
			"rot_y": float(inst.get("rot_y", 0.0)),
		})
	_dirty = true

func _apply_wind_uniforms_to(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("wind_dir", _wind_dir.normalized() if _wind_dir.length() > 0.0001 else Vector2(1, 0))
	mat.set_shader_parameter("wind_min", _wind_min)
	mat.set_shader_parameter("wind_max", _wind_max)
	mat.set_shader_parameter("wind_speed", _wind_speed)

func _apply_wind_uniforms() -> void:
	for pid in _materials.keys():
		_apply_wind_uniforms_to(_materials[pid])

func set_wind(dir: Vector2, lo: float, hi: float, speed: float) -> void:
	_wind_dir = dir
	_wind_min = max(0.0, lo)
	_wind_max = max(_wind_min, hi)
	_wind_speed = max(0.0, speed)
	_apply_wind_uniforms()

func get_wind() -> Dictionary:
	return {
		"dir_x": _wind_dir.x,
		"dir_y": _wind_dir.y,
		"min": _wind_min,
		"max": _wind_max,
		"speed": _wind_speed,
	}
