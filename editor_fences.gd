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
# Extra pull radius around real post positions on the picket grid. When
# the cursor is within this world-space distance of a post, the picket
# slot is overridden to the post slot — biases snapping toward posts
# over pickets without removing picket snap entirely.
const POST_PULL_RADIUS := 0.75
# Click-anywhere-on-a-fence radius for the per-section eraser. Measured
# from the cursor to the fence line, regardless of which segment.
const DELETE_LINE_RADIUS := 1.8

const DEFAULT_POST_SPACING := 2.36
const MIN_POST_SPACING := 0.8
const MAX_POST_SPACING := 6.0
# Two posts within this radius collapse into one. Snap radius is much
# larger so two snapped endpoints will always cluster here.
const POST_DEDUP_RADIUS := 0.05

# Physics layers (1-indexed in the editor UI).
#   Layer 6 — smooth wall box for player collision. Bullets ignore.
#   Layer 7 — per-element AABB boxes matching each post/picket/rail. The
#             player ignores so it doesn't catch on every picket and
#             jitter; bullets / raycasts use this for precise hits.
const WALL_COLLISION_LAYER: int = 1 << 5
const DETAIL_COLLISION_LAYER: int = 1 << 6

# Per-segment tunables. Defaults applied wherever the segment dict is
# missing a key — store overrides only.
const SEG_DEFAULTS := {
	"destructible": false,
	"respawn_time": 10.0,
	"wallbang": false,
}
# Per-variant overrides for segment defaults — applied on top of SEG_DEFAULTS
# but below an explicit per-segment override stored on the fence. Picket and
# tall_brown ship destructible + wallbang on by default; logs stay solid.
const VARIANT_SEG_DEFAULTS := {
	"picket":     {"destructible": true, "wallbang": true},
	"tall_brown": {"destructible": true, "wallbang": true},
}
# Group every picket collider in a destructible segment joins so weapon.gd
# can detect a fence-picket hit and route it back to this node.
const PICKET_GROUP := "fence_picket_destructible"
# Rail sub-pieces in a destructible segment land in this group so bullet
# decals can parent to them — same cleanup story as pickets, but rails
# don't take "damage" so they stay out of PICKET_GROUP.
const RAIL_GROUP := "fence_rail_destructible"

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
var _debris_root: Node3D = null
var _snap_hint_material: StandardMaterial3D = null
# Active debris pieces — { mi, vel, spin_axis, spin_speed, life, max_life }.
var _debris: Array = []
const DEBRIS_LIFE := 1.8
const DEBRIS_GRAVITY := 9.8
# When this fraction of a segment's pickets is destroyed, the smooth wall
# collider for that segment is freed (player can walk through) and the
# affected rail sub-pieces are hidden.
const SEG_BREACH_RATIO := 0.4

# Live damage state per segment in play mode.
#   key = "%d_%d" % [fence_idx, seg_idx]
#   val = {
#     destroyed: {pi: true},
#     hidden_pickets: {pi: {body, mi}},
#     hidden_rails:   {instance_id: {mesh, body}},
#     breached: bool,
#     timer: Timer (or null),
#     respawn_time: float,
#     wall_props: {pos: Vector3, basis: Basis, size: Vector3} or null,
#   }
# One respawn Timer per segment. Every fresh hit restarts it so the
# whole section comes back together once the LAST damage settles.
var _segment_state: Dictionary = {}
# Wall collider StaticBody3D per segment, keyed the same way.
var _wall_bodies: Dictionary = {}
# Per-segment Node3D holder that owns every picket + rail node spawned for
# the interval. Tearing this down on respawn nukes the whole segment cleanly
# (visuals + bodies + any decals parented to them) so the rebuilt version
# never inherits partial-damage state.
var _segment_holders: Dictionary = {}

# Cached world positions of every post placed so far — drives hard snap.
var _post_positions: Array = []

# Edit-mode selection — fence index + segment (interval) index within
# that run, or -1/-1 if nothing selected.
var _selected_fence: int = -1
var _selected_seg: int = -1
var _select_highlight: MeshInstance3D = null
var _select_material: StandardMaterial3D = null

signal segment_selected(props: Dictionary)
signal selection_cleared()

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
	_debris_root = Node3D.new()
	_debris_root.name = "FenceDebris"
	add_child(_debris_root)
	_snap_hint_material = StandardMaterial3D.new()
	_snap_hint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snap_hint_material.albedo_color = Color(1.0, 0.95, 0.35, 0.55)
	_snap_hint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_select_material = StandardMaterial3D.new()
	_select_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select_material.albedo_color = Color(0.35, 0.95, 1.0, 0.30)
	_select_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_select_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func set_variant(name: String) -> void:
	if VARIANTS.has(name):
		_active_variant = name

