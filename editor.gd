extends Node3D

# Map editor root. Owns the camera, the heightmap terrain, the brush
# overlay, and the on-screen tool UI. Mouse interaction is split:
#  - LMB while a terrain tool is active and MMB is NOT held → applies
#    the brush to whatever the cursor is over.
#  - MMB held → camera takes over for free-fly look (handled by
#    EditorCamera).
# F9 swaps to play mode (loads main.tscn).

const PLAY_SCENE := "res://main.tscn"

# Tool ids (extended later as more categories ship).
const TOOL_NONE := ""
const TOOL_T_RAISE := "t_raise"
const TOOL_T_LOWER := "t_lower"
const TOOL_T_FLATTEN := "t_flatten"
const TOOL_T_SMOOTH := "t_smooth"
const TOOL_T_RAMP := "t_ramp"
const TOOL_S_PLACE_SPAWN := "s_player_place"
const TOOL_S_DELETE_SPAWN := "s_player_delete"

const BRUSH_STRENGTH := 12.0    # m/s for raise/lower at full falloff
const SPAWN_DELETE_RADIUS := 2.5  # metres — click within this of a marker to remove it

@onready var _camera: Camera3D = $EditorCamera
@onready var _terrain: Node3D = $Terrain
@onready var _brush_ring: Node3D = $BrushRing
@onready var _flatten_ring: Node3D = $FlattenRing
@onready var _top_bar: Control = $UI/TopBar
@onready var _sub_bar: Control = $UI/SubBar
@onready var _radius_widget: Control = $UI/RadiusWidget

var _active_tool: String = TOOL_NONE
var _brush_radius: float = 4.0
var _brush_strength: float = 1.0
var _flatten_target: float = 0.0
var _ramp_start: Vector3 = Vector3.INF
var _was_painting: bool = false
# Player spawn markers — list of (Vector3 world_pos, Node3D visual).
var _spawn_visuals: Array[Node3D] = []
var _spawn_marker_mat: StandardMaterial3D = null
var _spawn_ghost_mat: StandardMaterial3D = null
var _spawn_ghost: Node3D = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Restore previously-edited heights if we're coming back from F9 play.
	if MapState.has_map() and MapState.heights.size() == _terrain.heights.size():
		_terrain.heights = MapState.heights.duplicate()
		_terrain.rebuild()
	_brush_ring.terrain = _terrain
	_brush_ring.set_radius(_brush_radius)
	_brush_ring.hide_ring()
	# Flatten preview ring — magenta so it pops against the surface ring.
	_flatten_ring.terrain = _terrain
	_flatten_ring.set_color(Color(1.0, 0.35, 0.85, 1.0))
	_flatten_ring.set_radius(_brush_radius)
	_flatten_ring.hide_ring()
	_top_bar.category_picked.connect(_on_category_picked)
	_sub_bar.tool_picked.connect(_on_tool_picked)
	_radius_widget.radius_changed.connect(_on_radius_changed)
	_radius_widget.strength_changed.connect(_on_strength_changed)
	_radius_widget.set_radius(_brush_radius)
	_radius_widget.set_strength(_brush_strength)
	# Default to Terrain → Heights view so the user lands on a useful page.
	_top_bar.select_category("terrain")
	# Restore spawn markers from MapState (if any).
	for pos in MapState.player_spawns:
		_add_spawn_visual(pos)
	# Pre-build the ghost marker — kept hidden until the place tool is active.
	_spawn_ghost = _build_marker_node(_get_ghost_material())
	_spawn_ghost.visible = false
	add_child(_spawn_ghost)

func _input(event: InputEvent) -> void:
	# F9 → play mode. Either the input action OR the raw key fires it,
	# but not both (after _enter_play_mode the scene is freed so we
	# must not touch self afterwards).
	var is_f9: bool = event.is_action_pressed("editor_play") \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9)
	if is_f9:
		_enter_play_mode()

func _enter_play_mode() -> void:
	# Snapshot the current map into the autoload so the play scene can
	# rebuild the same terrain on the other side of the scene swap.
	MapState.heights = _terrain.heights.duplicate()
	MapState.grid_w = _terrain.GRID_W
	MapState.grid_h = _terrain.GRID_H
	get_tree().change_scene_to_file(PLAY_SCENE)

