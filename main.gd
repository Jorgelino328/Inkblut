class_name Main extends Node

@onready var scene_controller: SceneController = $SceneController

func _ready():
	# Add this node to the "main" group so other scripts can find it
	add_to_group("main")
	# The scene controller will automatically start with the main menu
	pass

# Global functions that other scripts can access through the main scene
func change_to_scene(scene_name: String):
	scene_controller.go_to_scene(scene_name)

func show_game_over():
	scene_controller.show_game_over()

# Handle input for global actions (like pause menu, etc.)
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		# Handle escape key or back button - could show pause menu
		pass