func enable_collision(b: bool) -> void:
	_collision_enabled = b
	# Play-mode tag so weapon.gd can find this node by group lookup when
	# routing picket-hit notifications.
	if b:
		if not is_in_group("fences_runtime"):
			add_to_group("fences_runtime")
	else:
		if is_in_group("fences_runtime"):
			remove_from_group("fences_runtime")
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
	clear_selection()
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
	# Snap engaged iff the line snap returned a forward (i.e. picked up
	# an existing run); _last_snap_anchor is set in _maybe_snap.
	var snap_hit: bool = _last_snap_anchor != Vector3.ZERO
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
	# Line snap quantised to the picket grid is the only snap target — it
	# already lands on post positions when the cursor is near one, plus
	# every picket position in between. Alt suppresses snapping entirely.
	_last_snap_anchor = Vector3.ZERO
	if alt:
		return world_pos
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
	# Snap engages on perpendicular distance to the run's line, then quantises
	# the projection to the picket grid (positions where this run actually
	# places a picket or a post). Variants with no pickets (picket_spacing=0)
	# fall back to the post grid.
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
		var variant: Dictionary = _variant_for(f)
		var post_spacing: float = float(f.get("post_spacing", DEFAULT_POST_SPACING))
		var n_intervals: int = max(1, int(round(L / post_spacing)))
		var actual_post_spacing: float = L / float(n_intervals)
		var picket_spacing: float = float(variant.get("picket_spacing", 0.0))
		var sub_steps: int = 1
		if picket_spacing > 0.0:
			sub_steps = max(1, int(round(actual_post_spacing / picket_spacing)))
		var total_slots: int = n_intervals * sub_steps
		var slot_idx: int = clampi(int(round(raw_t * total_slots)), 0, total_slots)
		var slot_t: float = float(slot_idx) / float(total_slots)
		var p: Vector3 = a + ab * slot_t
		# Heavier pull toward real posts: if the cursor is within
		# POST_PULL_RADIUS of the nearest post slot, override the picket
		# slot with that post slot. Keeps picket snap but lets posts win
		# when the cursor is genuinely near them.
		if sub_steps > 1:
			var post_idx: int = clampi(int(round(float(slot_idx) / float(sub_steps))) * sub_steps, 0, total_slots)
			if post_idx != slot_idx:
				var post_t: float = float(post_idx) / float(total_slots)
				var post_pt: Vector3 = a + ab * post_t
				if post_pt.distance_to(wxz) <= POST_PULL_RADIUS:
					slot_idx = post_idx
					slot_t = post_t
					p = post_pt
		best_d = d_line
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

# --- Segment selection + per-segment props -----------------------------

func get_segment_props(fence_idx: int, seg_idx: int) -> Dictionary:
	# Layer order: SEG_DEFAULTS -> VARIANT_SEG_DEFAULTS[variant] -> per-segment
	# override. Always returns every key.
	var out: Dictionary = SEG_DEFAULTS.duplicate()
	if fence_idx < 0 or fence_idx >= _fences.size():
		return out
	var variant_name: String = _fences[fence_idx].get("variant", "picket")
	if VARIANT_SEG_DEFAULTS.has(variant_name):
		for k in VARIANT_SEG_DEFAULTS[variant_name].keys():
			out[k] = VARIANT_SEG_DEFAULTS[variant_name][k]
	var segs: Dictionary = _fences[fence_idx].get("segments", {})
	var key: String = str(seg_idx)
	if segs.has(key):
		for k in segs[key].keys():
			out[k] = segs[key][k]
	return out

func set_segment_prop(fence_idx: int, seg_idx: int, key: String, value) -> void:
	if fence_idx < 0 or fence_idx >= _fences.size():
		return
	if not _fences[fence_idx].has("segments"):
		_fences[fence_idx]["segments"] = {}
	var segs: Dictionary = _fences[fence_idx]["segments"]
	var k: String = str(seg_idx)
	if not segs.has(k):
		segs[k] = {}
	segs[k][key] = value
	fence_state_changed.emit()
	_rebuild_all()  # _rebuild_all restores selection highlight

func _segment_at(world_pos: Vector3, radius: float) -> Dictionary:
	# Mirrors delete_section_at hit-test. Returns {fence, seg} or {} if no hit.
	var wxz := Vector3(world_pos.x, 0.0, world_pos.z)
	var best_i: int = -1
	var best_seg: int = -1
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
		var d: float = (a + ab * raw_t).distance_to(wxz)
		if d >= best_d:
			continue
		var spacing: float = float(f.get("post_spacing", DEFAULT_POST_SPACING))
		var n_intervals: int = max(1, int(round(L / spacing)))
		best_d = d
		best_i = i
		best_seg = clampi(int(raw_t * n_intervals), 0, n_intervals - 1)
	if best_i < 0:
		return {}
	return {"fence": best_i, "seg": best_seg}

func select_segment_at(world_pos: Vector3, radius: float = DELETE_LINE_RADIUS) -> Dictionary:
	var hit: Dictionary = _segment_at(world_pos, radius)
	if hit.is_empty():
		clear_selection()
		return {}
	_selected_fence = hit["fence"]
	_selected_seg = hit["seg"]
	_update_selection_highlight()
	var props: Dictionary = get_segment_props(_selected_fence, _selected_seg)
	props["fence"] = _selected_fence
	props["seg"] = _selected_seg
	segment_selected.emit(props)
	return props

func clear_selection() -> void:
	_selected_fence = -1
	_selected_seg = -1
	if _select_highlight != null:
		_select_highlight.queue_free()
		_select_highlight = null
	selection_cleared.emit()

