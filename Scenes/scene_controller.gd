class_name SceneController extends Node

signal scene_changed(scene_name: String)

@onready var scene_container: Control = $SceneContainer
@onready var network_manager: NetworkManager = $NetworkManager
var current_scene: Node = null
var current_scene_name: String = ""

# UI scenes that go in the scene_container (Control)
const UI_SCENES = {
	"main_menu": "res://Scenes/UI/main_menu.tscn",
	"mode_select": "res://Scenes/UI/mode_select.tscn", 
	"find_game": "res://Scenes/UI/find_game.tscn",
	"custom_match": "res://Scenes/UI/custom_match.tscn",
	"lobby": "res://Scenes/UI/lobby.tscn",
	"game_over": "res://Scenes/UI/game_over.tscn"
}

# Game scenes that replace the entire scene tree
const GAME_SCENES = {
	"test_scene": "res://Scenes/test_scene.tscn",
	"map_1": "res://Scenes/Levels/map_1.tscn",
	"map_2": "res://Scenes/Levels/map_2.tscn",
	"map_3": "res://Scenes/Levels/map_3.tscn"
}

# Combined dictionary for backward compatibility (not const so we can modify it)
var SCENES = {}

func _ready():
	# Combine the scene dictionaries for backward compatibility
	for scene_name in UI_SCENES:
		SCENES[scene_name] = UI_SCENES[scene_name]
	for scene_name in GAME_SCENES:
		SCENES[scene_name] = GAME_SCENES[scene_name]
	
	# Add to group so other scripts can find this controller
	add_to_group("scene_controller")
	
	# Start with main menu
	change_scene("main_menu")

func change_scene(scene_name: String):
	print("=== SCENE CONTROLLER: CHANGE_SCENE CALLED ===")
	print("Attempting to change to scene: ", scene_name)
	print("Current scene: ", current_scene_name)
	print("Scene container visible: ", scene_container.visible)
	
	# Remove current scene if it exists
	if current_scene:
		print("Removing current scene: ", current_scene.name)
		current_scene.queue_free()
		current_scene = null
	
	# Also clean up any game scenes that might be siblings to this controller
	if get_parent():
		for child in get_parent().get_children():
			if child != self and child.name in ["map_1", "map_2", "map_3", "test_scene"]:
				print("Cleaning up old game scene: ", child.name)
				child.queue_free()
	
	# Determine if this is a UI scene or game scene
	var is_ui_scene = scene_name in UI_SCENES
	var is_game_scene = scene_name in GAME_SCENES
	
	print("Is UI scene: ", is_ui_scene)
	print("Is game scene: ", is_game_scene)
	
	# Show/hide UI container based on scene type
	if is_ui_scene:
		scene_container.visible = true
		print("Set scene container visible: true")
	elif is_game_scene:
		scene_container.visible = false
		print("Set scene container visible: false")
	
	if not (is_ui_scene or is_game_scene):
		print("Scene not found: ", scene_name)
		return
	
	var scene_path = SCENES[scene_name]
	print("Loading scene from path: ", scene_path)
	
	var scene_resource = null
	
	# Check if the file exists first
	if FileAccess.file_exists(scene_path):
		print("File exists, attempting to load...")
		scene_resource = ResourceLoader.load(scene_path)
		
		if not scene_resource:
			print("ResourceLoader failed, trying with load() function...")
			scene_resource = load(scene_path)
	else:
		print("ERROR: File does not exist at path: ", scene_path)
		# Try without the res:// prefix
		var alt_path = scene_path.replace("res://", "")
		print("Trying alternative path: ", alt_path)
		if FileAccess.file_exists(alt_path):
			scene_resource = load(alt_path)
	
	if scene_resource:
		print("Scene resource loaded successfully")
		current_scene = scene_resource.instantiate()
		if current_scene:
			if is_ui_scene:
				# UI scenes go in the scene container
				scene_container.add_child(current_scene)
				print("UI scene instantiated and added to scene container")
			elif is_game_scene:
				# Game scenes need to replace the UI completely
				scene_container.visible = false
				
				# Add the game scene as a sibling to SceneContainer, but after it
				# This ensures the game scene renders on top
				get_parent().add_child(current_scene)
				get_parent().move_child(current_scene, get_index() + 1)
				
				print("Game scene instantiated and added as sibling to SceneController")
				print("Game scene visible: ", current_scene.visible)
				print("Game scene position in tree: ", current_scene.get_index())
				print("Parent children count: ", get_parent().get_child_count())
			
			# Connect buttons based on scene type
			_connect_scene_buttons(scene_name)
			
			current_scene_name = scene_name
			scene_changed.emit(scene_name)
			print("Changed to scene: ", scene_name)
		else:
			print("Failed to instantiate scene: ", scene_name)
	else:
		print("Failed to load scene resource: ", scene_path)
		print("Falling back to test_scene...")
		# Fallback to test_scene if map loading fails
		if scene_name.begins_with("map_"):
			change_scene("test_scene")

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
		"lobby":
			_connect_lobby_buttons()
		"game_over":
			_connect_game_over_buttons()
		"map_1", "map_2", "map_3":
			# Map scenes don't have buttons to connect
			print("Map scene loaded: ", scene_name)

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
	# The find_game scene now handles its own button connections
	pass

