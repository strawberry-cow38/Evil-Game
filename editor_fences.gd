extends Node3D

# Fence authoring module owned by the editor. A fence is a straight run
# defined by two world-space endpoints + a post spacing. Posts get
# placed at every `post_spacing` metres along the run (snapped so an
# integer count of intervals fits exactly between the endpoints), with
# pickets + rails filling each interval.
#
# Modifier rules while dragging:
#   none           — end snaps to nearest existing post, then to nearest
#                    point on any existing fence line within SNAP_RADIUS
#   shift          — angle from start snaps to nearest 15°
#   ctrl           — length snaps to integer multiples of post_spacing
#   shift+ctrl     — both
#   alt            — all snapping off
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
		"wall_height": 1.0,
		"wall_thickness": 0.18,
	},
	"tall_brown": {
		"post_glb": "res://assets/models/tall_fence_post.glb",
		"picket_glb": "res://assets/models/tall_fence_board.glb",
		"rail_glb": "res://assets/models/tall_fence_rail.glb",
		"picket_spacing": 0.10,  # boards touch
		"post_width": 0.14,
		"rails": [0.30, 1.30],
		"picket_random": false,
		"wall_height": 1.7,
		"wall_thickness": 0.20,
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
		"wall_height": 1.5,
		"wall_thickness": 0.30,
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
		"wall_height": 0.95,
		"wall_thickness": 0.30,
	},
}

const MIN_RUN_LENGTH := 0.5
const SNAP_RADIUS := 0.6
# Perpendicular distance from cursor to an existing fence line within
# which line-snap engages and snaps the cursor onto that run's nearest
# post slot. Generous so the user only has to be vaguely near the line.
const LINE_SNAP_RADIUS := 1.4
# Click-anywhere-on-a-fence radius for the per-section eraser. Measured
# from the cursor to the fence line, regardless of which segment.
const DELETE_LINE_RADIUS := 1.8

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
# Off in the editor (would obstruct camera + raycasts), opt-in in play mode.
var _collision_enabled: bool = false

var _drag_active: bool = false
var _drag_start: Vector3 = Vector3.ZERO
var _drag_end: Vector3 = Vector3.ZERO
var _drag_spacing: float = DEFAULT_POST_SPACING
# Anchor forwards captured when an endpoint snaps to an existing fence
# line. Used at rebuild time to rotate the merged post to match the
# fence we're joining onto (zero vector = no anchor / free rotation).
var _drag_start_anchor: Vector3 = Vector3.ZERO
var _drag_end_anchor: Vector3 = Vector3.ZERO
# Set by _maybe_snap as a side-channel: forward of the line snapped onto,
# Vector3.ZERO if no line snap engaged on the latest call.
var _last_snap_anchor: Vector3 = Vector3.ZERO

var _visuals_root: Node3D = null
var _ghost_root: Node3D = null
var _snap_hint_root: Node3D = null
var _snap_hint_material: StandardMaterial3D = null

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
	_snap_hint_root = Node3D.new()
	_snap_hint_root.name = "FenceSnapHints"
	_snap_hint_root.visible = false
	add_child(_snap_hint_root)
	_snap_hint_material = StandardMaterial3D.new()
	_snap_hint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snap_hint_material.albedo_color = Color(1.0, 0.95, 0.35, 0.55)
	_snap_hint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func set_variant(name: String) -> void:
	if VARIANTS.has(name):
		_active_variant = name

func enable_collision(b: bool) -> void:
	_collision_enabled = b
	_rebuild_all()

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

func begin_drag(world_pos: Vector3, alt: bool, shift: bool, post_spacing: float, ctrl: bool = false) -> void:
	_drag_active = true
	_drag_spacing = clampf(post_spacing, MIN_POST_SPACING, MAX_POST_SPACING)
	# Shift / ctrl are end-relative-to-start constraints — they don't apply
	# to the start point itself. Only alt suppresses snapping on begin.
	_drag_start = _maybe_snap(world_pos, alt)
	_drag_start_anchor = _last_snap_anchor
	_drag_end_anchor = Vector3.ZERO
	_drag_end = _drag_start
	_refresh_ghost()

