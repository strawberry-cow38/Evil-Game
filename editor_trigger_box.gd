extends Node3D

# Editor visual for a trigger volume. Renders a translucent box clad in a
# tiled orange/black "TRIGGER" texture (generated once at runtime so we
# don't ship any borrowed Hammer art). Same gizmo-target interface as the
# other placement boxes: get_aabb_local, set_selected. The selectable
# wireframe sits inside the textured box so the gizmo + bounds picker
# work uniformly with object/effect boxes.

const SIZE := Vector3(4.0, 4.0, 4.0)
const COLOR_WIRE_NORMAL := Color(1.0, 0.55, 0.0, 1.0)
const COLOR_WIRE_SELECTED := Color(1.0, 0.95, 0.35, 1.0)

var prop_id: String = ""
# Per-trigger config — mirrors what the trigger panel edits. Conditions
# is an Array of dicts (see editor_trigger_panel.gd for shape). fire is
# the named events to fire when the compound condition resolves true.
var trigger_id: String = ""
var conditions: Array = []
var logic_op: String = "and"  # "and" | "or" | "xor"
var fire_event_ids: Array = []  # Array[String] of map_event ids
var delay: float = 0.0
var inter_event_delay: float = 0.0
var repeat_mode: String = "once"  # "once" | "n" | "infinite"
var repeat_count: int = 1
var repeat_cooldown: float = 1.0
var destroy_after_fire: bool = false
# Box size — uniform-scaled by the gizmo's scale handles.
var _size: Vector3 = SIZE

var _mi: MeshInstance3D
var _wire: MeshInstance3D
var _mat: StandardMaterial3D
var _wire_mat: StandardMaterial3D
var _selected: bool = false

static var _shared_tex: ImageTexture = null

func _ready() -> void:
	if prop_id == "":
		prop_id = "pr_%d_%d" % [Time.get_ticks_usec(), randi()]
	if trigger_id == "":
		trigger_id = "tr_%d_%d" % [Time.get_ticks_usec(), randi()]
	_mat = StandardMaterial3D.new()
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	_mat.albedo_texture = _ensure_texture()
	_mat.uv1_scale = Vector3(_size.x * 0.5, _size.y * 0.5, 1)
	_mat.uv1_triplanar = true
	var bm := BoxMesh.new()
	bm.size = _size
	_mi = MeshInstance3D.new()
	_mi.mesh = bm
	_mi.material_override = _mat
	_mi.position = Vector3(0, _size.y * 0.5, 0)
	add_child(_mi)
	_wire_mat = StandardMaterial3D.new()
	_wire_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_mat.albedo_color = COLOR_WIRE_NORMAL
	_wire_mat.no_depth_test = true
	_wire = MeshInstance3D.new()
	_wire.position = Vector3(0, _size.y * 0.5, 0)
	add_child(_wire)
	_rebuild_wire()

func set_selected(v: bool) -> void:
	_selected = v
	if _wire_mat != null:
		_wire_mat.albedo_color = COLOR_WIRE_SELECTED if v else COLOR_WIRE_NORMAL

func get_aabb_local() -> AABB:
	return AABB(Vector3(-_size.x * 0.5, 0.0, -_size.z * 0.5), _size)

func _rebuild_wire() -> void:
	var lo: Vector3 = -_size * 0.5
	var hi: Vector3 = _size * 0.5
	var c: Array = [
		Vector3(lo.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z),
		Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z),
		Vector3(lo.x, hi.y, hi.z),
	]
	var edges: Array = [
		[0,1],[1,2],[2,3],[3,0],
		[4,5],[5,6],[6,7],[7,4],
		[0,4],[1,5],[2,6],[3,7],
	]
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _wire_mat)
	for e in edges:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()
	_wire.mesh = im

# Builds the orange-bg / black-TRIGGER tile once and caches it on the
# class. 256x256, repeating, drawn directly on an Image so we don't need
# a SubViewport / font Label at runtime.
static func _ensure_texture() -> ImageTexture:
	if _shared_tex != null:
		return _shared_tex
	var w: int = 256
	var h: int = 256
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.55, 0.0, 1.0))
	# Draw "TRIGGER" twice (top + bottom rows) using a 5x7 bitmap font for
	# each letter, scaled up so it reads from gameplay distance.
	var word: String = "TRIGGER"
	var glyph_w: int = 5
	var glyph_h: int = 7
	var scale: int = 6
	var letter_px: int = glyph_w * scale
	var gap_px: int = scale * 2
	var total_w: int = word.length() * letter_px + (word.length() - 1) * gap_px
	var x0: int = int((w - total_w) * 0.5)
	var y_rows: Array = [int(h * 0.18), int(h * 0.58)]
	for y0 in y_rows:
		var x: int = x0
		for i in range(word.length()):
			_draw_glyph(img, word[i], x, y0, scale)
			x += letter_px + gap_px
	# Black border strip top+bottom so tiled UVs read as bands.
	var band: int = 6
	for y in range(band):
		for xx in range(w):
			img.set_pixel(xx, y, Color.BLACK)
			img.set_pixel(xx, h - 1 - y, Color.BLACK)
	_shared_tex = ImageTexture.create_from_image(img)
	return _shared_tex

# 5x7 ASCII bitmap subset for "TRIGGER".
const _GLYPHS: Dictionary = {
	"T": ["11111","00100","00100","00100","00100","00100","00100"],
	"R": ["11110","10001","10001","11110","10100","10010","10001"],
	"I": ["11111","00100","00100","00100","00100","00100","11111"],
	"G": ["01110","10001","10000","10011","10001","10001","01110"],
	"E": ["11111","10000","10000","11110","10000","10000","11111"],
}

static func _draw_glyph(img: Image, ch: String, x0: int, y0: int, scale: int) -> void:
	var rows: Array = _GLYPHS.get(ch, [])
	for r in range(rows.size()):
		var row: String = rows[r]
		for c in range(row.length()):
			if row[c] != "1":
				continue
			for dy in range(scale):
				for dx in range(scale):
					var x: int = x0 + c * scale + dx
					var y: int = y0 + r * scale + dy
					if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
						img.set_pixel(x, y, Color.BLACK)
