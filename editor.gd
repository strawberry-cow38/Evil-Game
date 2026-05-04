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
const TOOL_S_ITEMS := "s_items"
const TOOL_S_ITEMS_REMOVE := "s_items_remove"
const TOOL_L_EFFECTS := "l_effects"
const TOOL_O_OBJECTS := "o_objects"
const TOOL_E_LIGHTING := "e_lighting"

const EFFECT_BOX_SCRIPT := preload("res://editor_effect_box.gd")
const OBJECT_BOX_SCRIPT := preload("res://editor_object_box.gd")
const ITEM_SPAWN_BOX_SCRIPT := preload("res://editor_item_spawn_box.gd")
const GIZMO_SCRIPT := preload("res://editor_gizmo.gd")
const CONTAINER_PANEL_SCRIPT := preload("res://editor_container_panel.gd")
const LIGHTING_PANEL_SCRIPT := preload("res://editor_lighting_panel.gd")
const OBJECTS_CATALOG := preload("res://editor_objects_catalog.gd")
const CRATE := preload("res://crate.gd")

const BRUSH_STRENGTH := 12.0    # m/s for raise/lower at full falloff
const SPAWN_DELETE_RADIUS := 2.5  # metres — click within this of a marker to remove it

@onready var _camera: Camera3D = $EditorCamera
@onready var _terrain: Node3D = $Terrain
@onready var _brush_ring: Node3D = $BrushRing
@onready var _flatten_ring: Node3D = $FlattenRing
@onready var _top_bar: Control = $UI/TopBar
@onready var _sub_bar: Control = $UI/SubBar
@onready var _radius_widget: Control = $UI/RadiusWidget
@onready var _fps_label: Label = $UI/FpsLabel
@onready var _effects_panel: PanelContainer = $UI/EffectsPanel
@onready var _objects_panel: PanelContainer = $UI/ObjectsPanel
@onready var _item_tables_panel: PanelContainer = $UI/ItemTablesPanel
@onready var _item_picker_panel: PanelContainer = $UI/ItemPickerPanel
@onready var _space_toggle: PanelContainer = $UI/SpaceToggle

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
# Translucent cube preview shown while the Spawns → Items tool is active,
# tinted live to whatever the active table's color is.
var _item_spawn_ghost: MeshInstance3D = null
var _item_spawn_ghost_mat: StandardMaterial3D = null
# Placed props — wireframe-boxed nodes for both Effects and Objects.
# Both editor_effect_box and editor_object_box implement the same
# interface (set_selected, get_aabb_local) so picking + gizmo binding
# treats them uniformly. Source id lives on each node.
var _placed_props: Array[Node3D] = []
var _selected_prop: Node3D = null
# Item-spawn cubes (Spawns → Items). Owned separately because they
# don't participate in the gizmo / selection pipeline — they're plain
# colored cubes whose contents come from a roll table at play-mode
# bootstrap.
var _placed_item_spawns: Array[Node3D] = []
var _armed_effect_id: String = ""
var _armed_object_id: String = ""
var _gizmo: Node3D = null
# Drag state for translate gizmo. _drag_handle == "" means no drag in
# progress. _drag_axis / _drag_normal pin the axis or plane the drag is
# constrained to (in world space, captured at drag start). _drag_offset
# = offset from target.global_position to the cursor's projection on
# the constraint at drag start, so motion preserves grab point.
var _drag_handle: String = ""
var _drag_axis: Vector3 = Vector3.ZERO
var _drag_normal: Vector3 = Vector3.ZERO
var _drag_offset: Vector3 = Vector3.ZERO
var _drag_anchor: Vector3 = Vector3.ZERO  # gizmo origin at drag start
# Rotate/scale extras: snapshot of target state at drag start so motion
# is computed delta-from-start (no drift from accumulating tiny deltas).
var _drag_start_basis: Basis = Basis()
var _drag_start_scale: Vector3 = Vector3.ONE
var _drag_start_angle: float = 0.0
var _drag_start_dist: float = 1.0
var _drag_axis_u: Vector3 = Vector3.ZERO  # ring plane basis u
var _drag_axis_v: Vector3 = Vector3.ZERO  # ring plane basis v
var _drag_scale_index: int = 0            # 0=x, 1=y, 2=z (local scale)
# Scale-drag pivot in the box's pre-Node3D-scale local space. Sits at
# the OPPOSITE side of the grabbed handle on its axis, so scaling moves
# only the grabbed face outward — the opposite face stays in place.
# Only used when _drag_scale_pivot is true (6-handle mode); 3-axis mode
# keeps the legacy symmetric stretch around origin.
var _drag_pivot_local: Vector3 = Vector3.ZERO
var _drag_scale_pivot: bool = false
# Loot-table picker shown only when the selected prop is a crate. Built
# at runtime so editor.tscn doesn't need a new node.
var _container_panel: PanelContainer = null
# Lighting tuner shown only while Environment → Lighting is active.
var _lighting_panel: PanelContainer = null
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun

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
	_effects_panel.effect_picked.connect(_on_effect_picked)
	_effects_panel.visible = false
	_objects_panel.object_picked.connect(_on_object_picked)
	_objects_panel.visible = false
	_item_tables_panel.set_picker(_item_picker_panel)
	_item_tables_panel.active_table_changed.connect(_on_active_table_changed)
	_item_tables_panel.visible = false
	_item_picker_panel.visible = false
	_space_toggle.space_changed.connect(_on_space_changed)
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
	# Item-spawn ghost: translucent cube tinted to active table color.
	_item_spawn_ghost_mat = StandardMaterial3D.new()
	_item_spawn_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_item_spawn_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_item_spawn_ghost_mat.albedo_color = Color(1, 1, 1, 0.45)
	_item_spawn_ghost = MeshInstance3D.new()
	var ig_mesh := BoxMesh.new()
	ig_mesh.size = Vector3(0.6, 0.6, 0.6)
	_item_spawn_ghost.mesh = ig_mesh
	_item_spawn_ghost.material_override = _item_spawn_ghost_mat
	_item_spawn_ghost.visible = false
	add_child(_item_spawn_ghost)
	# Transform gizmo — follows the selected effect, hidden until Q/W/R.
	_gizmo = Node3D.new()
	_gizmo.set_script(GIZMO_SCRIPT)
	add_child(_gizmo)
	# Container loot-table picker. Sits next to the right-side panels so
	# both can be visible at once when a crate is selected while the user
	# is on the Objects tool.
	_container_panel = PanelContainer.new()
	_container_panel.set_script(CONTAINER_PANEL_SCRIPT)
	_container_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_container_panel.offset_left = -560
	_container_panel.offset_right = -292
	_container_panel.offset_top = 120
	_container_panel.offset_bottom = 320
	_container_panel.visible = false
	$UI.add_child(_container_panel)
	_container_panel.table_chosen.connect(_on_container_table_chosen)
	_container_panel.rolls_changed.connect(_on_container_rolls_changed)
	# Lighting tuner. Same pattern as the container panel — built at
	# runtime so editor.tscn doesn't need a new node, hidden until the
	# Environment → Lighting tool is picked.
	_lighting_panel = PanelContainer.new()
	_lighting_panel.set_script(LIGHTING_PANEL_SCRIPT)
	_lighting_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lighting_panel.offset_left = -300
	_lighting_panel.offset_right = -8
	_lighting_panel.offset_top = 60
	_lighting_panel.offset_bottom = 520
	_lighting_panel.visible = false
	$UI.add_child(_lighting_panel)
	_lighting_panel.lighting_changed.connect(_on_lighting_changed)
	# Restore prior lighting (round-trip from F9 play) so the editor
	# matches what the player saw.
	if not MapState.lighting.is_empty():
		_lighting_panel.set_state(MapState.lighting)
		_apply_lighting(MapState.lighting)

