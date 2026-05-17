extends Node3D

# Fence authoring module owned by the editor. A fence is a straight run
# defined by two world-space endpoints + a post spacing. Posts get
# placed at every `post_spacing` metres along the run (snapped so an
# integer count of intervals fits exactly between the endpoints), with
# pickets + rails filling each interval.
#
# Snap rules (applied to whichever endpoint the user is dragging):
#   default        — endpoint snaps to nearest existing fence post within
#                    SNAP_RADIUS if one is in range
#   shift held     — hard snap suppressed; endpoint goes where the cursor
#                    points
#   alt held       — all snapping off (reserved for future soft-snap)
#
# Glb meshes are loaded once at setup via GLTFDocument (mirrors
# editor_objects_catalog's runtime-load pattern so the launcher's
# source-pull build, which has no .import sidecars, still works) and
# reused as shared Mesh resources across every spawned MeshInstance3D.

signal fence_state_changed()

# Variant configs. Each entry describes meshes + geometry knobs for one
# fence style. Pickets and rails are independently optional; a "no rails"
# style sets rails: [] and a "no pickets" style sets picket_glb: "".
# rails: array of Y-heights — one rail spawned per entry.
const VARIANTS := {
	"picket": {
		"post_glb": "res://assets/models/fence_post.glb",
		"picket_glb": "res://assets/models/fence_picket.glb",
		"rail_glb": "res://assets/models/fence_rail.glb",
		"picket_spacing": 0.16,
		"post_width": 0.12,
		"rails": [0.175, 0.675],
		"picket_random": false,
	},
	"tall_brown": {
		"post_glb": "res://assets/models/tall_fence_post.glb",
		"picket_glb": "res://assets/models/tall_fence_board.glb",
		"rail_glb": "res://assets/models/tall_fence_rail.glb",
		"picket_spacing": 0.10,  # boards touch
		"post_width": 0.14,
		"rails": [0.30, 1.30],
		"picket_random": false,
	},
	"log_vertical": {
		"post_glb": "res://assets/models/log_pole.glb",
		"picket_glb": "res://assets/models/log_picket.glb",
		"rail_glb": "",
		"picket_spacing": 0.135,
		"post_width": 0.22,
		"rails": [],
		"picket_random": true,
		"post_scale_y": 1.0,
	},
	"log_beam": {
		"post_glb": "res://assets/models/log_pole.glb",
		"picket_glb": "",
		"rail_glb": "res://assets/models/log_beam.glb",
		"picket_spacing": 0.0,
		"post_width": 0.22,
		"rails": [0.20, 0.70],
		"picket_random": false,
		"post_scale_y": 0.58,
	},
}

const MIN_RUN_LENGTH := 0.5
const SNAP_RADIUS := 0.6

const DEFAULT_POST_SPACING := 2.36
const MIN_POST_SPACING := 0.8
const MAX_POST_SPACING := 6.0
# Two posts within this radius collapse into one. Snap radius is much
# larger so two snapped endpoints will always cluster here.
const POST_DEDUP_RADIUS := 0.05

var _fences: Array = []
var _terrain: Node3D = null
var _mesh_cache: Dictionary = {}  # path → Mesh
var _active_variant: String = "picket"

var _drag_active: bool = false
var _drag_start: Vector3 = Vector3.ZERO
var _drag_end: Vector3 = Vector3.ZERO
var _drag_spacing: float = DEFAULT_POST_SPACING

var _visuals_root: Node3D = null
var _ghost_root: Node3D = null

# Cached world positions of every post placed so far — drives hard snap.
var _post_positions: Array = []

func setup(terrain: Node3D) -> void:
	_terrain = terrain
	# Preload every variant's meshes once. Cheap — 4 variants × ~3 GLBs.
	for vname in VARIANTS.keys():
		var v: Dictionary = VARIANTS[vname]
		for key in ["post_glb", "picket_glb", "rail_glb"]:
			var p: String = v[key]
			if p != "" and not _mesh_cache.has(p):
				_mesh_cache[p] = _load_first_mesh(p)
	_visuals_root = Node3D.new()
	_visuals_root.name = "FenceVisuals"
	add_child(_visuals_root)
	_ghost_root = Node3D.new()
	_ghost_root.name = "FenceGhost"
	add_child(_ghost_root)

