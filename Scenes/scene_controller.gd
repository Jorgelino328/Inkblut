class_name SceneController extends Node

signal scene_changed(scene_name: String)

@onready var scene_container: Control = $SceneContainer
@onready var network_manager: NetworkManager = $NetworkManager
var current_scene: Node = null
var current_scene_name: String = ""

# UI scenes that go in the scene_container (Control)
const UI_SCENES = {
	"login": "res://Scenes/UI/login.tscn",
	"main_menu": "res://Scenes/UI/main_menu.tscn",
	"global_lobby": "res://Scenes/UI/global_lobby.tscn",
	"mode_select": "res://Scenes/UI/mode_select.tscn",
	"custom_match": "res://Scenes/UI/custom_match.tscn",
	"lobby": "res://Scenes/UI/lobby.tscn",
	"game_over": "res://Scenes/UI/game_over.tscn"
}

# Game scenes that replace the entire scene tree
const GAME_SCENES = {
	"map_1": "res://Scenes/Levels/map_1.tscn",
	"map_2": "res://Scenes/Levels/map_2.tscn",
	"map_3": "res://Scenes/Levels/map_3.tscn"
}

func _ready():
	# Add to group so other scripts can find this controller
	add_to_group("scene_controller")
	
	# Check if user is logged in, if not start with login
	var user_manager = get_node_or_null("/root/UserManager")
	if user_manager and user_manager.is_logged_in():
		change_scene("main_menu")
	else:
		change_scene("login")

func change_scene(scene_name: String):
	print("=== SCENE CONTROLLER: CHANGE_SCENE CALLED ===")
	print("Attempting to change to scene: ", scene_name)
	print("Current scene: ", current_scene_name)
	print("Scene container visible: ", scene_container.visible)
	print("Multiplayer ID: ", multiplayer.get_unique_id())
	print("Connected peers: ", multiplayer.get_peers())
	
	# Remove current scene if it exists
	if current_scene:
		print("Removing current scene: ", current_scene.name)
		current_scene.queue_free()
		current_scene = null
	
	# Clean up any existing game scenes that might be siblings to this controller
	# This is crucial for proper cleanup when transitioning from game scenes to UI scenes
	if get_parent():
		for child in get_parent().get_children():
			if child != self and (child.name in ["map_1", "map_2", "map_3"] or child.name.begins_with("Map")):
				print("Cleaning up old game scene: ", child.name)
				
				# Try to find and cleanup GameManager first
				var game_manager = child.get_node_or_null("GameManager")
				if game_manager and game_manager.has_method("cleanup_game_state"):
					print("Found GameManager, calling cleanup_game_state...")
					game_manager.cleanup_game_state()
				
				# Check for tanks within the game scene before freeing
				_cleanup_tanks_in_scene(child)
				child.queue_free()
	
	# Also check for any loose tank nodes that might be direct children of the root
	_cleanup_loose_tanks()
	
	# If we're transitioning from a game scene, wait a frame for cleanup
	var was_game_scene = current_scene_name in GAME_SCENES
	if was_game_scene:
		print("Was game scene, waiting for cleanup...")
		await get_tree().process_frame
	
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
	
	# Get the scene path from the appropriate dictionary
	var scene_path = ""
	if is_ui_scene:
		scene_path = UI_SCENES[scene_name]
	else:
		scene_path = GAME_SCENES[scene_name]
		
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
		print("Falling back to map_1...")
		# Fallback to map_1 if map loading fails
		if scene_name.begins_with("map_"):
			change_scene("map_1")

func _connect_scene_buttons(scene_name: String):
	match scene_name:
		"main_menu":
			_connect_main_menu_buttons()
		"global_lobby":
			_connect_global_lobby_buttons()
		"mode_select":
			_connect_mode_select_buttons()
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
	
func _connect_global_lobby_buttons():
	# The global_lobby scene now handles its own button connections
	pass

func _connect_mode_select_buttons():
	# Mode select scene handles its own button connections now
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

func _on_global_lobby_pressed():
	change_scene("global_lobby")

func _on_host_game_pressed():
	change_scene("custom_match")

func _on_back_to_main_menu_pressed():
	change_scene("main_menu")

func _on_back_to_global_lobby_pressed():
	change_scene("global_lobby")

func _on_back_to_mode_select_pressed():
	change_scene("mode_select")

func _on_respawn_pressed():
	change_scene("map_1")

func _on_quit_to_main_menu_pressed():
	change_scene("global_lobby")

