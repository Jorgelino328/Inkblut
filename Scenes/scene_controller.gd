class_name SceneController extends Node

signal scene_changed(scene_name: String)

@onready var scene_container: Control = $SceneContainer
@onready var network_manager: NetworkManager = $NetworkManager
var current_scene: Control = null

# Background servers for testing
var background_servers: Array[NetworkManager] = []

# Scene paths
const SCENES = {
	"main_menu": "res://Scenes/UI/main_menu.tscn",
	"mode_select": "res://Scenes/UI/mode_select.tscn", 
	"find_game": "res://Scenes/UI/find_game.tscn",
	"custom_match": "res://Scenes/UI/custom_match.tscn",
	"lobby": "res://Scenes/UI/lobby.tscn",
	"game_over": "res://Scenes/UI/game_over.tscn",
	"test_scene": "res://Scenes/test_scene.tscn"
}

func _ready():
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
		"lobby":
			_connect_lobby_buttons()
		"game_over":
			_connect_game_over_buttons()

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
	
	var game_mode = "Free-For-All"
	var map_name = "Map 1"
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
