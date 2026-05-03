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

const BRUSH_STRENGTH := 12.0    # m/s for raise/lower at full falloff

@onready var _camera: Camera3D = $EditorCamera
@onready var _terrain: Node3D = $Terrain
@onready var _brush_ring: Node3D = $BrushRing
@onready var _top_bar: Control = $UI/TopBar
@onready var _sub_bar: Control = $UI/SubBar
@onready var _radius_widget: Control = $UI/RadiusWidget

var _active_tool: String = TOOL_NONE
var _brush_radius: float = 4.0
var _flatten_target: float = 0.0
var _ramp_start: Vector3 = Vector3.INF

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Restore previously-edited heights if we're coming back from F9 play.
	if MapState.has_map() and MapState.heights.size() == _terrain.heights.size():
		_terrain.heights = MapState.heights.duplicate()
		_terrain.rebuild()
	_brush_ring.terrain = _terrain
	_brush_ring.set_radius(_brush_radius)
	_brush_ring.hide_ring()
	_top_bar.category_picked.connect(_on_category_picked)
	_sub_bar.tool_picked.connect(_on_tool_picked)
	_radius_widget.radius_changed.connect(_on_radius_changed)
	_radius_widget.set_radius(_brush_radius)
	# Default to Terrain → Heights view so the user lands on a useful page.
	_top_bar.select_category("terrain")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("editor_play"):
		_enter_play_mode()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		# Fallback if input map missing — same effect.
		_enter_play_mode()

func _enter_play_mode() -> void:
	# Snapshot the current map into the autoload so the play scene can
	# rebuild the same terrain on the other side of the scene swap.
	MapState.heights = _terrain.heights.duplicate()
	MapState.grid_w = _terrain.GRID_W
	MapState.grid_h = _terrain.GRID_H
	get_tree().change_scene_to_file(PLAY_SCENE)

func _process(delta: float) -> void:
	# Brush preview + LMB-stroke logic only runs when the cursor is free
	# (camera not in look-mode) and a terrain tool is active.
	if _camera.is_looking() or _active_tool == TOOL_NONE:
		_brush_ring.hide_ring()
		return
	var hit := _raycast_cursor()
	if hit.is_empty():
		_brush_ring.hide_ring()
		return
	_brush_ring.set_radius(_brush_radius)
	_brush_ring.place(hit.position)
	if _is_over_ui():
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _active_tool != TOOL_T_RAMP:
		_apply_tool(hit.position, delta)

func _unhandled_input(event: InputEvent) -> void:
	# Ramp uses click-down for start, click-up for end.
	if _active_tool != TOOL_T_RAMP:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _raycast_cursor()
		if hit.is_empty() or _is_over_ui() or _camera.is_looking():
			return
		if event.pressed:
			_ramp_start = hit.position
		else:
			if _ramp_start != Vector3.INF:
				_terrain.ramp_stroke(_ramp_start, hit.position, _brush_radius)
				_ramp_start = Vector3.INF

func _apply_tool(world_pos: Vector3, delta: float) -> void:
	match _active_tool:
		TOOL_T_RAISE:
			_terrain.raise_brush(world_pos, _brush_radius, BRUSH_STRENGTH, delta)
		TOOL_T_LOWER:
			_terrain.lower_brush(world_pos, _brush_radius, BRUSH_STRENGTH, delta)
		TOOL_T_FLATTEN:
			_terrain.flatten_brush(world_pos, _brush_radius, _flatten_target, 4.0, delta)
		TOOL_T_SMOOTH:
			_terrain.smooth_brush(world_pos, _brush_radius, 6.0, delta)

func _raycast_cursor() -> Dictionary:
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var to := from + _camera.project_ray_normal(mouse) * 1000.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
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
	if tool_id == TOOL_T_FLATTEN:
		# Snap target to whatever the cursor is over right now.
		var hit := _raycast_cursor()
		if not hit.is_empty():
			_flatten_target = hit.position.y

func _on_radius_changed(r: float) -> void:
	_brush_radius = r
	_brush_ring.set_radius(r)
