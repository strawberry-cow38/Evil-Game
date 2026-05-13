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
const TOOL_S_ACTORS := "s_actors"
const TOOL_S_ACTORS_REMOVE := "s_actors_remove"
const TOOL_L_EFFECTS := "l_effects"
const TOOL_L_TRIGGERS := "l_triggers"
const TOOL_O_OBJECTS := "o_objects"
const TOOL_E_LIGHTING := "e_lighting"
const TOOL_E_ROADS := "e_roads"
const TOOL_E_PAINT := "e_paint"

const EFFECT_BOX_SCRIPT := preload("res://editor_effect_box.gd")
const OBJECT_BOX_SCRIPT := preload("res://editor_object_box.gd")
const ITEM_SPAWN_BOX_SCRIPT := preload("res://editor_item_spawn_box.gd")
const ACTOR_SPAWN_BOX_SCRIPT := preload("res://editor_actor_spawn_box.gd")
const TRIGGER_BOX_SCRIPT := preload("res://editor_trigger_box.gd")
const GIZMO_SCRIPT := preload("res://editor_gizmo.gd")
const CONTAINER_PANEL_SCRIPT := preload("res://editor_container_panel.gd")
const LIGHTING_PANEL_SCRIPT := preload("res://editor_lighting_panel.gd")
const OBJECT_PROPS_PANEL_SCRIPT := preload("res://editor_object_props_panel.gd")
const PAUSE_MENU_SCRIPT := preload("res://editor_pause_menu.gd")
const ROADS_SCRIPT := preload("res://editor_roads.gd")
const ROADS_PANEL_SCRIPT := preload("res://editor_roads_panel.gd")
const PAINT_PANEL_SCRIPT := preload("res://editor_terrain_paint_panel.gd")
const SNAP_WIDGET_SCRIPT := preload("res://editor_snap_widget.gd")
const EVENTS_PANEL_SCRIPT := preload("res://editor_events_panel.gd")
const TRIGGER_PANEL_SCRIPT := preload("res://editor_trigger_panel.gd")
const MAIN_MENU_SCENE := "res://main_menu.tscn"
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
@onready var _actor_tables_panel: PanelContainer = $UI/ActorTablesPanel
@onready var _clothing_picker_panel: PanelContainer = $UI/ClothingPickerPanel
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
# Multi-select. `_selected_prop` is the *primary* (last clicked) — drives
# the gizmo target + side panels. `_selected_props` is the full set; the
# primary is always its last element. Shift+LMB toggles membership; plain
# LMB replaces. Plain LMB on empty clears everything; shift on empty is
# a no-op.
var _selected_prop: Node3D = null
var _selected_props: Array[Node3D] = []
# Item-spawn cubes (Spawns → Items). Owned separately because they
# don't participate in the gizmo / selection pipeline — they're plain
# colored cubes whose contents come from a roll table at play-mode
# bootstrap.
var _placed_item_spawns: Array[Node3D] = []
# Actor-spawn cubes (Spawns → Actors). Same shape as item spawns but
# routed through the actor-tables panel + the actor catalog at play
# bootstrap.
var _placed_actor_spawns: Array[Node3D] = []
# Translucent cube preview shown while the Spawns → Actors tool is
# active, tinted to the active actor table's color.
var _actor_spawn_ghost: MeshInstance3D = null
var _actor_spawn_ghost_mat: StandardMaterial3D = null
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
# Per-placement settings for the selected object_box (no-collide,
# destructible/HP). Built at runtime, hidden until an object is selected.
var _object_props_panel: PanelContainer = null
# Esc-toggled pause overlay (save / load / main menu). Built at runtime.
var _pause_menu: PanelContainer = null
# Object clipboard. Empty dict = nothing copied. `paste_at_mouse` true
# after a cut so V drops the copy where the cursor is; false after a
# copy so V re-stamps at the original transform (paste-in-place).
var _object_clipboard: Array = []
var _clipboard_paste_at_mouse: bool = false
# Transform clipboard for the Ctrl+B / Ctrl+N pose-snapshot tool. The
# bottom-left Global/Local toggle gates what gets captured: global only
# copies world position, local copies the full world transform (pos +
# rotation + scale). Snapshot survives the source being deleted — the
# values live in this dict, not in any node ref.
var _xform_clipboard: Dictionary = {}
var _use_local_space: bool = false
# Undo / redo stacks. Each entry is {kind: "spawn"/"delete"/"transform",
# data: ...}. spawn → undo deletes via prop_id, redo respawns from
# snapshots. delete → mirror. transform → per-prop_id before/after
# Transform3D maps. New commands clear _redo_stack. _gizmo_drag_start
# captures pre-drag xforms keyed by prop_id so a successful drag pushes
# a single transform command on release.
var _undo_stack: Array = []
var _redo_stack: Array = []
var _gizmo_drag_start: Dictionary = {}
const UNDO_LIMIT: int = 200
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
# Road authoring node. Owns its own visuals; we proxy clicks + E into it
# while the Environment → Roads tool is active.
var _roads_node: Node3D = null
var _roads_panel: PanelContainer = null
# Terrain Paint panel — runtime-built same as the roads panel.
var _paint_panel: PanelContainer = null
var _paint_material_id: int = 1   # 1 = grass
var _paint_shape: String = "circle"
# Snap settings panel — bottom-left, shown while placement tools are active.
var _snap_widget: PanelContainer = null
var _rotation_snap_deg: float = 15.0
# Uniform-scale drag — captured on press, applied each motion frame.
var _drag_uniform_start_dist: float = 1.0
# Triggers + events. Triggers piggyback on _placed_props for picking and
# gizmo binding (they expose set_selected + get_aabb_local). The events
# panel owns the master list; we mirror to MapState on snapshot.
var _trigger_panel: PanelContainer = null
var _events_panel: PanelContainer = null
var _eyedropper_event_id: String = ""
var _hover_event_id: String = ""

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Restore previously-edited heights if we're coming back from F9 play.
	if MapState.has_map() and MapState.heights.size() == _terrain.heights.size():
		_terrain.heights = MapState.heights.duplicate()
		if MapState.terrain_paint.size() == _terrain.paint.size():
			_terrain.paint = MapState.terrain_paint.duplicate()
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
	_actor_tables_panel.set_picker(_clothing_picker_panel)
	_actor_tables_panel.active_table_changed.connect(_on_active_actor_table_changed)
	_actor_tables_panel.visible = false
	_clothing_picker_panel.visible = false
	# Drop-table dropdown on the actor panel mirrors whatever's in the
	# item-tables panel, so push the current list now and any time the item
	# panel changes.
	_actor_tables_panel.set_item_tables_for_drop(_item_tables_panel.tables)
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
	_item_spawn_ghost_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
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
	# Actor-spawn ghost: same idea as the item-spawn ghost but taller so
	# the user can tell them apart at a glance.
	_actor_spawn_ghost_mat = StandardMaterial3D.new()
	_actor_spawn_ghost_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_actor_spawn_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_actor_spawn_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_actor_spawn_ghost_mat.albedo_color = Color(1, 1, 1, 0.45)
	_actor_spawn_ghost = MeshInstance3D.new()
	var ag_mesh := BoxMesh.new()
	ag_mesh.size = Vector3(0.7, 1.6, 0.7)
	_actor_spawn_ghost.mesh = ag_mesh
	_actor_spawn_ghost.material_override = _actor_spawn_ghost_mat
	_actor_spawn_ghost.visible = false
	add_child(_actor_spawn_ghost)
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
	# Object props panel — sits below the container panel on the right
	# rail. Visible only when an object_box is selected.
	_object_props_panel = PanelContainer.new()
	_object_props_panel.set_script(OBJECT_PROPS_PANEL_SCRIPT)
	_object_props_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_object_props_panel.offset_left = -560
	_object_props_panel.offset_right = -292
	_object_props_panel.offset_top = 340
	_object_props_panel.offset_bottom = 480
	_object_props_panel.visible = false
	$UI.add_child(_object_props_panel)
	_object_props_panel.no_collide_changed.connect(_on_no_collide_changed)
	_object_props_panel.destructible_changed.connect(_on_destructible_changed)
	_object_props_panel.hp_changed.connect(_on_hp_changed)
	# Snap widget — sits in the bottom-left corner, just above the brush
	# widget. Visible while a placement tool is active.
	_snap_widget = PanelContainer.new()
	_snap_widget.set_script(SNAP_WIDGET_SCRIPT)
	_snap_widget.anchor_left = 0.0
	_snap_widget.anchor_right = 0.0
	_snap_widget.anchor_top = 1.0
	_snap_widget.anchor_bottom = 1.0
	_snap_widget.offset_left = 8
	_snap_widget.offset_right = 240
	_snap_widget.offset_top = -190
	_snap_widget.offset_bottom = -100
	_snap_widget.visible = false
	$UI.add_child(_snap_widget)
	_snap_widget.rotation_snap_changed.connect(_on_rotation_snap_changed)
	_rotation_snap_deg = _snap_widget.get_rotation_snap_deg()
	# Pause menu — built last so it overlays everything else. Anchored
	# centre-screen via a CenterContainer wrapper so it sits in the middle
	# regardless of viewport size.
	var pause_wrap := CenterContainer.new()
	pause_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_wrap.visible = false
	$UI.add_child(pause_wrap)
	# Dim backdrop so the editor visibly recedes while the menu is up.
	var pause_dim := ColorRect.new()
	pause_dim.color = Color(0, 0, 0, 0.55)
	pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_wrap.add_child(pause_dim)
	_pause_menu = PanelContainer.new()
	_pause_menu.set_script(PAUSE_MENU_SCRIPT)
	pause_wrap.add_child(_pause_menu)
	_pause_menu.resume_pressed.connect(_close_pause_menu)
	_pause_menu.save_pressed.connect(_on_pause_save)
	_pause_menu.load_pressed.connect(_on_pause_load)
	_pause_menu.delete_pressed.connect(_on_pause_delete)
	_pause_menu.new_pressed.connect(_on_pause_new)
	_pause_menu.main_menu_pressed.connect(_on_pause_main_menu)
	# After load, the editor needs to know which container to dim/show, so
	# stash the wrapper on the panel for visibility flips.
	_pause_menu.set_meta("wrap", pause_wrap)
	# Final pass: rehydrate placed props + item tables/spawns from MapState
	# now that every sub-panel exists. Heights/spawns/lighting were already
	# applied above, but those are read-only one-shots; placed visuals need
	# all panels live before they can be added.
	if MapState.has_map() and MapState.placed_props.size() > 0:
		for entry in MapState.placed_props:
			var kind: String = String(entry.get("kind", ""))
			var id: String = String(entry.get("id", ""))
			var xform: Transform3D = entry.get("xform", Transform3D.IDENTITY)
			if id == "":
				continue
			var box: Node3D = Node3D.new()
			if kind == "effect":
				box.set_script(EFFECT_BOX_SCRIPT)
				box.effect_id = id
			elif kind == "object":
				box.set_script(OBJECT_BOX_SCRIPT)
				box.object_id = id
			else:
				continue
			if entry.has("prop_id") and String(entry.get("prop_id", "")) != "":
				box.prop_id = String(entry.get("prop_id"))
			add_child(box)
			box.global_transform = xform
			if kind == "object":
				if entry.has("loot_table_id"):
					box.loot_table_id = String(entry["loot_table_id"])
				if entry.has("roll_count_override"):
					box.roll_count_override = int(entry["roll_count_override"])
				if entry.has("no_collide"):
					box.no_collide = bool(entry["no_collide"])
				if entry.has("destructible"):
					box.destructible = bool(entry["destructible"])
				if entry.has("hp_max"):
					box.hp_max = int(entry["hp_max"])
			_placed_props.append(box)
	if MapState.item_tables.size() > 0:
		_item_tables_panel.set_tables(MapState.item_tables)
	if MapState.item_spawn_points.size() > 0:
		var color_by_id: Dictionary = {}
		for t in MapState.item_tables:
			color_by_id[String(t.get("id", ""))] = t.get("color", Color.WHITE)
		for sp in MapState.item_spawn_points:
			_spawn_item_box(
				String(sp.get("table_id", "")),
				color_by_id.get(String(sp.get("table_id", "")), Color.WHITE),
				sp.get("pos", Vector3.ZERO),
			)
	if MapState.actor_tables.size() > 0:
		_actor_tables_panel.set_tables(MapState.actor_tables)
	# Refresh drop-table dropdown options — item tables may have been
	# pulled from MapState above.
	_actor_tables_panel.set_item_tables_for_drop(_item_tables_panel.tables)
	if MapState.actor_spawn_points.size() > 0:
		var actor_color_by_id: Dictionary = {}
		for t in MapState.actor_tables:
			actor_color_by_id[String(t.get("id", ""))] = t.get("color", Color.WHITE)
		for sp in MapState.actor_spawn_points:
			_spawn_actor_box(
				String(sp.get("table_id", "")),
				actor_color_by_id.get(String(sp.get("table_id", "")), Color.WHITE),
				sp.get("pos", Vector3.ZERO),
			)
	# Roads node. Owns its own visuals; we proxy clicks + E while the
	# Environment → Roads tool is active.
	_roads_node = Node3D.new()
	_roads_node.set_script(ROADS_SCRIPT)
	add_child(_roads_node)
	_roads_node.setup(_terrain)
	if MapState.roads.size() > 0:
		_roads_node.set_state(MapState.roads)
	_roads_node.road_state_changed.connect(_on_roads_changed)
	# Side panel for per-node width + ignore-terrain. Built in code so we
	# don't have to touch the .tscn just to expose two controls.
	_roads_panel = PanelContainer.new()
	_roads_panel.set_script(ROADS_PANEL_SCRIPT)
	_roads_panel.anchor_left = 1.0
	_roads_panel.anchor_right = 1.0
	_roads_panel.anchor_top = 0.0
	_roads_panel.anchor_bottom = 0.0
	_roads_panel.offset_left = -300
	_roads_panel.offset_right = -16
	_roads_panel.offset_top = 90
	_roads_panel.offset_bottom = 640
	$UI.add_child(_roads_panel)
	_roads_panel.width_changed.connect(_on_roads_panel_width)
	_roads_panel.ignore_terrain_changed.connect(_on_roads_panel_ignore)
	_roads_panel.surface_changed.connect(_on_roads_panel_surface)
	_roads_panel.decal_add_request.connect(_on_roads_panel_decal_add)
	_roads_panel.decal_remove_request.connect(_on_roads_panel_decal_remove)
	_roads_panel.decal_change_request.connect(_on_roads_panel_decal_change)
	var surf_entries: Array = []
	for sid in ROADS_SCRIPT.SURFACES.keys():
		var spec: Dictionary = ROADS_SCRIPT.SURFACES[sid]
		surf_entries.append({"id": sid, "label": String(spec.get("label", sid))})
	_roads_panel.populate_surfaces(surf_entries)
	# Paint panel — runtime-built like the roads panel. Anchored to the
	# right edge under the sub-bar.
	_paint_panel = PanelContainer.new()
	_paint_panel.set_script(PAINT_PANEL_SCRIPT)
	_paint_panel.anchor_left = 1.0
	_paint_panel.anchor_right = 1.0
	_paint_panel.anchor_top = 0.0
	_paint_panel.anchor_bottom = 0.0
	_paint_panel.offset_left = -260
	_paint_panel.offset_right = -16
	_paint_panel.offset_top = 90
	_paint_panel.offset_bottom = 330
	$UI.add_child(_paint_panel)
	_paint_panel.material_changed.connect(_on_paint_material)
	_paint_panel.shape_changed.connect(_on_paint_shape)
	# Events panel (left rail) — global named-events list with eyedropper.
	_events_panel = PanelContainer.new()
	_events_panel.set_script(EVENTS_PANEL_SCRIPT)
	_events_panel.anchor_left = 0.0
	_events_panel.anchor_right = 0.0
	_events_panel.anchor_top = 0.0
	_events_panel.anchor_bottom = 0.0
	_events_panel.offset_left = 8
	_events_panel.offset_right = 340
	_events_panel.offset_top = 90
	_events_panel.offset_bottom = 540
	_events_panel.visible = false
	$UI.add_child(_events_panel)
	_events_panel.eyedropper_armed.connect(_on_eyedropper_armed)
	_events_panel.eyedropper_disarmed.connect(_on_eyedropper_disarmed)
	_events_panel.target_hover.connect(_on_event_hover)
	_events_panel.target_unhover.connect(_on_event_unhover)
	_events_panel.events_changed.connect(_on_events_changed)
	# Trigger panel (right rail) — per-trigger settings.
	_trigger_panel = PanelContainer.new()
	_trigger_panel.set_script(TRIGGER_PANEL_SCRIPT)
	_trigger_panel.anchor_left = 1.0
	_trigger_panel.anchor_right = 1.0
	_trigger_panel.anchor_top = 0.0
	_trigger_panel.anchor_bottom = 0.0
	_trigger_panel.offset_left = -340
	_trigger_panel.offset_right = -8
	_trigger_panel.offset_top = 90
	_trigger_panel.offset_bottom = 630
	_trigger_panel.visible = false
	$UI.add_child(_trigger_panel)
	_trigger_panel.set_events_source(_events_panel)
	_trigger_panel.trigger_changed.connect(_on_trigger_changed)
	# Object props panel gains a Focus-Event hook into the events panel.
	_object_props_panel.event_focused.connect(_on_object_event_focused)
	# Hydrate events + triggers from MapState (round-trip from F9 / load).
	if MapState.map_events.size() > 0:
		_events_panel.set_events(MapState.map_events)
	for entry in MapState.placed_triggers:
		var tb: Node3D = Node3D.new()
		tb.set_script(TRIGGER_BOX_SCRIPT)
		tb.prop_id = String(entry.get("prop_id", ""))
		tb.trigger_id = String(entry.get("trigger_id", ""))
		tb.conditions = (entry.get("conditions", []) as Array).duplicate(true)
		tb.logic_op = String(entry.get("logic_op", "and"))
		tb.fire_event_ids = (entry.get("fire_event_ids", []) as Array).duplicate()
		tb.delay = float(entry.get("delay", 0.0))
		tb.inter_event_delay = float(entry.get("inter_event_delay", 0.0))
		tb.repeat_mode = String(entry.get("repeat_mode", "once"))
		tb.repeat_count = int(entry.get("repeat_count", 1))
		tb.repeat_cooldown = float(entry.get("repeat_cooldown", 1.0))
		tb.destroy_after_fire = bool(entry.get("destroy_after_fire", false))
		tb.visible_in_play = bool(entry.get("visible_in_play", false))
		add_child(tb)
		tb.global_transform = entry.get("xform", Transform3D.IDENTITY)
		_placed_props.append(tb)

