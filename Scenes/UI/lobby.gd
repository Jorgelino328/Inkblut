extends Control

@onready var server_info_label: Label = $ServerInfoLabel
@onready var player_list: VBoxContainer = $PlayerListContainer/PlayerList
@onready var start_game_button: Button = $ButtonContainer/StartGameButton
@onready var leave_lobby_button: Button = $ButtonContainer/LeaveLobbyButton

var network_manager: NetworkManager
var is_host: bool = false

func _ready():
	print("=== LOBBY READY ===")
	
	# Get reference to network manager
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		network_manager = scene_controller.network_manager
		is_host = network_manager.is_hosting()
		
		print("Network Manager found: ", network_manager != null)
		print("Is Host: ", is_host)
		print("Multiplayer unique ID: ", multiplayer.get_unique_id())
		print("Connected peers: ", multiplayer.get_peers())
		
		# Connect to network manager signals
		if network_manager:
			network_manager.player_joined.connect(_on_player_joined)
			network_manager.player_left.connect(_on_player_left)
			
			var server_info = network_manager.get_server_info()
			print("Server info: ", server_info)
	else:
		print("ERROR: No scene controller found!")
	
	# Connect UI signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	
	# Update UI based on role
	start_game_button.visible = is_host
	print("Start game button visible: ", is_host)
	
	# Update server info
	_update_server_info()
	_update_player_list()

func _update_server_info():
	if network_manager:
		var info = network_manager.get_server_info()
		if info.size() > 0:
			server_info_label.text = "Server: %s - %s - %s" % [
				info.get("name", "Unknown"),
				info.get("game_mode", "Unknown"), 
				info.get("map", "Unknown")
			]

func _update_player_list():
	print("=== UPDATING PLAYER LIST ===")
	print("Is Host: ", is_host)
	print("Multiplayer ID: ", multiplayer.get_unique_id())
	print("Connected Peers: ", multiplayer.get_peers())
	print("Player list container children: ", player_list.get_child_count())
	
	# Clear existing player labels (except the first one)
	for i in range(player_list.get_child_count() - 1, 0, -1):
		player_list.get_child(i).queue_free()
	
	# Update host label
	var host_label = player_list.get_child(0) as Label
	if is_host:
		host_label.text = "1. Host (You)"
		print("Set host label to: Host (You)")
	else:
		host_label.text = "1. Host"
		print("Set host label to: Host")
	
	# Add other players (this would be expanded with actual multiplayer data)
	var connected_peers = multiplayer.get_peers()
	print("Adding ", connected_peers.size(), " connected peers to list")
	
	for i in range(connected_peers.size()):
		var player_label = Label.new()
		player_label.text = "%d. Player %d" % [i + 2, connected_peers[i]]
		player_label.add_theme_font_size_override("font_size", 24)
		player_list.add_child(player_label)
		print("Added player label: ", player_label.text)

func _update_debug_info():
	# Debug function removed - no longer needed for production
	pass

func _on_player_joined(id: int, name: String):
	print("Player joined lobby: ", name)
	_update_player_list()

func _on_player_left(id: int):
	print("Player left lobby: ", id)
	_update_player_list()

func _on_start_game_pressed():
	if is_host:
		# Start the game for all players
		_start_game.rpc()

func _on_leave_lobby_pressed():
	# Disconnect from server
	if network_manager:
		network_manager.disconnect_from_server()
	
	# Go back to mode select
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("mode_select")



@rpc("call_local", "reliable")
func _start_game():
	print("=== STARTING GAME ===")
	
	# Get the map and game mode info from network manager
	var map_scene = "test_scene"  # Default fallback
	var game_mode = "FREE-FOR-ALL"  # Default fallback
	
	if network_manager:
		var info = network_manager.get_server_info()
		print("Server info: ", info)
		
		var selected_map = info.get("map", "MAP 1")
		game_mode = info.get("game_mode", "FREE-FOR-ALL")
		
		print("Selected map from server: ", selected_map)
		print("Selected game mode from server: ", game_mode)
		
		# Map the displayed name to the actual scene
		match selected_map:
			"MAP 1":
				map_scene = "map_1"
			"MAP 2":
				map_scene = "map_2"
			"MAP 3":
				map_scene = "map_3"
			_:
				map_scene = "map_1"  # Default to map_1
		
		# Normalize game mode format for GameManager
		match game_mode:
			"TEAM DEATHMATCH":
				game_mode = "TEAM"
			"FREE-FOR-ALL":
				game_mode = "FREE-FOR-ALL"
			_:
				game_mode = "FREE-FOR-ALL"  # Default
		
		print("Final map scene: ", map_scene)
		print("Final game mode: ", game_mode)
	
	# Switch to the correct map scene for all players
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		print("Found scene controller, changing to scene with game mode")
		# Pass the game mode as additional data
		scene_controller.change_scene_with_game_mode(map_scene, game_mode)
	else:
		print("ERROR: No scene controller found!")