func get_selection() -> Dictionary:
	if _selected_fence < 0:
		return {}
	return {"fence": _selected_fence, "seg": _selected_seg}

func _update_selection_highlight() -> void:
	if _select_highlight != null:
		_select_highlight.queue_free()
		_select_highlight = null
	if _selected_fence < 0 or _selected_fence >= _fences.size():
		return
	var f: Dictionary = _fences[_selected_fence]
	var a: Vector3 = f.start
	var b: Vector3 = f.end
	var delta: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
	var L: float = delta.length()
	if L < 0.0001:
		return
	var forward: Vector3 = delta.normalized()
	var spacing: float = float(f.get("post_spacing", DEFAULT_POST_SPACING))
	var n: int = max(1, int(round(L / spacing)))
	var seg_len: float = L / float(n)
	var ps: Vector3 = a + forward * (_selected_seg * seg_len)
	var pe: Vector3 = a + forward * ((_selected_seg + 1) * seg_len)
	ps.y = _ground_y(ps)
	pe.y = _ground_y(pe)
	var variant: Dictionary = _variant_for(f)
	var height: float = float(variant.get("wall_height", 1.0)) + 0.20
	var thickness: float = float(variant.get("wall_thickness", 0.20)) + 0.10
	var mid: Vector3 = (ps + pe) * 0.5
	mid.y += height * 0.5
	var box := BoxMesh.new()
	box.size = Vector3(seg_len, height, thickness)
	box.material = _select_material
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = mid
	mi.basis = _yaw_basis(forward)
	_visuals_root.add_child(mi)
	_select_highlight = mi

# --- Play-mode picket destruction -------------------------------------

func notify_picket_hit(body: Node, hit_pos: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.UP) -> void:
	# Called by weapon.gd when a bullet ray hits a picket collider that's
	# part of a destructible segment. Spawns a flung debris piece, frees any
	# bullet-hole decals parented to the body, hides the picket mesh +
	# collider, then arms the segment-wide respawn timer.
	if body == null or not body.has_meta("picket_mesh_ref"):
		return
	var mi: MeshInstance3D = body.get_meta("picket_mesh_ref")
	if mi == null or not is_instance_valid(mi) or not mi.visible:
		return
	var fence_idx: int = int(body.get_meta("fence_idx", -1))
	var seg_idx: int = int(body.get_meta("seg_idx", -1))
	var picket_index: int = int(body.get_meta("picket_index", -1))
	var n_seg: int = int(body.get_meta("n_pickets_in_seg", 0))
	if fence_idx < 0 or seg_idx < 0 or n_seg <= 0:
		return
	var seg_key: String = "%d_%d" % [fence_idx, seg_idx]
	var state: Dictionary = _ensure_segment_state(seg_key, body)
	_spawn_debris(mi.mesh, mi.global_position, mi.basis, hit_normal)
	_spawn_picket_stub(seg_key, mi)
	_hide_picket(body, mi, picket_index, state)
	if not state["breached"]:
		var ratio: float = float(state["destroyed"].size()) / float(n_seg)
		if ratio >= SEG_BREACH_RATIO:
			state["breached"] = true
			_free_segment_wall(seg_key)
			_collapse_segment(seg_key, hit_normal)
	_segment_respawn_timer_reset(seg_key)

func _ensure_segment_state(seg_key: String, body: Node) -> Dictionary:
	if not _segment_state.has(seg_key):
		_segment_state[seg_key] = {
			"destroyed": {},
			"breached": false,
			"timer": null,
			"respawn_time": float(body.get_meta("respawn_time", 10.0)),
		}
	return _segment_state[seg_key]

func _hide_picket(body: Node, mi: MeshInstance3D, picket_index: int, state: Dictionary) -> void:
	# Hide the picket mesh + disable its body. The respawn path nukes the
	# whole segment holder so we don't need to retain refs here — just mark
	# the picket destroyed for the breach-threshold count.
	for c in body.get_children():
		if c is MeshInstance3D:
			c.queue_free()
	mi.visible = false
	if body is CollisionObject3D:
		(body as CollisionObject3D).process_mode = Node.PROCESS_MODE_DISABLED
	body.visible = false
	state["destroyed"][picket_index] = true

func _hide_rail(rail_mesh: MeshInstance3D, rail_body: Node) -> void:
	if rail_mesh == null or not is_instance_valid(rail_mesh):
		return
	rail_mesh.visible = false
	if rail_body != null and is_instance_valid(rail_body):
		for c in rail_body.get_children():
			if c is MeshInstance3D:
				c.queue_free()

func _segment_respawn_timer_reset(seg_key: String) -> void:
	# (Re)start the per-segment Timer so the wait counts from the LAST hit.
	# One Timer per segment, parented to self so it survives picket
	# disables and dies cleanly on scene unload.
	if not _segment_state.has(seg_key):
		return
	var state: Dictionary = _segment_state[seg_key]
	var timer: Timer = state.get("timer", null)
	var wait: float = float(state["respawn_time"])
	if timer == null or not is_instance_valid(timer):
		timer = Timer.new()
		timer.one_shot = true
		add_child(timer)
		var sk_capture: String = seg_key
		timer.timeout.connect(func() -> void: _respawn_segment(sk_capture))
		state["timer"] = timer
	timer.stop()
	timer.wait_time = wait
	timer.start()