func _on_rotation_snap_changed(deg: float) -> void:
	_rotation_snap_deg = deg

func _on_paint_material(mat_id: int) -> void:
	_paint_material_id = mat_id

func _on_paint_shape(s: String) -> void:
	_paint_shape = s
	_brush_ring.set_shape(s)

func _on_roads_changed() -> void:
	# Mirror the in-memory road state back to MapState so F9 + saves see
	# the latest edits without us pushing on every keystroke from editor.gd.
	MapState.roads = _roads_node.get_state()
	_refresh_roads_panel()

func _refresh_roads_panel() -> void:
	if _roads_panel == null:
		return
	if _active_tool != TOOL_E_ROADS:
		return
	var info: Dictionary = _roads_node.selected_info()
	if info.get("has", false):
		_roads_panel.refresh(float(info["width"]), bool(info["ignore_terrain"]), String(info["label"]), String(info.get("surface", "")), _roads_node.selected_road_decals())
	else:
		_roads_panel.refresh(-1.0, false, "Roads: nothing selected", "", [])

func _on_roads_panel_width(v: float) -> void:
	_roads_node.set_selected_width(v)

func _on_roads_panel_ignore(v: bool) -> void:
	_roads_node.set_selected_ignore_terrain(v)

func _on_roads_panel_surface(sid: String) -> void:
	_roads_node.set_selected_surface(sid)

