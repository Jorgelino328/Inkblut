extends Control

@onready var server_info_label: Label = $ServerInfoLabel
@onready var player_list: VBoxContainer = $PlayerListContainer/PlayerList
@onready var start_game_button: Button = $ButtonContainer/StartGameButton
@onready var leave_lobby_button: Button = $ButtonContainer/LeaveLobbyButton

# Debug UI elements
@onready var server_status_label: Label = $DebugPanel/DebugContainer/ServerStatus
@onready var port_info_label: Label = $DebugPanel/DebugContainer/PortInfo
@onready var player_count_label: Label = $DebugPanel/DebugContainer/PlayerCount
@onready var refresh_debug_button: Button = $DebugPanel/DebugContainer/RefreshButton
@onready var test_discovery_button: Button = $DebugPanel/DebugContainer/TestDiscoveryButton

var network_manager: NetworkManager
var is_host: bool = false

func _ready():
	# Get reference to network manager
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		network_manager = scene_controller.network_manager
		is_host = network_manager.is_hosting()
		
		# Connect to network manager signals
		if network_manager:
			network_manager.player_joined.connect(_on_player_joined)
			network_manager.player_left.connect(_on_player_left)
	
	# Connect UI signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	refresh_debug_button.pressed.connect(_on_refresh_debug_pressed)
	test_discovery_button.pressed.connect(_on_test_discovery_pressed)
	
	# Update UI based on role
	start_game_button.visible = is_host
	
	# Update server info
	_update_server_info()
	_update_player_list()
	_update_debug_info()

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
	# Clear existing player labels (except the first one)
	for i in range(player_list.get_child_count() - 1, 0, -1):
		player_list.get_child(i).queue_free()
	
	# Update host label
	var host_label = player_list.get_child(0) as Label
	if is_host:
		host_label.text = "1. Host (You)"
	else:
		host_label.text = "1. Host"
	
	# Add other players (this would be expanded with actual multiplayer data)
	var connected_peers = multiplayer.get_peers()
	for i in range(connected_peers.size()):
		var player_label = Label.new()
		player_label.text = "%d. Player %d" % [i + 2, connected_peers[i]]
		player_label.theme_override_font_sizes["font_size"] = 24
		player_list.add_child(player_label)

func _update_debug_info():
	if network_manager:
		var info = network_manager.get_server_info()
		
		if is_host:
			server_status_label.text = "Server Status: HOSTING"
			port_info_label.text = "Port: " + str(info.get("port", "Unknown"))
			player_count_label.text = "Players: %d/%d" % [
				info.get("current_players", 0),
				info.get("max_players", 0)
			]
		else:
			server_status_label.text = "Server Status: CLIENT"
			port_info_label.text = "Connected to: " + str(info.get("port", "Unknown"))
			player_count_label.text = "Players: " + str(multiplayer.get_peers().size() + 1)
	else:
		server_status_label.text = "Server Status: NO NETWORK MANAGER"
		port_info_label.text = "Port: Unknown"
		player_count_label.text = "Players: Unknown"

func _on_player_joined(id: int, name: String):
	print("Player joined lobby: ", name)
	_update_player_list()
	_update_debug_info()

func _on_player_left(id: int):
	print("Player left lobby: ", id)
	_update_player_list()
	_update_debug_info()

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

func _on_refresh_debug_pressed():
	_update_debug_info()
	print("=== DEBUG INFO ===")
	if network_manager:
		var info = network_manager.get_server_info()
		print("Server Info: ", info)
		print("Is Host: ", is_host)
		print("Multiplayer Peers: ", multiplayer.get_peers())
		print("Multiplayer ID: ", multiplayer.get_unique_id())
	print("==================")

func _on_test_discovery_pressed():
	if network_manager:
		network_manager.test_server_discovery()
	else:
		print("No network manager available")

@rpc("call_local", "reliable")
func _start_game():
	# Switch to game scene for all players
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("test_scene")