func _respawn_segment(seg_key: String) -> void:
	# Full teardown + rebuild. Frees the segment's Node3D holder (taking
	# every picket, rail, body, and decal child with it) and the wall
	# collider, then rebuilds the interval from the fence's stored params.
	# Guarantees the respawned segment has zero stale state.
	if not _segment_state.has(seg_key):
		return
	var parts: PackedStringArray = seg_key.split("_")
	if parts.size() < 2:
		_drop_segment_state(seg_key)
		return
	var fi: int = int(parts[0])
	var si: int = int(parts[1])
	if fi < 0 or fi >= _fences.size():
		_drop_segment_state(seg_key)
		return
	var holder: Node = _segment_holders.get(seg_key, null)
	if holder != null and is_instance_valid(holder):
		holder.queue_free()
	_segment_holders.erase(seg_key)
	if _wall_bodies.has(seg_key):
		var wb: Node = _wall_bodies[seg_key]
		if wb != null and is_instance_valid(wb):
			wb.queue_free()
		_wall_bodies.erase(seg_key)
	_drop_segment_state(seg_key)
	var f: Dictionary = _fences[fi]
	var delta: Vector3 = f.end - f.start
	delta.y = 0.0
	var L: float = delta.length()
	if L < MIN_RUN_LENGTH:
		return
	var forward: Vector3 = delta.normalized()
	var n_intervals: int = max(1, int(round(L / f.post_spacing)))
	if si >= n_intervals:
		return
	var actual_spacing: float = L / float(n_intervals)
	var p_start: Vector3 = f.start + forward * (si * actual_spacing)
	var p_end: Vector3 = f.start + forward * ((si + 1) * actual_spacing)
	p_start.y = _ground_y(p_start)
	p_end.y = _ground_y(p_end)
	_build_interval(_visuals_root, p_start, p_end, forward, _variant_for(f), false, fi, si)
	if _collision_enabled:
		_spawn_wall_collider_one(fi, si, n_intervals, f, _variant_for(f))

func _drop_segment_state(seg_key: String) -> void:
	if not _segment_state.has(seg_key):
		return
	var timer: Timer = _segment_state[seg_key].get("timer", null)
	if timer != null and is_instance_valid(timer):
		timer.queue_free()
	_segment_state.erase(seg_key)

func _free_segment_wall(seg_key: String) -> void:
	# Drop the player-smoothing wall box for the breached segment so the
	# player can walk through the gap. Per-element picket colliders stay
	# alive on layer 7 — bullets still resolve on the remaining wood. The
	# wall comes back when the respawn timer rebuilds the whole segment.
	if not _wall_bodies.has(seg_key):
		return
	var body: StaticBody3D = _wall_bodies[seg_key]
	if is_instance_valid(body):
		body.queue_free()
	_wall_bodies.erase(seg_key)

func _collapse_segment(seg_key: String, hit_normal: Vector3) -> void:
	# Breach: convert every still-standing picket + every rail sub-piece in
	# this segment into falling debris. The rails get a small outward kick
	# (away from the shooter) plus gravity so they topple toward the player.
	# All hidden refs land in _segment_state so the unified segment respawn
	# can flip them back together.
	if not _segment_state.has(seg_key):
		return
	var state: Dictionary = _segment_state[seg_key]
	var parts: PackedStringArray = seg_key.split("_")
	if parts.size() < 2:
		return
	var sk_fence: int = int(parts[0])
	var sk_seg: int = int(parts[1])
	var rails_seen: Dictionary = {}
	var n: Vector3 = hit_normal
	if n.length_squared() < 0.001:
		n = Vector3(0, 0, -1)
	else:
		n = n.normalized()
	for node in get_tree().get_nodes_in_group(PICKET_GROUP):
		if not (node is StaticBody3D):
			continue
		var b: StaticBody3D = node
		if int(b.get_meta("fence_idx", -1)) != sk_fence:
			continue
		if int(b.get_meta("seg_idx", -1)) != sk_seg:
			continue
		var mi: MeshInstance3D = b.get_meta("picket_mesh_ref", null)
		if mi != null and is_instance_valid(mi) and mi.visible:
			_spawn_collapse_debris(mi.mesh, mi.global_position, mi.basis, -n, 0.6)
			_spawn_picket_stub(seg_key, mi)
			var pi: int = int(b.get_meta("picket_index", -1))
			_hide_picket(b, mi, pi, state)
		# Each picket carries refs to its adjacent rail sub-pieces as
		# {mesh, body} dicts. Dedup via instance id so each rail piece
		# collapses once even though both top+bottom pickets reference it.
		var rails: Array = b.get_meta("adjacent_rails", [])
		for r in rails:
			var rmesh: MeshInstance3D = r.get("mesh", null) if r is Dictionary else null
			var rbody: Node = r.get("body", null) if r is Dictionary else null
			if rmesh == null or not is_instance_valid(rmesh) or not rmesh.visible:
				continue
			var rid: int = rmesh.get_instance_id()
			if rails_seen.has(rid):
				continue
			rails_seen[rid] = true
			_spawn_collapse_debris(rmesh.mesh, rmesh.global_position, rmesh.basis, -n, 1.0)
			_hide_rail(rmesh, rbody)