func _on_roads_panel_decal_add(decal: Dictionary) -> void:
	_roads_node.add_decal_to_selected(decal)

func _on_roads_panel_decal_remove(index: int) -> void:
	_roads_node.remove_decal_from_selected(index)

func _on_roads_panel_decal_change(index: int, field: String, value) -> void:
	_roads_node.update_decal_on_selected(index, field, value)

func _input(event: InputEvent) -> void:
	# Esc toggles the pause menu. While it's open we swallow other shortcuts
	# so typing into the save-name field doesn't trigger F9 / Q / etc.
	if event.is_action_pressed("ui_cancel"):
		if _is_pause_menu_open():
			_close_pause_menu()
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _is_pause_menu_open():
		return
	# F9 → play mode. Either the input action OR the raw key fires it,
	# but not both (after _enter_play_mode the scene is freed so we
	# must not touch self afterwards).
	var is_f9: bool = event.is_action_pressed("editor_play") \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9)
	if is_f9:
		_enter_play_mode()
		return
	# E → place an armed effect or object at the cursor (depends on tool).
	# Under the Roads tool, E toggles grab-mode on the selected node so the
	# user can drag it with the cursor (LMB or another E commits).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if not _camera.is_looking() and not _is_over_ui():
			if _active_tool == TOOL_E_ROADS:
				var mp_e := get_viewport().get_mouse_position()
				var ro_e := _camera.project_ray_origin(mp_e)
				var rd_e := _camera.project_ray_normal(mp_e)
				_roads_node.toggle_grab_at_cursor(ro_e, rd_e)
			elif _active_tool == TOOL_L_EFFECTS and _armed_effect_id != "":
				var hit := _raycast_cursor()
				if not hit.is_empty():
					_spawn_effect_at(_armed_effect_id, hit.position)
			elif _active_tool == TOOL_O_OBJECTS and _armed_object_id != "":
				var hit2 := _raycast_cursor()
				if not hit2.is_empty():
					_spawn_object_at(_armed_object_id, hit2.position)
			elif _active_tool == TOOL_L_TRIGGERS:
				var hit3 := _raycast_cursor()
				if not hit3.is_empty():
					_spawn_trigger_at(hit3.position)
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
	# Delete → remove selected effect, or active road node.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
		if _active_tool == TOOL_E_ROADS:
			_roads_node.delete_selected_node()
		elif _selected_prop != null and not _camera.is_looking():
			_delete_selected_prop()
	# [ / ] → adjust width of the active road node (per-node).
	if event is InputEventKey and event.pressed and not event.echo and _active_tool == TOOL_E_ROADS and not _camera.is_looking() and not _is_over_ui():
		if event.keycode == KEY_BRACKETLEFT:
			_roads_node.adjust_selected_width(-0.5)
		elif event.keycode == KEY_BRACKETRIGHT:
			_roads_node.adjust_selected_width(0.5)
	# F1 → toggle road overlay visibility (spheres + handles). Mesh stays.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		if _roads_node != null:
			_roads_node.set_overlays_visible(not _roads_node.overlays_visible())
	# Ctrl+C / Ctrl+X / Ctrl+V on object boxes. Effects + spawns aren't
	# clipboard-eligible (no good "what does it mean" story for those yet).
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		if event.keycode == KEY_C:
			_clipboard_copy()
		elif event.keycode == KEY_X:
			_clipboard_cut()
		elif event.keycode == KEY_V:
			_clipboard_paste()
		elif event.keycode == KEY_B:
			_xform_capture()
		elif event.keycode == KEY_N:
			_xform_apply()
		elif event.keycode == KEY_Z:
			# Ctrl+Shift+Z is the conventional alt redo binding.
			if event.shift_pressed:
				_apply_redo()
			else:
				_apply_undo()
		elif event.keycode == KEY_Y:
			_apply_redo()

func _enter_play_mode() -> void:
	_snapshot_to_mapstate()
	get_tree().change_scene_to_file(PLAY_SCENE)

func _snapshot_to_mapstate() -> void:
	# Roll up everything the editor has authored into the MapState autoload
	# so it survives a scene swap (F9 → play, or Main Menu return) and so
	# MapIO can serialize it to disk for save-to-file.
	MapState.heights = _terrain.heights.duplicate()
	MapState.terrain_paint = _terrain.paint.duplicate()
	MapState.grid_w = _terrain.GRID_W
	MapState.grid_h = _terrain.GRID_H
	MapState.placed_props.clear()
	for box in _placed_props:
		if not is_instance_valid(box):
			continue
		var kind: String = ""
		var id: String = ""
		if "trigger_id" in box:
			# Triggers serialise separately — skip the placed_props pass.
			continue
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
			"prop_id": String(box.get("prop_id")),
			"xform": box.global_transform,
		}
		# Container objects carry their assigned loot table forward so the
		# play-mode bootstrap can roll loot into the spawned crate.
		if kind == "object" and "loot_table_id" in box:
			entry["loot_table_id"] = String(box.loot_table_id)
		if kind == "object" and "roll_count_override" in box:
			entry["roll_count_override"] = int(box.roll_count_override)
		if kind == "object" and "no_collide" in box:
			entry["no_collide"] = bool(box.no_collide)
		if kind == "object" and "destructible" in box:
			entry["destructible"] = bool(box.destructible)
			entry["hp_max"] = int(box.hp_max)
		MapState.placed_props.append(entry)
	# Triggers + named events snapshot.
	MapState.placed_triggers.clear()
	for box in _placed_props:
		if not is_instance_valid(box) or not "trigger_id" in box:
			continue
		MapState.placed_triggers.append({
			"prop_id":           String(box.prop_id),
			"trigger_id":        String(box.trigger_id),
			"xform":             box.global_transform,
			"conditions":        (box.conditions as Array).duplicate(true),
			"logic_op":          String(box.logic_op),
			"fire_event_ids":    (box.fire_event_ids as Array).duplicate(),
			"delay":             float(box.delay),
			"inter_event_delay": float(box.inter_event_delay),
			"repeat_mode":       String(box.repeat_mode),
			"repeat_count":      int(box.repeat_count),
			"repeat_cooldown":   float(box.repeat_cooldown),
			"destroy_after_fire": bool(box.destroy_after_fire),
			"visible_in_play":   bool(box.visible_in_play),
		})
	MapState.map_events.clear()
	if _events_panel != null:
		for ev in _events_panel.events:
			MapState.map_events.append(ev.duplicate(true))
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
	# Actor tables + placed actor cubes — same deep-dup pattern as items so
	# the play scene never aliases editor state.
	MapState.actor_tables.clear()
	for t in _actor_tables_panel.tables:
		MapState.actor_tables.append(t.duplicate(true))
	MapState.actor_spawn_points.clear()
	for box in _placed_actor_spawns:
		if not is_instance_valid(box):
			continue
		MapState.actor_spawn_points.append({
			"table_id": String(box.table_id),
			"pos": box.global_position,
		})
	if _roads_node != null:
		MapState.roads = _roads_node.get_state()