func _process(delta: float) -> void:
	# Hide all hover visuals by default; per-tool branches re-enable them.
	_spawn_ghost.visible = false
	_flatten_ring.hide_ring()
	# Brush preview + LMB-stroke logic only runs when the cursor is free
	# (camera not in look-mode) and a terrain tool is active.
	if _camera.is_looking() or _active_tool == TOOL_NONE:
		_brush_ring.hide_ring()
		return
	# Spawn-place ghost: cyan translucent marker that follows the cursor
	# on the terrain so the user previews exactly where the click lands.
	if _active_tool == TOOL_S_PLACE_SPAWN:
		_brush_ring.hide_ring()
		if _is_over_ui():
			return
		var ghost_hit := _raycast_cursor()
		if not ghost_hit.is_empty():
			_spawn_ghost.global_position = ghost_hit.position
			_spawn_ghost.visible = true
		return
	# Brush ring only makes sense for terrain brushes; spawn tools use
	# pinpoint clicks.
	var is_brush_tool: bool = _active_tool in [TOOL_T_RAISE, TOOL_T_LOWER, TOOL_T_FLATTEN, TOOL_T_SMOOTH, TOOL_T_RAMP]
	if not is_brush_tool:
		_brush_ring.hide_ring()
		return
	var hit := _raycast_cursor()
	if hit.is_empty():
		_brush_ring.hide_ring()
		return
	_brush_ring.set_radius(_brush_radius)
	_brush_ring.place(hit.position)
	# Flatten target preview ring at the sampled height.
	if _active_tool == TOOL_T_FLATTEN:
		_flatten_ring.set_radius(_brush_radius)
		_flatten_ring.place_flat(hit.position, _flatten_target)
	if _is_over_ui():
		return
	# Shift-LMB on flatten = "sample target height" gesture, not a paint
	# stroke. Detected via _unhandled_input below; suppressed here.
	var shift_sample: bool = _active_tool == TOOL_T_FLATTEN and Input.is_key_pressed(KEY_SHIFT)
	var painting: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		and _active_tool != TOOL_T_RAMP \
		and not shift_sample
	if painting:
		_apply_tool(hit.position, delta)
	# Stroke just ended: snapshot collision so play mode walks the new shape.
	if _was_painting and not painting:
		_terrain.end_stroke()
	_was_painting = painting

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _is_over_ui() or _camera.is_looking():
		return
	# Flatten tool: shift+click samples target height from terrain
	# under the cursor. Subsequent un-shifted strokes flatten toward it.
	if _active_tool == TOOL_T_FLATTEN and event.pressed and Input.is_key_pressed(KEY_SHIFT):
		var fh := _raycast_cursor()
		if not fh.is_empty():
			_flatten_target = fh.position.y
		return
	# Ramp tool: click-down picks start, click-up commits with end point.
	if _active_tool == TOOL_T_RAMP:
		var hit := _raycast_cursor()
		if hit.is_empty():
			return
		if event.pressed:
			_ramp_start = hit.position
		else:
			if _ramp_start != Vector3.INF:
				_terrain.ramp_stroke(_ramp_start, hit.position, _brush_radius)
				_terrain.end_stroke()
				_ramp_start = Vector3.INF
		return
	# Spawn place: each press drops a marker.
	if _active_tool == TOOL_S_PLACE_SPAWN and event.pressed:
		var hit2 := _raycast_cursor()
		if hit2.is_empty():
			return
		MapState.player_spawns.append(hit2.position)
		_add_spawn_visual(hit2.position)
		return
	# Spawn delete: each press removes the closest marker within radius.
	if _active_tool == TOOL_S_DELETE_SPAWN and event.pressed:
		var hit3 := _raycast_cursor()
		if hit3.is_empty():
			return
		_delete_nearest_spawn(hit3.position)