func _input(event: InputEvent) -> void:
	# F9 → play mode. Either the input action OR the raw key fires it,
	# but not both (after _enter_play_mode the scene is freed so we
	# must not touch self afterwards).
	var is_f9: bool = event.is_action_pressed("editor_play") \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9)
	if is_f9:
		_enter_play_mode()
		return
	# E → place an armed effect or object at the cursor (depends on tool).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if not _camera.is_looking() and not _is_over_ui():
			if _active_tool == TOOL_L_EFFECTS and _armed_effect_id != "":
				var hit := _raycast_cursor()
				if not hit.is_empty():
					_spawn_effect_at(_armed_effect_id, hit.position)
			elif _active_tool == TOOL_O_OBJECTS and _armed_object_id != "":
				var hit2 := _raycast_cursor()
				if not hit2.is_empty():
					_spawn_object_at(_armed_object_id, hit2.position)
	# Q → translate gizmo. Only when an effect is selected and the
	# camera isn't grabbing the key for fly-down (camera only consumes
	# Q while MMB is held).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		if _selected_prop != null and not _camera.is_looking():
			_gizmo.set_target(_selected_prop)
			_gizmo.cycle_translate()
	# W → rotate gizmo. R → scale gizmo.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_W:
		if _selected_prop != null and not _camera.is_looking():
			_gizmo.set_target(_selected_prop)
			_gizmo.set_mode(_gizmo.MODE_ROTATE)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if _selected_prop != null and not _camera.is_looking():
			_gizmo.set_target(_selected_prop)
			_gizmo.cycle_scale()
	# Delete → remove selected effect.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
		if _selected_prop != null and not _camera.is_looking():
			_delete_selected_prop()