func _restore_from_mapstate() -> void:
	# Inverse of _snapshot_to_mapstate. Wipes whatever's currently in the
	# editor and rebuilds it from MapState. Called after MapIO.load_map and
	# from _ready when MapState already carries data (F9 round-trip).
	# Heights — adopt only when the source grid matches; size mismatch
	# means a foreign map and we'd rather skip than crash.
	if MapState.has_map() and MapState.heights.size() == _terrain.heights.size():
		_terrain.heights = MapState.heights.duplicate()
		if MapState.terrain_paint.size() == _terrain.paint.size():
			_terrain.paint = MapState.terrain_paint.duplicate()
		_terrain.rebuild()
	# Clear placed visuals.
	for box in _placed_props:
		if is_instance_valid(box):
			box.queue_free()
	_placed_props.clear()
	for box in _placed_item_spawns:
		if is_instance_valid(box):
			box.queue_free()
	_placed_item_spawns.clear()
	for box in _placed_actor_spawns:
		if is_instance_valid(box):
			box.queue_free()
	_placed_actor_spawns.clear()
	for s in _spawn_visuals:
		if is_instance_valid(s):
			s.queue_free()
	_spawn_visuals.clear()
	_selected_prop = null
	_selected_props.clear()
	# Load wipes history — old commands reference now-freed nodes.
	_undo_stack.clear()
	_redo_stack.clear()
	if _gizmo != null:
		_gizmo.set_target(null)
	# Rehydrate spawns + props.
	for pos in MapState.player_spawns:
		_add_spawn_visual(pos)
	for entry in MapState.placed_props:
		var kind: String = String(entry.get("kind", ""))
		var id: String = String(entry.get("id", ""))
		var xform: Transform3D = entry.get("xform", Transform3D.IDENTITY)
		if id == "":
			continue
		var box: Node3D = Node3D.new()
		if kind == "effect":
			box.set_script(EFFECT_BOX_SCRIPT)
			box.effect_id = id
		elif kind == "object":
			box.set_script(OBJECT_BOX_SCRIPT)
			box.object_id = id
		else:
			continue
		if entry.has("prop_id") and String(entry.get("prop_id", "")) != "":
			box.prop_id = String(entry.get("prop_id"))
		add_child(box)
		box.global_transform = xform
		if kind == "object":
			if entry.has("loot_table_id"):
				box.loot_table_id = String(entry["loot_table_id"])
			if entry.has("roll_count_override"):
				box.roll_count_override = int(entry["roll_count_override"])
			if entry.has("no_collide"):
				box.no_collide = bool(entry["no_collide"])
			if entry.has("destructible"):
				box.destructible = bool(entry["destructible"])
			if entry.has("hp_max"):
				box.hp_max = int(entry["hp_max"])
		_placed_props.append(box)
	# Triggers + events (round-trip from F9 / load).
	if _events_panel != null:
		_events_panel.set_events(MapState.map_events)
	for tentry in MapState.placed_triggers:
		var tb: Node3D = Node3D.new()
		tb.set_script(TRIGGER_BOX_SCRIPT)
		tb.prop_id = String(tentry.get("prop_id", ""))
		tb.trigger_id = String(tentry.get("trigger_id", ""))
		tb.conditions = (tentry.get("conditions", []) as Array).duplicate(true)
		tb.logic_op = String(tentry.get("logic_op", "and"))
		tb.fire_event_ids = (tentry.get("fire_event_ids", []) as Array).duplicate()
		tb.delay = float(tentry.get("delay", 0.0))
		tb.inter_event_delay = float(tentry.get("inter_event_delay", 0.0))
		tb.repeat_mode = String(tentry.get("repeat_mode", "once"))
		tb.repeat_count = int(tentry.get("repeat_count", 1))
		tb.repeat_cooldown = float(tentry.get("repeat_cooldown", 1.0))
		tb.destroy_after_fire = bool(tentry.get("destroy_after_fire", false))
		tb.visible_in_play = bool(tentry.get("visible_in_play", false))
		add_child(tb)
		tb.global_transform = tentry.get("xform", Transform3D.IDENTITY)
		_placed_props.append(tb)
	# Item-spawn cubes — colour comes from the matching table.
	var color_by_id: Dictionary = {}
	for t in MapState.item_tables:
		color_by_id[String(t.get("id", ""))] = t.get("color", Color.WHITE)
	for sp in MapState.item_spawn_points:
		var tid: String = String(sp.get("table_id", ""))
		var pos: Vector3 = sp.get("pos", Vector3.ZERO)
		var col: Color = color_by_id.get(tid, Color.WHITE)
		_spawn_item_box(tid, col, pos)
	# Tables -> picker panel + lighting -> sky/sun.
	if _item_tables_panel != null:
		_item_tables_panel.set_tables(MapState.item_tables)
	if _actor_tables_panel != null:
		_actor_tables_panel.set_tables(MapState.actor_tables)
		_actor_tables_panel.set_item_tables_for_drop(_item_tables_panel.tables)
	# Actor cubes — colour comes from the matching actor table.
	var actor_color_by_id: Dictionary = {}
	for t in MapState.actor_tables:
		actor_color_by_id[String(t.get("id", ""))] = t.get("color", Color.WHITE)
	for sp in MapState.actor_spawn_points:
		var atid: String = String(sp.get("table_id", ""))
		var apos: Vector3 = sp.get("pos", Vector3.ZERO)
		_spawn_actor_box(atid, actor_color_by_id.get(atid, Color.WHITE), apos)
	if not MapState.lighting.is_empty():
		_lighting_panel.set_state(MapState.lighting)
		_apply_lighting(MapState.lighting)
	if _roads_node != null:
		_roads_node.set_state(MapState.roads)

func _open_pause_menu() -> void:
	if _pause_menu == null:
		return
	var wrap: Node = _pause_menu.get_meta("wrap")
	if wrap is Control:
		(wrap as Control).visible = true
	_pause_menu.open()

func _close_pause_menu() -> void:
	if _pause_menu == null:
		return
	var wrap: Node = _pause_menu.get_meta("wrap")
	if wrap is Control:
		(wrap as Control).visible = false
	_pause_menu.close()

func _is_pause_menu_open() -> bool:
	# Read the wrap's visibility — _pause_menu itself stays visible inside
	# the wrap so its own Controls (LineEdit etc) lay out correctly. The
	# wrap is the gate, not the panel.
	if _pause_menu == null:
		return false
	var wrap: Node = _pause_menu.get_meta("wrap")
	return wrap is Control and (wrap as Control).visible

func _on_pause_save(save_name: String) -> void:
	_snapshot_to_mapstate()
	if MapIO.save_map(save_name):
		_pause_menu.set_status("Saved: %s" % save_name)
		_pause_menu.refresh()
	else:
		_pause_menu.set_status("Save failed.")

func _on_pause_load(save_name: String) -> void:
	if MapIO.load_map(save_name):
		_restore_from_mapstate()
		_pause_menu.set_status("Loaded: %s" % save_name)
		_close_pause_menu()
	else:
		_pause_menu.set_status("Load failed.")

func _on_pause_delete(save_name: String) -> void:
	if MapIO.delete_save(save_name):
		_pause_menu.set_status("Deleted: %s" % save_name)
		_pause_menu.refresh()
	else:
		_pause_menu.set_status("Delete failed.")

func _on_pause_new() -> void:
	# Wipe MapState + editor — gives the user a blank canvas without
	# kicking them back to the main menu.
	MapState.clear()
	_restore_from_mapstate()
	_pause_menu.set_status("New empty map.")

func _on_pause_main_menu() -> void:
	# Snapshot first so the autoload still has the working map if the user
	# wants to come back via the main menu's editor button.
	_snapshot_to_mapstate()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _process(delta: float) -> void:
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# Hide all hover visuals by default; per-tool branches re-enable them.
	_spawn_ghost.visible = false
	if _item_spawn_ghost != null:
		_item_spawn_ghost.visible = false
	if _actor_spawn_ghost != null:
		_actor_spawn_ghost.visible = false
	_flatten_ring.hide_ring()
	# Roads grab-follow: if the user has E-grabbed a node, slide it under
	# the cursor every frame so they see it tracking before they commit.
	if _active_tool == TOOL_E_ROADS and _roads_node != null and _roads_node.is_grabbing():
		if not _camera.is_looking() and not _is_over_ui():
			var grab_hit := _raycast_cursor()
			if not grab_hit.is_empty():
				_roads_node.on_cursor_world(grab_hit.position)
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
	# Actor-spawn ghost: tinted to active actor table colour.
	if _active_tool == TOOL_S_ACTORS:
		_brush_ring.hide_ring()
		if _is_over_ui():
			return
		var at: Dictionary = _actor_tables_panel.get_active_table()
		if at.is_empty():
			return
		var ag_hit := _raycast_cursor()
		if ag_hit.is_empty():
			return
		var agp: Vector3 = ag_hit.position
		agp.y = _terrain.sample_height(agp)
		_actor_spawn_ghost.global_position = agp + Vector3(0, 0.8, 0)
		var acol: Color = at.get("color", Color.WHITE)
		_actor_spawn_ghost_mat.albedo_color = Color(acol.r, acol.g, acol.b, 0.45)
		_actor_spawn_ghost.visible = true
		return
	# Brush ring only makes sense for terrain brushes; spawn tools use
	# pinpoint clicks.
	var is_brush_tool: bool = _active_tool in [TOOL_T_RAISE, TOOL_T_LOWER, TOOL_T_FLATTEN, TOOL_T_SMOOTH, TOOL_T_RAMP, TOOL_S_ITEMS_REMOVE, TOOL_S_ACTORS_REMOVE, TOOL_E_PAINT]
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
	# Roads tool: a quick RMB tap (press+release with no significant motion)
	# deselects the current road. A held RMB drag is camera look — handled
	# by editor_camera. We sample the tap state on RMB release.
	if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		if _active_tool == TOOL_E_ROADS and not _is_over_ui() and _camera.consume_tap():
			_roads_node.deselect()
			return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# In-progress drag always consumes the release, even over UI / look-mode.
	if _drag_handle != "" and not event.pressed:
		_finish_gizmo_drag()
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
	# Actor-spawn place: drop a colored cube tied to the active actor table.
	if _active_tool == TOOL_S_ACTORS and event.pressed:
		var at: Dictionary = _actor_tables_panel.get_active_table()
		if at.is_empty():
			return
		var hit_a := _raycast_cursor()
		if hit_a.is_empty():
			return
		var p_a: Vector3 = hit_a.position
		p_a.y = _terrain.sample_height(p_a)
		_spawn_actor_box(String(at.get("id", "")), at.get("color", Color.WHITE), p_a)
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
	# Roads: LMB places a node on the active road (or selects one if the
	# click landed on an existing node). If a grab is in progress, LMB
	# commits the grab instead of placing.
	if _active_tool == TOOL_E_ROADS and event.pressed:
		if _roads_node.is_grabbing():
			_roads_node.commit_grab()
			return
		var mp := get_viewport().get_mouse_position()
		var ro := _camera.project_ray_origin(mp)
		var rd := _camera.project_ray_normal(mp)
		var picked: Vector3i = _roads_node.pick_node(ro, rd)
		if picked.x >= 0:
			_roads_node.on_click(Vector3.ZERO, picked)
			return
		var hit_r := _raycast_cursor()
		if hit_r.is_empty():
			return
		var pr: Vector3 = hit_r.position
		pr.y = _terrain.sample_height(pr)
		_roads_node.on_click(pr, Vector3i(-1, -1, -1))
		return
	# Effects / Objects / Triggers tools: LMB picks a gizmo handle first
	# (so dragging an arrow doesn't deselect the prop underneath). Falls
	# through to pick the box itself if no handle was hit. Release ends
	# the drag. When the events-panel eyedropper is armed, the LMB pick
	# instead routes the prop_id back to the armed event.
	if _active_tool == TOOL_L_EFFECTS or _active_tool == TOOL_O_OBJECTS or _active_tool == TOOL_L_TRIGGERS:
		if event.pressed:
			if _eyedropper_event_id != "":
				_handle_eyedropper_click()
				return
			if _try_start_gizmo_drag():
				return
			_pick_prop_under_cursor()
		else:
			if _drag_handle != "":
				_finish_gizmo_drag()
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
		TOOL_S_ACTORS_REMOVE:
			_remove_actor_spawns_in_radius(world_pos, _brush_radius)
		TOOL_E_PAINT:
			_terrain.paint_brush(world_pos, _brush_radius, 4.0 * s, delta, _paint_material_id, _paint_shape)

