extends Control

# Top-level entry point. Two paths into the app:
#  - Play: load main.tscn (the FPS sandbox)
#  - Editor: load editor.tscn (terrain + content authoring)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$Buttons/Play.pressed.connect(_on_play)
	$Buttons/Editor.pressed.connect(_on_editor)
	$Buttons/Quit.pressed.connect(_on_quit)

func _on_play() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func _on_editor() -> void:
	get_tree().change_scene_to_file("res://editor.tscn")

func _on_quit() -> void:
	get_tree().quit()
