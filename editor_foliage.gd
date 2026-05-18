extends Node3D

# Foliage authoring + runtime. Owns one MultiMeshInstance3D per preset so
# each variant (different blade height + tint) keeps its own batched draw
# call. Per-instance state is { preset, pos, scale, rot_y } and round-trips
# through MapState as plain JSON. Used by both the editor and
# main_bootstrap.

const TEX_SIZE: int = 32
const SHRUB_TILE: int = 32
const SHRUB_VARIANTS: int = 3
# How many distinct mesh+UV-offset buckets exist per shrub preset. Each
# placed shrub picks one at random so a cluster of bushes shows real
# silhouette variation instead of one repeated drawing.
const SHRUB_BUCKETS: int = 5
const GRASS_SHADER := preload("res://grass.gdshader")
const DEFAULT_PRESET: String = "short_green"

# Per-cell instance cap so spraying in one spot can't build a million-tri
# super-patch. The grid sums every preset together — "patch density" is
# what we actually care about, not per-variant counts. Spray samples that
# would push a cell past MAX_PER_CELL are silently rejected.
#
# 0.5m cell × 8 instances ≈ 32 plants per m² peak. Sparse enough that
# fragment overdraw stays bounded even on flat lawns; thick fields can
# still be built by painting a wider area instead of stacking. Bump if
# a future tuning pass wants denser carpets.
const DENSITY_CELL_SIZE: float = 0.5
const MAX_PER_CELL: int = 5

# Grass displacement budget. Shader iterates this many slots per vertex,
# so bumping it costs real GPU. Persistent registrants (items) live in
# the low end of the array; transient trail wakes (player/vehicle) fill
# the rest. Newest trail wakes evict oldest when the slice fills.
const MAX_DISPLACERS: int = 24
const DEFAULT_WAKE_LIFETIME: float = 3.0

# Preset table. Each preset is one MultiMesh bucket — same shader/texture
# but its own quad height + tint uniform. Tints picked to read against the
# terrain paint colours (grass = green, dirt = dry/brown, sand = pale).
const PRESETS: Array = [
	{"id": "short_green", "label": "Short Green", "kind": "grass", "height": 0.4, "width": 0.6, "tint": Color(0.26, 0.68, 0.21, 1.0)},
	{"id": "long_green",  "label": "Long Green",  "kind": "grass", "height": 0.875, "width": 0.75, "tint": Color(0.26, 0.68, 0.21, 1.0)},
	{"id": "short_brown", "label": "Short Brown", "kind": "grass", "height": 0.4, "width": 0.6, "tint": Color(0.55, 0.40, 0.18, 1.0)},
	{"id": "long_brown",  "label": "Long Brown",  "kind": "grass", "height": 0.875, "width": 0.75, "tint": Color(0.55, 0.40, 0.18, 1.0)},
	{"id": "short_sand",  "label": "Short Sand",  "kind": "grass", "height": 0.4, "width": 0.6, "tint": Color(0.80, 0.72, 0.45, 1.0)},
	{"id": "long_sand",   "label": "Long Sand",   "kind": "grass", "height": 0.875, "width": 0.75, "tint": Color(0.80, 0.72, 0.45, 1.0)},
	# White tint — shrub textures bake brown branches + green leaves, so the
	# shader multiply must preserve the painted colours instead of
	# recolouring everything green. Each placed shrub_round picks one of
	# SHRUB_BUCKETS internal mesh variants at random so neighbours don't
	# look like carbon copies.
	{"id": "shrub_round", "label": "Round Shrub", "kind": "shrub", "style": "round", "height": 1.8, "width": 1.8, "tint": Color(1, 1, 1, 1)},
	{"id": "clover_patch", "label": "Clover Patch", "kind": "clover", "height": 0.0, "width": 0.45, "tint": Color(0.30, 0.62, 0.20, 1.0)},
	# Daisy keeps a white tint so the texture's baked-in petal/centre/stem
	# colours survive the shader multiply. Other presets use grayscale tex *
	# coloured tint, but a daisy has more than one colour per blade.
	{"id": "daisy", "label": "Daisy", "kind": "daisy", "height": 0.28, "width": 0.20, "tint": Color(1, 1, 1, 1)},
	# Trees come from a baked .glb (assets/models/maple.glb). Multimesh
	# instances of the merged mesh — no per-instance scale variation here
	# beyond the global jitter applied by the spray brush.
	{"id": "tree_maple", "label": "Maple Tree", "kind": "tree", "glb": "res://assets/models/maple.glb", "height": 1.0, "width": 1.0, "tint": Color(1, 1, 1, 1)},
	# Stump preset bundles 3 baked .glb variants — each placement routes
	# to a random variant bucket (mirrors SHRUB_BUCKETS pattern) so a
	# spray of stumps reads as three distinct silhouettes.
	# display_scale: per-instance scale multiplier applied at add_instance.
	# clear_grass_radius: when a stump lands, every grass instance inside
	# this XZ radius is deleted so the stump isn't sitting in a tuft.
	{"id": "tree_stump", "label": "Stump", "kind": "tree", "glb_variants": [
		"res://assets/models/stump_0.glb",
		"res://assets/models/stump_1.glb",
		"res://assets/models/stump_2.glb",
	], "height": 1.0, "width": 1.0, "tint": Color(1, 1, 1, 1),
	 # collision_radius/height match the stump silhouette at display_scale.
	 # Native stump is ~0.6m wide × ~0.5m tall at scale 1.0 — scale 1.4 →
	 # radius ≈ 0.42, height ≈ 0.7. Clear radius tight so we don't carve
	 # a bald ring around each stump.
	 "display_scale": 1.4, "clear_grass_radius": 0.65,
	 "collision_radius": 0.42, "collision_height": 0.7},
	# cow_tree — 3 baked variants of the stylized stub-canopy tree
	# authored in Blender. Spray-time scale jitter goes up to 1.5x for
	# size variation; trunk collision cylinder matches the ~0.30m main
	# shell radius measured in-blend, with ~2.3m vertical extent.
	{"id": "tree_cow", "label": "Cow Tree", "kind": "tree", "glb_variants": [
		"res://assets/models/cow_tree_0.glb",
		"res://assets/models/cow_tree_1.glb",
		"res://assets/models/cow_tree_2.glb",
	], "height": 1.0, "width": 1.0, "tint": Color(1, 1, 1, 1),
	 "display_scale": 1.0, "clear_grass_radius": 0.55,
	 "scale_jitter_min": 1.5, "scale_jitter_max": 2.0,
	 "collision_radius": 0.30, "collision_height": 2.3},
]

# Per-instance state keyed by preset id:
#   _instances[preset_id] = [ { pos: Vector3, scale: float, rot_y: float }, ... ]
var _instances: Dictionary = {}
var _mmis: Dictionary = {}
var _multimeshes: Dictionary = {}
var _materials: Dictionary = {}
var _dirty: bool = false

# Shared procedural textures, one per kind. Height/colour vary per preset
# via the mesh size + the shader's albedo_tint uniform, so a single bitmap
# is enough per kind.
var _shared_blade_tex: ImageTexture = null
# Shrub atlases live per-preset so each style ("round", "tall", "wide",
# "sparse") gets its own painted silhouette. Keyed by preset id.
var _shrub_textures: Dictionary = {}
var _shared_clover_tex: ImageTexture = null
var _shared_daisy_tex: ImageTexture = null
var _shared_shadow_tex: ImageTexture = null
var _shared_shadow_mat: StandardMaterial3D = null

# Spatial counter for the per-cell density cap. Key = Vector2i cell coord
# in DENSITY_CELL_SIZE units; value = current instance count across all
# presets. Kept in sync inside add_instance / remove_in_radius / clear_all
# / set_state so any caller path stays honest.
var _density_grid: Dictionary = {}