func update_drag(world_pos: Vector3, alt: bool, shift: bool, post_spacing: float, ctrl: bool = false) -> void:
	if not _drag_active:
		return
	_drag_spacing = clampf(post_spacing, MIN_POST_SPACING, MAX_POST_SPACING)
	_drag_end = _resolve_end(world_pos, alt, shift, ctrl)
	_refresh_ghost()

func commit_drag(world_pos: Vector3, alt: bool, shift: bool, post_spacing: float, ctrl: bool = false) -> void:
	if not _drag_active:
		return
	_drag_spacing = clampf(post_spacing, MIN_POST_SPACING, MAX_POST_SPACING)
	_drag_end = _resolve_end(world_pos, alt, shift, ctrl)
	var dist: float = _drag_start.distance_to(_drag_end)
	if dist >= MIN_RUN_LENGTH:
		_fences.append({
			"start": _drag_start,
			"end": _drag_end,
			"post_spacing": _drag_spacing,
			"variant": _active_variant,
			"start_anchor": _drag_start_anchor,
			"end_anchor": _drag_end_anchor,
		})
		fence_state_changed.emit()
	_drag_active = false
	_drag_start_anchor = Vector3.ZERO
	_drag_end_anchor = Vector3.ZERO
	_clear_ghost()
	_rebuild_all()

func _resolve_end(world_pos: Vector3, alt: bool, shift: bool, ctrl: bool) -> Vector3:
	# alt: freehand, no snap at all.
	# shift: angle-only snap (15° increments around start).
	# ctrl:  distance-only snap (integer multiples of post_spacing).
	# none of the above: snap end to nearest existing fence line/post.
	_drag_end_anchor = Vector3.ZERO
	if alt:
		return world_pos
	if shift or ctrl:
		return _modifier_snap(_drag_start, world_pos, shift, ctrl, _drag_spacing)
	var end_pos: Vector3 = _maybe_snap(world_pos, false)
	_drag_end_anchor = _last_snap_anchor
	return end_pos

func cancel_drag() -> void:
	_drag_active = false
	_clear_ghost()

func update_hover(world_pos: Vector3, alt: bool, shift: bool, post_spacing: float, ctrl: bool = false) -> void:
	# Pre-click ghost: a single post at the hover position + a ring on the
	# ground when the hover landed on an existing post via hard snap.
	if _drag_active:
		return
	_clear_ghost()
	var spacing: float = clampf(post_spacing, MIN_POST_SPACING, MAX_POST_SPACING)
	var snapped: Vector3 = _maybe_snap(world_pos, alt)
	# Snap engaged iff the snap actually moved the cursor onto an existing post.
	var snap_hit: bool = (snapped != world_pos) and _post_position_taken(snapped)
	snapped.y = _ground_y(snapped)
	# Forward direction for the ghost post is meaningless before the first
	# click, so use world +X to give the post a stable yaw.
	var forward := Vector3(1, 0, 0)
	var variant: Dictionary = VARIANTS[_active_variant]
	_spawn_post(_ghost_root, snapped, forward, variant, true)
	if snap_hit:
		_spawn_snap_ring(snapped)

func clear_hover() -> void:
	if _drag_active:
		return
	_clear_ghost()

func _modifier_snap(start: Vector3, end: Vector3, shift: bool, ctrl: bool, spacing: float) -> Vector3:
	# Independent snaps: shift = angle (15°), ctrl = length (multiple of spacing).
	var d: Vector3 = end - start
	d.y = 0.0
	var L: float = d.length()
	if L < 0.001:
		return start
	var ang: float = atan2(d.z, d.x)
	if shift:
		var step: float = deg_to_rad(15.0)
		ang = round(ang / step) * step
	if ctrl:
		var n: int = max(1, int(round(L / spacing)))
		L = n * spacing
	var out: Vector3 = start + Vector3(cos(ang), 0.0, sin(ang)) * L
	out.y = _ground_y(out)
	return out