func _connect_custom_match_buttons():
	var create_lobby_button = current_scene.get_node_or_null("MenuContainer/CreateLobbyButton")
	var back_button = current_scene.get_node_or_null("MenuContainer/BackButton")
	
	if create_lobby_button:
		create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_to_mode_select_pressed)

func _connect_game_over_buttons():
	var respawn_button = current_scene.get_node_or_null("GameOverContainer/RespawnButton")
	var quit_button = current_scene.get_node_or_null("GameOverContainer/QuitButton")
	
	if respawn_button:
		respawn_button.pressed.connect(_on_respawn_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_to_main_menu_pressed)

func _connect_lobby_buttons():
	# The lobby scene handles its own button connections
	pass

# Button callback functions
func _on_play_pressed():
	change_scene("mode_select")

func _on_settings_pressed():
	print("Settings not implemented yet")

func _on_quit_pressed():
	get_tree().quit()

func _on_quick_game_pressed():
	print("Quick play initiated...")
	network_manager.quick_play()

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

func _on_create_lobby_pressed():
	# Get the selected options from the custom match scene
	var game_mode_option = current_scene.get_node_or_null("MenuContainer/GameModeButton")
	var map_option = current_scene.get_node_or_null("MenuContainer/MapButton")
	var player_limit_option = current_scene.get_node_or_null("MenuContainer/OptionsContainer/PlayerContainer/OptionButton")
	
	var game_mode = "FREE-FOR-ALL"
	var map_name = "MAP 1"
	var max_players = 4
	
	if game_mode_option and game_mode_option.selected > 0:
		game_mode = game_mode_option.get_item_text(game_mode_option.selected)
	
	if map_option and map_option.selected > 0:
		map_name = map_option.get_item_text(map_option.selected)
	
	if player_limit_option:
		max_players = player_limit_option.selected + 2  # Options start from 2 players
	
	var server_name = "Player's Lobby"
	
	# Create the server (await since it's a coroutine)
	var success = await network_manager.create_server(server_name, game_mode, map_name, max_players)
	
	if success:
		print("Server created successfully!")
		# Go to lobby to wait for players
		change_scene("lobby")
	else:
		print("Failed to create server")

# Public function for other scripts to change scenes
func go_to_scene(scene_name: String):
	change_scene(scene_name)

# Function to show game over screen
func show_game_over():
	change_scene("game_over")

# Public function for other scripts to change scenes with game mode data
func change_scene_with_game_mode(scene_name: String, game_mode: String):
	change_scene(scene_name)
	
	# Wait for the scene to be fully ready before setting game mode
	if current_scene:
		call_deferred("_set_game_mode_deferred", game_mode, scene_name)

func _set_game_mode_deferred(game_mode: String, scene_name: String):
	print("Setting game mode deferred: ", game_mode, " for scene: ", scene_name)
	
	if current_scene:
		print("Current scene exists, looking for GameManager...")
		var game_manager = current_scene.get_node_or_null("GameManager")
		if game_manager:
			print("Found GameManager, checking for set_game_mode method...")
			if game_manager.has_method("set_game_mode"):
				game_manager.set_game_mode(game_mode)
				print("Set game mode to: ", game_mode, " for scene: ", scene_name)
			else:
				print("GameManager found but no set_game_mode method")
		else:
			print("Warning: GameManager not found in scene: ", scene_name)
			print("Available children: ")
			for child in current_scene.get_children():
				print("  - ", child.name, " (", child.get_class(), ")")
	else:
		print("ERROR: No current_scene when trying to set game mode")