func _spawn_collapse_debris(mesh: Mesh, world_pos: Vector3, basis: Basis, kick_dir: Vector3, weight: float) -> void:
	# Heavy-collapse variant of _spawn_debris: mostly downward fall with a
	# gentle outward kick + slow tumble, longer life so the rail piece
	# actually hits the ground before fading out.
	if mesh == null or _debris_root == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debris_root.add_child(mi)
	mi.global_position = world_pos
	mi.basis = basis
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var vel: Vector3 = kick_dir.normalized() * rng.randf_range(0.6, 1.6)
	vel.y += rng.randf_range(0.2, 0.8)
	var axis_seed := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 0.2), rng.randf_range(-1.0, 1.0))
	if axis_seed.length_squared() < 0.001:
		axis_seed = Vector3(1, 0, 0)
	var life: float = DEBRIS_LIFE * (1.8 if weight >= 1.0 else 1.3)
	_debris.append({
		"mi": mi,
		"vel": vel,
		"spin_axis": axis_seed.normalized(),
		"spin_speed": rng.randf_range(1.5, 4.5),
		"life": life,
		"max_life": life,
	})

func _spawn_picket_stub(seg_key: String, mi: MeshInstance3D) -> void:
	# Leave a short broken stub where the picket used to stand. Parents under
	# the segment holder so it dies cleanly with the next teardown/rebuild.
	# Y-component of the picket's basis is rescaled to ~18% so the stub is
	# a stumpy bottom slice of the original mesh, anchored at ground level.
	if mi == null or mi.mesh == null:
		return
	var holder: Node = _segment_holders.get(seg_key, null)
	if holder == null or not is_instance_valid(holder):
		return
	const STUB_HEIGHT: float = 0.18
	var stub := MeshInstance3D.new()
	stub.mesh = mi.mesh
	stub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.add_child(stub)
	stub.global_position = mi.global_position
	stub.basis = Basis(mi.basis.x, mi.basis.y * STUB_HEIGHT, mi.basis.z)

func _spawn_debris(mesh: Mesh, world_pos: Vector3, basis: Basis, normal: Vector3) -> void:
	if mesh == null or _debris_root == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debris_root.add_child(mi)
	mi.global_position = world_pos
	mi.basis = basis
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n: Vector3 = normal
	if n.length_squared() < 0.001:
		n = Vector3.UP
	else:
		n = n.normalized()
	# Fling away from the surface + a kick upward + a bit of horizontal scatter.
	var vel: Vector3 = -n * rng.randf_range(3.0, 5.5) + Vector3.UP * rng.randf_range(2.5, 4.0)
	vel.x += rng.randf_range(-1.5, 1.5)
	vel.z += rng.randf_range(-1.5, 1.5)
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if axis.length_squared() < 0.001:
		axis = Vector3.UP
	axis = axis.normalized()
	_debris.append({
		"mi": mi,
		"vel": vel,
		"spin_axis": axis,
		"spin_speed": rng.randf_range(5.0, 12.0),
		"life": DEBRIS_LIFE,
		"max_life": DEBRIS_LIFE,
	})

func _process(dt: float) -> void:
	if _debris.is_empty():
		return
	for i in range(_debris.size() - 1, -1, -1):
		var d: Dictionary = _debris[i]
		var mi: MeshInstance3D = d["mi"]
		if not is_instance_valid(mi):
			_debris.remove_at(i)
			continue
		d["life"] -= dt
		if d["life"] <= 0.0:
			mi.queue_free()
			_debris.remove_at(i)
			continue
		var vel: Vector3 = d["vel"]
		vel.y -= DEBRIS_GRAVITY * dt
		d["vel"] = vel
		mi.global_position += vel * dt
		mi.basis = mi.basis.rotated(d["spin_axis"], d["spin_speed"] * dt)
		# Fade only over the final third of the life so it stays vivid first.
		var t01: float = clampf(d["life"] / d["max_life"], 0.0, 1.0)
		var alpha: float = clampf(t01 / 0.33, 0.0, 1.0)
		mi.transparency = 1.0 - alpha

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
	for fi_e in range(_fences.size()):
		var f: Dictionary = _fences[fi_e]
		var sa: Vector3 = f.get("start_anchor", Vector3.ZERO)
		var ea: Vector3 = f.get("end_anchor", Vector3.ZERO)
		_collect_segment_posts(f.start, f.end, f.post_spacing, _variant_for(f), entries, sa, ea, fi_e)
	for cl in _cluster_posts(entries):
		var pw: Vector3 = cl["pos"]
		pw.y = _ground_y(pw)
		_spawn_post(_visuals_root, pw, cl["forward"], cl["variant"], false, bool(cl.get("wallbang", false)))
		_post_positions.append(pw)
	# Pickets + rails are per-interval and never overlap across runs, so
	# they can run independently per segment.
	for fi in range(_fences.size()):
		var ff: Dictionary = _fences[fi]
		_build_intervals(_visuals_root, ff.start, ff.end, ff.post_spacing, _variant_for(ff), false, fi)
	# Snap-hint flat lines on the ground beneath every committed run so the
	# user can see where their next drag can branch off.
	for f in _fences:
		_build_snap_hint(f.start, f.end)
	for sk in _segment_state.keys():
		var t: Timer = _segment_state[sk].get("timer", null)
		if t != null and is_instance_valid(t):
			t.queue_free()
	_segment_state.clear()
	_wall_bodies.clear()
	_segment_holders.clear()
	if _collision_enabled:
		for fi in range(_fences.size()):
			_spawn_wall_collider(fi, _fences[fi], _variant_for(_fences[fi]))
	# Highlight survives rebuilds while a segment is selected.
	if _selected_fence >= 0:
		_select_highlight = null  # was a child of the freed _visuals_root
		_update_selection_highlight()

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

