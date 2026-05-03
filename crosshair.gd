extends Control

@export var weapon_path: NodePath
@export var camera_path: NodePath

const SMOOTH_RATE := 18.0
const MIN_RADIUS_PX := 3.0
const TICK_LEN := 6.0
const TICK_THICK := 2.0
const COLOR := Color(1, 1, 1, 0.9)
const OUTLINE_THICK := 1.0
const OUTLINE_COLOR := Color(0, 0, 0, 0.65)

var _weapon: Node
var _camera: Camera3D
var _radius_px := MIN_RADIUS_PX

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if weapon_path != NodePath():
		_weapon = get_node(weapon_path)
	if camera_path != NodePath():
		_camera = get_node(camera_path)

func _process(delta: float) -> void:
	var ads: bool = _weapon != null and _weapon.has_method("is_ads") and _weapon.is_ads()
	visible = not ads
	if not visible:
		return
	var target: float = _compute_radius_px()
	var alpha: float = 1.0 - exp(-SMOOTH_RATE * delta)
	_radius_px = lerpf(_radius_px, target, alpha)
	queue_redraw()

func _compute_radius_px() -> float:
	if _weapon == null or _camera == null or not _weapon.has_method("get_current_bloom_deg"):
		return MIN_RADIUS_PX
	var bloom_deg: float = _weapon.get_current_bloom_deg()
	var vp_h: float = get_viewport_rect().size.y
	var half_fov_deg: float = _camera.fov * 0.5
	# px offset of cone edge at the screen plane, given the camera FOV.
	var px: float = (tan(deg_to_rad(bloom_deg)) / tan(deg_to_rad(half_fov_deg))) * (vp_h * 0.5)
	return maxf(px, MIN_RADIUS_PX)

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = _radius_px
	var dirs := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	for d in dirs:
		var a: Vector2 = c + d * r
		var b: Vector2 = c + d * (r + TICK_LEN)
		# Outline pass for readability on light backgrounds.
		draw_line(a, b, OUTLINE_COLOR, TICK_THICK + OUTLINE_THICK * 2.0, true)
		draw_line(a, b, COLOR, TICK_THICK, true)
	# Center dot.
	draw_circle(c, 1.6, OUTLINE_COLOR)
	draw_circle(c, 1.0, COLOR)
