class_name NetworkManager extends Node

signal server_created(success: bool)
signal server_list_updated(servers: Array)
signal connected_to_server(success: bool)
signal player_joined(id: int, name: String)
signal player_left(id: int)

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 10

var multiplayer_peer: ENetMultiplayerPeer
var is_server: bool = false
var server_info: Dictionary = {}
var available_servers: Array[Dictionary] = []

# Server discovery
var udp_server: UDPServer
var udp_client: PacketPeerUDP
var broadcast_timer: Timer

func _ready():
	# Add to network manager group for discovery
	add_to_group("network_manager")
	
	# Set up multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Set up UDP for server discovery
	udp_client = PacketPeerUDP.new()
	
	# Set up broadcast timer for server discovery
	broadcast_timer = Timer.new()
	broadcast_timer.wait_time = 2.0
	broadcast_timer.timeout.connect(_broadcast_server_info)
	add_child(broadcast_timer)

func create_server(server_name: String, game_mode: String, map_name: String, max_players: int, port: int = DEFAULT_PORT) -> bool:
	multiplayer_peer = ENetMultiplayerPeer.new()
	var error = multiplayer_peer.create_server(port, max_players)
	
	if error != OK:
		print("Failed to create server: ", error)
		server_created.emit(false)
		return false
	
	multiplayer.multiplayer_peer = multiplayer_peer
	is_server = true
	
	# Store server info
	server_info = {
		"name": server_name,
		"game_mode": game_mode,
		"map": map_name,
		"max_players": max_players,
		"current_players": 1,
		"port": port
	}
	
	# Start UDP server for discovery
	_start_discovery_server()
	
	print("=== SERVER CREATED ===")
	print("Name: ", server_name)
	print("Port: ", port)
	print("Max Players: ", max_players)
	print("======================")
	server_created.emit(true)
	return true

func connect_to_server(ip: String, port: int = DEFAULT_PORT) -> bool:
	multiplayer_peer = ENetMultiplayerPeer.new()
	var error = multiplayer_peer.create_client(ip, port)
	
	if error != OK:
		print("Failed to connect to server: ", error)
		connected_to_server.emit(false)
		return false
	
	multiplayer.multiplayer_peer = multiplayer_peer
	is_server = false
	
	print("Attempting to connect to: ", ip, ":", port)
	return true

func disconnect_from_server():
	if multiplayer_peer:
		multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_server = false
	
	# Stop server discovery if we were hosting
	_stop_discovery_server()
	
	print("Disconnected from server")

func start_server_discovery():
	available_servers.clear()
	_discover_servers()

func _start_discovery_server():
	udp_server = UDPServer.new()
	udp_server.listen(DEFAULT_PORT + 1)
	broadcast_timer.start()

func _stop_discovery_server():
	if udp_server:
		udp_server.stop()
		udp_server = null
	broadcast_timer.stop()

func _broadcast_server_info():
	if not is_server or not udp_server:
		return
		
	# Handle UDP server requests
	udp_server.poll()
	
	if udp_server.is_connection_available():
		var peer = udp_server.take_connection()
		var request = peer.get_packet().get_string_from_utf8()
		
		if request == "DISCOVER_SERVERS":
			var response = JSON.stringify(server_info)
			peer.put_packet(response.to_utf8_buffer())

func _discover_servers():
	available_servers.clear()
	
	# For local testing, discover all NetworkManager instances that are hosting servers
	var all_network_managers = get_tree().get_nodes_in_group("network_manager")
	if all_network_managers.is_empty():
		# If no group exists, check all NetworkManager instances in the scene tree
		_find_all_network_managers(get_tree().current_scene)
	else:
		for nm in all_network_managers:
			if nm != self and nm.is_hosting():
				available_servers.append(nm.get_server_info())
	
	# Add this server if it's hosting
	if is_server:
		available_servers.append(server_info)
	
	# Send discovery request to local network for real network discovery
	udp_client.connect_to_host("255.255.255.255", DEFAULT_PORT + 1)
	udp_client.put_packet("DISCOVER_SERVERS".to_utf8_buffer())
	
	# Start a timer to collect responses
	var discovery_timer = Timer.new()
	discovery_timer.wait_time = 1.0  # Reduced time for faster testing
	discovery_timer.one_shot = true
	discovery_timer.timeout.connect(_finish_discovery.bind(discovery_timer))
	add_child(discovery_timer)
	discovery_timer.start()

func _find_all_network_managers(node: Node):
	if node is NetworkManager and node != self and node.is_hosting():
		available_servers.append(node.get_server_info())
	
	for child in node.get_children():
		_find_all_network_managers(child)

func _finish_discovery(timer: Timer):
	# Collect any responses
	while udp_client.get_available_packet_count() > 0:
		var response = udp_client.get_packet().get_string_from_utf8()
		var server_data = JSON.parse_string(response)
		if server_data:
			available_servers.append(server_data)
	
	timer.queue_free()
	server_list_updated.emit(available_servers)

# Multiplayer callbacks
func _on_peer_connected(id: int):
	print("Player connected: ", id)
	server_info.current_players += 1
	player_joined.emit(id, "Player " + str(id))

func _on_peer_disconnected(id: int):
	print("Player disconnected: ", id)
	if is_server:
		server_info.current_players -= 1
	player_left.emit(id)

func _on_connected_to_server():
	print("Successfully connected to server")
	connected_to_server.emit(true)

func _on_connection_failed():
	print("Failed to connect to server")
	connected_to_server.emit(false)

func _on_server_disconnected():
	print("Server disconnected")
	disconnect_from_server()

# Utility functions
func get_server_info() -> Dictionary:
	return server_info

func get_available_servers() -> Array[Dictionary]:
	return available_servers

func is_hosting() -> bool:
	return is_server

# Debug function to test if server is discoverable
func test_server_discovery():
	print("=== TESTING SERVER DISCOVERY ===")
	if is_server:
		print("This instance is hosting a server:")
		print("  Name: ", server_info.get("name", "Unknown"))
		print("  Port: ", server_info.get("port", "Unknown"))
		print("  Game Mode: ", server_info.get("game_mode", "Unknown"))
		print("  Players: ", server_info.get("current_players", 0), "/", server_info.get("max_players", 0))
		print("  UDP Server Active: ", udp_server != null)
	else:
		print("This instance is not hosting a server")
		print("Starting discovery test...")
		start_server_discovery()
	print("=================================")