func _build_snap_hint(start: Vector3, end: Vector3) -> void:
	var delta: Vector3 = end - start
	delta.y = 0.0
	var L: float = delta.length()
	if L < 0.01:
		return
	var forward: Vector3 = delta.normalized()
	var mid: Vector3 = start + forward * (L * 0.5)
	mid.y = _ground_y(mid) + 0.015  # nudge above ground to avoid z-fighting
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.005, 0.06)  # flat strip 6cm wide
	box.material = _snap_hint_material
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = mid
	mi.basis = _yaw_basis(forward).scaled_local(Vector3(L, 1.0, 1.0))
	_snap_hint_root.add_child(mi)

func _spawn_snap_ring(world_pos: Vector3) -> void:
	# Flat torus on the ground marking that the hover snapped to a post.
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.44
	tm.ring_segments = 6
	tm.rings = 32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.35, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	# Torus default axis = +Y in Godot, so it already lies flat. Lift 2cm
	# above ground to avoid z-fighting.
	mi.position = world_pos + Vector3(0, 0.02, 0)
	_ghost_root.add_child(mi)

func _maybe_snap(world_pos: Vector3, alt: bool) -> Vector3:
	# Post snap wins over line snap (sharper feedback). Alt suppresses both.
	# Sets `_last_snap_anchor` to the snapped line's forward when line-snap
	# engages so the caller can record an anchor direction.
	_last_snap_anchor = Vector3.ZERO
	if alt:
		return world_pos
	var nearest_post: Vector3 = _nearest_post(world_pos, SNAP_RADIUS)
	if nearest_post != Vector3.INF:
		# Recover the run that owns this post — gives us the anchor forward
		# so a junction's merged post inherits the existing run's rotation.
		_last_snap_anchor = _forward_at(nearest_post)
		return nearest_post
	var line_hit: Dictionary = _nearest_line_slot(world_pos, LINE_SNAP_RADIUS)
	if not line_hit.is_empty():
		_last_snap_anchor = line_hit["forward"]
		return line_hit["pos"]
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

func _nearest_line_slot(world: Vector3, radius: float) -> Dictionary:
	# Snap engages on perpendicular distance to the run's line (so the user
	# only has to be near the line, not near a slot). Result is the nearest
	# post slot on that run, which butts cleanly into the existing grid.
	var best_pos: Vector3 = Vector3.INF
	var best_fwd: Vector3 = Vector3.ZERO
	var best_d: float = radius
	var wxz := Vector3(world.x, 0.0, world.z)
	for f in _fences:
		var a: Vector3 = Vector3(f.start.x, 0.0, f.start.z)
		var b: Vector3 = Vector3(f.end.x,   0.0, f.end.z)
		var ab: Vector3 = b - a
		var L: float = ab.length()
		if L < 0.0001:
			continue
		var raw_t: float = clampf((wxz - a).dot(ab) / (L * L), 0.0, 1.0)
		var line_pt: Vector3 = a + ab * raw_t
		var d_line: float = line_pt.distance_to(wxz)
		if d_line >= best_d:
			continue
		best_d = d_line
		var spacing: float = float(f.get("post_spacing", DEFAULT_POST_SPACING))
		var n_intervals: int = max(1, int(round(L / spacing)))
		var slot_idx: int = clampi(int(round(raw_t * n_intervals)), 0, n_intervals)
		var slot_t: float = float(slot_idx) / float(n_intervals)
		var p: Vector3 = a + ab * slot_t
		best_pos = Vector3(p.x, world.y, p.z)
		best_fwd = (ab / L)
	if best_pos == Vector3.INF:
		return {}
	return {"pos": best_pos, "forward": best_fwd}