func _collect_segment_posts(start: Vector3, end: Vector3, post_spacing: float, variant: Dictionary, out_entries: Array, start_anchor: Vector3 = Vector3.ZERO, end_anchor: Vector3 = Vector3.ZERO, fence_idx: int = -1) -> void:
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
		# Wallbang the post if either neighbouring segment opts in. End posts
		# only have one neighbour. Variant-default wallbang still applies if
		# neither neighbour set it explicitly.
		var wb: bool = bool(variant.get("wallbang", false))
		if fence_idx >= 0:
			if i > 0:
				wb = wb or bool(get_segment_props(fence_idx, i - 1).get("wallbang", false))
			if i < n_intervals:
				wb = wb or bool(get_segment_props(fence_idx, i).get("wallbang", false))
		out_entries.append({"pos": pw, "forward": fwd, "variant": variant, "wallbang": wb})

func _build_intervals(root: Node3D, start: Vector3, end: Vector3, post_spacing: float, variant: Dictionary, ghost: bool, fence_idx: int = -1) -> void:
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
		_build_interval(root, p_start, p_end, forward, variant, ghost, fence_idx, i)

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
		# Post wallbang is the OR of every contributing entry — if ANY adjacent
		# segment opted into wallbang, the shared post gets it too.
		var cluster_wb: bool = false
		for e in cl["entries"]:
			if bool(e.get("wallbang", false)):
				cluster_wb = true
				break
		out.append({"pos": cl["pos"], "forward": sample["forward"], "variant": sample["variant"], "wallbang": cluster_wb})
	return out

func _cardinality(f: Vector3) -> float:
	# 1.0 for perfectly axis-aligned, 0.0 for 45deg diagonal.
	return absf(absf(f.x) - absf(f.z))

func _attach_collider(root: Node3D, mesh: Mesh, world_pos: Vector3, basis: Basis) -> StaticBody3D:
	# Per-element AABB collider on DETAIL_COLLISION_LAYER: matches each
	# spawned post / picket / rail tightly so bullets+raycasts hit only the
	# wood. The player does NOT mask this layer (it uses the smooth wall
	# box instead) so it never catches on individual pickets.
	if mesh == null:
		return null
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
		return null
	var body := StaticBody3D.new()
	body.position = center_world
	body.basis = ortho
	body.collision_layer = DETAIL_COLLISION_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	return body

func _spawn_wall_collider(fence_idx: int, f: Dictionary, variant: Dictionary) -> void:
	# Smooth wall box per segment on WALL_COLLISION_LAYER. Sole purpose is to
	# give the player capsule a single flat surface to slide along instead of
	# the bumpy per-picket geometry that causes jitter on movement. Bullets
	# don't mask this layer so they pass straight through to the per-element
	# colliders behind.
	var height: float = float(variant.get("wall_height", 1.0))
	var thickness: float = float(variant.get("wall_thickness", 0.20))
	var spacing: float = float(f.get("post_spacing", DEFAULT_POST_SPACING))
	var delta: Vector3 = f.end - f.start
	delta.y = 0.0
	var L: float = delta.length()
	if L < MIN_RUN_LENGTH:
		return
	var forward: Vector3 = delta.normalized()
	var n_intervals: int = max(1, int(round(L / spacing)))
	var seg_len: float = L / float(n_intervals)
	for i in range(n_intervals):
		var ps: Vector3 = f.start + forward * (i * seg_len)
		var pe: Vector3 = f.start + forward * ((i + 1) * seg_len)
		ps.y = _ground_y(ps)
		pe.y = _ground_y(pe)
		var mid: Vector3 = (ps + pe) * 0.5
		mid.y += height * 0.5
		var body := StaticBody3D.new()
		body.position = mid
		body.basis = _yaw_basis(forward)
		body.collision_layer = WALL_COLLISION_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(seg_len, height, thickness)
		shape.shape = box
		body.add_child(shape)
		_visuals_root.add_child(body)
		var seg_key: String = "%d_%d" % [fence_idx, i]
		body.set_meta("seg_key", seg_key)
		_wall_bodies[seg_key] = body