func _raycast_cursor() -> Dictionary:
	# Two cursor modes:
	#  - Terrain brush tools: mouse vs flat y=0 plane. Cheap, fully
	#    decoupled from terrain state so brush input never stalls.
	#  - Spawn / non-terrain tools: 3D ray vs the live heightmap so
	#    markers land on the actual surface under the cursor.
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var is_terrain_tool: bool = _active_tool in [TOOL_T_RAISE, TOOL_T_LOWER, TOOL_T_FLATTEN, TOOL_T_SMOOTH, TOOL_T_RAMP, TOOL_E_PAINT]
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
	for c in [_top_bar, _sub_bar, _radius_widget, _effects_panel, _objects_panel, _item_tables_panel, _item_picker_panel, _actor_tables_panel, _clothing_picker_panel, _space_toggle, _container_panel, _lighting_panel, _object_props_panel, _paint_panel, _roads_panel, _snap_widget, _events_panel, _trigger_panel]:
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
	var is_brush_tool: bool = tool_id == TOOL_T_RAISE or tool_id == TOOL_T_LOWER or tool_id == TOOL_T_FLATTEN or tool_id == TOOL_T_SMOOTH or tool_id == TOOL_T_RAMP or tool_id == TOOL_S_PLACE_SPAWN or tool_id == TOOL_S_DELETE_SPAWN or tool_id == TOOL_S_ITEMS or tool_id == TOOL_S_ITEMS_REMOVE or tool_id == TOOL_S_ACTORS or tool_id == TOOL_S_ACTORS_REMOVE or tool_id == TOOL_E_PAINT
	_radius_widget.visible = is_brush_tool
	if _paint_panel != null:
		_paint_panel.visible = (tool_id == TOOL_E_PAINT)
		if tool_id == TOOL_E_PAINT:
			_brush_ring.set_shape(_paint_shape)
		else:
			_brush_ring.set_shape("circle")
	_space_toggle.visible = tool_id == TOOL_L_EFFECTS or tool_id == TOOL_O_OBJECTS or tool_id == TOOL_L_TRIGGERS
	if _snap_widget != null:
		_snap_widget.visible = tool_id == TOOL_L_EFFECTS or tool_id == TOOL_O_OBJECTS or tool_id == TOOL_L_TRIGGERS
	if _events_panel != null:
		_events_panel.visible = (tool_id == TOOL_L_TRIGGERS)
		if tool_id == TOOL_L_TRIGGERS:
			_events_panel.set_events(_events_panel.events)  # refresh row UI
			_trigger_panel.set_item_tables(_item_tables_panel.tables)
			_trigger_panel.set_actor_tables(_actor_tables_panel.tables)
	if _roads_panel != null:
		_roads_panel.visible = (tool_id == TOOL_E_ROADS)
		if tool_id == TOOL_E_ROADS:
			_refresh_roads_panel()
	_effects_panel.visible = (tool_id == TOOL_L_EFFECTS)
	_objects_panel.visible = (tool_id == TOOL_O_OBJECTS)
	_item_tables_panel.visible = (tool_id == TOOL_S_ITEMS)
	if tool_id != TOOL_S_ITEMS:
		_item_picker_panel.visible = false
	# Push fresh item-table list into the actor panel so the Drop dropdown
	# is current the moment the user opens the Actors tool.
	if tool_id == TOOL_S_ACTORS:
		_actor_tables_panel.set_item_tables_for_drop(_item_tables_panel.tables)
	_actor_tables_panel.visible = (tool_id == TOOL_S_ACTORS)
	if tool_id != TOOL_S_ACTORS:
		_clothing_picker_panel.visible = false
	if _lighting_panel != null:
		_lighting_panel.visible = (tool_id == TOOL_E_LIGHTING)
	# Gizmo only matters while a placement tool is active.
	if _gizmo != null:
		if tool_id == TOOL_L_EFFECTS or tool_id == TOOL_O_OBJECTS or tool_id == TOOL_L_TRIGGERS:
			_gizmo.set_target(_selected_prop)
		else:
			_gizmo.set_target(null)
			_drag_handle = ""
	# Trigger panel only relevant while triggers tool is active AND the
	# current selection is a trigger box.
	_refresh_trigger_panel()

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
	# Same story for the actor panel's drop-table dropdown — it caches the
	# item-tables list so renames/creates need a fresh push.
	if _actor_tables_panel != null:
		_actor_tables_panel.set_item_tables_for_drop(_item_tables_panel.tables)

func _on_active_actor_table_changed(_idx: int) -> void:
	# Live-recolor every actor cube whose table id matches the active
	# table's color, mirroring the item-spawn hook.
	for box in _placed_actor_spawns:
		if not is_instance_valid(box):
			continue
		var t: Dictionary = _find_actor_table(String(box.table_id))
		if t.is_empty():
			continue
		box.set_color(t.get("color", Color.WHITE))

func _find_actor_table(table_id: String) -> Dictionary:
	for t in _actor_tables_panel.tables:
		if String(t.get("id", "")) == table_id:
			return t
	return {}

func _spawn_actor_box(table_id: String, color: Color, world_pos: Vector3) -> void:
	var box: Node3D = Node3D.new()
	box.set_script(ACTOR_SPAWN_BOX_SCRIPT)
	box.table_id = table_id
	box.color = color
	add_child(box)
	box.global_position = world_pos
	_placed_actor_spawns.append(box)

func _remove_actor_spawns_in_radius(world_pos: Vector3, radius: float) -> void:
	var keep: Array[Node3D] = []
	for box in _placed_actor_spawns:
		if not is_instance_valid(box):
			continue
		if box.global_position.distance_to(world_pos) <= radius:
			box.queue_free()
		else:
			keep.append(box)
	_placed_actor_spawns = keep

func _find_table(table_id: String) -> Dictionary:
	for t in _item_tables_panel.tables:
		if String(t.get("id", "")) == table_id:
			return t
	return {}

func _on_space_changed(use_local: bool) -> void:
	_use_local_space = use_local
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
		_spawn_marker_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_spawn_marker_mat.albedo_color = Color(0.25, 0.95, 1.0, 1.0)
		_spawn_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _spawn_marker_mat

func _get_ghost_material() -> StandardMaterial3D:
	if _spawn_ghost_mat == null:
		_spawn_ghost_mat = StandardMaterial3D.new()
		_spawn_ghost_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
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
	_push_undo({"kind": "spawn", "snapshots": [_snapshot_prop_box(box)]})

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
	_push_undo({"kind": "spawn", "snapshots": [_snapshot_prop_box(box)]})

func _select_prop(box: Node3D) -> void:
	# Single-select replacement. Clears any existing multi-select.
	if box == null:
		_apply_selection([], null)
	else:
		_apply_selection([box], box)

func _apply_selection(new_set: Array, primary: Node3D) -> void:
	# Turn off old highlights, swap arrays, turn on new ones, rebind gizmo.
	# Primary is the gizmo target and side-panel source; it must be a
	# member of new_set or null. new_set may be empty for clear.
	for box in _selected_props:
		if box != null and is_instance_valid(box) and box.has_method("set_selected"):
			box.set_selected(false)
	var typed: Array[Node3D] = []
	for b in new_set:
		if b != null and is_instance_valid(b):
			typed.append(b as Node3D)
	_selected_props = typed
	_selected_prop = primary if primary != null and is_instance_valid(primary) else null
	for box in _selected_props:
		if box.has_method("set_selected"):
			box.set_selected(true)
	if _gizmo != null:
		_gizmo.set_target(_selected_prop)
		if _selected_prop != null and _gizmo.mode == _gizmo.MODE_NONE:
			_gizmo.set_mode(_gizmo.MODE_TRANSLATE_AXES)
	_refresh_container_panel()
	_refresh_object_props_panel()
	_refresh_trigger_panel()