# Tree collider parents — one Node3D per tree variant key. Rebuilt
# alongside the MultiMesh during _rebuild_all so collision shapes stay
# in lockstep with the visible instance list. Stumps need real physics
# so the player can't walk through them.
var _tree_collider_holders: Dictionary = {}

# Persistent displacers — Node3Ds that flatten grass around themselves
# until they leave the scene tree. Pickups register here so a dropped
# apple still looks like it's sitting in matted grass minutes later.
var _persistent_displacers: Array = []
# Trail wakes — short-lived flat spots a moving entity drops behind it.
# Each entry: { "pos": Vector3, "born": float, "lifetime": float }.
var _wake_trail: Array = []

var _wind_dir: Vector2 = Vector2(1.0, 0.0)
var _wind_min: float = 0.04
var _wind_max: float = 0.18
var _wind_speed: float = 1.8

func _ready() -> void:
	add_to_group("foliage")
	_shared_blade_tex = _build_blade_texture()
	for p in PRESETS:
		if String(p.get("kind", "grass")) == "shrub":
			_shrub_textures[String(p.id)] = _build_shrub_texture(p)
	_shared_clover_tex = _build_clover_texture()
	_shared_daisy_tex = _build_daisy_texture()
	_shared_shadow_tex = _build_shadow_texture()
	_shared_shadow_mat = _make_shadow_material(_shared_shadow_tex)
	for p in PRESETS:
		_init_preset(p)
	_rebuild_all()

func _process(_delta: float) -> void:
	if _dirty:
		_rebuild_all()
		_dirty = false
	_update_displacer_uniforms()

# Public API — anything that walks/sits on grass calls this. Pickups call
# register_persistent_displacer once on _ready; movers (player, vehicles)
# call push_wake every step distance. Both eventually feed the same vec4
# slot array on the grass shader.
func register_persistent_displacer(node: Node3D) -> void:
	if node == null or _persistent_displacers.has(node):
		return
	_persistent_displacers.append(node)
	# Auto-cleanup so pickups removed via queue_free don't leak slots.
	node.tree_exited.connect(_on_displacer_tree_exited.bind(node))

func _on_displacer_tree_exited(node: Node3D) -> void:
	_persistent_displacers.erase(node)

func unregister_persistent_displacer(node: Node3D) -> void:
	_persistent_displacers.erase(node)

func push_wake(pos: Vector3, lifetime: float = DEFAULT_WAKE_LIFETIME) -> void:
	_wake_trail.append({"pos": pos, "born": Time.get_ticks_msec() / 1000.0, "lifetime": lifetime})

func _update_displacer_uniforms() -> void:
	# Compose persistent + trail into the single uniform array the shader
	# loops over. Persistent first (strength 1.0); trail wakes after, with
	# strength fading linearly over their lifetime. Empty tail slots have
	# w=0 so the shader's `if (d.w <= 0.0) continue` skips them.
	var now: float = Time.get_ticks_msec() / 1000.0
	# Cull dead wakes in-place.
	var kept_trail: Array = []
	for w in _wake_trail:
		var age: float = now - float(w["born"])
		if age < float(w["lifetime"]):
			kept_trail.append(w)
	_wake_trail = kept_trail
	# Drop dead Node3D refs (paranoia — tree_exited should handle this, but
	# scripts can null nodes via free() without firing it in some cases).
	_persistent_displacers = _persistent_displacers.filter(func(n): return is_instance_valid(n) and n.is_inside_tree())
	var slots: PackedVector4Array = PackedVector4Array()
	slots.resize(MAX_DISPLACERS)
	var idx: int = 0
	for n in _persistent_displacers:
		if idx >= MAX_DISPLACERS:
			break
		var p: Vector3 = (n as Node3D).global_position
		slots[idx] = Vector4(p.x, p.y, p.z, 1.0)
		idx += 1
	# Newest wakes first so eviction (truncation past MAX) drops the
	# stalest tail rather than the freshest puff right at the player's
	# feet — that one matters most visually.
	_wake_trail.sort_custom(func(a, b): return float(a["born"]) > float(b["born"]))
	for w in _wake_trail:
		if idx >= MAX_DISPLACERS:
			break
		var p2: Vector3 = w["pos"]
		var age2: float = now - float(w["born"])
		var strength: float = 1.0 - (age2 / float(w["lifetime"]))
		slots[idx] = Vector4(p2.x, p2.y, p2.z, strength)
		idx += 1
	# Tail slots stay at (0,0,0,0) from the resize — w=0 makes the shader
	# skip them, so we don't need to overwrite.
	for pid in _materials.keys():
		var mat: ShaderMaterial = _materials[pid]
		mat.set_shader_parameter("displacers", slots)
		mat.set_shader_parameter("disp_count", idx)