func set_variant(name: String) -> void:
	if VARIANTS.has(name):
		_active_variant = name

func get_variant() -> String:
	return _active_variant

func _variant_for(f: Dictionary) -> Dictionary:
	var n: String = f.get("variant", "picket")
	if not VARIANTS.has(n):
		n = "picket"
	return VARIANTS[n]

func _load_first_mesh(path: String) -> Mesh:
	var abs_path: String = ProjectSettings.globalize_path(path)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(abs_path, state) != OK:
		push_error("fence: glb load failed " + abs_path)
		return null
	var scn := doc.generate_scene(state)
	if scn == null:
		return null
	var mesh := _find_first_mesh(scn)
	scn.queue_free()
	return mesh

func _find_first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and n.mesh != null:
		return n.mesh
	for c in n.get_children():
		var m := _find_first_mesh(c)
		if m != null:
			return m
	return null

func set_state(state: Array) -> void:
	_fences = state.duplicate(true)
	_rebuild_all()

func get_state() -> Array:
	return _fences.duplicate(true)

func is_dragging() -> bool:
	return _drag_active

func begin_drag(world_pos: Vector3, alt: bool, shift: bool, post_spacing: float) -> void:
	_drag_active = true
	_drag_spacing = clampf(post_spacing, MIN_POST_SPACING, MAX_POST_SPACING)
	_drag_start = _maybe_snap(world_pos, alt, shift)
	_drag_end = _drag_start
	_refresh_ghost()

func update_drag(world_pos: Vector3, alt: bool, shift: bool, post_spacing: float) -> void:
	if not _drag_active:
		return
	_drag_spacing = clampf(post_spacing, MIN_POST_SPACING, MAX_POST_SPACING)
	_drag_end = _maybe_snap(world_pos, alt, shift)
	_refresh_ghost()

func commit_drag(world_pos: Vector3, alt: bool, shift: bool, post_spacing: float) -> void:
	if not _drag_active:
		return
	_drag_spacing = clampf(post_spacing, MIN_POST_SPACING, MAX_POST_SPACING)
	_drag_end = _maybe_snap(world_pos, alt, shift)
	var dist: float = _drag_start.distance_to(_drag_end)
	if dist >= MIN_RUN_LENGTH:
		_fences.append({
			"start": _drag_start,
			"end": _drag_end,
			"post_spacing": _drag_spacing,
			"variant": _active_variant,
		})
		fence_state_changed.emit()
	_drag_active = false
	_clear_ghost()
	_rebuild_all()

func cancel_drag() -> void:
	_drag_active = false
	_clear_ghost()

func _maybe_snap(world_pos: Vector3, alt: bool, shift: bool) -> Vector3:
	if alt:
		return world_pos
	if not shift:
		var nearest := _nearest_post(world_pos, SNAP_RADIUS)
		if nearest != Vector3.INF:
			return nearest
	return world_pos

func _nearest_post(world: Vector3, radius: float) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_d: float = radius
	for p in _post_positions:
		var d: float = p.distance_to(world)
		if d < best_d:
			best_d = d
			best = p
	return best

func _rebuild_all() -> void:
	for c in _visuals_root.get_children():
		c.queue_free()
	_post_positions.clear()
	# Collect every post (position + the run's forward + variant) across
	# all fences, then collapse overlapping posts at shared corners. Without
	# this, two runs meeting at a snapped endpoint stack two posts at the
	# same world position rotated differently — visible mess.
	var entries: Array = []
	for f in _fences:
		_collect_segment_posts(f.start, f.end, f.post_spacing, _variant_for(f), entries)
	for cl in _cluster_posts(entries):
		var pw: Vector3 = cl["pos"]
		pw.y = _ground_y(pw)
		_spawn_post(_visuals_root, pw, cl["forward"], cl["variant"], false)
		_post_positions.append(pw)
	# Pickets + rails are per-interval and never overlap across runs, so
	# they can run independently per segment.
	for f in _fences:
		_build_intervals(_visuals_root, f.start, f.end, f.post_spacing, _variant_for(f), false)

