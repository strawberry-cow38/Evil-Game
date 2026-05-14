extends Node3D

# Computer Station — placed via the Objects tool. At runtime, player
# walks within `mount_radius`, presses E, and switches into a CCTV
# feed UI driven by this station's per-instance camera list. F exits.
#
# Per-instance fields (mirrored through MapState so they survive save
# / load and F9 → play):
#   pre_added_cams : Array[String]  — IDs preloaded into the cam list
#   allow_add      : bool           — false locks the "Add Camera" box
#
# The editor wireframe box exposes these via the object-props panel.

const STATION_FEED_UI := preload("res://station_feed_ui.gd")

var pre_added_cams: Array = []
var allow_add: bool = true
# Mount-prompt + mount radius are runtime knobs. Editor doesn't touch
# them — they exist here so the play-scene code has a single source.
var mount_radius: float = 1.8

var _mounted_player: Node = null
var _player_saved_cam: Camera3D = null
var _ui: CanvasLayer = null

func _ready() -> void:
	add_to_group("computer_station")

func try_mount(player: Node) -> bool:
	if _mounted_player != null or player == null:
		return false
	if not (player is Node3D):
		return false
	if (player as Node3D).global_position.distance_to(global_position) > mount_radius:
		return false
	_mounted_player = player
	# Stash the player's currently-active Camera3D so we can hand control
	# back on dismount — otherwise leaving the feed leaves you stuck in
	# the last CCTV's view.
	_player_saved_cam = _find_current_camera(player)
	if player.has_method("set_in_station"):
		player.set_in_station(self)
	_ui = CanvasLayer.new()
	_ui.set_script(STATION_FEED_UI)
	add_child(_ui)
	if _ui.has_method("bind"):
		_ui.bind(self, player)
	return true

func dismount() -> void:
	if _mounted_player == null:
		return
	if _ui != null:
		if _ui.has_method("teardown"):
			_ui.teardown()
		_ui.queue_free()
		_ui = null
	# Restore the player's own Camera3D as the active view.
	if _player_saved_cam != null and is_instance_valid(_player_saved_cam):
		_player_saved_cam.current = true
	var p: Node = _mounted_player
	_mounted_player = null
	_player_saved_cam = null
	if p != null and p.has_method("set_in_station"):
		p.set_in_station(null)

func _find_current_camera(n: Node) -> Camera3D:
	if n is Camera3D and (n as Camera3D).current:
		return n
	for c in n.get_children():
		var found: Camera3D = _find_current_camera(c)
		if found != null:
			return found
	return null

func get_state() -> Dictionary:
	return {
		"pre_added_cams": pre_added_cams.duplicate(),
		"allow_add": allow_add,
	}

func apply_state(d: Dictionary) -> void:
	# Per-instance values restored from MapState. Arrays come through
	# as Variant-typed Array; copy into a fresh Array[String] so later
	# code can rely on the element type.
	pre_added_cams.clear()
	for c in d.get("pre_added_cams", []):
		pre_added_cams.append(String(c))
	allow_add = bool(d.get("allow_add", true))
