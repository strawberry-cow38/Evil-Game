extends Node3D

# One-off demo scene: flat green ground + a few maple trees spawned
# through editor_foliage so the tree preset can be visually checked
# without firing up the full editor + brush flow.

const FOLIAGE := preload("res://editor_foliage.gd")

func _ready() -> void:
	# Sky / env so the scene isn't black.
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.78, 1.0)
	sky_mat.sky_horizon_color = Color(0.80, 0.85, 0.92, 1.0)
	sky_mat.ground_horizon_color = Color(0.60, 0.55, 0.42, 1.0)
	sky_mat.ground_bottom_color = Color(0.32, 0.28, 0.20, 1.0)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	# Big flat green ground.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.55, 0.20, 1.0)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)

	# Foliage system + a handful of maple trees scattered.
	var fol := Node3D.new()
	fol.set_script(FOLIAGE)
	add_child(fol)
	# Wait a frame so editor_foliage._ready runs and its multimesh
	# buckets exist before we call add_instance.
	await get_tree().process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var positions := [
		Vector3(-6, 0, -4),
		Vector3( 2, 0, -7),
		Vector3( 7, 0,  1),
		Vector3(-3, 0,  5),
		Vector3( 4, 0,  6),
		Vector3(-9, 0,  2),
	]
	for p in positions:
		var s: float = rng.randf_range(0.85, 1.15)
		var r: float = rng.randf_range(0.0, TAU)
		fol.add_instance("tree_maple", p, s, r)

	# Sprinkle some grass between trees so the "less dense than grass"
	# point reads visually.
	for _i in range(9000):
		var gx: float = rng.randf_range(-22, 22)
		var gz: float = rng.randf_range(-22, 22)
		fol.add_instance("long_green", Vector3(gx, 0, gz),
			rng.randf_range(0.7, 1.3), rng.randf_range(0.0, TAU))

	# Camera at ground / eye level.
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 14)
	add_child(cam)
	cam.look_at(Vector3(0, 1.6, 0), Vector3.UP)
	cam.current = true

	# Auto-screenshot if env asks.
	if OS.get_environment("COW_SCREENSHOT") == "1":
		var delay: float = 4.0
		var raw: String = OS.get_environment("COW_SCREENSHOT_DELAY")
		if not raw.is_empty():
			delay = raw.to_float()
		var path: String = OS.get_environment("COW_SCREENSHOT_PATH")
		if path.is_empty():
			path = "user://tree_demo.png"
		var t := get_tree().create_timer(delay)
		await t.timeout
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var abs_path: String = path
			if abs_path.begins_with("user://") or abs_path.begins_with("res://"):
				abs_path = ProjectSettings.globalize_path(abs_path)
			img.save_png(abs_path)
			print("saved screenshot: ", abs_path)
		get_tree().quit()