func _enter_play_mode() -> void:
	# Snapshot the current map into the autoload so the play scene can
	# rebuild the same terrain on the other side of the scene swap.
	MapState.heights = _terrain.heights.duplicate()
	MapState.grid_w = _terrain.GRID_W
	MapState.grid_h = _terrain.GRID_H
	# Snapshot placed effects + objects so the play scene can rebuild them.
	MapState.placed_props.clear()
	for box in _placed_props:
		if not is_instance_valid(box):
			continue
		var kind: String = ""
		var id: String = ""
		if "effect_id" in box and String(box.effect_id) != "":
			kind = "effect"
			id = String(box.effect_id)
		elif "object_id" in box and String(box.object_id) != "":
			kind = "object"
			id = String(box.object_id)
		else:
			continue
		var entry: Dictionary = {
			"kind": kind,
			"id": id,
			"xform": box.global_transform,
		}
		# Container objects carry their assigned loot table forward so the
		# play-mode bootstrap can roll loot into the spawned crate.
		if kind == "object" and "loot_table_id" in box:
			entry["loot_table_id"] = String(box.loot_table_id)
		if kind == "object" and "roll_count_override" in box:
			entry["roll_count_override"] = int(box.roll_count_override)
		MapState.placed_props.append(entry)
	# Snapshot item-spawn tables + placed cubes. Tables are deep-duped so
	# the play scene never aliases editor state (color edits in a future
	# F9 session won't retro-affect a baked map).
	MapState.item_tables.clear()
	for t in _item_tables_panel.tables:
		var entries_dup: Array = []
		for e in t.get("entries", []):
			entries_dup.append({
				"id": String(e.get("id", "")),
				"weight": float(e.get("weight", 1.0)),
				"min_count": int(e.get("min_count", 1)),
				"max_count": int(e.get("max_count", 1)),
			})
		MapState.item_tables.append({
			"id": String(t.get("id", "")),
			"name": String(t.get("name", "")),
			"color": t.get("color", Color.WHITE),
			"entries": entries_dup,
		})
	MapState.item_spawn_points.clear()
	for box in _placed_item_spawns:
		if not is_instance_valid(box):
			continue
		MapState.item_spawn_points.append({
			"table_id": String(box.table_id),
			"pos": box.global_position,
		})
	get_tree().change_scene_to_file(PLAY_SCENE)

