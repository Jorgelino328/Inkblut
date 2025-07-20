class_name SceneController extends Node

signal scene_changed(scene_name: String)

@onready var scene_container: Control = $SceneContainer
@onready var network_manager: NetworkManager = $NetworkManager
var current_scene: Node = null

# Background servers for testing
var background_servers: Array[NetworkManager] = []

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
	
	# Check for command line arguments for testing
	var args = OS.get_cmdline_args()
	if "--server" in args:
		print("Starting as server...")
		_start_test_server()
	elif "--client" in args:
		print("Starting as client...")
		_start_test_client()
	else:
		# Start with main menu normally
		change_scene("main_menu")

func change_scene(scene_name: String):
	print("Attempting to change to scene: ", scene_name)
	
	# Remove current scene if it exists
	if current_scene:
		current_scene.queue_free()
		current_scene = null
	
	# Determine if this is a UI scene or game scene
	var is_ui_scene = scene_name in UI_SCENES
	var is_game_scene = scene_name in GAME_SCENES
	
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
				# Game scenes replace the entire scene tree
				get_tree().current_scene.add_child(current_scene)
				print("Game scene instantiated and added to scene tree")
			
			# Connect buttons based on scene type
			_connect_scene_buttons(scene_name)
			
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
	var test_server_button = current_scene.get_node_or_null("MenuContainer/TestServerButton")
	var test_client_button = current_scene.get_node_or_null("MenuContainer/TestClientButton")
	var create_debug_server_button = current_scene.get_node_or_null("MenuContainer/CreateDebugServerButton")
	
	if play_button:
		play_button.pressed.connect(_on_play_pressed)
	else:
		print("Warning: Play button not found in main menu")
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	if test_server_button:
		test_server_button.pressed.connect(_on_test_server_pressed)
	if test_client_button:
		test_client_button.pressed.connect(_on_test_client_pressed)
	if create_debug_server_button:
		create_debug_server_button.pressed.connect(_on_create_debug_server_pressed)

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

func _on_test_server_pressed():
	print("Starting test server...")
	_start_test_server()

func _on_test_client_pressed():
	print("Starting test client...")
	_start_test_client()

func _on_create_debug_server_pressed():
	print("Creating debug server in background...")
	_create_background_server()

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
	
	# Connect to network manager signals
	if not network_manager.server_created.is_connected(_on_server_created):
		network_manager.server_created.connect(_on_server_created)
	
	# Create the server
	network_manager.create_server(server_name, game_mode, map_name, max_players)

func _on_server_created(success: bool):
	if success:
		print("Server created successfully!")
		# Go to lobby to wait for players
		change_scene("lobby")
	else:
		print("Failed to create server")
		# Could show an error dialog here

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
	if current_scene:
		var game_manager = current_scene.get_node_or_null("GameManager")
		if game_manager and game_manager.has_method("set_game_mode"):
			game_manager.set_game_mode(game_mode)
			print("Set game mode to: ", game_mode, " for scene: ", scene_name)
		else:
			print("Warning: GameManager not found in scene: ", scene_name)
			

# Testing functions for command line
func _start_test_server():
	# Connect to network manager signals
	if not network_manager.server_created.is_connected(_on_server_created):
		network_manager.server_created.connect(_on_server_created)
	
	# Create a test server
	network_manager.create_server("Test Server", "Free-For-All", "Test Map", 4)

func _start_test_client():
	# Skip menu and go directly to find game screen
	change_scene("find_game")

func _create_background_server():
	# Create a separate network manager for background server
	var bg_network_manager = NetworkManager.new()
	add_child(bg_network_manager)
	
	# Generate a unique server name and port
	var server_count = background_servers.size() + 1
	var server_name = "Debug Server " + str(server_count)
	var server_port = 7000 + server_count
	
	# Connect to success signal
	bg_network_manager.server_created.connect(_on_background_server_created.bind(bg_network_manager, server_name))
	
	# Create the server
	var success = bg_network_manager.create_server(
		server_name,
		"Free-For-All", 
		"Debug Map", 
		4, 
		server_port
	)
	
	if success:
		background_servers.append(bg_network_manager)
		print("Debug server created: ", server_name, " on port ", server_port)
	else:
		bg_network_manager.queue_free()
		print("Failed to create debug server")

func _on_background_server_created(network_manager: NetworkManager, server_name: String, success: bool):
	if success:
		print("Background server '", server_name, "' is now discoverable!")
		print("You can now go to Find Game to see it listed")
	else:
		print("Background server '", server_name, "' failed to start")
		# Remove from array and free the node
		background_servers.erase(network_manager)
		network_manager.queue_free()