func _forward_at(world_post: Vector3) -> Vector3:
	# Returns the forward of any fence whose endpoint coincides with the
	# given world-space post position. Used to anchor a snapped post to the
	# direction of the run we're joining onto.
	for f in _fences:
		if Vector3(f.start.x, 0.0, f.start.z).distance_to(Vector3(world_post.x, 0.0, world_post.z)) < POST_DEDUP_RADIUS:
			return _segment_forward(f)
		if Vector3(f.end.x, 0.0, f.end.z).distance_to(Vector3(world_post.x, 0.0, world_post.z)) < POST_DEDUP_RADIUS:
			return _segment_forward(f)
		# Also check interior slot positions for very long runs.
		var a := Vector3(f.start.x, 0.0, f.start.z)
		var b := Vector3(f.end.x,   0.0, f.end.z)
		var L := (b - a).length()
		if L < 0.0001:
			continue
		var spacing: float = float(f.get("post_spacing", DEFAULT_POST_SPACING))
		var n_intervals: int = max(1, int(round(L / spacing)))
		for i in range(1, n_intervals):
			var p := a + (b - a) * (float(i) / float(n_intervals))
			if p.distance_to(Vector3(world_post.x, 0.0, world_post.z)) < POST_DEDUP_RADIUS:
				return _segment_forward(f)
	return Vector3.ZERO

func _segment_forward(f: Dictionary) -> Vector3:
	var d: Vector3 = Vector3(f.end.x, 0.0, f.end.z) - Vector3(f.start.x, 0.0, f.start.z)
	if d.length_squared() < 0.0001:
		return Vector3.ZERO
	return d.normalized()

func delete_section_at(world_pos: Vector3, radius: float = DELETE_LINE_RADIUS) -> bool:
	# Find the run whose line is closest to `world_pos` (perp distance),
	# pick the segment under the projected point, replace the run with up to
	# two sub-runs covering the portions before/after the deleted segment.
	var wxz := Vector3(world_pos.x, 0.0, world_pos.z)
	var best_i: int = -1
	var best_seg: int = -1
	var best_n: int = 0
	var best_d: float = radius
	for i in range(_fences.size()):
		var f: Dictionary = _fences[i]
		var a: Vector3 = Vector3(f.start.x, 0.0, f.start.z)
		var b: Vector3 = Vector3(f.end.x,   0.0, f.end.z)
		var ab: Vector3 = b - a
		var L: float = ab.length()
		if L < 0.0001:
			continue
		var raw_t: float = clampf((wxz - a).dot(ab) / (L * L), 0.0, 1.0)
		var line_pt: Vector3 = a + ab * raw_t
		var d: float = line_pt.distance_to(wxz)
		if d >= best_d:
			continue
		var spacing: float = float(f.get("post_spacing", DEFAULT_POST_SPACING))
		var n_intervals: int = max(1, int(round(L / spacing)))
		best_d = d
		best_i = i
		best_seg = clampi(int(raw_t * n_intervals), 0, n_intervals - 1)
		best_n = n_intervals
	if best_i < 0:
		return false
	var orig: Dictionary = _fences[best_i]
	var seg_a: Vector3 = orig.start.lerp(orig.end, float(best_seg) / float(best_n))
	var seg_b: Vector3 = orig.start.lerp(orig.end, float(best_seg + 1) / float(best_n))
	_fences.remove_at(best_i)
	var insert_at: int = best_i
	if best_seg > 0:
		var pre: Dictionary = orig.duplicate(true)
		pre["start"] = orig.start
		pre["end"] = seg_a
		pre["end_anchor"] = Vector3.ZERO
		_fences.insert(insert_at, pre)
		insert_at += 1
	if best_seg < best_n - 1:
		var post: Dictionary = orig.duplicate(true)
		post["start"] = seg_b
		post["end"] = orig.end
		post["start_anchor"] = Vector3.ZERO
		_fences.insert(insert_at, post)
	fence_state_changed.emit()
	_rebuild_all()
	return true

func set_snap_hint_visible(b: bool) -> void:
	if _snap_hint_root != null:
		_snap_hint_root.visible = b