func _process(delta: float) -> void:
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# Hide all hover visuals by default; per-tool branches re-enable them.
	_spawn_ghost.visible = false
	if _item_spawn_ghost != null:
		_item_spawn_ghost.visible = false
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
			var gp: Vector3 = ghost_hit.position
			gp.y = _terrain.sample_height(gp)
			_spawn_ghost.global_position = gp
			_spawn_ghost.visible = true
		return
	# Item-spawn ghost: translucent cube tinted to active table color,
	# bottom face on the terrain so the user previews exactly where the
	# placed cube will land.
	if _active_tool == TOOL_S_ITEMS:
		_brush_ring.hide_ring()
		if _is_over_ui():
			return
		var t: Dictionary = _item_tables_panel.get_active_table()
		if t.is_empty():
			return
		var ig_hit := _raycast_cursor()
		if ig_hit.is_empty():
			return
		var igp: Vector3 = ig_hit.position
		igp.y = _terrain.sample_height(igp)
		# Mesh is centred on origin, so lift by half so the bottom sits on terrain.
		_item_spawn_ghost.global_position = igp + Vector3(0, 0.3, 0)
		var col: Color = t.get("color", Color.WHITE)
		_item_spawn_ghost_mat.albedo_color = Color(col.r, col.g, col.b, 0.45)
		_item_spawn_ghost.visible = true
		return
	# Brush ring only makes sense for terrain brushes; spawn tools use
	# pinpoint clicks.
	var is_brush_tool: bool = _active_tool in [TOOL_T_RAISE, TOOL_T_LOWER, TOOL_T_FLATTEN, TOOL_T_SMOOTH, TOOL_T_RAMP, TOOL_S_ITEMS_REMOVE]
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
	# Mouse motion drives an in-progress gizmo drag (always handled,
	# regardless of tool — once a drag starts the user is committed).
	if event is InputEventMouseMotion and _drag_handle != "":
		_continue_gizmo_drag()
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# In-progress drag always consumes the release, even over UI / look-mode.
	if _drag_handle != "" and not event.pressed:
		_drag_handle = ""
		return
	if _is_over_ui() or _camera.is_looking():
		return
	# Flatten tool: shift+click samples target height from terrain
	# under the cursor. Subsequent un-shifted strokes flatten toward it.
	if _active_tool == TOOL_T_FLATTEN and event.pressed and Input.is_key_pressed(KEY_SHIFT):
		var fh := _raycast_cursor()
		if not fh.is_empty():
			_flatten_target = _terrain.sample_height(fh.position)
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
		var p2: Vector3 = hit2.position
		p2.y = _terrain.sample_height(p2)
		MapState.player_spawns.append(p2)
		_add_spawn_visual(p2)
		return
	# Item-spawn place: drop a colored cube tied to the active table.
	if _active_tool == TOOL_S_ITEMS and event.pressed:
		var t: Dictionary = _item_tables_panel.get_active_table()
		if t.is_empty():
			return
		var hit_i := _raycast_cursor()
		if hit_i.is_empty():
			return
		var p_i: Vector3 = hit_i.position
		p_i.y = _terrain.sample_height(p_i)
		_spawn_item_box(String(t.get("id", "")), t.get("color", Color.WHITE), p_i)
		return
	# Spawn delete: each press removes the closest marker within radius.
	if _active_tool == TOOL_S_DELETE_SPAWN and event.pressed:
		var hit3 := _raycast_cursor()
		if hit3.is_empty():
			return
		# Bump the cursor y to terrain height so the 3D distance check
		# matches the markers (which sit on the surface).
		var p3: Vector3 = hit3.position
		p3.y = _terrain.sample_height(p3)
		_delete_nearest_spawn(p3)
		return
	# Effects / Objects tools: LMB picks a gizmo handle first (so dragging
	# an arrow doesn't deselect the prop underneath). Falls through to pick
	# the box itself if no handle was hit. Release ends the drag.
	if _active_tool == TOOL_L_EFFECTS or _active_tool == TOOL_O_OBJECTS:
		if event.pressed:
			if _try_start_gizmo_drag():
				return
			_pick_prop_under_cursor()
		else:
			_drag_handle = ""

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
		TOOL_S_ITEMS_REMOVE:
			_remove_item_spawns_in_radius(world_pos, _brush_radius)

func _raycast_cursor() -> Dictionary:
	# Two cursor modes:
	#  - Terrain brush tools: mouse vs flat y=0 plane. Cheap, fully
	#    decoupled from terrain state so brush input never stalls.
	#  - Spawn / non-terrain tools: 3D ray vs the live heightmap so
	#    markers land on the actual surface under the cursor.
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var is_terrain_tool: bool = _active_tool in [TOOL_T_RAISE, TOOL_T_LOWER, TOOL_T_FLATTEN, TOOL_T_SMOOTH, TOOL_T_RAMP]
	if is_terrain_tool:
		if absf(dir.y) < 0.0001:
			return {}
		var t: float = -from.y / dir.y
		if t <= 0.0:
			return {}
		return {"position": from + dir * t, "normal": Vector3.UP}
	var p: Vector3 = _terrain.ray_pick(from, dir)
	if p == Vector3.INF:
		return {}
	return {"position": p, "normal": Vector3.UP}

func _is_over_ui() -> bool:
	var mp := get_viewport().get_mouse_position()
	for c in [_top_bar, _sub_bar, _radius_widget, _effects_panel, _objects_panel, _item_tables_panel, _item_picker_panel, _space_toggle, _container_panel, _lighting_panel]:
		if c == null or not c.visible:
			continue
		var r: Rect2 = c.get_global_rect()
		if r.has_point(mp):
			return true
	return false