func _spawn_wall_collider_one(fence_idx: int, seg_idx: int, n_intervals: int, f: Dictionary, variant: Dictionary) -> void:
	# Single-segment wall body — used by the respawn path so we don't have to
	# tear down + rebuild the whole fence's wall colliders just to refresh one.
	var height: float = float(variant.get("wall_height", 1.0))
	var thickness: float = float(variant.get("wall_thickness", 0.20))
	var delta: Vector3 = f.end - f.start
	delta.y = 0.0
	var L: float = delta.length()
	if L < MIN_RUN_LENGTH or n_intervals <= 0 or seg_idx < 0 or seg_idx >= n_intervals:
		return
	var forward: Vector3 = delta.normalized()
	var seg_len: float = L / float(n_intervals)
	var ps: Vector3 = f.start + forward * (seg_idx * seg_len)
	var pe: Vector3 = f.start + forward * ((seg_idx + 1) * seg_len)
	ps.y = _ground_y(ps)
	pe.y = _ground_y(pe)
	var mid: Vector3 = (ps + pe) * 0.5
	mid.y += height * 0.5
	var body := StaticBody3D.new()
	body.position = mid
	body.basis = _yaw_basis(forward)
	body.collision_layer = WALL_COLLISION_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(seg_len, height, thickness)
	shape.shape = box
	body.add_child(shape)
	_visuals_root.add_child(body)
	var seg_key: String = "%d_%d" % [fence_idx, seg_idx]
	body.set_meta("seg_key", seg_key)
	_wall_bodies[seg_key] = body

func _post_position_taken(pos: Vector3) -> bool:
	for p in _post_positions:
		if (p as Vector3).distance_to(pos) < POST_DEDUP_RADIUS:
			return true
	return false

func _build_interval(root: Node3D, p_start: Vector3, p_end: Vector3, forward: Vector3, variant: Dictionary, ghost: bool, fence_idx: int = -1, seg_idx: int = -1) -> void:
	var span: float = p_start.distance_to(p_end)
	var picket_glb: String = variant["picket_glb"]
	var picket_spacing: float = variant["picket_spacing"]
	# Resolve segment props once per interval so pickets share the lookup.
	var destructible: bool = false
	var respawn_time: float = 10.0
	var wallbang: bool = false
	if fence_idx >= 0 and seg_idx >= 0:
		var props: Dictionary = get_segment_props(fence_idx, seg_idx)
		destructible = bool(props.get("destructible", false))
		respawn_time = float(props.get("respawn_time", 10.0))
		wallbang = bool(props.get("wallbang", false))
	# Destructible segments get a private Node3D holder so the respawn path
	# can free the entire interval in one shot.
	var spawn_parent: Node3D = root
	if destructible and not ghost and fence_idx >= 0 and seg_idx >= 0:
		var seg_key: String = "%d_%d" % [fence_idx, seg_idx]
		var holder := Node3D.new()
		root.add_child(holder)
		holder.set_meta("seg_key", seg_key)
		_segment_holders[seg_key] = holder
		spawn_parent = holder
	# Picket positions along the run (axis distance from p_start) — computed
	# up-front so rails can split into per-picket cells.
	var n_pickets: int = 0
	var picket_positions: Array = []
	var picket_t_axis: Array = []  # signed distance along forward from p_start
	if picket_glb != "" and picket_spacing > 0.0:
		# Picket count: pick the integer N that makes the spacing s = span/(N+1)
		# closest to picket_spacing. Treating end-to-post as another picket slot
		# guarantees symmetric end gaps that match the inter-picket gap.
		n_pickets = max(0, int(round(span / picket_spacing)) - 1)
		if n_pickets > 0:
			var s: float = span / float(n_pickets + 1)
			for i in range(n_pickets):
				var t: float = s * (i + 1)
				var pw: Vector3 = p_start + forward * t
				pw.y = _ground_y(pw)
				picket_positions.append(pw)
				picket_t_axis.append(t)
	# Rails sit between posts (inner edge → inner edge). Heights per variant.
	# Split each rail into n_pickets sub-pieces (one per picket cell) when
	# destructible so we can hide just the affected part on picket death.
	var post_width: float = variant["post_width"]
	var rail_origin: Vector3 = p_start + forward * (post_width * 0.5)
	var rail_length: float = span - post_width
	var rail_subs_by_height: Array = []  # Array[Array[MeshInstance3D|null]]
	for ry in variant["rails"]:
		var rp: Vector3 = rail_origin
		rp.y = _ground_y(rp) + ry
		if destructible and n_pickets > 0 and not ghost:
			rail_subs_by_height.append(_spawn_split_rail(spawn_parent, p_start, rp.y, forward, post_width, rail_length, variant, picket_t_axis, wallbang))
		else:
			_spawn_rail(spawn_parent, rp, forward, rail_length, variant, ghost, wallbang)
	# Spawn pickets and (if destructible) tag each body with its segment +
	# picket index + adjacent rail sub-pieces. The picket-hit handler uses
	# those refs to hide the affected rail cells when the picket dies.
	# adjacent_rails entries are {mesh, body} dicts so the breach path can
	# free any bullet-hole decals parented to the rail's body.
	for i in range(n_pickets):
		var pw_i: Vector3 = picket_positions[i]
		var adj_rails: Array = []
		if destructible:
			for sub_arr in rail_subs_by_height:
				if i < sub_arr.size() and sub_arr[i] != null and (sub_arr[i] as Dictionary).get("mesh", null) != null:
					adj_rails.append(sub_arr[i])
		var picket_tags: Dictionary = {}
		if destructible:
			picket_tags = {
				"fence_idx": fence_idx,
				"seg_idx": seg_idx,
				"picket_index": i,
				"n_pickets_in_seg": n_pickets,
				"adjacent_rails": adj_rails,
				"wallbang": wallbang,
			}
		_spawn_picket(spawn_parent, pw_i, forward, variant, ghost, destructible, respawn_time, picket_tags)

