extends Node

# Global graphics + quality settings, persisted to user://settings.cfg.
# Autoloaded as `GameSettings`. The settings overlay (settings_menu.gd) reads
# / writes these via get/set; apply_all() walks the current scene tree to
# push values onto the WorldEnvironment, Sun, and viewport.

const CFG_PATH := "user://settings.cfg"
const SECTION := "graphics"

# Single source of truth. Type-coerced on load.
const DEFAULTS: Dictionary = {
	# Environment
	"tonemap_mode": int(Environment.TONE_MAPPER_ACES),
	"glow_enabled": true,
	"glow_intensity": 0.4,
	"ssao_enabled": true,
	"ssil_enabled": false,
	"ssr_enabled": false,
	"sdfgi_enabled": false,
	"fog_enabled": false,
	# Sun
	"sun_shadow_enabled": true,
	"sun_shadow_distance": 100.0,
	"sun_angular_distance": 0.5,
	# Viewport
	"msaa_3d": 2,        # 0=Disabled, 1=2x, 2=4x, 3=8x
	"taa": false,
	"fxaa": false,
	"scaling_mode": 0,   # 0=Bilinear, 1=FSR1.0, 2=FSR2.2
	"render_scale": 1.0,
}

const SETTINGS_MENU_SCRIPT := preload("res://settings_menu.gd")

var _values: Dictionary = DEFAULTS.duplicate(true)
var _menu: CanvasLayer = null

func _ready() -> void:
	load_from_disk()
	# Apply once on autoload boot. Scene-load points (main_bootstrap, editor,
	# main_menu) re-apply via apply_all() after their WorldEnvironment + Sun
	# are in the tree. Avoid hooking tree_changed — fires per-node and would
	# thrash apply_all every projectile spawn.
	_deferred_apply()

func toggle_menu() -> void:
	_ensure_menu()
	if _menu != null:
		_menu.toggle()

func is_menu_open() -> bool:
	return _menu != null and _menu.is_open()

func _ensure_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		return
	_menu = CanvasLayer.new()
	_menu.set_script(SETTINGS_MENU_SCRIPT)
	# Parent to the autoload — survives scene changes so ESC works in main
	# menu, editor, and play.
	add_child(_menu)

func _deferred_apply() -> void:
	call_deferred("apply_all")

func get_value(key: String):
	return _values.get(key, DEFAULTS.get(key))

func set_value(key: String, value) -> void:
	if not DEFAULTS.has(key):
		return
	_values[key] = value
	save_to_disk()
	apply_all()

func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)
	save_to_disk()
	apply_all()

func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	for k in DEFAULTS.keys():
		if cfg.has_section_key(SECTION, k):
			var def = DEFAULTS[k]
			var raw = cfg.get_value(SECTION, k, def)
			# Coerce to the default's type to survive int/float drift.
			if typeof(def) == TYPE_BOOL:
				_values[k] = bool(raw)
			elif typeof(def) == TYPE_INT:
				_values[k] = int(raw)
			elif typeof(def) == TYPE_FLOAT:
				_values[k] = float(raw)
			else:
				_values[k] = raw

func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for k in _values.keys():
		cfg.set_value(SECTION, k, _values[k])
	cfg.save(CFG_PATH)

func apply_all() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	_apply_environment(root)
	_apply_sun(root)
	_apply_viewport()

func _apply_environment(root: Node) -> void:
	var we: WorldEnvironment = _find_first(root, "WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env: Environment = we.environment
	env.tonemap_mode = int(get_value("tonemap_mode"))
	env.glow_enabled = bool(get_value("glow_enabled"))
	env.glow_intensity = float(get_value("glow_intensity"))
	env.ssao_enabled = bool(get_value("ssao_enabled"))
	env.ssil_enabled = bool(get_value("ssil_enabled"))
	env.ssr_enabled = bool(get_value("ssr_enabled"))
	env.sdfgi_enabled = bool(get_value("sdfgi_enabled"))
	env.fog_enabled = bool(get_value("fog_enabled"))

func _apply_sun(root: Node) -> void:
	var sun: DirectionalLight3D = _find_first(root, "DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		return
	sun.shadow_enabled = bool(get_value("sun_shadow_enabled"))
	sun.directional_shadow_max_distance = float(get_value("sun_shadow_distance"))
	sun.light_angular_distance = float(get_value("sun_angular_distance"))

func _apply_viewport() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	# Window-scoped viewport carries the rendering knobs.
	vp.msaa_3d = int(get_value("msaa_3d"))
	vp.use_taa = bool(get_value("taa"))
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(get_value("fxaa")) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = int(get_value("scaling_mode"))
	vp.scaling_3d_scale = float(get_value("render_scale"))

func _find_first(root: Node, type_name: String) -> Node:
	# Breadth-first walk — first node whose class matches wins. WorldEnvironment
	# and the sun typically live at scene root, so this terminates fast.
	if root.get_class() == type_name or root.is_class(type_name):
		return root
	for c in root.get_children():
		var hit := _find_first(c, type_name)
		if hit != null:
			return hit
	return null