func _on_category_picked(category: String) -> void:
	_sub_bar.show_category(category)
	# Picking a category clears the active tool until the user picks one
	# from the sub-bar.
	_active_tool = TOOL_NONE
	_effects_panel.visible = false
	_objects_panel.visible = false

func _on_tool_picked(tool_id: String) -> void:
	_active_tool = tool_id
	_effects_panel.visible = (tool_id == TOOL_L_EFFECTS)
	_objects_panel.visible = (tool_id == TOOL_O_OBJECTS)
	_item_tables_panel.visible = (tool_id == TOOL_S_ITEMS)
	if tool_id != TOOL_S_ITEMS:
		_item_picker_panel.visible = false
	if _lighting_panel != null:
		_lighting_panel.visible = (tool_id == TOOL_E_LIGHTING)
	# Gizmo only matters while a placement tool is active.
	if _gizmo != null:
		if tool_id == TOOL_L_EFFECTS or tool_id == TOOL_O_OBJECTS:
			_gizmo.set_target(_selected_prop)
		else:
			_gizmo.set_target(null)
			_drag_handle = ""

func _on_effect_picked(id: String) -> void:
	_armed_effect_id = id

func _on_object_picked(id: String) -> void:
	_armed_object_id = id

func _on_active_table_changed(_idx: int) -> void:
	# Live-recolor every spawn cube whose table id matches the (possibly
	# edited) active table's color. Cheap — the placed-spawn list is short.
	for box in _placed_item_spawns:
		if not is_instance_valid(box):
			continue
		var t: Dictionary = _find_table(String(box.table_id))
		if t.is_empty():
			continue
		box.set_color(t.get("color", Color.WHITE))
	# Refresh the container panel too so newly-created or renamed tables
	# show up in its dropdown without needing to reselect the crate.
	_refresh_container_panel()

func _find_table(table_id: String) -> Dictionary:
	for t in _item_tables_panel.tables:
		if String(t.get("id", "")) == table_id:
			return t
	return {}

func _on_space_changed(use_local: bool) -> void:
	if _gizmo != null:
		_gizmo.set_use_local(use_local)

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

func _spawn_effect_at(effect_id: String, world_pos: Vector3) -> void:
	var box: Node3D = Node3D.new()
	box.set_script(EFFECT_BOX_SCRIPT)
	box.effect_id = effect_id
	add_child(box)
	# global_position needs the node in the tree, so set after add_child.
	box.global_position = world_pos
	_placed_props.append(box)
	_select_prop(box)

func _spawn_item_box(table_id: String, color: Color, world_pos: Vector3) -> void:
	var box: Node3D = Node3D.new()
	box.set_script(ITEM_SPAWN_BOX_SCRIPT)
	box.table_id = table_id
	box.color = color
	add_child(box)
	box.global_position = world_pos
	_placed_item_spawns.append(box)

func _remove_item_spawns_in_radius(world_pos: Vector3, radius: float) -> void:
	var keep: Array[Node3D] = []
	for box in _placed_item_spawns:
		if not is_instance_valid(box):
			continue
		if box.global_position.distance_to(world_pos) <= radius:
			box.queue_free()
		else:
			keep.append(box)
	_placed_item_spawns = keep

func _spawn_object_at(object_id: String, world_pos: Vector3) -> void:
	var box: Node3D = Node3D.new()
	box.set_script(OBJECT_BOX_SCRIPT)
	box.object_id = object_id
	add_child(box)
	box.global_position = world_pos
	_placed_props.append(box)
	_select_prop(box)

func _select_prop(box: Node3D) -> void:
	if _selected_prop != null and is_instance_valid(_selected_prop):
		_selected_prop.set_selected(false)
	_selected_prop = box
	if box != null:
		box.set_selected(true)
	# Re-bind the gizmo to the new selection. If nothing's selected the
	# gizmo hides itself; if something IS selected, default to the
	# translate gizmo so the user doesn't need to hit Q just to nudge it.
	if _gizmo != null:
		_gizmo.set_target(_selected_prop)
		if _selected_prop != null and _gizmo.mode == _gizmo.MODE_NONE:
			_gizmo.set_mode(_gizmo.MODE_TRANSLATE_AXES)
	_refresh_container_panel()