func _apply_tool(world_pos: Vector3, delta: float) -> void:
	var s: float = _brush_strength
	match _active_tool:
		TOOL_T_RAISE:
			_terrain.raise_brush(world_pos, _brush_radius, BRUSH_STRENGTH * s, delta)
		TOOL_T_LOWER:
			_terrain.lower_brush(world_pos, _brush_radius, BRUSH_STRENGTH * s, delta)
		TOOL_T_FLATTEN:
			_terrain.flatten_brush(world_pos, _brush_radius, _flatten_target, 4.0 * s, delta)
		TOOL_T_SMOOTH:
			_terrain.smooth_brush(world_pos, _brush_radius, 6.0 * s, delta)

func _raycast_cursor() -> Dictionary:
	# For terrain brush tools we march against the *live* heightmap so
	# the cursor tracks freshly-modified ground instead of the stale
	# ConcavePolygon collider (which only refreshes on stroke release).
	# Spawn / non-terrain tools fall back to physics raycast.
	if _active_tool in [TOOL_T_RAISE, TOOL_T_LOWER, TOOL_T_FLATTEN, TOOL_T_SMOOTH, TOOL_T_RAMP]:
		var mouse := get_viewport().get_mouse_position()
		var from := _camera.project_ray_origin(mouse)
		var dir := _camera.project_ray_normal(mouse)
		var p: Vector3 = _terrain.ray_pick(from, dir)
		if p == Vector3.INF:
			return {}
		return {"position": p, "normal": Vector3.UP}
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var fr := _camera.project_ray_origin(mp)
	var to := fr + _camera.project_ray_normal(mp) * 1000.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(fr, to)
	return space.intersect_ray(q)

func _is_over_ui() -> bool:
	var mp := get_viewport().get_mouse_position()
	for c in [_top_bar, _sub_bar, _radius_widget]:
		var r: Rect2 = c.get_global_rect()
		if r.has_point(mp):
			return true
	return false

func _on_category_picked(category: String) -> void:
	_sub_bar.show_category(category)
	# Picking a category clears the active tool until the user picks one
	# from the sub-bar.
	_active_tool = TOOL_NONE

func _on_tool_picked(tool_id: String) -> void:
	_active_tool = tool_id

func _on_radius_changed(r: float) -> void:
	_brush_radius = r
	_brush_ring.set_radius(r)
	_flatten_ring.set_radius(r)

func _on_strength_changed(s: float) -> void:
	_brush_strength = s

# Spawn-marker visual: vertical pillar with a flag on top, tinted
# cyan. Used both for committed markers and the placement ghost
# (different material, same geometry).
func _build_marker_node(material: StandardMaterial3D) -> Node3D:
	var holder := Node3D.new()
	var pillar := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.10
	pm.bottom_radius = 0.10
	pm.height = 1.8
	pillar.mesh = pm
	pillar.material_override = material
	pillar.position = Vector3(0, 0.9, 0)
	holder.add_child(pillar)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.6, 0.35, 0.04)
	flag.mesh = fm
	flag.material_override = material
	flag.position = Vector3(0.30, 1.65, 0)
	holder.add_child(flag)
	return holder

func _get_marker_material() -> StandardMaterial3D:
	if _spawn_marker_mat == null:
		_spawn_marker_mat = StandardMaterial3D.new()
		_spawn_marker_mat.albedo_color = Color(0.25, 0.95, 1.0, 1.0)
		_spawn_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _spawn_marker_mat

func _get_ghost_material() -> StandardMaterial3D:
	if _spawn_ghost_mat == null:
		_spawn_ghost_mat = StandardMaterial3D.new()
		_spawn_ghost_mat.albedo_color = Color(0.25, 0.95, 1.0, 0.45)
		_spawn_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spawn_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _spawn_ghost_mat

func _add_spawn_visual(world_pos: Vector3) -> void:
	var holder := _build_marker_node(_get_marker_material())
	holder.position = world_pos
	add_child(holder)
	_spawn_visuals.append(holder)

func _delete_nearest_spawn(world_pos: Vector3) -> void:
	var best_i: int = -1
	var best_d: float = SPAWN_DELETE_RADIUS
	for i in range(MapState.player_spawns.size()):
		var d: float = MapState.player_spawns[i].distance_to(world_pos)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return
	MapState.player_spawns.remove_at(best_i)
	if best_i < _spawn_visuals.size():
		var v: Node3D = _spawn_visuals[best_i]
		_spawn_visuals.remove_at(best_i)
		v.queue_free()