func _on_create_lobby_pressed():
	"""Handle create lobby button press with validation"""
	var game_mode_button = current_scene.get_node_or_null("MenuContainer/GameModeButton")
	var map_button = current_scene.get_node_or_null("MenuContainer/MapButton")
	var player_limit_button = current_scene.get_node_or_null("MenuContainer/OptionsContainer/PlayerContainer/sss")
	
	# Validate selections
	if not game_mode_button or game_mode_button.selected <= 0:
		print("ERROR: Please select a game mode")
		return
	
	if not map_button or map_button.selected <= 0:
		print("ERROR: Please select a map")
		return
	
	# Get values
	var game_mode = game_mode_button.get_item_text(game_mode_button.selected)
	var map_name = map_button.get_item_text(map_button.selected)
	var max_players = 4
	
	if player_limit_button and player_limit_button.selected >= 0:
		max_players = player_limit_button.get_item_id(player_limit_button.selected)
	
	# Convert map name to scene format
	var scene_map_name = map_name.to_lower().replace(" ", "_")
	var server_name = "Custom Match"
	
	print("Creating server: ", server_name, ", Mode: ", game_mode, ", Map: ", scene_map_name, ", Players: ", max_players)
	
	# Create server
	var success = await network_manager.create_server(server_name, game_mode, scene_map_name, max_players)
	if success:
		print("Server created successfully")
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
	
	# Wait a few frames to ensure the scene is fully loaded
	await get_tree().process_frame
	await get_tree().process_frame
	
	if current_scene:
		print("Current scene exists, looking for GameManager...")
		var game_manager = current_scene.get_node_or_null("GameManager")
		if game_manager:
			print("Found GameManager, checking details...")
			print("GameManager script: ", game_manager.get_script())
			print("GameManager class: ", game_manager.get_class())
			print("GameManager has set_game_mode: ", game_manager.has_method("set_game_mode"))
			
			# Try calling the method directly
			if game_manager.has_method("set_game_mode"):
				print("Calling set_game_mode(", game_mode, ")")
				game_manager.set_game_mode(game_mode)
				print("Set game mode to: ", game_mode, " for scene: ", scene_name)
			else:
				print("GameManager found but no set_game_mode method")
				print("Available methods: ")
				for method in game_manager.get_method_list():
					if not method.name.begins_with("_"):  # Skip private methods
						print("  - ", method.name)
				
				# Try calling it by name directly as fallback
				print("Trying to call set_game_mode directly...")
				if game_manager.has_signal("game_started"):
					print("GameManager has game_started signal - script is loaded")
				
				# Try using call() method as fallback
				var result = game_manager.call("set_game_mode", game_mode)
				print("Called set_game_mode via call(), result: ", result)
		else:
			print("Warning: GameManager not found in scene: ", scene_name)
			print("Available children: ")
			for child in current_scene.get_children():
				print("  - ", child.name, " (", child.get_class(), ")")
	else:
		print("ERROR: No current_scene when trying to set game mode")

# Helper function to clean up tanks within a game scene
func _cleanup_tanks_in_scene(scene_node: Node):
	"""Remove all tank nodes from a game scene"""
	if not scene_node:
		return
		
	print("Checking for tanks in scene: ", scene_node.name)
	var tanks_found = 0
	
	# Recursively search for tank nodes
	_find_and_cleanup_tanks_recursive(scene_node, tanks_found)
	
	if tanks_found > 0:
		print("Cleaned up ", tanks_found, " tank(s) from scene: ", scene_node.name)

func _find_and_cleanup_tanks_recursive(node: Node, tanks_found: int):
	"""Recursively find and clean up tank nodes"""
	for child in node.get_children():
		# Check if this is a tank node (by name or by script)
		if child.name.begins_with("Tank") or child.name.to_lower().contains("tank"):
			print("Found tank to cleanup: ", child.name, " at position: ", child.global_position if child.has_method("get_global_position") else "unknown")
			child.queue_free()
			tanks_found += 1
		elif child.get_script() and child.get_script().resource_path.contains("tank.gd"):
			print("Found tank by script: ", child.name, " at position: ", child.global_position if child.has_method("get_global_position") else "unknown")
			child.queue_free()
			tanks_found += 1
		else:
			# Recursively check children
			_find_and_cleanup_tanks_recursive(child, tanks_found)

func _cleanup_loose_tanks():
	"""Clean up any tanks that might be direct children of the root scene"""
	var root = get_tree().current_scene
	if root:
		print("Checking root scene for loose tanks: ", root.name)
		var tanks_found = 0
		
		for child in root.get_children():
			if child.name.begins_with("Tank") or child.name.to_lower().contains("tank"):
				print("Found loose tank to cleanup: ", child.name, " at position: ", child.global_position if child.has_method("get_global_position") else "unknown")
				child.queue_free()
				tanks_found += 1
			elif child.get_script() and child.get_script().resource_path.contains("tank.gd"):
				print("Found loose tank by script: ", child.name, " at position: ", child.global_position if child.has_method("get_global_position") else "unknown")
				child.queue_free()
				tanks_found += 1
		
		if tanks_found > 0:
			print("Cleaned up ", tanks_found, " loose tank(s) from root scene")