func _toggle_in_selection(box: Node3D) -> void:
	# Shift+click handler. If already selected, remove (primary falls
	# back to whatever else is left). If not selected, add as primary.
	if box == null:
		return
	var idx: int = _selected_props.find(box)
	var new_set: Array = []
	var primary: Node3D = null
	if idx >= 0:
		for b in _selected_props:
			if b != box:
				new_set.append(b)
		primary = new_set.back() if new_set.size() > 0 else null
	else:
		for b in _selected_props:
			new_set.append(b)
		new_set.append(box)
		primary = box
	_apply_selection(new_set, primary)

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

func _refresh_object_props_panel() -> void:
	if _object_props_panel == null:
		return
	if _selected_prop == null or not "object_id" in _selected_prop:
		_object_props_panel.visible = false
		return
	var oid: String = String(_selected_prop.object_id)
	var events: Array = []
	if _events_panel != null and "prop_id" in _selected_prop:
		events = _events_panel.events_for_prop(String(_selected_prop.prop_id))
	_object_props_panel.bind(
		"Object: %s" % oid,
		bool(_selected_prop.get("no_collide")),
		bool(_selected_prop.get("destructible")),
		int(_selected_prop.get("hp_max")),
		events,
	)
	_object_props_panel.visible = true

func _refresh_trigger_panel() -> void:
	if _trigger_panel == null:
		return
	var is_trigger: bool = _selected_prop != null and "trigger_id" in _selected_prop
	if not is_trigger or _active_tool != TOOL_L_TRIGGERS:
		_trigger_panel.visible = false
		return
	_trigger_panel.set_item_tables(_item_tables_panel.tables)
	_trigger_panel.set_actor_tables(_actor_tables_panel.tables)
	_trigger_panel.bind(_selected_prop)
	_trigger_panel.visible = true

func _spawn_trigger_at(world_pos: Vector3) -> void:
	var tb: Node3D = Node3D.new()
	tb.set_script(TRIGGER_BOX_SCRIPT)
	add_child(tb)
	tb.global_position = world_pos
	_placed_props.append(tb)
	_select_prop(tb)
	_push_undo({"kind": "spawn", "snapshots": [_snapshot_prop_box(tb)]})

func _on_eyedropper_armed(event_id: String) -> void:
	_eyedropper_event_id = event_id

func _on_eyedropper_disarmed() -> void:
	_eyedropper_event_id = ""

func _on_event_hover(event_id: String) -> void:
	_hover_event_id = event_id
	_apply_event_hover_tint()

func _on_event_unhover() -> void:
	_hover_event_id = ""
	_apply_event_hover_tint()

func _on_events_changed() -> void:
	_refresh_trigger_panel()
	_refresh_object_props_panel()
	if _trigger_panel != null:
		_trigger_panel.refresh_events()

func _on_trigger_changed() -> void:
	pass  # values already mirrored onto selected trigger box by the panel

func _on_object_event_focused(event_id: String) -> void:
	# Jump the user to the events panel + arm hover so the targeted prop
	# set is highlighted.
	if event_id == "":
		return
	_hover_event_id = event_id
	_apply_event_hover_tint()

func _handle_eyedropper_click() -> void:
	# Pick a prop under the cursor and add its prop_id to the armed event.
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var best: Node3D = null
	var best_t: float = INF
	for box in _placed_props:
		if not is_instance_valid(box):
			continue
		if not "prop_id" in box:
			continue
		var inv: Transform3D = box.global_transform.affine_inverse()
		var lo: Vector3 = inv * from
		var ld: Vector3 = inv.basis * dir
		var aabb: AABB = box.get_aabb_local()
		var t: float = _ray_aabb(lo, ld, aabb)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = box
	if best != null and _events_panel != null:
		_events_panel.add_target_to_armed(String(best.prop_id))
		_apply_event_hover_tint()

func _apply_event_hover_tint() -> void:
	# Reset all prop selection visuals to their non-hover state. The
	# tint here piggybacks on set_selected — props highlighted as event
	# targets render in their selected color.
	if _events_panel == null:
		return
	var hover_ids: Array = []
	if _hover_event_id != "":
		for ev in _events_panel.events:
			if String(ev.get("id", "")) == _hover_event_id:
				hover_ids = ev.get("targets", [])
				break
	for box in _placed_props:
		if not is_instance_valid(box) or not "prop_id" in box:
			continue
		if _selected_props.has(box):
			continue  # leave selection visual alone for the whole selection set
		var on: bool = hover_ids.has(String(box.prop_id))
		if box.has_method("set_selected"):
			box.set_selected(on)

func _on_no_collide_changed(v: bool) -> void:
	if _selected_prop == null or not "no_collide" in _selected_prop:
		return
	_selected_prop.no_collide = v

func _on_destructible_changed(v: bool) -> void:
	if _selected_prop == null or not "destructible" in _selected_prop:
		return
	_selected_prop.destructible = v

func _on_hp_changed(v: int) -> void:
	if _selected_prop == null or not "hp_max" in _selected_prop:
		return
	_selected_prop.hp_max = v

# Clipboard ops. Only object_box props are supported (effects + spawn
# cubes don't carry the same per-placement settings yet — when they do,
# extend the clipboard dict's `kind` field accordingly).
func _clipboard_copy() -> void:
	# Snapshot every currently-selected prop. Each snap is a freshly
	# minted dict (no node refs) and carries its kind so paste dispatches
	# properly across effects / objects / triggers.
	var snaps: Array = []
	for box in _selected_props:
		var s: Dictionary = _snapshot_prop_box(box)
		if not s.is_empty():
			snaps.append(s)
	if snaps.is_empty():
		return
	_object_clipboard = snaps
	_clipboard_paste_at_mouse = false

func _clipboard_cut() -> void:
	# Same as copy, but the selection is then deleted (which itself
	# pushes a delete-undo command separate from any later paste).
	var snaps: Array = []
	for box in _selected_props:
		var s: Dictionary = _snapshot_prop_box(box)
		if not s.is_empty():
			snaps.append(s)
	if snaps.is_empty():
		return
	_object_clipboard = snaps
	_clipboard_paste_at_mouse = true
	_delete_selected_prop()

func _clipboard_paste() -> void:
	if _object_clipboard.is_empty():
		return
	# Group offset: if pasting at the cursor (after a cut), centre the
	# group's centroid on the cursor; otherwise stamp at source xforms
	# (paste-in-place, useful for duplicating in situ).
	var delta: Vector3 = Vector3.ZERO
	if _clipboard_paste_at_mouse:
		var hit: Dictionary = _raycast_cursor()
		if not hit.is_empty():
			var centroid: Vector3 = Vector3.ZERO
			var n: int = 0
			for s in _object_clipboard:
				var t: Transform3D = (s as Dictionary).get("xform", Transform3D.IDENTITY)
				centroid += t.origin
				n += 1
			if n > 0:
				centroid /= float(n)
			delta = hit.position - centroid
	# Stamp each snapshot. Each gets a fresh prop_id / trigger_id so we
	# don't collide with the originals (or with previous paste rounds).
	var fresh: Array = []
	var spawn_snaps: Array = []
	for s in _object_clipboard:
		var dup: Dictionary = (s as Dictionary).duplicate(true)
		# Strip ids so the boxes generate new ones on _ready.
		dup.erase("prop_id")
		if dup.has("trigger_id"):
			dup.erase("trigger_id")
		var t2: Transform3D = dup.get("xform", Transform3D.IDENTITY)
		t2.origin = t2.origin + delta
		dup["xform"] = t2
		var b: Node3D = _spawn_from_snapshot(dup)
		if b != null:
			fresh.append(b)
			# Re-snapshot after spawn so the undo entry carries the new
			# prop_id (the original copy didn't have one).
			spawn_snaps.append(_snapshot_prop_box(b))
	if fresh.size() > 0:
		_apply_selection(fresh, fresh.back())
		_push_undo({"kind": "spawn", "snapshots": spawn_snaps})
	# After a cut+paste, subsequent V should keep stamping at the
	# original (post-paste) layout, not retarget to cursor again.
	_clipboard_paste_at_mouse = false
	# Update clipboard xforms so consecutive pastes don't re-stack.
	for i in range(min(_object_clipboard.size(), spawn_snaps.size())):
		(_object_clipboard[i] as Dictionary)["xform"] = (spawn_snaps[i] as Dictionary).get("xform", Transform3D.IDENTITY)

# Pose snapshot tied to the bottom-left Global/Local toggle. Global mode
# only stamps position; Local mode stamps the full transform (pos + rot
# + scale). The snapshot lives in _xform_clipboard, so deleting the
# source object doesn't lose the saved pose.
func _xform_capture() -> void:
	if _selected_prop == null or not is_instance_valid(_selected_prop):
		return
	if _use_local_space:
		_xform_clipboard = {
			"mode":     "local",
			"position": _selected_prop.global_position,
			"basis":    _selected_prop.global_transform.basis,
		}
	else:
		_xform_clipboard = {
			"mode":     "global",
			"position": _selected_prop.global_position,
		}

