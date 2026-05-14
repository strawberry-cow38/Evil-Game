extends CanvasLayer

# F2 overlay — foliage cost breakdown so we can see *which* preset is
# burning frames in a dense patch. Engine-wide Performance monitors give
# the headline (drawcalls / primitives), and the per-bucket table from
# editor_foliage tells us where the foliage budget is going.

const REFRESH_HZ: float = 4.0  # 4 updates/sec keeps the label calm

var _label: Label = null

var _foliage: Node = null
var _accum: float = 0.0
# Smoothed frame ms for stable readout. Engine.get_frames_per_second is
# already smoothed by Godot, but Performance.TIME_PROCESS is per-frame.
var _ms_smooth: float = 0.0

func _ready() -> void:
	layer = 100
	visible = false
	_label = Label.new()
	_label.name = "Label"
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

func set_foliage(node: Node) -> void:
	_foliage = node

func toggle() -> void:
	visible = not visible

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < 1.0 / REFRESH_HZ:
		return
	_accum = 0.0
	_refresh()

func _refresh() -> void:
	var fps: int = Engine.get_frames_per_second()
	var ms_proc: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	_ms_smooth = lerpf(_ms_smooth, ms_proc, 0.4) if _ms_smooth > 0.0 else ms_proc
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var vmem: float = float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0)
	var lines: Array = []
	lines.append("[F2] Foliage Profiler")
	lines.append("FPS %d   frame %.2f ms" % [fps, _ms_smooth])
	lines.append("draws %d   tris %s   vmem %.1f MB" % [draw_calls, _human(prims), vmem])
	lines.append("")
	if _foliage == null or not _foliage.has_method("get_profile_breakdown"):
		lines.append("(no foliage node bound)")
		_label.text = "\n".join(lines)
		return
	var rows: Array = _foliage.call("get_profile_breakdown")
	var total_inst: int = 0
	var total_tris: int = 0
	var total_draws: int = 0
	# Header: pid (left-pad), count, tris, surfaces (= MMI drawcalls)
	lines.append("%-22s %6s %9s %3s" % ["preset", "inst", "tris", "dc"])
	lines.append("-".repeat(44))
	for r in rows:
		var pid: String = String(r.get("pid", ""))
		var count: int = int(r.get("count", 0))
		var tris: int = int(r.get("tris_total", 0))
		var surf: int = int(r.get("surfaces", 1))
		total_inst += count
		total_tris += tris
		total_draws += surf
		if count == 0:
			continue
		lines.append("%-22s %6d %9s %3d" % [pid, count, _human(tris), surf])
	lines.append("-".repeat(44))
	lines.append("%-22s %6d %9s %3d" % ["TOTAL", total_inst, _human(total_tris), total_draws])
	_label.text = "\n".join(lines)

# Compact 1.2k / 3.4M for the tri/primitive columns — 12345678 doesn't fit
# in a 9-wide cell and the eye can't read it anyway.
func _human(n: int) -> String:
	var v: float = float(n)
	if absf(v) >= 1_000_000.0:
		return "%.1fM" % (v / 1_000_000.0)
	if absf(v) >= 1_000.0:
		return "%.1fk" % (v / 1_000.0)
	return "%d" % n