# Show + bind the loot-table picker iff the current selection is a crate;
# hide it otherwise. Called from _select_prop and from the table-list
# changed signal so newly-created tables show up immediately.
func _refresh_container_panel() -> void:
	if _container_panel == null:
		return
	if _selected_prop == null or not "object_id" in _selected_prop:
		_container_panel.visible = false
		return
	var oid: String = String(_selected_prop.object_id)
	if not OBJECTS_CATALOG.is_container(oid):
		_container_panel.visible = false
		return
	var current_id: String = String(_selected_prop.get("loot_table_id"))
	var current_rolls: int = int(_selected_prop.get("roll_count_override"))
	# Pull capacity / roll info from a throwaway built crate so the panel
	# shows the same numbers main_bootstrap will use at play.
	var info: String = ""
	var default_rolls: int = 0
	var probe: Node3D = OBJECTS_CATALOG.build(oid)
	if probe != null:
		info = "Capacity: %.0f kg" % float(probe.get("max_weight"))
		default_rolls = int(probe.get("roll_count"))
		probe.queue_free()
	var label: String = "Container: %s" % oid
	_container_panel.bind(label, current_id, _item_tables_panel.tables, info, current_rolls, default_rolls)
	_container_panel.visible = true

func _on_container_table_chosen(table_id: String) -> void:
	if _selected_prop == null or not "loot_table_id" in _selected_prop:
		return
	_selected_prop.loot_table_id = table_id

func _on_container_rolls_changed(rolls: int) -> void:
	if _selected_prop == null or not "roll_count_override" in _selected_prop:
		return
	_selected_prop.roll_count_override = rolls

func _on_lighting_changed(state: Dictionary) -> void:
	# Live-edit feedback + persist for the F9 round-trip. main_bootstrap
	# reads MapState.lighting on play scene start.
	MapState.lighting = state.duplicate(true)
	_apply_lighting(state)

# Apply a lighting dict (same shape as editor_lighting_panel.DEFAULTS) to
# the scene's WorldEnvironment + Sun. Shared by the live-edit hook and
# the F9-restore path so both behave identically.
static func apply_lighting_to(env_node: WorldEnvironment, sun: DirectionalLight3D, state: Dictionary) -> void:
	if env_node == null or sun == null or state.is_empty():
		return
	var env: Environment = env_node.environment
	if env != null:
		env.ambient_light_energy = float(state.get("ambient_energy", 0.5))
		env.ambient_light_color = state.get("ambient_color", Color(0.6, 0.65, 0.7, 1))
		env.background_energy_multiplier = float(state.get("sky_energy", 1.0))
		var sky: Sky = env.sky
		if sky != null and sky.sky_material is ProceduralSkyMaterial:
			var mat: ProceduralSkyMaterial = sky.sky_material
			mat.sky_top_color = state.get("sky_top", mat.sky_top_color)
			mat.sky_horizon_color = state.get("sky_horizon", mat.sky_horizon_color)
	sun.light_energy = float(state.get("sun_energy", 1.0))
	sun.light_color = state.get("sun_color", Color.WHITE)
	# Pitch = elevation above horizon, yaw = compass. Build basis with
	# yaw around Y first then pitch around the rotated X so the sun
	# rotates intuitively (yaw spins, pitch tilts).
	var pitch: float = deg_to_rad(float(state.get("sun_pitch_deg", 45.0)))
	var yaw: float = deg_to_rad(float(state.get("sun_yaw_deg", 30.0)))
	var b: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	var t: Transform3D = sun.global_transform
	t.basis = b
	sun.global_transform = t

func _apply_lighting(state: Dictionary) -> void:
	apply_lighting_to(_world_env, _sun, state)

func _pick_prop_under_cursor() -> void:
	# Ray-vs-AABB pick over every placed effect; closest hit wins.
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var best: Node3D = null
	var best_t: float = INF
	for box in _placed_props:
		if not is_instance_valid(box):
			continue
		# Transform ray into box's local space (handles rotation/scale once
		# gizmos move parts around).
		var inv: Transform3D = box.global_transform.affine_inverse()
		var lo: Vector3 = inv * from
		var ld: Vector3 = inv.basis * dir
		var aabb: AABB = box.get_aabb_local()
		var t: float = _ray_aabb(lo, ld, aabb)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = box
	# Clicking on empty space (no box hit) deselects — same convention as
	# every other 3D editor. Gizmo handle picks short-circuit before this
	# runs, so dragging an arrow off into space won't accidentally drop
	# the selection.
	_select_prop(best)