func _xform_apply() -> void:
	if _selected_prop == null or not is_instance_valid(_selected_prop):
		return
	if _xform_clipboard.is_empty():
		return
	var mode: String = String(_xform_clipboard.get("mode", "global"))
	if mode == "local":
		var t: Transform3D = Transform3D(
			_xform_clipboard.get("basis", Basis()),
			_xform_clipboard.get("position", Vector3.ZERO),
		)
		_selected_prop.global_transform = t
	else:
		_selected_prop.global_position = _xform_clipboard.get("position", Vector3.ZERO)
	# Rebind the gizmo so its handles redraw at the new pose.
	if _gizmo != null:
		_gizmo.set_target(_selected_prop)

func _snapshot_object_box(box: Node3D) -> Dictionary:
	return {
		"kind":                "object",
		"prop_id":             String(box.get("prop_id")),
		"object_id":           String(box.object_id),
		"xform":               box.global_transform,
		"loot_table_id":       String(box.get("loot_table_id")),
		"roll_count_override": int(box.get("roll_count_override")),
		"no_collide":          bool(box.get("no_collide")),
		"destructible":        bool(box.get("destructible")),
		"hp_max":              int(box.get("hp_max")),
	}

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
	# Shift+LMB adds/removes from selection. Plain LMB replaces. Plain
	# LMB on empty deselects everything (gizmo handle picks short-circuit
	# upstream so dragging an arrow off into space won't drop selection).
	# Shift on empty is a no-op — preserves selection during fiddly picks.
	var additive: bool = Input.is_key_pressed(KEY_SHIFT)
	if additive:
		if best != null:
			_toggle_in_selection(best)
	else:
		_select_prop(best)

func _delete_selected_prop() -> void:
	# Deletes everything in _selected_props (single-select degrades to a
	# 1-element list). Records a single undo command for the whole batch.
	if _selected_props.is_empty():
		return
	var snaps: Array = []
	var doomed_list: Array = _selected_props.duplicate()
	for box in doomed_list:
		if box == null or not is_instance_valid(box):
			continue
		var snap: Dictionary = _snapshot_prop_box(box)
		if not snap.is_empty():
			snaps.append(snap)
		_placed_props.erase(box)
		box.queue_free()
	_apply_selection([], null)
	_drag_handle = ""
	if not snaps.is_empty():
		_push_undo({"kind": "delete", "snapshots": snaps})

func _snapshot_prop_box(box: Node3D) -> Dictionary:
	# Unified snapshot covering object / effect / trigger boxes. The
	# returned dict round-trips through _spawn_from_snapshot.
	if box == null or not is_instance_valid(box):
		return {}
	if "trigger_id" in box:
		return {
			"kind":               "trigger",
			"prop_id":            String(box.get("prop_id")),
			"trigger_id":         String(box.trigger_id),
			"xform":              box.global_transform,
			"conditions":         (box.conditions as Array).duplicate(true),
			"logic_op":           String(box.logic_op),
			"fire_event_ids":     (box.fire_event_ids as Array).duplicate(),
			"delay":              float(box.delay),
			"inter_event_delay":  float(box.inter_event_delay),
			"repeat_mode":        String(box.repeat_mode),
			"repeat_count":       int(box.repeat_count),
			"repeat_cooldown":    float(box.repeat_cooldown),
			"destroy_after_fire": bool(box.destroy_after_fire),
			"visible_in_play":    bool(box.visible_in_play),
		}
	if "object_id" in box and String(box.object_id) != "":
		return _snapshot_object_box(box)
	if "effect_id" in box and String(box.effect_id) != "":
		return {
			"kind":     "effect",
			"effect_id": String(box.effect_id),
			"prop_id":   String(box.get("prop_id")),
			"xform":     box.global_transform,
		}
	return {}

func _spawn_from_snapshot(snap: Dictionary) -> Node3D:
	# Inverse of _snapshot_prop_box. Reuses the original prop_id /
	# trigger_id so event-target wiring + undo identity stays stable.
	var kind: String = String(snap.get("kind", "object"))
	var box: Node3D = Node3D.new()
	if kind == "trigger":
		box.set_script(TRIGGER_BOX_SCRIPT)
		if snap.has("prop_id") and String(snap["prop_id"]) != "":
			box.prop_id = String(snap["prop_id"])
		if snap.has("trigger_id") and String(snap["trigger_id"]) != "":
			box.trigger_id = String(snap["trigger_id"])
		box.conditions = (snap.get("conditions", []) as Array).duplicate(true)
		box.logic_op = String(snap.get("logic_op", "and"))
		box.fire_event_ids = (snap.get("fire_event_ids", []) as Array).duplicate()
		box.delay = float(snap.get("delay", 0.0))
		box.inter_event_delay = float(snap.get("inter_event_delay", 0.0))
		box.repeat_mode = String(snap.get("repeat_mode", "once"))
		box.repeat_count = int(snap.get("repeat_count", 1))
		box.repeat_cooldown = float(snap.get("repeat_cooldown", 1.0))
		box.destroy_after_fire = bool(snap.get("destroy_after_fire", false))
		box.visible_in_play = bool(snap.get("visible_in_play", false))
	elif kind == "effect":
		box.set_script(EFFECT_BOX_SCRIPT)
		box.effect_id = String(snap.get("effect_id", ""))
		if snap.has("prop_id") and String(snap["prop_id"]) != "":
			box.prop_id = String(snap["prop_id"])
	else:
		box.set_script(OBJECT_BOX_SCRIPT)
		box.object_id = String(snap.get("object_id", ""))
		if snap.has("prop_id") and String(snap["prop_id"]) != "":
			box.prop_id = String(snap["prop_id"])
	add_child(box)
	box.global_transform = snap.get("xform", Transform3D.IDENTITY)
	if kind == "object":
		box.loot_table_id = String(snap.get("loot_table_id", ""))
		box.roll_count_override = int(snap.get("roll_count_override", -1))
		box.no_collide = bool(snap.get("no_collide", false))
		box.destructible = bool(snap.get("destructible", false))
		box.hp_max = int(snap.get("hp_max", 100))
	_placed_props.append(box)
	return box

func _find_prop_by_id(pid: String) -> Node3D:
	if pid == "":
		return null
	for box in _placed_props:
		if not is_instance_valid(box):
			continue
		if "prop_id" in box and String(box.prop_id) == pid:
			return box
	return null

func _delete_props_by_ids(ids: Array) -> void:
	# Used by undo of spawn / redo of delete. Operates by prop_id so
	# stale Node refs don't matter.
	var doomed: Array = []
	for pid in ids:
		var b: Node3D = _find_prop_by_id(String(pid))
		if b != null:
			doomed.append(b)
	for b in doomed:
		_placed_props.erase(b)
		b.queue_free()
	# Drop any deleted nodes from the live selection so the gizmo
	# doesn't keep a stale target.
	var keep: Array = []
	for s in _selected_props:
		if s != null and is_instance_valid(s) and not doomed.has(s):
			keep.append(s)
	var prim: Node3D = keep.back() if keep.size() > 0 else null
	_apply_selection(keep, prim)

func _push_undo(cmd: Dictionary) -> void:
	_undo_stack.append(cmd)
	if _undo_stack.size() > UNDO_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()

func _apply_undo() -> void:
	if _undo_stack.is_empty():
		return
	var cmd: Dictionary = _undo_stack.pop_back()
	_invert_command(cmd, true)
	_redo_stack.append(cmd)

func _apply_redo() -> void:
	if _redo_stack.is_empty():
		return
	var cmd: Dictionary = _redo_stack.pop_back()
	_invert_command(cmd, false)
	_undo_stack.append(cmd)

func _invert_command(cmd: Dictionary, undo: bool) -> void:
	# Apply or revert a command. `undo=true` means we're playing the
	# command backwards (popping from undo); `undo=false` is redo.
	var kind: String = String(cmd.get("kind", ""))
	match kind:
		"spawn":
			# Forward = spawn; backward = delete by prop_id.
			if undo:
				var ids: Array = []
				for s in cmd.get("snapshots", []):
					ids.append(String((s as Dictionary).get("prop_id", "")))
				_delete_props_by_ids(ids)
			else:
				var fresh: Array = []
				for s in cmd.get("snapshots", []):
					var b: Node3D = _spawn_from_snapshot(s)
					if b != null:
						fresh.append(b)
				if fresh.size() > 0:
					_apply_selection(fresh, fresh.back())
		"delete":
			# Forward = delete; backward = respawn from snapshots.
			if undo:
				var fresh2: Array = []
				for s in cmd.get("snapshots", []):
					var b: Node3D = _spawn_from_snapshot(s)
					if b != null:
						fresh2.append(b)
				if fresh2.size() > 0:
					_apply_selection(fresh2, fresh2.back())
			else:
				var ids2: Array = []
				for s in cmd.get("snapshots", []):
					ids2.append(String((s as Dictionary).get("prop_id", "")))
				_delete_props_by_ids(ids2)
		"transform":
			var target: Dictionary = cmd.get("befores", {}) if undo else cmd.get("afters", {})
			for pid in target.keys():
				var b: Node3D = _find_prop_by_id(String(pid))
				if b != null:
					b.global_transform = target[pid]
			if _gizmo != null and _selected_prop != null:
				_gizmo.set_target(_selected_prop)

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
	# Capture basis + scale for every drag type — used by ctrl-snap to
	# compute the object's world-space extent on the drag axis.
	_drag_start_basis = _selected_prop.global_transform.basis
	_drag_start_scale = _selected_prop.scale
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
	elif handle == "su":
		# Uniform-scale drag — distance from cursor to gizmo origin (on the
		# plane perpendicular to the camera through the anchor) is the
		# scale ratio reference. Symmetric around origin, so no pivot logic.
		_drag_start_scale = _selected_prop.scale
		_drag_start_basis = _selected_prop.global_transform.basis
		var n_u: Vector3 = -_camera.global_transform.basis.z
		var hit_u: Dictionary = _ray_plane_hit_world(from, dir, _drag_anchor, n_u)
		if hit_u.is_empty():
			_drag_handle = ""
			return false
		var d_u: float = (hit_u.point - _drag_anchor).length()
		if d_u < 0.05:
			d_u = 0.05
		_drag_uniform_start_dist = d_u
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
	# Capture per-selected pre-drag xforms — used by both the multi-target
	# replay in _continue_gizmo_drag and the transform-command push when
	# the drag releases.
	_gizmo_drag_start.clear()
	for sb in _selected_props:
		if sb == null or not is_instance_valid(sb) or not "prop_id" in sb:
			continue
		_gizmo_drag_start[String(sb.prop_id)] = sb.global_transform
	return true