func _spawn_split_rail(root: Node3D, p_start: Vector3, rail_y: float, forward: Vector3, post_width: float, rail_length: float, variant: Dictionary, picket_t_axis: Array, wallbang: bool = false) -> Array:
	# Split a rail into one sub-piece per picket cell. Each cell spans from
	# midway-with-previous-picket to midway-with-next-picket (clamped to the
	# rail's left/right inner-post bounds). Returns an array indexed by
	# picket_index of {mesh, body} pairs (or null entries for cells too
	# narrow to spawn). The body ref lets the collapse path free decals
	# parented to it.
	var refs: Array = []
	var mesh: Mesh = _mesh_cache.get(variant["rail_glb"], null)
	if mesh == null or picket_t_axis.is_empty():
		return refs
	var rail_left: float = post_width * 0.5
	var rail_right: float = rail_left + rail_length
	var n: int = picket_t_axis.size()
	for i in range(n):
		var L: float = rail_left
		var R: float = rail_right
		if i > 0:
			L = (picket_t_axis[i - 1] + picket_t_axis[i]) * 0.5
		if i < n - 1:
			R = (picket_t_axis[i] + picket_t_axis[i + 1]) * 0.5
		var sub_len: float = R - L
		if sub_len <= 0.01:
			refs.append(null)
			continue
		var left_world: Vector3 = p_start + forward * L
		left_world.y = rail_y
		var basis: Basis = _yaw_basis(forward).scaled_local(Vector3(sub_len, 1.0, 1.0))
		var pair: Dictionary = _spawn(root, mesh, left_world, basis, false, wallbang)
		var rb: Node = pair.get("body", null)
		if rb != null:
			rb.add_to_group(RAIL_GROUP)
		refs.append({"mesh": pair.get("mesh", null), "body": rb})
	return refs

func _spawn_post(root: Node3D, world_pos: Vector3, forward: Vector3, variant: Dictionary, ghost: bool, wallbang_override: bool = false) -> void:
	var mesh: Mesh = _mesh_cache.get(variant["post_glb"], null)
	var basis: Basis = _yaw_basis(forward)
	var ysc: float = variant.get("post_scale_y", 1.0)
	if ysc != 1.0:
		basis = basis.scaled_local(Vector3(1.0, ysc, 1.0))
	# Wallbang the post if either of its adjacent segments opts in. The
	# cluster pass ORs neighbouring entries before this point.
	var wallbang: bool = wallbang_override or bool(variant.get("wallbang", false))
	_spawn(root, mesh, world_pos, basis, ghost, wallbang)

func _spawn_picket(root: Node3D, world_pos: Vector3, forward: Vector3, variant: Dictionary, ghost: bool, destructible: bool = false, respawn_time: float = 10.0, tags: Dictionary = {}) -> void:
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
	var wallbang_tag: bool = bool(tags.get("wallbang", false))
	var pair: Dictionary = _spawn(root, mesh, world_pos, basis, ghost, wallbang_tag)
	if destructible and pair.has("body") and pair["body"] != null:
		var body: StaticBody3D = pair["body"]
		body.add_to_group(PICKET_GROUP)
		body.set_meta("picket_mesh_ref", pair["mesh"])
		body.set_meta("respawn_time", respawn_time)
		for k in tags.keys():
			body.set_meta(k, tags[k])

func _spawn_rail(root: Node3D, world_pos: Vector3, forward: Vector3, length: float, variant: Dictionary, ghost: bool, wallbang: bool = false) -> void:
	var mesh: Mesh = _mesh_cache.get(variant["rail_glb"], null)
	if mesh == null:
		return
	# scaled_local (right-multiply) stretches the rail's local +X by length.
	var basis: Basis = _yaw_basis(forward).scaled_local(Vector3(length, 1.0, 1.0))
	_spawn(root, mesh, world_pos, basis, ghost, wallbang)

func _spawn(root: Node3D, mesh: Mesh, world_pos: Vector3, basis: Basis, ghost: bool, wallbang: bool = false) -> Dictionary:
	if mesh == null:
		return {}
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = world_pos
	mi.basis = basis
	if ghost:
		mi.transparency = 0.55
	root.add_child(mi)
	var body: StaticBody3D = null
	if _collision_enabled and not ghost:
		body = _attach_collider(root, mesh, world_pos, basis)
		if body != null and wallbang:
			body.set_meta("wallbang", true)
	return {"mesh": mi, "body": body}

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