func _rebuild_all() -> void:
	for c in _visuals_root.get_children():
		c.queue_free()
	for c in _snap_hint_root.get_children():
		c.queue_free()
	_post_positions.clear()
	# Collect every post (position + the run's forward + variant) across
	# all fences, then collapse overlapping posts at shared corners. Without
	# this, two runs meeting at a snapped endpoint stack two posts at the
	# same world position rotated differently — visible mess.
	var entries: Array = []
	for f in _fences:
		var sa: Vector3 = f.get("start_anchor", Vector3.ZERO)
		var ea: Vector3 = f.get("end_anchor", Vector3.ZERO)
		_collect_segment_posts(f.start, f.end, f.post_spacing, _variant_for(f), entries, sa, ea)
	for cl in _cluster_posts(entries):
		var pw: Vector3 = cl["pos"]
		pw.y = _ground_y(pw)
		_spawn_post(_visuals_root, pw, cl["forward"], cl["variant"], false)
		_post_positions.append(pw)
	# Pickets + rails are per-interval and never overlap across runs, so
	# they can run independently per segment.
	for f in _fences:
		_build_intervals(_visuals_root, f.start, f.end, f.post_spacing, _variant_for(f), false)
	# Snap-hint flat lines on the ground beneath every committed run so the
	# user can see where their next drag can branch off.
	for f in _fences:
		_build_snap_hint(f.start, f.end)

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

func _collect_segment_posts(start: Vector3, end: Vector3, post_spacing: float, variant: Dictionary, out_entries: Array, start_anchor: Vector3 = Vector3.ZERO, end_anchor: Vector3 = Vector3.ZERO) -> void:
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
		# First / last post inherit the anchor forward when snapped onto an
		# existing run so the merged post rotates to match it.
		var fwd: Vector3 = forward
		if i == 0 and start_anchor != Vector3.ZERO:
			fwd = start_anchor
		elif i == n_intervals and end_anchor != Vector3.ZERO:
			fwd = end_anchor
		out_entries.append({"pos": pw, "forward": fwd, "variant": variant})

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
		# Group entries by approximately-equal forward (dot ≈ ±1). The most
		# populous group wins so a T-junction post inherits the through-line's
		# rotation; ties fall back to whichever entry is closer to axis-aligned.
		var groups: Array = []
		for e in cl["entries"]:
			var matched: bool = false
			for g in groups:
				if absf((g["forward"] as Vector3).dot(e["forward"])) > 0.985:
					g["count"] += 1
					matched = true
					break
			if not matched:
				groups.append({"forward": e["forward"], "count": 1, "sample": e})
		var best_group: Dictionary = groups[0]
		for g in groups:
			if g["count"] > best_group["count"] or (g["count"] == best_group["count"] and _cardinality(g["forward"]) > _cardinality(best_group["forward"])):
				best_group = g
		var sample: Dictionary = best_group["sample"]
		out.append({"pos": cl["pos"], "forward": sample["forward"], "variant": sample["variant"]})
	return out

func _cardinality(f: Vector3) -> float:
	# 1.0 for perfectly axis-aligned, 0.0 for 45deg diagonal.
	return absf(absf(f.x) - absf(f.z))

func _attach_collider(root: Node3D, mesh: Mesh, world_pos: Vector3, basis: Basis) -> void:
	# Per-element AABB collider: one BoxShape3D sized to the spawned mesh's
	# world-space bounds. Bullets / raycasts that pass between pickets, over
	# rails, or through the gap on a beam fence cleanly miss every body.
	if mesh == null:
		return
	var aabb: AABB = mesh.get_aabb()
	var scale_vec: Vector3 = basis.get_scale()
	# Drop scale from the basis so the StaticBody3D stays unit-scaled and we
	# apply the scale to the box size + center offset directly (avoids the
	# physics-server warnings Godot logs for scaled bodies).
	var ortho := Basis(basis.x.normalized(), basis.y.normalized(), basis.z.normalized())
	var center_local: Vector3 = aabb.get_center() * scale_vec
	var center_world: Vector3 = world_pos + ortho * center_local
	var size: Vector3 = aabb.size * scale_vec
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	var body := StaticBody3D.new()
	body.position = center_world
	body.basis = ortho
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)

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
	# scaled_local (right-multiply) stretches the rail's local +X by length.
	var basis: Basis = _yaw_basis(forward).scaled_local(Vector3(length, 1.0, 1.0))
	_spawn(root, mesh, world_pos, basis, ghost)

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
	if _collision_enabled and not ghost:
		_attach_collider(root, mesh, world_pos, basis)

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
