extends Node3D

# CCTV Camera — placed via the Objects tool. Identified by `cam_id`,
# which a Computer Station feed picks up by string. When viewed, the
# play scene swaps the active Camera3D to the one this node owns.
#
# Per-instance fields:
#   cam_id      : String  — unique-per-map identifier. Stations switch
#                           to this cam by typing/loading the same id.
#   ptz_enabled : bool    — when true, mounted user can pan/tilt/zoom
#                           while this feed is active.
#
# Runtime layout:
#   self (Node3D)
#     ├─ visual meshes (bracket / sphere / lens, built by the catalog)
#     └─ _yaw (Node3D)       ← horizontal pan pivot
#          └─ _pitch (Node3D) ← vertical tilt pivot
#               └─ Camera3D   ← rotated 180° around Y so it looks +Z
#
# PTZ stays clamped (yaw ±60°, pitch ±30°, fov 35°…85°) so we can't
# spin all the way through the wall behind the housing.

const PTZ_YAW_LIMIT := PI / 3.0   # 60°
const PTZ_PITCH_LIMIT := PI / 6.0  # 30°
const PTZ_FOV_MIN := 35.0
const PTZ_FOV_MAX := 85.0
const PTZ_FOV_DEFAULT := 65.0
const CAMERA_LOCAL := Vector3(0.0, 0.32, 0.0)  # matches sphere body position

var cam_id: String = ""
var ptz_enabled: bool = false

# Persisted PTZ state. Survives an unmount/re-mount cycle so the
# station feed picks the cam back up at the same angle/zoom.
var ptz_yaw: float = 0.0
var ptz_pitch: float = 0.0
var ptz_fov: float = PTZ_FOV_DEFAULT

var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _camera: Camera3D

func _ready() -> void:
	add_to_group("cctv_camera")
	_yaw_pivot = Node3D.new()
	add_child(_yaw_pivot)
	_pitch_pivot = Node3D.new()
	_yaw_pivot.add_child(_pitch_pivot)
	_camera = Camera3D.new()
	# Camera3D's -Z is "forward"; our protrusion faces +Z so we yaw 180°
	# at the camera node and keep all PTZ math in plus-axes elsewhere.
	_camera.rotation = Vector3(0.0, PI, 0.0)
	_camera.position = CAMERA_LOCAL
	_camera.fov = ptz_fov
	_camera.current = false
	_pitch_pivot.add_child(_camera)
	_apply_ptz()

func get_camera() -> Camera3D:
	return _camera

func activate() -> void:
	if _camera != null:
		_camera.current = true

func deactivate() -> void:
	if _camera != null:
		_camera.current = false

# Called by the station UI while this cam is the active feed. Deltas
# are radians for yaw/pitch and degrees for FOV (matches the input
# scale the UI feeds in).
func apply_ptz_delta(dyaw: float, dpitch: float, dfov: float) -> void:
	if not ptz_enabled:
		return
	ptz_yaw = clamp(ptz_yaw + dyaw, -PTZ_YAW_LIMIT, PTZ_YAW_LIMIT)
	ptz_pitch = clamp(ptz_pitch + dpitch, -PTZ_PITCH_LIMIT, PTZ_PITCH_LIMIT)
	ptz_fov = clamp(ptz_fov + dfov, PTZ_FOV_MIN, PTZ_FOV_MAX)
	_apply_ptz()

func _apply_ptz() -> void:
	if _yaw_pivot == null or _pitch_pivot == null or _camera == null:
		return
	_yaw_pivot.rotation = Vector3(0.0, ptz_yaw, 0.0)
	_pitch_pivot.rotation = Vector3(ptz_pitch, 0.0, 0.0)
	_camera.fov = ptz_fov

func get_state() -> Dictionary:
	return {
		"cam_id": cam_id,
		"ptz_enabled": ptz_enabled,
	}

func apply_state(d: Dictionary) -> void:
	cam_id = String(d.get("cam_id", ""))
	ptz_enabled = bool(d.get("ptz_enabled", false))
