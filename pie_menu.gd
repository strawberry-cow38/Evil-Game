extends Control

# Radial reload menu. Shows compatible ammo types around screen center; player
# flicks the mouse toward a segment to pick it. Mouse stays captured (no cursor
# warp) — accumulated motion since open determines selection direction.

const RADIUS_INNER := 70.0
const RADIUS_OUTER := 200.0
const SELECT_DEADZONE := 36.0   # px of motion before any selection registers
const FONT_SIZE_NAME := 18
const FONT_SIZE_COUNT := 22

var _open: bool = false
var _options: Array = []   # Array of {"id": String, "name": String, "count": int, "color": Color}
var _delta: Vector2 = Vector2.ZERO
var _font: Font

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font

func is_open() -> bool:
	return _open

func open(opts: Array) -> void:
	_options = opts
	_delta = Vector2.ZERO
	_open = true
	visible = true
	queue_redraw()

func close() -> void:
	_open = false
	visible = false

# Returns id of selected option, or "" if none.
func get_picked() -> String:
	var idx := _selected_index()
	if idx < 0:
		return ""
	return String(_options[idx].id)

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		_delta += (event as InputEventMouseMotion).relative
		queue_redraw()

func _selected_index() -> int:
	if _options.is_empty() or _delta.length() < SELECT_DEADZONE:
		return -1
	# Convert mouse delta to "world" angle: 0 = right, +PI/2 = up.
	# Y is inverted because screen-y grows downward.
	var ang := atan2(-_delta.y, _delta.x)
	if ang < 0.0:
		ang += TAU
	var n := _options.size()
	var seg := TAU / float(n)
	# Segment 0 centered straight up (PI/2). Shift so floor() lands cleanly.
	var shifted: float = ang - (PI * 0.5) + (seg * 0.5)
	while shifted < 0.0:
		shifted += TAU
	while shifted >= TAU:
		shifted -= TAU
	return int(floor(shifted / seg)) % n

func _draw() -> void:
	if not _open or _options.is_empty():
		return
	var center: Vector2 = size * 0.5
	var n := _options.size()
	var seg: float = TAU / float(n)
	var sel := _selected_index()
	for i in range(n):
		var opt: Dictionary = _options[i]
		var ca: float = PI * 0.5 + float(i) * seg   # segment center angle
		var bg: Color = Color(0.05, 0.05, 0.05, 0.78)
		var ring: Color = Color(opt.get("color", Color(0.85, 0.85, 0.85)))
		if i == sel:
			bg = Color(ring.r * 0.65 + 0.20, ring.g * 0.65 + 0.20, ring.b * 0.65 + 0.20, 0.92)
		_draw_wedge(center, RADIUS_INNER, RADIUS_OUTER, ca - seg * 0.5, ca + seg * 0.5, bg)
		# Label at mid-radius.
		var mid_r: float = (RADIUS_INNER + RADIUS_OUTER) * 0.5
		var lpos: Vector2 = center + Vector2(cos(ca), -sin(ca)) * mid_r
		var name_str: String = String(opt.get("name", "?"))
		var count_str: String = "×%d" % int(opt.get("count", 0))
		_draw_centered(lpos + Vector2(0, -10), name_str, FONT_SIZE_NAME, Color(1, 1, 1, 1))
		_draw_centered(lpos + Vector2(0, 16), count_str, FONT_SIZE_COUNT, ring)
	# Center dot.
	draw_circle(center, 6.0, Color(0.95, 0.95, 0.95, 0.85))

func _draw_centered(pos: Vector2, text: String, fs: int, color: Color) -> void:
	if _font == null:
		return
	var ts: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, pos - Vector2(ts.x * 0.5, -fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

func _draw_wedge(center: Vector2, r_in: float, r_out: float, a0: float, a1: float, color: Color) -> void:
	var steps := 28
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = lerpf(a0, a1, t)
		pts.append(center + Vector2(cos(a), -sin(a)) * r_out)
	for i in range(steps + 1):
		var t: float = 1.0 - float(i) / float(steps)
		var a: float = lerpf(a0, a1, t)
		pts.append(center + Vector2(cos(a), -sin(a)) * r_in)
	draw_colored_polygon(pts, color)
