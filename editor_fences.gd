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

const POST_GLB := "res://assets/models/fence_post.glb"
const PICKET_GLB := "res://assets/models/fence_picket.glb"
const RAIL_GLB := "res://assets/models/fence_rail.glb"

const PICKET_SPACING := 0.16
const PICKET_WIDTH := 0.12
const POST_WIDTH := 0.12
const RAIL_Y_TOP := 0.675
const RAIL_Y_BOT := 0.175
const MIN_RUN_LENGTH := 0.5
const SNAP_RADIUS := 0.6

const DEFAULT_POST_SPACING := 2.36
const MIN_POST_SPACING := 0.8
const MAX_POST_SPACING := 6.0

var _fences: Array = []
var _terrain: Node3D = null
var _post_mesh: Mesh = null
var _picket_mesh: Mesh = null
var _rail_mesh: Mesh = null

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
	_post_mesh = _load_first_mesh(POST_GLB)
	_picket_mesh = _load_first_mesh(PICKET_GLB)
	_rail_mesh = _load_first_mesh(RAIL_GLB)
	_visuals_root = Node3D.new()
	_visuals_root.name = "FenceVisuals"
	add_child(_visuals_root)
	_ghost_root = Node3D.new()
	_ghost_root.name = "FenceGhost"
	add_child(_ghost_root)

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
	for f in _fences:
		_build_segment(_visuals_root, f.start, f.end, f.post_spacing, false)

func _refresh_ghost() -> void:
	_clear_ghost()
	if not _drag_active:
		return
	_build_segment(_ghost_root, _drag_start, _drag_end, _drag_spacing, true)

func _clear_ghost() -> void:
	for c in _ghost_root.get_children():
		c.queue_free()

func _build_segment(root: Node3D, start: Vector3, end: Vector3, post_spacing: float, ghost: bool) -> void:
	var delta: Vector3 = end - start
	delta.y = 0.0
	var L: float = delta.length()
	if L < MIN_RUN_LENGTH:
		return
	var forward: Vector3 = delta.normalized()
	var n_intervals: int = max(1, int(round(L / post_spacing)))
	var actual_spacing: float = L / n_intervals
	# Posts
	for i in range(n_intervals + 1):
		var pw: Vector3 = start + forward * (i * actual_spacing)
		pw.y = _ground_y(pw)
		_spawn_post(root, pw, forward, ghost)
		if not ghost:
			_post_positions.append(pw)
	# Per-interval pickets + 2 rails
	for i in range(n_intervals):
		var p_start: Vector3 = start + forward * (i * actual_spacing)
		var p_end: Vector3 = start + forward * ((i + 1) * actual_spacing)
		p_start.y = _ground_y(p_start)
		p_end.y = _ground_y(p_end)
		_build_interval(root, p_start, p_end, forward, ghost)

func _build_interval(root: Node3D, p_start: Vector3, p_end: Vector3, forward: Vector3, ghost: bool) -> void:
	var span: float = p_start.distance_to(p_end)
	var gap: float = span - POST_WIDTH
	# Pickets: integer count fitting at PICKET_SPACING centers within the
	# clear gap between post inner faces.
	if gap > PICKET_WIDTH + 0.02:
		var n_pickets: int = max(0, int(floor((gap - PICKET_WIDTH) / PICKET_SPACING)) + 1)
		if n_pickets > 0:
			var total_span: float = (n_pickets - 1) * PICKET_SPACING
			var margin: float = (gap - total_span) * 0.5
			var picket_origin: Vector3 = p_start + forward * (POST_WIDTH * 0.5 + margin)
			for i in range(n_pickets):
				var pw: Vector3 = picket_origin + forward * (i * PICKET_SPACING)
				pw.y = _ground_y(pw)
				_spawn_picket(root, pw, forward, ghost)
	# Rails: 2 rails (top + bottom) spanning post-outer-edge to post-outer-edge
	var rail_origin: Vector3 = p_start - forward * (POST_WIDTH * 0.5)
	var rail_length: float = span + POST_WIDTH
	for ry in [RAIL_Y_BOT, RAIL_Y_TOP]:
		var rp: Vector3 = rail_origin
		rp.y = _ground_y(rp) + ry
		_spawn_rail(root, rp, forward, rail_length, ghost)

func _spawn_post(root: Node3D, world_pos: Vector3, forward: Vector3, ghost: bool) -> void:
	_spawn(root, _post_mesh, world_pos, _yaw_basis(forward), ghost)

func _spawn_picket(root: Node3D, world_pos: Vector3, forward: Vector3, ghost: bool) -> void:
	# Picket cross-faces sit perpendicular to the run. Rotate so local +X
	# of the picket aligns with the forward direction (picket's natural
	# wide-face axis is +X in the exported glb).
	_spawn(root, _picket_mesh, world_pos, _yaw_basis(forward), ghost)

func _spawn_rail(root: Node3D, world_pos: Vector3, forward: Vector3, length: float, ghost: bool) -> void:
	if _rail_mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _rail_mesh
	mi.position = world_pos
	mi.basis = _yaw_basis(forward).scaled(Vector3(length, 1.0, 1.0))
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
