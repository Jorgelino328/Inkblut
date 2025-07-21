extends Control

# UI References based on the actual scene structure
@onready var game_mode_select: OptionButton = $MenuContainer/GameModeButton
@onready var map_select: OptionButton = $MenuContainer/MapButton
@onready var max_players_select: OptionButton = $MenuContainer/OptionsContainer/PlayerContainer/sss
@onready var create_lobby_button: Button = $MenuContainer/CreateLobbyButton
@onready var back_button: Button = $MenuContainer/BackButton

# Manager references
var network_manager: NetworkManager
var user_manager: Node

func _ready():
	print("=== CUSTOM MATCH READY ===")
	
	# Get manager references
	user_manager = get_node("/root/UserManager")
	
	# Get network manager from scene controller
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		network_manager = scene_controller.network_manager
	
	# Connect button signals
	if create_lobby_button:
		create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Debug UI structure
	_debug_ui_structure()

func _debug_ui_structure():
	"""Debug the UI structure to ensure we have the right references"""
	print("UI References Check:")
	print("  - Game mode select: ", game_mode_select != null)
	print("  - Map select: ", map_select != null)
	print("  - Max players select: ", max_players_select != null)
	print("  - Create lobby button: ", create_lobby_button != null)
	print("  - Back button: ", back_button != null)

func _on_create_lobby_pressed():
	"""Validate selections and create the lobby"""
	print("Create lobby button pressed - validating selections...")
	
	# Validate game mode selection (0 is default "GAME MODE")
	if not game_mode_select or game_mode_select.selected <= 0:
		_show_error("Please select a game mode")
		return
	
	# Validate map selection (0 is default "CHOOSE MAP")
	if not map_select or map_select.selected <= 0:
		_show_error("Please select a map")
		return
	
	# Get selected values
	var game_mode = game_mode_select.get_item_text(game_mode_select.selected)
	var map_name = map_select.get_item_text(map_select.selected)
	var max_players = 4  # Default
	
	if max_players_select and max_players_select.selected >= 0:
		max_players = max_players_select.get_item_id(max_players_select.selected)
	
	# Convert map name to scene format (MAP 1 -> map_1)
	var scene_map_name = map_name.to_lower().replace(" ", "_")
	
	# Generate server name
	var server_name = "Custom Match"
	if user_manager and user_manager.current_user:
		server_name = user_manager.current_user.username + "'s Match"
	
	print("Creating lobby with:")
	print("  Name: ", server_name)
	print("  Mode: ", game_mode)
	print("  Map: ", map_name, " (", scene_map_name, ")")
	print("  Max Players: ", max_players)
	
	# Create the server
	if network_manager:
		var success = await network_manager.create_server(server_name, game_mode, scene_map_name, max_players)
		if success:
			print("Server created successfully!")
			_go_to_lobby()
		else:
			_show_error("Failed to create server")
	else:
		_show_error("Network manager not available")

func _on_back_pressed():
	"""Go back to mode select"""
	_go_to_scene("mode_select")

func _go_to_lobby():
	"""Navigate to the lobby scene"""
	_go_to_scene("lobby")

func _go_to_scene(scene_name: String):
	"""Request scene change from scene controller"""
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene(scene_name)
	else:
		print("ERROR: Could not find scene controller")

func _show_error(message: String):
	"""Show an error message to the user"""
	print("Custom Match Error: ", message)
	# For now, just push error to console
	# In a full implementation, you'd show a popup or status message
	push_error("Custom Match: " + message)