func _init_preset(p: Dictionary) -> void:
	var pid: String = String(p.id)
	var kind: String = String(p.get("kind", "grass"))
	var tree_variants: Array = p.get("glb_variants", []) as Array if kind == "tree" else []
	if kind == "tree" and tree_variants.size() > 0:
		for vi in range(tree_variants.size()):
			var key: String = _tree_variant_key(pid, vi)
			_instances[key] = []
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = false
			mm.use_custom_data = false
			mm.mesh = _build_tree_mesh_from_path(String(tree_variants[vi]))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mmi)
			_multimeshes[key] = mm
			_mmis[key] = mmi
		return
	if kind == "shrub":
		# One MMI per bucket. Each bucket uses the same atlas + material
		# but pulls a different 3-tile slice. add_instance routes shrubs
		# to a random bucket so neighbouring bushes look different.
		for b in range(SHRUB_BUCKETS):
			var key: String = _shrub_bucket_key(pid, b)
			_instances[key] = []
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = false
			mm.use_custom_data = false
			mm.mesh = _build_shrub_mesh(p, b)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			_multimeshes[key] = mm
			_mmis[key] = mmi
		return
	_instances[pid] = []
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	if kind == "clover":
		mm.mesh = _build_clover_mesh(p)
	elif kind == "daisy":
		mm.mesh = _build_daisy_mesh(p)
	elif kind == "tree":
		mm.mesh = _build_tree_mesh(p)
	else:
		mm.mesh = _build_blade_mesh(p)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Trees cast real shadows (unlike grass blades which use baked shadow
	# decals) — turn shadow casting back on for tree presets.
	mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if kind == "tree" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	add_child(mmi)
	_multimeshes[pid] = mm
	_mmis[pid] = mmi

func _shrub_bucket_key(pid: String, bucket: int) -> String:
	return pid + "#" + str(bucket)

func _tree_variant_key(pid: String, variant: int) -> String:
	return pid + "#" + str(variant)

func _is_shrub_preset(pid: String) -> bool:
	for p in PRESETS:
		if String(p.id) == pid:
			return String(p.get("kind", "grass")) == "shrub"
	return false

func _tree_variant_count(pid: String) -> int:
	for p in PRESETS:
		if String(p.id) == pid and String(p.get("kind", "")) == "tree":
			var v: Array = p.get("glb_variants", []) as Array
			return v.size()
	return 0

func _make_foliage_material(p: Dictionary, tex: ImageTexture, billboard_mode: int) -> ShaderMaterial:
	# Buckets reuse the same atlas + tint → reuse the cached material so
	# wind uniform updates (keyed by preset id) reach every bucket mesh.
	if _materials.has(String(p.id)):
		return _materials[String(p.id)]
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("albedo_tint", p.tint)
	# 0.6 vs the old 0.5: discards alpha-tested pixels a touch earlier so
	# the soft-edge halo around each blade contributes fewer rasterised
	# fragments. Visible silhouette stays effectively identical at the
	# 32-texel source resolution.
	mat.set_shader_parameter("alpha_scissor", 0.6)
	mat.set_shader_parameter("billboard_mode", billboard_mode)
	# Shrubs are dense volumes — full blade-amplitude wind makes them look
	# like they're flailing. Damp heavily so they breathe instead. Clover
	# lies flat on the ground; sway on a flat quad would just shear the
	# texture sideways, which reads as the patch sliding — disable entirely.
	var kind: String = String(p.get("kind", "grass"))
	var sway: float = 1.0
	if kind == "shrub":
		sway = 0.4
	elif kind == "clover":
		sway = 0.0
	elif kind == "daisy":
		# Daisy flower head is small + far from the root, so even a modest
		# tip displacement reads as visible nodding. Damp to ~0.6 of blade
		# amplitude so flowers bob instead of whipping.
		sway = 0.6
	mat.set_shader_parameter("sway_mult", sway)
	# Grass tufts and clover patches hide behind-camera by collapsing to zero
	# area. Shrubs are sparse enough that the cull cost outweighs the saving,
	# plus they're tall enough that fringe instances clip into view from
	# oblique angles — keep shrubs always-on.
	var cull_dot: float = -1.0 if kind == "shrub" else -0.2
	mat.set_shader_parameter("cull_back_dot", cull_dot)
	# Distance cull: blades past this XZ distance from the camera collapse
	# to zero-area in the vertex shader. Grass tufts are tiny + dense, so
	# the visual cost of cutting them past ~28m is invisible against the
	# fragment savings. Shrubs/clover/daisy stay always-on (they're sparse
	# enough that the cull check is a net loss).
	var far_dist: float = 28.0 if kind == "grass" else -1.0
	mat.set_shader_parameter("cull_far_dist", far_dist)
	# Crossed-quad → single-billboard LOD for grass blades only. Window
	# 4m → 9m: anything inside 4m keeps the two authored quads (rot_y
	# variety visible), anything past 9m is a single Y-billboarded quad
	# (half the tris, half the fragment fill). The 5m blend lets each
	# blade pop out gradually instead of all at once — combined with the
	# scale-down + rotation-blend, the LOD seam is below pixel-noise
	# threshold at typical FOV.
	var lod_start: float = -1.0
	var lod_end: float = -1.0
	if kind == "grass":
		lod_start = 4.0
		lod_end = 9.0
	mat.set_shader_parameter("lod_start", lod_start)
	mat.set_shader_parameter("lod_end", lod_end)
	_materials[String(p.id)] = mat
	_apply_wind_uniforms_to(mat)
	return mat

func _build_blade_mesh(p: Dictionary) -> Mesh:
	# Two crossed quads at 0° / 90° — full X gives a tuft from any angle but
	# triples the vert/fragment cost; two perpendicular quads still cover
	# every horizontal viewing direction without going edge-on, at 2/3 the
	# cost of the shrub mesh.
	#
	# UV2.x encodes the quad index (0 = base quad, 1 = cross quad). The
	# shader fades the cross quad out + Y-billboards the base quad past
	# a distance threshold so far blades are effectively single quads
	# always facing the camera. UV2.y stays 0 (reserved).
	var w: float = float(p.width)
	var h: float = float(p.height)
	var hw: float = w * 0.5
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var angles: Array = [0.0, PI * 0.5]
	var idx: int = 0
	for qi in range(angles.size()):
		var a: float = angles[qi]
		var c: float = cos(a)
		var s: float = sin(a)
		var p0 := Vector3(-hw * c, 0.0, -hw * s)
		var p1 := Vector3( hw * c, 0.0,  hw * s)
		var p2 := Vector3( hw * c, h,    hw * s)
		var p3 := Vector3(-hw * c, h,   -hw * s)
		verts.push_back(p0); verts.push_back(p1); verts.push_back(p2); verts.push_back(p3)
		uvs.push_back(Vector2(0, 1)); uvs.push_back(Vector2(1, 1))
		uvs.push_back(Vector2(1, 0)); uvs.push_back(Vector2(0, 0))
		var qf: float = float(qi)
		uv2s.push_back(Vector2(qf, 0)); uv2s.push_back(Vector2(qf, 0))
		uv2s.push_back(Vector2(qf, 0)); uv2s.push_back(Vector2(qf, 0))
		indices.push_back(idx);     indices.push_back(idx + 1); indices.push_back(idx + 2)
		indices.push_back(idx);     indices.push_back(idx + 2); indices.push_back(idx + 3)
		idx += 4
	var am := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _make_foliage_material(p, _shared_blade_tex, 0))
	return am

func _build_shrub_mesh(p: Dictionary, bucket: int = 0) -> Mesh:
	# Three quads intersecting at 0° / 60° / 120° around Y. Each quad UVs into
	# a different column of the shrub atlas so the three silhouettes that
	# make up the bush aren't carbon copies of each other — breaks up the
	# bilateral-symmetry "screwhead" look the single-tile version had.
	# The bucket index picks WHICH triplet of columns to use; placing 5
	# variant buckets and routing instances at random gives per-bush
	# silhouette variation across a cluster.
	var w: float = float(p.width)
	var h: float = float(p.height)
	var hw: float = w * 0.5
	# Sink the bottom edge below ground so the empty pixel band at the
	# bottom of the elliptical texture mask (the ellipse doesn't reach the
	# corners of the tile) ends up underground — visible silhouette lands
	# on the ground instead of hovering.
	var y_lo: float = -h * 0.12
	var y_hi: float = h * 0.88
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var angles: Array = [0.0, PI / 3.0, 2.0 * PI / 3.0]
	var total_tiles: float = float(SHRUB_BUCKETS * SHRUB_VARIANTS)
	var col_base: int = bucket * SHRUB_VARIANTS
	var idx: int = 0
	for vi in range(angles.size()):
		var a: float = angles[vi]
		var c: float = cos(a)
		var s: float = sin(a)
		var p0 := Vector3(-hw * c, y_lo, -hw * s)
		var p1 := Vector3( hw * c, y_lo,  hw * s)
		var p2 := Vector3( hw * c, y_hi,  hw * s)
		var p3 := Vector3(-hw * c, y_hi, -hw * s)
		verts.push_back(p0); verts.push_back(p1); verts.push_back(p2); verts.push_back(p3)
		# Slice U into the matching column of the atlas. UV V=0 stays at the
		# top so the wind sway top_factor still bends the bush dome.
		var u0: float = float(col_base + vi) / total_tiles
		var u1: float = float(col_base + vi + 1) / total_tiles
		uvs.push_back(Vector2(u0, 1)); uvs.push_back(Vector2(u1, 1))
		uvs.push_back(Vector2(u1, 0)); uvs.push_back(Vector2(u0, 0))
		indices.push_back(idx);     indices.push_back(idx + 1); indices.push_back(idx + 2)
		indices.push_back(idx);     indices.push_back(idx + 2); indices.push_back(idx + 3)
		idx += 4
	var am := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _make_foliage_material(p, _shrub_textures[String(p.id)], 0))
	# Ground shadow disc — flat XZ quad just above the ground, soft radial
	# alpha. Uses a separate StandardMaterial3D so it sits in the transparent
	# queue and blends instead of getting clipped by the foliage alpha-scissor.
	# Shadow disc width tuned to the visible bush base (pear_bot * 0.5 * w ≈
	# 0.53w) plus a small skirt — bigger discs read as the bush sitting on a
	# saucer rather than as a grounded shadow.
	var sw: float = w * 1.05
	var sh_verts := PackedVector3Array([
		Vector3(-sw * 0.5, 0.01, -sw * 0.5),
		Vector3( sw * 0.5, 0.01, -sw * 0.5),
		Vector3( sw * 0.5, 0.01,  sw * 0.5),
		Vector3(-sw * 0.5, 0.01,  sw * 0.5),
	])
	var sh_uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var sh_indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var sh_arrays: Array = []
	sh_arrays.resize(Mesh.ARRAY_MAX)
	sh_arrays[Mesh.ARRAY_VERTEX] = sh_verts
	sh_arrays[Mesh.ARRAY_TEX_UV] = sh_uvs
	sh_arrays[Mesh.ARRAY_INDEX] = sh_indices
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sh_arrays)
	am.surface_set_material(1, _shared_shadow_mat)
	return am