func _delete_selected_prop() -> void:
	if _selected_prop == null:
		return
	var doomed: Node3D = _selected_prop
	_placed_props.erase(doomed)
	_selected_prop = null
	if _gizmo != null:
		_gizmo.set_target(null)
	_drag_handle = ""
	doomed.queue_free()

func _try_start_gizmo_drag() -> bool:
	if _gizmo == null or _gizmo.mode == _gizmo.MODE_NONE or _selected_prop == null:
		return false
	if _is_over_ui() or _camera.is_looking():
		return false
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var pick: Dictionary = _gizmo.pick_handle(from, dir)
	var handle: String = String(pick.get("handle", ""))
	if handle == "":
		return false
	_drag_handle = handle
	# Resolve the constraint (axis or plane) and capture the grab offset
	# in world space so the cursor anchor doesn't snap on first motion.
	_drag_anchor = _selected_prop.global_position
	if handle.begins_with("r"):
		# Rotate ring drag — capture start basis + initial cursor angle on
		# the ring plane. Motion computes delta angle and applies
		# Basis(axis, delta) * start_basis (deltas-from-start avoid drift).
		_drag_axis = pick.get("axis", Vector3.UP).normalized()
		_drag_start_basis = _selected_prop.global_transform.basis
		var u: Vector3 = _drag_axis.cross(Vector3.UP)
		if u.length() < 0.001:
			u = _drag_axis.cross(Vector3.RIGHT)
		u = u.normalized()
		var v: Vector3 = _drag_axis.cross(u).normalized()
		_drag_axis_u = u
		_drag_axis_v = v
		var hit_r: Dictionary = _ray_plane_hit_world(from, dir, _drag_anchor, _drag_axis)
		if hit_r.is_empty():
			_drag_handle = ""
			return false
		var local_r: Vector3 = hit_r.point - _drag_anchor
		_drag_start_angle = atan2(local_r.dot(v), local_r.dot(u))
	elif handle in ["sx", "sy", "sz", "-sx", "-sy", "-sz"]:
		# Scale axis drag — captures start scale + signed projection along
		# the axis, plus a pivot point at the OPPOSITE face of the box so
		# only the grabbed face moves (one-direction scale, not centered).
		_drag_axis = pick.get("axis", Vector3.RIGHT).normalized()
		_drag_start_scale = _selected_prop.scale
		_drag_start_basis = _selected_prop.global_transform.basis
		_drag_scale_index = "xyz".find(handle.right(1))
		# 1st tier (3-axis MODE_SCALE) = legacy symmetric stretch around
		# origin. 2nd tier (MODE_SCALE_6) = pivot at opposite face so only
		# the grabbed face moves.
		_drag_scale_pivot = (_gizmo.mode == _gizmo.MODE_SCALE_6)
		var positive: bool = not handle.begins_with("-")
		var aabb: AABB = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
		if _selected_prop.has_method("get_aabb_local"):
			aabb = _selected_prop.get_aabb_local()
		var pivot_axis_value: float = aabb.position[_drag_scale_index]
		if not positive:
			pivot_axis_value = aabb.position[_drag_scale_index] + aabb.size[_drag_scale_index]
		_drag_pivot_local = Vector3.ZERO
		_drag_pivot_local[_drag_scale_index] = pivot_axis_value
		var ap_s: Vector3 = _closest_point_on_axis(from, dir, _drag_anchor, _drag_axis)
		var dist_s: float = (ap_s - _drag_anchor).dot(_drag_axis)
		if absf(dist_s) < 0.05:
			dist_s = 0.05 if dist_s >= 0.0 else -0.05
		_drag_start_dist = dist_s
	elif handle.begins_with("p"):
		_drag_normal = pick.get("normal", Vector3.UP)
		var hit_p: Dictionary = _ray_plane_hit_world(from, dir, _drag_anchor, _drag_normal)
		if hit_p.is_empty():
			_drag_handle = ""
			return false
		_drag_offset = _drag_anchor - hit_p.point
	else:
		_drag_axis = pick.get("axis", Vector3.RIGHT)
		var ap: Vector3 = _closest_point_on_axis(from, dir, _drag_anchor, _drag_axis)
		_drag_offset = _drag_anchor - ap
	return true