func _continue_gizmo_drag() -> void:
	if _selected_prop == null or not is_instance_valid(_selected_prop):
		_drag_handle = ""
		return
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var snap: bool = Input.is_key_pressed(KEY_CTRL)
	if _drag_handle.begins_with("r"):
		var hit_r: Dictionary = _ray_plane_hit_world(from, dir, _drag_anchor, _drag_axis)
		if hit_r.is_empty():
			return
		var local_r: Vector3 = hit_r.point - _drag_anchor
		var ang: float = atan2(local_r.dot(_drag_axis_v), local_r.dot(_drag_axis_u))
		var delta: float = ang - _drag_start_angle
		if snap and _rotation_snap_deg > 0.0:
			var step: float = deg_to_rad(_rotation_snap_deg)
			delta = round(delta / step) * step
		var new_basis: Basis = Basis(_drag_axis, delta) * _drag_start_basis
		var t: Transform3D = _selected_prop.global_transform
		t.basis = new_basis
		_selected_prop.global_transform = t
	elif _drag_handle == "su":
		var n_u: Vector3 = -_camera.global_transform.basis.z
		var hit_u: Dictionary = _ray_plane_hit_world(from, dir, _drag_anchor, n_u)
		if hit_u.is_empty():
			return
		var d_u: float = (hit_u.point - _drag_anchor).length()
		var ratio_u: float = d_u / _drag_uniform_start_dist
		if snap:
			ratio_u = max(1.0, round(ratio_u))
		elif ratio_u < 0.05:
			ratio_u = 0.05
		_selected_prop.scale = _drag_start_scale * ratio_u
	elif _drag_handle in ["sx", "sy", "sz", "-sx", "-sy", "-sz"]:
		var ap_s: Vector3 = _closest_point_on_axis(from, dir, _drag_anchor, _drag_axis)
		var dist_s: float = (ap_s - _drag_anchor).dot(_drag_axis)
		var ratio: float = dist_s / _drag_start_dist
		if snap:
			# Snap ratio to nearest integer ≥1 — so multipliers go 1x, 2x, 3x
			# from the start scale rather than landing on arbitrary fractions.
			ratio = max(1.0, round(ratio))
		elif ratio < 0.05:
			# Clamp absurdly tiny/negative ratios so the box doesn't collapse
			# or invert (negative scale silently flips winding everywhere).
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
		var new_pos_p: Vector3 = hit_p.point + _drag_offset
		if snap:
			new_pos_p = _snap_translate_plane(new_pos_p)
		_selected_prop.global_position = new_pos_p
	else:
		var ap: Vector3 = _closest_point_on_axis(from, dir, _drag_anchor, _drag_axis)
		var new_pos: Vector3 = ap + _drag_offset
		if snap:
			new_pos = _snap_translate_axis(new_pos, _drag_axis)
		_selected_prop.global_position = new_pos
	# Multi-select replay: mirror the primary's delta onto siblings.
	# Translate handles propagate the position delta verbatim. Rotate
	# handles compose the rotation around the primary's pre-drag origin.
	# Scale handles intentionally stay single-target — propagating
	# arbitrary-orientation per-axis scale to siblings is ambiguous.
	if _selected_props.size() > 1:
		var primary_pid: String = String(_selected_prop.get("prop_id"))
		if _gizmo_drag_start.has(primary_pid):
			var p_start: Transform3D = _gizmo_drag_start[primary_pid]
			var p_now: Transform3D = _selected_prop.global_transform
			if _drag_handle.begins_with("r"):
				var r_delta: Basis = p_now.basis.orthonormalized() * p_start.basis.orthonormalized().inverse()
				var pivot: Vector3 = p_start.origin
				for sb in _selected_props:
					if sb == _selected_prop:
						continue
					if sb == null or not is_instance_valid(sb) or not "prop_id" in sb:
						continue
					var spid: String = String(sb.prop_id)
					if not _gizmo_drag_start.has(spid):
						continue
					var s_start: Transform3D = _gizmo_drag_start[spid]
					var s_new: Transform3D = s_start
					s_new.basis = r_delta * s_start.basis
					s_new.origin = pivot + r_delta * (s_start.origin - pivot)
					sb.global_transform = s_new
			elif _drag_handle.begins_with("p") or _drag_handle in ["x", "y", "z"] or (not _drag_handle.begins_with("s") and not _drag_handle.begins_with("r")):
				var d_pos: Vector3 = p_now.origin - p_start.origin
				for sb in _selected_props:
					if sb == _selected_prop:
						continue
					if sb == null or not is_instance_valid(sb) or not "prop_id" in sb:
						continue
					var spid2: String = String(sb.prop_id)
					if not _gizmo_drag_start.has(spid2):
						continue
					var s_start2: Transform3D = _gizmo_drag_start[spid2]
					sb.global_position = s_start2.origin + d_pos

func _finish_gizmo_drag() -> void:
	# Called when LMB releases mid-drag. Pushes a single transform
	# command containing every prop that actually moved.
	if _gizmo_drag_start.is_empty():
		return
	var befores: Dictionary = {}
	var afters: Dictionary = {}
	for pid in _gizmo_drag_start.keys():
		var b: Node3D = _find_prop_by_id(String(pid))
		if b == null:
			continue
		var before: Transform3D = _gizmo_drag_start[pid]
		var after: Transform3D = b.global_transform
		if not before.is_equal_approx(after):
			befores[pid] = before
			afters[pid] = after
	_gizmo_drag_start.clear()
	if not befores.is_empty():
		_push_undo({"kind": "transform", "befores": befores, "afters": afters})

func _snap_translate_axis(new_pos: Vector3, axis: Vector3) -> Vector3:
	# Snap motion to multiples of the object's world-space width along `axis`.
	# Other axes pass through unchanged. Anchor = drag start position.
	var w: float = _object_world_width_on_axis(axis)
	if w <= 0.0001:
		return new_pos
	var delta: Vector3 = new_pos - _drag_anchor
	var proj: float = delta.dot(axis)
	var snapped: float = round(proj / w) * w
	return _drag_anchor + axis * snapped + (delta - axis * proj)

func _snap_translate_plane(new_pos: Vector3) -> Vector3:
	# Snap on each of the plane's two in-plane axes independently. Plane axes
	# are derived from _drag_normal (world-space) — pick any two orthogonal
	# vectors in the plane that line up with the object's frame.
	var n: Vector3 = _drag_normal.normalized()
	var b: Basis = _drag_start_basis
	# Plane axes = the two basis cols whose normal is the plane normal.
	# Approximate by picking the two cols closest to the in-plane direction.
	var cols: Array = [b.x, b.y, b.z]
	var in_plane: Array = []
	for c in cols:
		var cn: Vector3 = c.normalized()
		if absf(cn.dot(n)) < 0.95:
			in_plane.append(cn)
	if in_plane.size() < 2:
		return new_pos
	var u: Vector3 = in_plane[0]
	var v: Vector3 = in_plane[1]
	var w_u: float = _object_world_width_on_axis(u)
	var w_v: float = _object_world_width_on_axis(v)
	var delta: Vector3 = new_pos - _drag_anchor
	var proj_u: float = delta.dot(u)
	var proj_v: float = delta.dot(v)
	var snapped_u: float = (round(proj_u / w_u) * w_u) if w_u > 0.0001 else proj_u
	var snapped_v: float = (round(proj_v / w_v) * w_v) if w_v > 0.0001 else proj_v
	var residual: Vector3 = delta - u * proj_u - v * proj_v
	return _drag_anchor + u * snapped_u + v * snapped_v + residual

func _object_world_width_on_axis(axis: Vector3) -> float:
	# AABB extent along a world-space axis = sum of |axis · (basis_col * scale)|
	# over the three local cols. This handles arbitrarily rotated objects.
	if _selected_prop == null:
		return 1.0
	var aabb: AABB = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	if _selected_prop.has_method("get_aabb_local"):
		aabb = _selected_prop.get_aabb_local()
	var b: Basis = _drag_start_basis
	var s: Vector3 = _drag_start_scale
	var sx: float = absf((b.x * s.x).dot(axis)) * aabb.size.x
	var sy: float = absf((b.y * s.y).dot(axis)) * aabb.size.y
	var sz: float = absf((b.z * s.z).dot(axis)) * aabb.size.z
	return sx + sy + sz

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