func _build_clover_mesh(p: Dictionary) -> Mesh:
	# Single flat quad lying on the XZ plane just above the ground — clover
	# patches read as a decal, not as a billboard. y=0.015 to clear the grass
	# shadow disc (0.01) below and any sub-pixel z-fight against the terrain.
	var w: float = float(p.width)
	var hw: float = w * 0.5
	var verts := PackedVector3Array([
		Vector3(-hw, 0.015, -hw),
		Vector3( hw, 0.015, -hw),
		Vector3( hw, 0.015,  hw),
		Vector3(-hw, 0.015,  hw),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var am := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _make_foliage_material(p, _shared_clover_tex, 0))
	return am

func _build_clover_texture() -> ImageTexture:
	# Top-down view of a small clover cluster — 3-4 trefoil leaves placed
	# around the patch with random rotation. Each trefoil = three heart
	# leaflets arranged at 120°. Cluster sits centred so the quad's edges
	# fade out to transparent and the patch reads as a soft tuft, not a
	# square decal.
	var size: int = TEX_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC10E
	# 3 trefoils dotted around the centre. Each trefoil's centre stays
	# inside the inner 60% of the tile so leaflets don't get clipped.
	var trefoils: Array = []
	for i in range(3):
		var ang: float = rng.randf() * TAU
		var rr: float = rng.randf_range(0.0, float(size) * 0.18)
		var cx: float = float(size - 1) * 0.5 + cos(ang) * rr
		var cy: float = float(size - 1) * 0.5 + sin(ang) * rr
		var rot: float = rng.randf() * TAU
		# Leaflet radial offset from trefoil centre and per-leaflet radius.
		var leaf_off: float = float(size) * 0.16
		var leaf_r: float = float(size) * 0.14
		trefoils.append({"cx": cx, "cy": cy, "rot": rot, "off": leaf_off, "r": leaf_r})
	for x in range(size):
		for y in range(size):
			var best: float = -1.0
			# Score = leaflet coverage. A leaflet is a circle with a small
			# notch toward the trefoil centre — fake the heart-shape by
			# subtracting a smaller circle at the inner edge.
			for t in trefoils:
				for li in range(3):
					var la: float = t.rot + float(li) * TAU / 3.0
					var lx: float = t.cx + cos(la) * t.off
					var ly: float = t.cy + sin(la) * t.off
					var dx: float = float(x) - lx
					var dy: float = float(y) - ly
					var d: float = sqrt(dx * dx + dy * dy)
					if d >= t.r:
						continue
					# Notch: subtract a small inner disc on the side
					# nearest the trefoil centre to carve the heart cleft.
					var nx: float = lx - cos(la) * t.r * 0.55
					var ny: float = ly - sin(la) * t.r * 0.55
					var nd: float = sqrt((float(x) - nx) * (float(x) - nx) + (float(y) - ny) * (float(y) - ny))
					if nd < t.r * 0.42:
						continue
					var t_norm: float = 1.0 - d / t.r
					# Brighter at leaflet centre, mid-vein hint along the
					# axis toward the trefoil centre.
					var vein_t: float = clamp(1.0 - (absf(dx * sin(la) - dy * cos(la)) / (t.r * 0.18)), 0.0, 1.0)
					var s: float = lerp(0.6, 0.95, t_norm) + vein_t * 0.08
					if s > best:
						best = s
			if best < 0.0:
				continue
			var shade: float = clamp(best, 0.0, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_tree_mesh(p: Dictionary) -> Mesh:
	# Load merged tree mesh from baked .glb (assets/models/*.glb). GLTF
	# pull at runtime (not res:// PackedScene load) so the launcher
	# source-pull works without Godot's .import sidecars.
	return _build_tree_mesh_from_path(String(p.get("glb", "")))

func _build_tree_mesh_from_path(path: String) -> Mesh:
	var am := ArrayMesh.new()
	if path.is_empty():
		push_warning("editor_foliage: tree mesh missing glb path")
		return am
	var abs_path: String = ProjectSettings.globalize_path(path)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(abs_path, state)
	if err != OK:
		push_warning("editor_foliage: glb load failed (%d) for %s" % [err, abs_path])
		return am
	var scene := doc.generate_scene(state)
	if scene == null:
		push_warning("editor_foliage: glb produced no scene: %s" % abs_path)
		return am
	# Merge every MeshInstance3D surface under the imported root into one
	# ArrayMesh so a single MultiMeshInstance3D can draw the whole forest.
	_merge_into(scene, Transform3D.IDENTITY, am)
	scene.queue_free()
	return am

func _merge_into(node: Node, parent_xform: Transform3D, into: ArrayMesh) -> void:
	var xform: Transform3D = parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var src := mi.mesh
		for s in range(src.get_surface_count()):
			var arrays: Array = src.surface_get_arrays(s)
			# transform vertex positions + normals into merged space
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in range(positions.size()):
					positions[i] = xform * positions[i]
				arrays[Mesh.ARRAY_VERTEX] = positions
			if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var basis := xform.basis.inverse().transposed()
				for i in range(normals.size()):
					normals[i] = (basis * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat: Material = mi.get_active_material(s)
			if mat == null:
				mat = src.surface_get_material(s)
			if mat != null:
				_sanitize_imported_material(mat)
				into.surface_set_material(into.get_surface_count() - 1, mat)
	for c in node.get_children():
		_merge_into(c, xform, into)

func _sanitize_imported_material(mat: Material) -> void:
	# Godot's gltf importer can carry across emission / specular / clearcoat
	# and vertex-color-multiply settings from the source Principled BSDF.
	# Vertex colors are stored linear in glb but the importer flags them
	# srgb→linear in the StandardMaterial3D, so the albedo gets
	# double-multiplied under directional light and the canopy reads as
	# nuclear. Stomp every brightness amplifier we know of.
	if mat is BaseMaterial3D:
		var sm := mat as BaseMaterial3D
		sm.emission_enabled = false
		sm.metallic = 0.0
		sm.metallic_specular = 0.0
		sm.roughness = 1.0
		sm.clearcoat_enabled = false
		sm.rim_enabled = false
		sm.subsurf_scatter_enabled = false
		sm.vertex_color_use_as_albedo = false
		sm.vertex_color_is_srgb = false
		# Force a neutral white tint — texture albedo stays the source of
		# truth. The Principled chain in Blender mapped tex × vertex-color ×
		# hue/sat into base color; we collapse that to just the texture.
		sm.albedo_color = Color(1, 1, 1, 1)
		sm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

func _build_daisy_mesh(p: Dictionary) -> Mesh:
	# Single Y-billboard quad — the grass shader rebuilds the basis from cam
	# direction when billboard_mode=1, so crossed quads buy nothing here.
	# Texture carries baked petal/centre/stem colours so we skip the tint.
	var w: float = float(p.width)
	var h: float = float(p.height)
	var hw: float = w * 0.5
	var verts := PackedVector3Array([
		Vector3(-hw, 0.0, 0.0),
		Vector3( hw, 0.0, 0.0),
		Vector3( hw, h,   0.0),
		Vector3(-hw, h,   0.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var am := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _make_foliage_material(p, _shared_daisy_tex, 1))
	return am

func _build_daisy_texture() -> ImageTexture:
	# Daisy painted into a single 32px tile. UV.y=0 is the top (flower head),
	# UV.y=1 the root, matching the shader's top_factor so wind nods the
	# bloom while the stem base stays put.
	#
	# Layout (in UV space):
	#   stem  : thin green column at u ≈ 0.5, v 0.45 → 0.95
	#   head  : centred at (u=0.5, v=0.22), petal radius ≈ 0.25
	#   centre: yellow disc, radius ≈ 0.08
	var size: int = TEX_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var fs: float = float(size)
	var cx_px: float = fs * 0.5
	var head_y_px: float = fs * 0.22
	var petal_outer: float = fs * 0.25
	var petal_inner: float = fs * 0.085
	var stem_x_w: float = fs * 0.04
	var stem_top: float = fs * 0.45
	var stem_bot: float = fs * 0.95
	# Eight petals stamped as elongated ellipses radiating from the centre.
	# Each petal is a circular brush smeared along the petal's axis so it
	# reads as a tongue, not a perfect disc.
	var petal_count: int = 8
	var petal_len: float = petal_outer - petal_inner * 0.5
	var petal_half_w: float = fs * 0.06
	for x in range(size):
		for y in range(size):
			var px: float = float(x) + 0.5
			var py: float = float(y) + 0.5
			# Stem first (drawn under petals — petals overwrite).
			if py >= stem_top and py <= stem_bot and absf(px - cx_px) <= stem_x_w:
				var stem_t: float = (py - stem_top) / (stem_bot - stem_top)
				var stem_shade: float = lerp(0.45, 0.30, stem_t)
				img.set_pixel(x, y, Color(stem_shade * 0.35, stem_shade, stem_shade * 0.30, 1.0))
			# Now the head — covers stem near the top if any pixel overlap.
			var dx: float = px - cx_px
			var dy: float = py - head_y_px
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < petal_inner:
				# Yellow centre disc. Slight darkening at the edge for shape.
				var c_t: float = clamp(dist / petal_inner, 0.0, 1.0)
				var y_shade: float = lerp(1.0, 0.78, c_t)
				img.set_pixel(x, y, Color(1.0 * y_shade, 0.85 * y_shade, 0.25 * y_shade, 1.0))
				continue
			# Petal pass: for each radial direction, project the pixel onto
			# the petal axis. If we're within the petal's length AND within
			# its half-width, we're inside that petal.
			var hit: bool = false
			for pi in range(petal_count):
				var pa: float = float(pi) * TAU / float(petal_count)
				var ax: float = cos(pa)
				var ay: float = sin(pa)
				# Along-axis distance from petal start (just outside centre).
				var along: float = dx * ax + dy * ay - petal_inner * 0.6
				if along < 0.0 or along > petal_len:
					continue
				var across: float = absf(dx * (-ay) + dy * ax)
				# Petal narrows toward the tip — half-width tapers from
				# petal_half_w at the base to ~30% of that at the tip.
				var along_t: float = along / petal_len
				var hw_at_t: float = petal_half_w * lerp(1.0, 0.35, along_t)
				if across <= hw_at_t:
					# White with a tiny falloff toward the tip.
					var pshade: float = lerp(1.0, 0.88, along_t)
					img.set_pixel(x, y, Color(pshade, pshade, pshade, 1.0))
					hit = true
					break
			if hit:
				continue
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_blade_texture() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	# Fill transparent pixels with the blade's mid-tone (alpha 0) so the mip
	# chain averages toward the silhouette colour instead of toward black.
	# Without this, distant mips mix bright blade rgb with (0,0,0,0) and
	# produce dark fringes that look like blackness at the carpet horizon.
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
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

func _build_shrub_texture(p: Dictionary) -> ImageTexture:
	# Atlas wide enough to hold every bucket's 3-tile triplet side by side:
	# SHRUB_BUCKETS * SHRUB_VARIANTS columns total. Each bucket mesh UVs
	# into its own contiguous 3-tile slice. Style config is shared across
	# the whole atlas (so all buckets read as the same species) while seed
	# varies per tile so individual silhouettes don't repeat.
	var tile: int = SHRUB_TILE
	var total_tiles: int = SHRUB_BUCKETS * SHRUB_VARIANTS
	var atlas_w: int = tile * total_tiles
	var img := Image.create(atlas_w, tile, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var style: String = String(p.get("style", "round"))
	var cfg: Dictionary = _shrub_style_config(style)
	var base_seed: int = int(hash(String(p.id)))
	for ti in range(total_tiles):
		_paint_shrub_tile(img, ti * tile, 0, tile, base_seed + ti * 17, cfg)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _shrub_style_config(style: String) -> Dictionary:
	# Style → painter parameters. Tweaking these reshapes the canopy
	# silhouette + branch + leaf density without changing the mesh; the
	# mesh's per-preset width/height stretches whichever silhouette this
	# emits to fit the bush footprint in world space.
	match style:
		"tall":
			# Slim columnar bush — narrow mask, sub-branches kept short and
			# leaf clusters stacked vertically along the trunk.
			return {
				"mask_rx": 0.30, "mask_ry": 0.48, "mask_cy_frac": 0.45,
				"sub_count": 3, "sub_len_min": 0.10, "sub_len_max": 0.18,
				"sub_ang_min": 0.35, "sub_ang_max": 0.70,
				"crown_r": 0.14, "crown_n": 5,
				"tip_r": 0.10, "tip_n": 4,
				"mid_r": 0.08, "mid_n": 2,
				"trunk_extra_clusters": true,
			}
		"wide":
			# Squat, sprawling bush — many sub-branches at wide angles, low
			# crown. Mask flatter than it is tall.
			return {
				"mask_rx": 0.48, "mask_ry": 0.30, "mask_cy_frac": 0.55,
				"sub_count": 6, "sub_len_min": 0.18, "sub_len_max": 0.28,
				"sub_ang_min": 0.80, "sub_ang_max": 1.30,
				"crown_r": 0.10, "crown_n": 3,
				"tip_r": 0.11, "tip_n": 5,
				"mid_r": 0.09, "mid_n": 3,
				"trunk_extra_clusters": false,
			}
		"sparse":
			# Same footprint as round but ~60% leaf density — branches show
			# through prominently for a dead/winter-bramble look.
			return {
				"mask_rx": 0.45, "mask_ry": 0.42, "mask_cy_frac": 0.48,
				"sub_count": 5, "sub_len_min": 0.18, "sub_len_max": 0.30,
				"sub_ang_min": 0.55, "sub_ang_max": 1.05,
				"crown_r": 0.10, "crown_n": 3,
				"tip_r": 0.09, "tip_n": 2,
				"mid_r": 0.08, "mid_n": 1,
				"trunk_extra_clusters": false,
			}
		_:
			# "round" — baseline. Mask pulled fully inside tile so the canopy
			# top has a curved dome instead of getting clipped flat by the
			# texture boundary. mask_edge_jitter perturbs the per-blob
			# accept threshold so the silhouette edge wavers instead of
			# tracing a clean ellipse → no straight edges along any tile
			# border.
			return {
				"mask_rx": 0.44, "mask_ry": 0.42, "mask_cy_frac": 0.49,
				"mask_edge_jitter": 0.22,
				"sub_count": 4, "sub_len_min": 0.16, "sub_len_max": 0.26,
				"sub_ang_min": 0.55, "sub_ang_max": 1.05,
				"crown_r": 0.16, "crown_n": 10,
				"crown_y_frac": 0.13,
				"crown_dome_off_x": 0.16, "crown_dome_off_y": 0.07,
				"crown_dome_r": 0.12, "crown_dome_n": 4,
				"tip_r": 0.12, "tip_n": 7,
				"mid_r": 0.10, "mid_n": 4,
				"trunk_extra_clusters": false,
			}

func _paint_shrub_tile(img: Image, ox: int, oy: int, tile: int, seed: int, cfg: Dictionary) -> void:
	# Skeletal shrub painter — replaces the old pear-blob silhouette with a
	# trunk + sub-branches + clumped leaves so the bush reads as a sparse
	# bramble. Texture bakes both brown (twig) and green (leaf) colours
	# directly, so the foliage material tints with white to preserve them.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var t_f: float = float(tile)
	var cx: float = (t_f - 1.0) * 0.5
	# Trunk polyline — sampled root→tip. UV.y=0 is the top of the texture
	# (mesh top edge), so tip lives at small y, root at large y. Trunk tip
	# stops a hair below the crown anchor so the brown branch never pokes
	# out above the leaf canopy.
	var trunk_top_y_frac: float = float(cfg.get("crown_y_frac", 0.0))
	if trunk_top_y_frac <= 0.0:
		trunk_top_y_frac = 0.04
	trunk_top_y_frac += 0.03
	var trunk_top_y: float = t_f * trunk_top_y_frac
	var trunk: Array = []
	var lean: float = rng.randf_range(-0.10, 0.10)
	var samples: int = 9
	for i in range(samples):
		var v: float = float(i) / float(samples - 1)  # 0=root, 1=tip
		var tx: float = cx + sin(v * PI) * t_f * lean + sin(v * 5.0 + float(seed) * 0.07) * t_f * 0.04
		var ty: float = lerp(t_f - 1.0, trunk_top_y, v)
		trunk.append(Vector2(tx, ty))
	# Branch segments — main trunk (wide) + 4 sub-branches sprouting outward
	# and slightly upward. Wider segments paint a chunkier brown.
	var segments: Array = []
	for i in range(samples - 1):
		segments.append({"a": trunk[i], "b": trunk[i + 1], "w": 1.1})
	# Leaf anchors get paired with each sub-branch tip + a mid-branch cluster.
	# Crown of the trunk also gets a small cluster so the top isn't bald.
	var leaf_anchors: Array = []
	# Crown anchor — if crown_y_frac > 0, place the crown explicitly below
	# the top edge of the tile (so leaf blobs jittered upward stay inside
	# the texture and form a dome) and add two shoulder anchors fanning
	# down-and-out for dome curvature. Otherwise fall back to the trunk
	# tip directly.
	var crown_y_frac: float = float(cfg.get("crown_y_frac", 0.0))
	if crown_y_frac > 0.0:
		var crown_pt := Vector2(cx, t_f * crown_y_frac)
		leaf_anchors.append({"p": crown_pt, "r": t_f * float(cfg.crown_r), "n": int(cfg.crown_n)})
		var dome_off_x: float = t_f * float(cfg.get("crown_dome_off_x", 0.15))
		var dome_off_y: float = t_f * float(cfg.get("crown_dome_off_y", 0.06))
		var dome_r: float = t_f * float(cfg.get("crown_dome_r", 0.12))
		var dome_n: int = int(cfg.get("crown_dome_n", 5))
		leaf_anchors.append({"p": crown_pt + Vector2(-dome_off_x, dome_off_y), "r": dome_r, "n": dome_n})
		leaf_anchors.append({"p": crown_pt + Vector2( dome_off_x, dome_off_y), "r": dome_r, "n": dome_n})
	else:
		leaf_anchors.append({"p": trunk[samples - 1], "r": t_f * float(cfg.crown_r), "n": int(cfg.crown_n)})
	var sub_count: int = int(cfg.sub_count)
	var sub_len_min: float = float(cfg.sub_len_min)
	var sub_len_max: float = float(cfg.sub_len_max)
	var sub_ang_min: float = float(cfg.sub_ang_min)
	var sub_ang_max: float = float(cfg.sub_ang_max)
	for i in range(sub_count):
		var idx: int = rng.randi_range(2, samples - 2)
		var start: Vector2 = trunk[idx]
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		# Angle measured against +x; -PI*0.5 = straight up, so the per-style
		# range tilts the sub-branch outward — wide styles use a bigger range.
		var ang: float = side * rng.randf_range(sub_ang_min, sub_ang_max) - PI * 0.5
		var sub_len: float = rng.randf_range(t_f * sub_len_min, t_f * sub_len_max)
		var sub_steps: int = 4
		var prev: Vector2 = start
		for s in range(1, sub_steps + 1):
			var t_s: float = float(s) / float(sub_steps)
			var ex: float = start.x + cos(ang) * sub_len * t_s
			var ey: float = start.y + sin(ang) * sub_len * t_s
			var endpt := Vector2(ex, ey)
			segments.append({"a": prev, "b": endpt, "w": 0.85})
			prev = endpt
		leaf_anchors.append({"p": prev, "r": t_f * float(cfg.tip_r), "n": int(cfg.tip_n)})
		var mid_t: float = rng.randf_range(0.55, 0.85)
		var mid_pt := Vector2(start.x + cos(ang) * sub_len * mid_t, start.y + sin(ang) * sub_len * mid_t)
		leaf_anchors.append({"p": mid_pt, "r": t_f * float(cfg.mid_r), "n": int(cfg.mid_n)})
	# Tall styles want leaf clusters stacked along the trunk between the
	# root and the crown so the vertical column doesn't have a bald midriff.
	if bool(cfg.get("trunk_extra_clusters", false)):
		for trunk_i in [3, 5, 7]:
			if trunk_i < samples:
				leaf_anchors.append({"p": trunk[trunk_i], "r": t_f * 0.09, "n": 2})
	# Materialise leaf clumps from each anchor — many small blobs jittered
	# inside the anchor radius. Reject any blob whose centre sits outside a
	# soft canopy ellipse: keeps the silhouette rounded so corners read as
	# sky, not as a square bush outline.
	var leaves: Array = []
	var mask_rx: float = t_f * float(cfg.mask_rx)
	var mask_ry: float = t_f * float(cfg.mask_ry)
	var mask_cy: float = (t_f - 1.0) * float(cfg.mask_cy_frac)
	var mask_edge_jitter: float = float(cfg.get("mask_edge_jitter", 0.0))
	for a in leaf_anchors:
		var pp: Vector2 = a.p
		var ar: float = float(a.r)
		var nleaves: int = int(a.n)
		for li in range(nleaves):
			var dang: float = rng.randf() * TAU
			var drr: float = sqrt(rng.randf()) * ar
			var lx: float = pp.x + cos(dang) * drr
			var ly: float = pp.y + sin(dang) * drr
			var mdx: float = (lx - cx) / mask_rx
			var mdy: float = (ly - mask_cy) / mask_ry
			# Per-blob threshold noise breaks the clean ellipse boundary
			# so the canopy outline doesn't read as a circle drawn against
			# the square texture edge — keeps the silhouette organic.
			var threshold: float = 1.0
			if mask_edge_jitter > 0.0:
				threshold = 1.0 + rng.randf_range(-mask_edge_jitter, mask_edge_jitter)
			if mdx * mdx + mdy * mdy > threshold:
				continue
			var lr: float = rng.randf_range(t_f * 0.09, t_f * 0.13)
			# Reject blobs whose disc would extend past the tile boundary.
			# Without this, blobs near the edge get clipped along the tile
			# border and the silhouette gains a visible straight line where
			# the disc meets the texture edge.
			var edge_margin: float = 1.0
			if lx - lr < edge_margin or lx + lr > t_f - edge_margin:
				continue
			if ly - lr < edge_margin or ly + lr > t_f - edge_margin:
				continue
			var ls: float = rng.randf_range(0.78, 1.0)
			leaves.append({"x": lx, "y": ly, "r": lr, "s": ls})
	for x in range(tile):
		for y in range(tile):
			var px: float = float(x) + 0.5
			var py: float = float(y) + 0.5
			# Distance to nearest branch segment (and the segment's width).
			var d_branch: float = INF
			var branch_w: float = 0.0
			for seg in segments:
				var sa: Vector2 = seg.a
				var sb: Vector2 = seg.b
				var vx: float = sb.x - sa.x
				var vy: float = sb.y - sa.y
				var wx: float = px - sa.x
				var wy: float = py - sa.y
				var len2: float = vx * vx + vy * vy
				var tt: float = 0.0
				if len2 > 0.0001:
					tt = clamp((wx * vx + wy * vy) / len2, 0.0, 1.0)
				var cxp: float = sa.x + vx * tt
				var cyp: float = sa.y + vy * tt
				var dd: float = sqrt((px - cxp) * (px - cxp) + (py - cyp) * (py - cyp))
				if dd < d_branch:
					d_branch = dd
					branch_w = float(seg.w)
			# Leaf coverage (max over all blobs). Leaves draw on top of
			# branches so leaf-covered twig pixels read as foliage.
			var leaf_best: float = -1.0
			for lf in leaves:
				var ddx: float = px - lf.x
				var ddy: float = py - lf.y
				var d: float = sqrt(ddx * ddx + ddy * ddy)
				if d < lf.r:
					var lt: float = 1.0 - d / lf.r
					var sc: float = lf.s * lerp(0.78, 1.0, lt)
					if sc > leaf_best:
						leaf_best = sc
			if leaf_best > 0.0:
				var g: float = clamp(leaf_best, 0.0, 1.0)
				var r_c: float = lerp(0.14, 0.30, g)
				var g_c: float = lerp(0.32, 0.62, g)
				var b_c: float = lerp(0.10, 0.22, g)
				img.set_pixel(ox + x, oy + y, Color(r_c, g_c, b_c, 1.0))
				continue
			if d_branch <= branch_w:
				# Brown twig. Slight variation along the trunk via segment
				# centre y would be nice but a flat brown reads fine at 32px.
				img.set_pixel(ox + x, oy + y, Color(0.36, 0.22, 0.10, 1.0))

func _build_shadow_texture() -> ImageTexture:
	# Soft radial gradient — white RGB so the material's albedo_color tints
	# to whatever shade we want, falling alpha from centre to edge.
	var size: int = 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var cx: float = float(size - 1) * 0.5
	var cy: float = float(size - 1) * 0.5
	for x in range(size):
		for y in range(size):
			var dx: float = (float(x) - cx) / cx
			var dy: float = (float(y) - cy) / cy
			var r: float = sqrt(dx * dx + dy * dy)
			if r >= 1.0:
				continue
			# smoothstep gives a nicely tapered edge — pure 1/0 lerp produces
			# a hard outer ring that catches the eye.
			var a: float = (1.0 - smoothstep(0.0, 1.0, r)) * 0.55
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_shadow_material(tex: ImageTexture) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 1)
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Negative priority so the disc draws before the bush surfaces — keeps
	# the shadow under the bush silhouette instead of competing for the
	# same screen pixels.
	m.render_priority = -1
	return m

func _rebuild_all() -> void:
	for pid in _instances.keys():
		var mm: MultiMesh = _multimeshes[pid]
		var list: Array = _instances[pid]
		var n: int = list.size()
		if _preset_kind(pid) == "tree":
			_rebuild_tree_colliders(pid, list)
		# Empty MultiMesh spams "Buffer argument is not a valid buffer of any
		# type" once per frame in 4.6.x — Godot's rendering device tries to
		# bind a zero-length transform buffer. Hiding the MMI when empty
		# stops the draw call (and the error) entirely; we re-show it on
		# the next non-empty rebuild.
		var mmi: MultiMeshInstance3D = _mmis[pid]
		mmi.visible = n > 0
		if n == 0:
			continue
		mm.instance_count = n
		var min_p: Vector3 = Vector3.INF
		var max_p: Vector3 = -Vector3.INF
		for i in range(n):
			var inst: Dictionary = list[i]
			var pos: Vector3 = inst.get("pos", Vector3.ZERO)
			var s: float = float(inst.get("scale", 1.0))
			var ry: float = float(inst.get("rot_y", 0.0))
			var t: Transform3D = Transform3D(Basis(Vector3.UP, ry).scaled(Vector3.ONE * s), pos)
			mm.set_instance_transform(i, t)
			min_p = Vector3(min(min_p.x, pos.x), min(min_p.y, pos.y), min(min_p.z, pos.z))
			max_p = Vector3(max(max_p.x, pos.x), max(max_p.y, pos.y), max(max_p.z, pos.z))
		# Tight per-MMI custom_aabb. Default MultiMesh AABB grows to the
		# union of all instance world-space mesh AABBs — for one MMI per
		# preset spanning a whole map, that's "the entire map" and Godot
		# can never frustum-cull it. Setting it explicitly to the instance
		# spread + height + sway/wind margin lets the engine skip the
		# whole batch when none of the patch is on-screen, which only
		# pays off once patches are spatially clustered (small islands of
		# foliage with empty space between them).
		var height_margin: float = 2.0
		var sway_pad: float = 1.0
		var aabb := AABB(
			min_p - Vector3(sway_pad, 0.1, sway_pad),
			(max_p - min_p) + Vector3(sway_pad * 2.0, height_margin, sway_pad * 2.0),
		)
		mmi.custom_aabb = aabb

func _resolve_preset(preset_id: String) -> String:
	# Direct hit on an _instances key (already a leaf — either a non-shrub
	# preset or an already-bucketed shrub key like "shrub_round#2").
	if _instances.has(preset_id):
		return preset_id
	# Public shrub id → pick a random bucket so a cluster of placements
	# spreads across all SHRUB_BUCKETS silhouette variants.
	if _is_shrub_preset(preset_id):
		var b: int = randi() % SHRUB_BUCKETS
		return _shrub_bucket_key(preset_id, b)
	# Public tree id with glb_variants → pick a random variant bucket.
	var tv_count: int = _tree_variant_count(preset_id)
	if tv_count > 0:
		return _tree_variant_key(preset_id, randi() % tv_count)
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

func get_preset_scale_jitter(preset_id: String) -> Vector2:
	for p in PRESETS:
		if String(p.id) == preset_id:
			return Vector2(float(p.get("scale_jitter_min", 0.85)),
				float(p.get("scale_jitter_max", 1.15)))
	return Vector2(0.85, 1.15)

func add_instance(preset_id: String, world_pos: Vector3, scale: float, rot_y: float) -> bool:
	# Per-cell density cap. Cells already at MAX_PER_CELL refuse new
	# placements — caller paths (spray + exact + state restore) treat the
	# bool return as "did this actually land". Spray loops use it to count
	# real placements; exact-mode placement currently ignores it (single
	# clicks are infrequent enough that overflow doesn't matter).
	# Trees are large + sparse — counting them against the same 0.5m grass
	# cap means a single stump steals a slot a whole tuft of grass needs.
	# Skip the cap for tree presets.
	var is_tree: bool = _preset_kind(preset_id) == "tree"
	var key: Vector2i = _density_cell(world_pos)
	if not is_tree and int(_density_grid.get(key, 0)) >= MAX_PER_CELL:
		return false
	# Apply preset display_scale multiplier (lets stumps render at 1.8x
	# native mesh size without rebaking the .glb).
	var p_data: Dictionary = _preset_data(preset_id)
	var display_scale: float = float(p_data.get("display_scale", 1.0))
	var final_scale: float = scale * display_scale
	# Trees clear grass underneath so a stump doesn't grow out of a tuft.
	if is_tree:
		var clear_r: float = float(p_data.get("clear_grass_radius", 0.0))
		if clear_r > 0.0:
			_clear_grass_in_radius(world_pos, clear_r)
	var pid: String = _resolve_preset(preset_id)
	_instances[pid].append({"pos": world_pos, "scale": final_scale, "rot_y": rot_y})
	if not is_tree:
		_density_grid[key] = int(_density_grid.get(key, 0)) + 1
	_dirty = true
	return true

func _rebuild_tree_colliders(pid: String, list: Array) -> void:
	# Tear down any existing colliders under this variant key, then spawn
	# fresh ones to match the current instance list. Trees are sparse —
	# rebuilding on every dirty pass is cheaper than diffing.
	var holder: Node3D = _tree_collider_holders.get(pid)
	if holder == null:
		holder = Node3D.new()
		holder.name = "TreeColliders_" + pid
		add_child(holder)
		_tree_collider_holders[pid] = holder
	for c in holder.get_children():
		c.queue_free()
	if list.is_empty():
		return
	var p_data: Dictionary = _preset_data(pid)
	var radius: float = float(p_data.get("collision_radius", 0.0))
	if radius <= 0.0:
		return
	var height: float = float(p_data.get("collision_height", radius * 2.0))
	for inst in list:
		var pos: Vector3 = inst.get("pos", Vector3.ZERO)
		var s: float = float(inst.get("scale", 1.0))
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		# scale already baked the display_scale at add_instance, so the
		# radius/height constants in the preset assume that factor.
		cyl.radius = radius * (s / float(p_data.get("display_scale", 1.0)))
		cyl.height = height * (s / float(p_data.get("display_scale", 1.0)))
		shape.shape = cyl
		body.add_child(shape)
		# Lift body up so the cylinder centre sits at half-height above ground.
		body.position = pos + Vector3(0.0, cyl.height * 0.5, 0.0)
		holder.add_child(body)

func _preset_data(preset_id: String) -> Dictionary:
	var base: String = preset_id
	var hash_idx: int = preset_id.find("#")
	if hash_idx >= 0:
		base = preset_id.substr(0, hash_idx)
	for p in PRESETS:
		if String(p.id) == base:
			return p
	return {}

func _clear_grass_in_radius(world_pos: Vector3, radius: float) -> void:
	var r2: float = radius * radius
	for pid in _instances.keys():
		if _preset_kind(pid) != "grass":
			continue
		var keep: Array = []
		for inst in _instances[pid]:
			var ip: Vector3 = inst.get("pos", Vector3.ZERO)
			var dx: float = ip.x - world_pos.x
			var dz: float = ip.z - world_pos.z
			if dx * dx + dz * dz <= r2:
				var ck: Vector2i = _density_cell(ip)
				var c: int = int(_density_grid.get(ck, 0)) - 1
				if c <= 0:
					_density_grid.erase(ck)
				else:
					_density_grid[ck] = c
			else:
				keep.append(inst)
		_instances[pid] = keep

func _preset_kind(preset_id: String) -> String:
	# Accepts public id or bucketed key (strips "#<n>" suffix).
	var base: String = preset_id
	var hash_idx: int = preset_id.find("#")
	if hash_idx >= 0:
		base = preset_id.substr(0, hash_idx)
	for p in PRESETS:
		if String(p.id) == base:
			return String(p.get("kind", "grass"))
	return "grass"

func _density_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / DENSITY_CELL_SIZE)),
		int(floor(world_pos.z / DENSITY_CELL_SIZE)),
	)

func _rebuild_density_grid() -> void:
	_density_grid.clear()
	for pid in _instances.keys():
		if _preset_kind(pid) == "tree":
			continue
		for inst in _instances[pid]:
			var key: Vector2i = _density_cell(inst.get("pos", Vector3.ZERO))
			_density_grid[key] = int(_density_grid.get(key, 0)) + 1

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
				if _preset_kind(pid) != "tree":
					var key: Vector2i = _density_cell(p)
					var c: int = int(_density_grid.get(key, 0)) - 1
					if c <= 0:
						_density_grid.erase(key)
					else:
						_density_grid[key] = c
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

# Per-bucket breakdown for the F2 profiler overlay. Each row is one
# MultiMesh (= 1+ drawcalls depending on surface count). Shrub buckets are
# kept separate so the overlay can show drawcall amortisation cost.
#
# Tris per instance (sum across surfaces):
#   grass  = 2 crossed quads (4 tri foliage), shadow killed
#   shrub  = 3 quads (6 tri foliage) + shadow disc (2 tri) = 8
#   clover = 1 flat quad (2 tri)
#   daisy  = 1 Y-billboard quad (2 tri)
#
# Surface count drives the MMI's drawcall count — MultiMesh batches all
# instances into one draw per surface, so total drawcalls = surfaces.
func get_profile_breakdown() -> Array:
	var rows: Array = []
	var kind_by_public: Dictionary = {}
	for p in PRESETS:
		kind_by_public[String(p.id)] = String(p.kind)
	# Stable order: walk PRESETS, expand shrub buckets in index order.
	for p in PRESETS:
		var public_id: String = String(p.id)
		var kind: String = String(p.kind)
		if kind == "shrub":
			for b in range(SHRUB_BUCKETS):
				var key: String = _shrub_bucket_key(public_id, b)
				if _instances.has(key):
					rows.append(_profile_row(key, public_id, kind))
		elif kind == "tree" and _tree_variant_count(public_id) > 0:
			for v in range(_tree_variant_count(public_id)):
				var tkey: String = _tree_variant_key(public_id, v)
				if _instances.has(tkey):
					rows.append(_profile_row(tkey, public_id, kind))
		else:
			if _instances.has(public_id):
				rows.append(_profile_row(public_id, public_id, kind))
	return rows

func _profile_row(pid: String, public_id: String, kind: String) -> Dictionary:
	var count: int = (_instances[pid] as Array).size()
	var tris_per: int
	var surfaces: int
	match kind:
		"grass":
			tris_per = 4
			surfaces = 1
		"shrub":
			tris_per = 8
			surfaces = 2
		"clover":
			tris_per = 2
			surfaces = 1
		"daisy":
			tris_per = 2
			surfaces = 1
		_:
			tris_per = 2
			surfaces = 1
	return {
		"pid": pid,
		"public_id": public_id,
		"kind": kind,
		"count": count,
		"tris_per": tris_per,
		"tris_total": count * tris_per,
		"surfaces": surfaces,
	}

func clear_all() -> void:
	for pid in _instances.keys():
		_instances[pid] = []
	_density_grid.clear()
	_dirty = true

func get_state() -> Array:
	# Flattened list — one dict per instance with preset id, so loaders can
	# restore each into the right bucket without knowing about MultiMeshes.
	# Shrub bucket suffixes are stripped — saves shouldn't lock a placement
	# to a specific silhouette variant; reloads re-roll across buckets.
	var out: Array = []
	for pid in _instances.keys():
		var public_id: String = pid.split("#")[0]
		for inst in _instances[pid]:
			out.append({
				"preset": public_id,
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
	# Old saves predate the density cap, so a restored map can legitimately
	# exceed MAX_PER_CELL. Just rebuild the counter from the loaded state
	# instead of dropping overflow on load.
	_rebuild_density_grid()
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
