class_name SceneController extends Node

signal scene_changed(scene_name: String)

@onready var scene_container: Control = $SceneContainer
var current_scene: Control = null

# Scene paths
const SCENES = {
	"main_menu": "res://Scenes/UI/main_menu.tscn",
	"mode_select": "res://Scenes/UI/mode_select.tscn", 
	"find_game": "res://Scenes/UI/find_game.tscn",
	"custom_match": "res://Scenes/UI/custom_match.tscn",
	"game_over": "res://Scenes/UI/game_over.tscn",
	"test_scene": "res://Scenes/test_scene.tscn"
}

func _ready():
	# Start with main menu
	change_scene("main_menu")

func change_scene(scene_name: String):
	# Remove current scene if it exists
	if current_scene:
		current_scene.queue_free()
		current_scene = null
	
	# Load and instantiate new scene
	if scene_name in SCENES:
		var scene_resource = load(SCENES[scene_name])
		if scene_resource:
			current_scene = scene_resource.instantiate()
			scene_container.add_child(current_scene)
			
			# Connect buttons based on scene type
			_connect_scene_buttons(scene_name)
			
			scene_changed.emit(scene_name)
			print("Changed to scene: ", scene_name)
		else:
			print("Failed to load scene: ", scene_name)
	else:
		print("Scene not found: ", scene_name)

func _connect_scene_buttons(scene_name: String):
	match scene_name:
		"main_menu":
			_connect_main_menu_buttons()
		"mode_select":
			_connect_mode_select_buttons()
		"find_game":
			_connect_find_game_buttons()
		"custom_match":
			_connect_custom_match_buttons()
		"game_over":
			_connect_game_over_buttons()

func _connect_main_menu_buttons():
	var play_button = current_scene.get_node_or_null("MenuContainer/PlayButton")
	var settings_button = current_scene.get_node_or_null("MenuContainer/SettingButton")
	var quit_button = current_scene.get_node_or_null("MenuContainer/QuitButton")
	
	if play_button:
		play_button.pressed.connect(_on_play_pressed)
	else:
		print("Warning: Play button not found in main menu")
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func _connect_mode_select_buttons():
	var quick_game_button = current_scene.get_node_or_null("ModeContainer/QuickGameButton")
	var find_game_button = current_scene.get_node_or_null("ModeContainer/FindGameButton")
	var host_game_button = current_scene.get_node_or_null("ModeContainer/HostGameButton")
	var back_button = current_scene.get_node_or_null("ModeContainer/BackButton")
	
	if quick_game_button:
		quick_game_button.pressed.connect(_on_quick_game_pressed)
	if find_game_button:
		find_game_button.pressed.connect(_on_find_game_pressed)
	if host_game_button:
		host_game_button.pressed.connect(_on_host_game_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_to_main_menu_pressed)

func _connect_find_game_buttons():
	var back_button = current_scene.get_node_or_null("MenuContainerH/MenuContainerV/BackButton")
	
	if back_button:
		back_button.pressed.connect(_on_back_to_mode_select_pressed)

func _connect_custom_match_buttons():
	var back_button = current_scene.get_node_or_null("MenuContainer/BackButton")
	
	if back_button:
		back_button.pressed.connect(_on_back_to_mode_select_pressed)

func _connect_game_over_buttons():
	var respawn_button = current_scene.get_node_or_null("GameOverContainer/RespawnButton")
	var quit_button = current_scene.get_node_or_null("GameOverContainer/QuitButton")
	
	if respawn_button:
		respawn_button.pressed.connect(_on_respawn_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_to_main_menu_pressed)

# Button callback functions
func _on_play_pressed():
	change_scene("mode_select")

func _on_settings_pressed():
	print("Settings not implemented yet")

func _on_quit_pressed():
	get_tree().quit()

func _on_quick_game_pressed():
	change_scene("test_scene")

func _on_find_game_pressed():
	change_scene("find_game")

func _on_host_game_pressed():
	change_scene("custom_match")

func _on_back_to_main_menu_pressed():
	change_scene("main_menu")

func _on_back_to_mode_select_pressed():
	change_scene("mode_select")

func _on_respawn_pressed():
	change_scene("test_scene")

func _on_quit_to_main_menu_pressed():
	change_scene("main_menu")

# Public function for other scripts to change scenes
func go_to_scene(scene_name: String):
	change_scene(scene_name)

# Function to show game over screen
func show_game_over():
	change_scene("game_over")