func _refresh_ghost() -> void:
	_clear_ghost()
	if not _drag_active:
		return
	var delta: Vector3 = _drag_end - _drag_start
	delta.y = 0.0
	var L: float = delta.length()
	if L < MIN_RUN_LENGTH:
		return
	var forward: Vector3 = delta.normalized()
	var n_intervals: int = max(1, int(round(L / _drag_spacing)))
	var actual_spacing: float = L / n_intervals
	var variant: Dictionary = VARIANTS[_active_variant]
	# Ghost posts: skip any whose world position is already taken by a
	# committed post — keeps the live preview from overlapping at the
	# snapped endpoint while the user is still dragging.
	for i in range(n_intervals + 1):
		var pw: Vector3 = _drag_start + forward * (i * actual_spacing)
		if _post_position_taken(pw):
			continue
		pw.y = _ground_y(pw)
		_spawn_post(_ghost_root, pw, forward, variant, true)
	for i in range(n_intervals):
		var ps: Vector3 = _drag_start + forward * (i * actual_spacing)
		var pe: Vector3 = _drag_start + forward * ((i + 1) * actual_spacing)
		ps.y = _ground_y(ps)
		pe.y = _ground_y(pe)
		_build_interval(_ghost_root, ps, pe, forward, variant, true)

func _clear_ghost() -> void:
	for c in _ghost_root.get_children():
		c.queue_free()

func _collect_segment_posts(start: Vector3, end: Vector3, post_spacing: float, variant: Dictionary, out_entries: Array) -> void:
	var delta: Vector3 = end - start
	delta.y = 0.0
	var L: float = delta.length()
	if L < MIN_RUN_LENGTH:
		return
	var forward: Vector3 = delta.normalized()
	var n_intervals: int = max(1, int(round(L / post_spacing)))
	var actual_spacing: float = L / n_intervals
	for i in range(n_intervals + 1):
		var pw: Vector3 = start + forward * (i * actual_spacing)
		out_entries.append({"pos": pw, "forward": forward, "variant": variant})

func _build_intervals(root: Node3D, start: Vector3, end: Vector3, post_spacing: float, variant: Dictionary, ghost: bool) -> void:
	var delta: Vector3 = end - start
	delta.y = 0.0
	var L: float = delta.length()
	if L < MIN_RUN_LENGTH:
		return
	var forward: Vector3 = delta.normalized()
	var n_intervals: int = max(1, int(round(L / post_spacing)))
	var actual_spacing: float = L / n_intervals
	for i in range(n_intervals):
		var p_start: Vector3 = start + forward * (i * actual_spacing)
		var p_end: Vector3 = start + forward * ((i + 1) * actual_spacing)
		p_start.y = _ground_y(p_start)
		p_end.y = _ground_y(p_end)
		_build_interval(root, p_start, p_end, forward, variant, ghost)

func _cluster_posts(entries: Array) -> Array:
	# O(N^2) greedy cluster — N is small (few hundred posts max).
	var clusters: Array = []
	for e in entries:
		var ep: Vector3 = e["pos"]
		var found: bool = false
		for cl in clusters:
			if (cl["pos"] as Vector3).distance_to(ep) < POST_DEDUP_RADIUS:
				cl["entries"].append(e)
				found = true
				break
		if not found:
			clusters.append({"pos": ep, "entries": [e]})
	var out: Array = []
	for cl in clusters:
		var best: Dictionary = cl["entries"][0]
		var best_score: float = _cardinality(best["forward"])
		for e in cl["entries"]:
			var s: float = _cardinality(e["forward"])
			if s > best_score:
				best_score = s
				best = e
		out.append({"pos": cl["pos"], "forward": best["forward"], "variant": best["variant"]})
	return out

func _cardinality(f: Vector3) -> float:
	# 1.0 for perfectly axis-aligned, 0.0 for 45deg diagonal.
	return absf(absf(f.x) - absf(f.z))

func _post_position_taken(pos: Vector3) -> bool:
	for p in _post_positions:
		if (p as Vector3).distance_to(pos) < POST_DEDUP_RADIUS:
			return true
	return false

