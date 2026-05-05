extends Control

# Top-right HUD panel: shows the equipped weapon's recoil pattern, the player's
# camera drift over the current burst, and a control-score percentage.

const PANEL_W := 220.0
const PANEL_H := 200.0
# Pixels per degree of pattern offset. Set so a 5° total climb roughly fills
# the vertical space inside the panel. Raise to zoom out, lower to zoom in.
const PX_PER_DEG := 14.0

var _weapon: Node

func bind_weapon(w: Node) -> void:
	_weapon = w

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -PANEL_W - 12.0
	offset_right = -12.0
	offset_top = 12.0
	offset_bottom = 12.0 + PANEL_H
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_W, PANEL_H)), Color(0, 0, 0, 0.55))
	var font: Font = ThemeDB.fallback_font
	var fs: int = 12
	draw_string(font, Vector2(8, 16), "Recoil Pattern", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.9, 0.9, 0.9))
	if _weapon == null:
		return
	if _weapon.has_method("is_equipped") and not _weapon.is_equipped():
		draw_string(font, Vector2(8, PANEL_H - 10), "—", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
		return

	var pattern: Array = _weapon.get_recoil_pattern() if _weapon.has_method("get_recoil_pattern") else []
	var session: Dictionary = _weapon.get_recoil_session() if _weapon.has_method("get_recoil_session") else {}

	# Anchor near bottom-center so the climbing pattern grows upward into the panel.
	var center: Vector2 = Vector2(PANEL_W / 2.0, PANEL_H - 32.0)

	# Faint axes
	draw_line(Vector2(center.x, 24), Vector2(center.x, PANEL_H - 12), Color(1, 1, 1, 0.10))
	draw_line(Vector2(8, center.y), Vector2(PANEL_W - 8, center.y), Color(1, 1, 1, 0.10))

	# Reference pattern (cumulative path through pattern[0..N-1]).
	var cum: Vector2 = Vector2.ZERO
	var prev: Vector2 = center
	for v in pattern:
		var p: Vector2 = v as Vector2
		cum += p
		var screen: Vector2 = Vector2(center.x + cum.x * PX_PER_DEG, center.y - cum.y * PX_PER_DEG)
		draw_line(prev, screen, Color(0.55, 0.65, 0.85, 0.75), 1.5)
		draw_circle(screen, 2.0, Color(0.55, 0.65, 0.85, 0.95))
		prev = screen

	# Player path: per-shot drift samples + live drift point.
	var history: Array = session.get("history", [])
	var path_pts: Array = [center]
	for h in history:
		var d: Vector2 = h.get("drift", Vector2.ZERO)
		var d_deg: Vector2 = Vector2(rad_to_deg(d.x), rad_to_deg(d.y))
		path_pts.append(Vector2(center.x + d_deg.x * PX_PER_DEG, center.y - d_deg.y * PX_PER_DEG))
	if session.get("active", false):
		var dn: Vector2 = session.get("drift", Vector2.ZERO)
		var dn_deg: Vector2 = Vector2(rad_to_deg(dn.x), rad_to_deg(dn.y))
		path_pts.append(Vector2(center.x + dn_deg.x * PX_PER_DEG, center.y - dn_deg.y * PX_PER_DEG))
	for i in range(1, path_pts.size()):
		draw_line(path_pts[i - 1], path_pts[i], Color(0.95, 0.55, 0.20, 0.95), 1.5)
		draw_circle(path_pts[i], 2.2, Color(0.95, 0.55, 0.20, 0.95))

	# Score: how close drift is to the anchor relative to total kick. 100% =
	# camera is back where it started despite the kick.
	var shots: int = int(session.get("shots", 0))
	var kick_total: Vector2 = session.get("kick_total", Vector2.ZERO)
	var drift: Vector2 = session.get("drift", Vector2.ZERO)
	var score: float = 100.0
	if kick_total.length() > 0.0001:
		score = clampf(1.0 - drift.length() / kick_total.length(), 0.0, 1.0) * 100.0
	var col: Color = Color(0.25, 0.85, 0.30)
	if score < 70.0:
		col = Color(0.95, 0.80, 0.20)
	if score < 40.0:
		col = Color(0.95, 0.30, 0.20)
	draw_string(font, Vector2(8, PANEL_H - 10),
		"Control: %d%%   shots: %d" % [int(round(score)), shots],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