func _continue_gizmo_drag() -> void:
	if _selected_prop == null or not is_instance_valid(_selected_prop):
		_drag_handle = ""
		return
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	if _drag_handle.begins_with("r"):
		var hit_r: Dictionary = _ray_plane_hit_world(from, dir, _drag_anchor, _drag_axis)
		if hit_r.is_empty():
			return
		var local_r: Vector3 = hit_r.point - _drag_anchor
		var ang: float = atan2(local_r.dot(_drag_axis_v), local_r.dot(_drag_axis_u))
		var delta: float = ang - _drag_start_angle
		var new_basis: Basis = Basis(_drag_axis, delta) * _drag_start_basis
		var t: Transform3D = _selected_prop.global_transform
		t.basis = new_basis
		_selected_prop.global_transform = t
	elif _drag_handle in ["sx", "sy", "sz", "-sx", "-sy", "-sz"]:
		var ap_s: Vector3 = _closest_point_on_axis(from, dir, _drag_anchor, _drag_axis)
		var dist_s: float = (ap_s - _drag_anchor).dot(_drag_axis)
		var ratio: float = dist_s / _drag_start_dist
		# Clamp absurdly tiny/negative ratios so the box doesn't collapse
		# or invert (negative scale silently flips winding everywhere).
		if ratio < 0.05:
			ratio = 0.05
		var idx: int = _drag_scale_index
		var new_axis_scale: float = _drag_start_scale[idx] * ratio
		var new_scale: Vector3 = _drag_start_scale
		new_scale[idx] = new_axis_scale
		_selected_prop.scale = new_scale
		# 6-handle mode also re-anchors the origin so the OPPOSITE face
		# stays put (one-direction sizing). 3-axis mode skips this and
		# stretches symmetrically around origin.
		if _drag_scale_pivot:
			var pivot_world: Vector3 = _drag_anchor + _drag_start_basis * _drag_pivot_local
			var basis_cols: Array = [_drag_start_basis.x, _drag_start_basis.y, _drag_start_basis.z]
			var col_i: Vector3 = basis_cols[idx] * (new_axis_scale / _drag_start_scale[idx])
			var new_offset: Vector3 = col_i * _drag_pivot_local[idx]
			_selected_prop.global_position = pivot_world - new_offset
	elif _drag_handle.begins_with("p"):
		var hit_p: Dictionary = _ray_plane_hit_world(from, dir, _drag_anchor, _drag_normal)
		if hit_p.is_empty():
			return
		_selected_prop.global_position = hit_p.point + _drag_offset
	else:
		var ap: Vector3 = _closest_point_on_axis(from, dir, _drag_anchor, _drag_axis)
		_selected_prop.global_position = ap + _drag_offset

func _closest_point_on_axis(ro: Vector3, rd: Vector3, ap: Vector3, ax: Vector3) -> Vector3:
	# Closest point on the infinite line (ap, ax) to the ray (ro, rd).
	# Uses w = ro - ap (not ap - ro — that flipped signs and inverted
	# every drag direction).
	var u: Vector3 = ax.normalized()
	var w: Vector3 = ro - ap
	var b: float = u.dot(rd)
	var d: float = u.dot(w)
	var e: float = rd.dot(w)
	var denom: float = 1.0 - b * b
	if absf(denom) < 1e-7:
		return ap
	var s: float = (d - b * e) / denom
	return ap + u * s

func _ray_plane_hit_world(ro: Vector3, rd: Vector3, p: Vector3, n: Vector3) -> Dictionary:
	var denom: float = rd.dot(n)
	if absf(denom) < 1e-6:
		return {}
	var t: float = (p - ro).dot(n) / denom
	if t < 0.0:
		return {}
	return {"point": ro + rd * t, "t": t}

func _ray_aabb(o: Vector3, d: Vector3, b: AABB) -> float:
	# Slab method. Returns the entry t along the ray (≥0) or -1.0 if miss.
	var tmin: float = -INF
	var tmax: float = INF
	for i in range(3):
		var oi: float = o[i]
		var di: float = d[i]
		var bmin: float = b.position[i]
		var bmax: float = b.position[i] + b.size[i]
		if absf(di) < 1e-7:
			if oi < bmin or oi > bmax:
				return -1.0
			continue
		var inv_d: float = 1.0 / di
		var t1: float = (bmin - oi) * inv_d
		var t2: float = (bmax - oi) * inv_d
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		tmin = max(tmin, t1)
		tmax = min(tmax, t2)
		if tmin > tmax:
			return -1.0
	if tmax < 0.0:
		return -1.0
	return max(tmin, 0.0)