func _build_interval(root: Node3D, p_start: Vector3, p_end: Vector3, forward: Vector3, variant: Dictionary, ghost: bool) -> void:
	var span: float = p_start.distance_to(p_end)
	var picket_glb: String = variant["picket_glb"]
	var picket_spacing: float = variant["picket_spacing"]
	if picket_glb != "" and picket_spacing > 0.0:
		# Picket count: pick the integer N that makes the spacing s = span/(N+1)
		# closest to picket_spacing. Treating end-to-post as another picket slot
		# guarantees symmetric end gaps that match the inter-picket gap.
		var n_pickets: int = max(0, int(round(span / picket_spacing)) - 1)
		if n_pickets > 0:
			var s: float = span / float(n_pickets + 1)
			for i in range(n_pickets):
				var pw: Vector3 = p_start + forward * (s * (i + 1))
				pw.y = _ground_y(pw)
				_spawn_picket(root, pw, forward, variant, ghost)
	# Rails sit between posts (inner edge → inner edge). Heights per variant.
	var post_width: float = variant["post_width"]
	var rail_origin: Vector3 = p_start + forward * (post_width * 0.5)
	var rail_length: float = span - post_width
	for ry in variant["rails"]:
		var rp: Vector3 = rail_origin
		rp.y = _ground_y(rp) + ry
		_spawn_rail(root, rp, forward, rail_length, variant, ghost)

func _spawn_post(root: Node3D, world_pos: Vector3, forward: Vector3, variant: Dictionary, ghost: bool) -> void:
	var mesh: Mesh = _mesh_cache.get(variant["post_glb"], null)
	var basis: Basis = _yaw_basis(forward)
	var ysc: float = variant.get("post_scale_y", 1.0)
	if ysc != 1.0:
		basis = basis.scaled_local(Vector3(1.0, ysc, 1.0))
	_spawn(root, mesh, world_pos, basis, ghost)

func _spawn_picket(root: Node3D, world_pos: Vector3, forward: Vector3, variant: Dictionary, ghost: bool) -> void:
	var mesh: Mesh = _mesh_cache.get(variant["picket_glb"], null)
	if mesh == null:
		return
	var basis: Basis = _yaw_basis(forward)
	if variant.get("picket_random", false):
		# Deterministic random per world position so a given picket stays
		# stable across rebuilds. Vary height (Y-scale), radius (X+Z scale),
		# and yaw spin to avoid the seam-aligned look on cylindrical logs.
		var seed_v: int = int(world_pos.x * 173.0) ^ int(world_pos.z * 991.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var h_scale: float = rng.randf_range(0.82, 1.18)
		var r_scale: float = rng.randf_range(0.98, 1.18)
		var spin: float = rng.randf_range(-PI, PI)
		var tilt: float = rng.randf_range(-0.04, 0.04)
		basis = basis.rotated(Vector3.UP, spin)
		basis = basis.rotated(forward, tilt)
		basis = basis.scaled_local(Vector3(r_scale, h_scale, r_scale))
	_spawn(root, mesh, world_pos, basis, ghost)

func _spawn_rail(root: Node3D, world_pos: Vector3, forward: Vector3, length: float, variant: Dictionary, ghost: bool) -> void:
	var mesh: Mesh = _mesh_cache.get(variant["rail_glb"], null)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = world_pos
	# scaled_local (right-multiply) stretches the rail's local +X by length.
	mi.basis = _yaw_basis(forward).scaled_local(Vector3(length, 1.0, 1.0))
	if ghost:
		mi.transparency = 0.55
	root.add_child(mi)

func _spawn(root: Node3D, mesh: Mesh, world_pos: Vector3, basis: Basis, ghost: bool) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = world_pos
	mi.basis = basis
	if ghost:
		mi.transparency = 0.55
	root.add_child(mi)

func _yaw_basis(forward: Vector3) -> Basis:
	# Build a basis whose local +X axis maps to `forward` (XZ-plane only),
	# local +Y stays world up, local +Z = cross(X, Y). Used for everything
	# placed along a fence run so the model's length axis aligns with the
	# run direction.
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length_squared() < 0.0001:
		return Basis.IDENTITY
	f = f.normalized()
	var up := Vector3(0, 1, 0)
	var z_axis := f.cross(up).normalized()
	return Basis(f, up, z_axis)

func _ground_y(world: Vector3) -> float:
	if _terrain != null and _terrain.has_method("sample_height"):
		return _terrain.sample_height(world)
	return 0.0
