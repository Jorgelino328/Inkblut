class_name NetworkManager extends Node

signal server_created(success: bool)
signal server_list_updated(servers: Array)
signal connected_to_server(success: bool)
signal player_joined(id: int, name: String)
signal player_left(id: int)
signal server_info_updated

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 10

var multiplayer_peer: ENetMultiplayerPeer
var is_server: bool = false
var server_info: Dictionary = {}
var available_servers: Array[Dictionary] = []
var connected_players: Dictionary = {}  # player_id -> username mapping

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
	print("=== CREATE_SERVER CALLED ===")
	print("Server Name: ", server_name)
	print("Port: ", port)
	print("Max Players: ", max_players)
	
	# First, properly disconnect any existing server/client connection
	if multiplayer_peer:
		print("Disconnecting existing multiplayer peer...")
		multiplayer_peer.close()
		multiplayer_peer = null
	
	if multiplayer.multiplayer_peer:
		print("Clearing existing multiplayer.multiplayer_peer...")
		multiplayer.multiplayer_peer = null
	
	# Stop any existing UDP discovery server
	_stop_discovery_server()
	
	# Clear any existing server info
	server_info.clear()
	is_server = false
	
	# Wait longer to ensure port is released
	await get_tree().create_timer(1.0).timeout
	
	# Try different ports if the default one fails
	var attempts = 0
	var current_port = port
	var max_attempts = 50  # Try many more ports
	while attempts < max_attempts:
		print("Attempting to create server on port: ", current_port)
		multiplayer_peer = ENetMultiplayerPeer.new()
		var error = multiplayer_peer.create_server(current_port, max_players)
		
		print("ENet create_server result: ", error)
		
		if error == OK:
			print("Successfully created server on port: ", current_port)
			port = current_port  # Update port to the one that worked
			break
		else:
			print("Port ", current_port, " failed with error ", error, ", trying next port...")
			current_port += 1
			attempts += 1
			if multiplayer_peer:
				multiplayer_peer.close()
				multiplayer_peer = null
			# Shorter wait time for faster port scanning
			await get_tree().create_timer(0.1).timeout
	
	if attempts >= max_attempts:
		print("Failed to find available port after ", max_attempts, " attempts")
		server_created.emit(false)
		return false
	
	# Verify the server is actually listening
	await get_tree().process_frame
	
	print("Setting up multiplayer peer...")
	multiplayer.multiplayer_peer = multiplayer_peer
	is_server = true
	
	print("Multiplayer peer connection status: ", multiplayer_peer.get_connection_status())
	print("Multiplayer unique ID: ", multiplayer.get_unique_id())
	
	# Store server info
	server_info = {
		"name": server_name,
		"game_mode": game_mode,
		"map": map_name,
		"max_players": max_players,
		"current_players": 1,
		"port": port,
		"status": "waiting"  # waiting, active, ended
	}
	
	# Start UDP server for discovery
	print("Starting UDP discovery server for created server...")
	_start_discovery_server(port)
	
	# Add host to connected players and emit player_joined for the host (server)
	var user_manager = get_node("/root/UserManager")
	var host_username = "Host"
	if user_manager:
		var current_user = user_manager.get_current_user()
		if current_user:
			host_username = current_user.username
	
	connected_players[1] = host_username  # Server ID is always 1
	print("Emitting player_joined for host: ", host_username)
	player_joined.emit(1, host_username)  # Server ID is always 1
	
	print("=== SERVER CREATED SUCCESSFULLY ===")
	print("Name: ", server_name)
	print("Port: ", port)
	print("Max Players: ", max_players)
	print("UDP Discovery Port: ", port + 1000)
	print("======================================")
	server_created.emit(true)
	return true

func connect_to_server(ip: String, port: int = DEFAULT_PORT) -> bool:
	print("=== CONNECT_TO_SERVER CALLED ===")
	print("Target IP: ", ip)
	print("Target Port: ", port)
	
	# Clean up any existing connection first
	if multiplayer_peer:
		print("Cleaning up existing multiplayer peer...")
		multiplayer_peer.close()
		multiplayer_peer = null
		multiplayer.multiplayer_peer = null
	
	print("Creating new ENetMultiplayerPeer...")
	multiplayer_peer = ENetMultiplayerPeer.new()
	var error = multiplayer_peer.create_client(ip, port)
	
	print("ENet create_client result: ", error)
	
	if error != OK:
		print("Failed to connect to server: ", error)
		connected_to_server.emit(false)
		return false
	
	print("Setting multiplayer.multiplayer_peer...")
	multiplayer.multiplayer_peer = multiplayer_peer
	is_server = false
	
	print("Connection setup complete. Attempting to connect to: ", ip, ":", port)
	print("Multiplayer peer state: ", multiplayer_peer.get_connection_status())
	return true

func disconnect_from_server():
	if multiplayer_peer:
		multiplayer_peer.close()
		multiplayer_peer = null
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	
	is_server = false
	
	# Stop server discovery if we were hosting
	_stop_discovery_server()
	
	# Clear server info if we were hosting
	if server_info.size() > 0:
		server_info.clear()
	
	# Clear connected players list
	connected_players.clear()
	
	print("Disconnected from server")

func start_server_discovery():
	print("Starting server discovery...")
	available_servers.clear()
	_discover_servers()

func _start_discovery_server(server_port: int = DEFAULT_PORT):
	print("=== STARTING UDP DISCOVERY SERVER ===")
	udp_server = UDPServer.new()
	
	# Try multiple UDP discovery ports if needed
	var discovery_port = server_port + 1000
	var udp_attempts = 0
	var max_udp_attempts = 20
	
	while udp_attempts < max_udp_attempts:
		print("Attempting to start UDP server on port: ", discovery_port)
		var error = udp_server.listen(discovery_port)
		
		if error == OK:
			print("SUCCESS: UDP discovery server started on port ", discovery_port)
			print("Server will respond to DISCOVER_SERVERS requests")
			broadcast_timer.start()
			print("Broadcast timer started with interval: ", broadcast_timer.wait_time, " seconds")
			return
		else:
			print("UDP port ", discovery_port, " failed with error ", error, ", trying next port...")
			discovery_port += 1
			udp_attempts += 1
	
	print("ERROR: Failed to find available UDP discovery port after ", max_udp_attempts, " attempts")

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
	
	# Process all pending connections
	while udp_server.is_connection_available():
		var peer = udp_server.take_connection()
		print("UDP server: New connection from ", peer.get_packet_ip(), ":", peer.get_packet_port())
		
		if peer.get_available_packet_count() > 0:
			var packet = peer.get_packet()
			var request = packet.get_string_from_utf8()
			
			print("UDP server: Received request: '", request, "'")
			
			if request == "DISCOVER_SERVERS":
				var response = JSON.stringify(server_info)
				print("UDP server: Responding with server info: ", response)
				var send_result = peer.put_packet(response.to_utf8_buffer())
				print("UDP server: Send result: ", send_result)
			else:
				print("UDP server: Unknown request: ", request)
		else:
			print("UDP server: Connection available but no packets")

func _discover_servers():
	print("=== STARTING SERVER DISCOVERY ===")
	available_servers.clear()
	
	# Create a new UDP client for discovery
	if udp_client:
		udp_client.close()
	udp_client = PacketPeerUDP.new()
	
	# Try to connect and send discovery requests
	_send_discovery_requests()
	
	print("Discovery requests sent, waiting for responses...")
	
	# Start a timer to collect responses
	var discovery_timer = Timer.new()
	discovery_timer.wait_time = 2.0
	discovery_timer.one_shot = true
	discovery_timer.timeout.connect(_finish_discovery.bind(discovery_timer))
	add_child(discovery_timer)
	discovery_timer.start()

func _send_discovery_requests():
	# Send to localhost specifically for local testing
	print("Attempting localhost discovery...")
	var localhost_error = udp_client.connect_to_host("127.0.0.1", DEFAULT_PORT + 1000)
	print("Localhost connection result: ", localhost_error)
	
	if localhost_error == OK:
		var packet_result = udp_client.put_packet("DISCOVER_SERVERS".to_utf8_buffer())
		print("Localhost packet send result: ", packet_result)
	else:
		print("Failed to connect to localhost for discovery")
	
	# Try a simple port scan approach as backup
	_try_direct_port_scan()

func _try_direct_port_scan():
	print("Trying direct port scan approach...")
	# Try common ports where servers might be running
	var common_ports = [DEFAULT_PORT, DEFAULT_PORT + 1, DEFAULT_PORT + 2, DEFAULT_PORT + 3, DEFAULT_PORT + 4]
	
	for port in common_ports:
		var udp_discovery_port = port + 1000
		print("Scanning UDP discovery port: ", udp_discovery_port)
		
		# Create a new UDP client for each attempt
		var scan_client = PacketPeerUDP.new()
		var connect_result = scan_client.connect_to_host("127.0.0.1", udp_discovery_port)
		
		if connect_result == OK:
			print("Connected to port ", udp_discovery_port, ", sending discovery request")
			scan_client.put_packet("DISCOVER_SERVERS".to_utf8_buffer())
			
			# Wait briefly for response
			await get_tree().create_timer(0.2).timeout
			
			if scan_client.get_available_packet_count() > 0:
				var response = scan_client.get_packet().get_string_from_utf8()
				print("Got response from port ", udp_discovery_port, ": ", response)
				var server_data = JSON.parse_string(response)
				if server_data:
					available_servers.append(server_data)
					print("Added server from port scan: ", server_data.get("name", "Unknown"))
		else:
			print("Could not connect to port ", udp_discovery_port)
		
		scan_client.close()

func _finish_discovery(timer: Timer):
	print("Finishing discovery, collecting responses...")
	
	# Collect any responses
	var response_count = 0
	while udp_client.get_available_packet_count() > 0:
		var response = udp_client.get_packet().get_string_from_utf8()
		print("Received server discovery response: ", response)
		var server_data = JSON.parse_string(response)
		if server_data:
			available_servers.append(server_data)
			response_count += 1
			print("Added server to list: ", server_data.get("name", "Unknown"))
	
	print("Discovery complete. Found ", response_count, " servers via UDP")
	print("Total servers available: ", available_servers.size())
	
	timer.queue_free()
	server_list_updated.emit(available_servers)

# Multiplayer callbacks
func _on_peer_connected(id: int):
	print("=== PEER CONNECTED ===")
	print("Player ID: ", id)
	print("Is Server: ", is_server)
	print("Current multiplayer ID: ", multiplayer.get_unique_id())
	print("All connected peers: ", multiplayer.get_peers())
	
	if is_server:
		# Check if we're at max capacity
		var max_players = server_info.get("max_players", 4)
		var current_players = server_info.get("current_players", 1)
		
		if current_players >= max_players:
			print("Server at capacity, disconnecting player ", id)
			multiplayer_peer.disconnect_peer(id)
			return
		
		# For now, don't enforce team balance during connection - handle in lobby
		# TODO: Re-enable team balance enforcement once core multiplayer issues are resolved
		
		server_info.current_players += 1
		print("Updated server player count: ", server_info.current_players)
		
		# Tell the new client what scene to join
		_send_scene_info_to_new_client(id)
		
		# Send complete server info to the new client
		_sync_server_info_to_client.rpc_id(id, server_info)
		
		# Send the host's username to the new client immediately
		var host_username = connected_players.get(1, "Host")
		_notify_player_joined.rpc_id(id, 1, host_username)
		
		# Request the client's username
		_request_username.rpc_id(id)
		
		# After getting the username, we'll send the player list in _send_username
		
		# Don't emit player_joined yet - wait for username response
	else:
		# If we're a client and someone else connected, emit with temporary name
		player_joined.emit(id, "Player " + str(id))
	
	server_info_updated.emit()
	print("Updated server info for new peer connection")

func _on_peer_disconnected(id: int):
	print("=== PEER DISCONNECTED ===")
	print("Player ID: ", id)
	print("Is Server: ", is_server)
	
	if is_server:
		server_info.current_players -= 1
		print("Updated server player count: ", server_info.current_players)
		
		# Remove player from connected_players dictionary
		connected_players.erase(id)
		print("Removed player from connected_players list")
	
	player_left.emit(id)
	server_info_updated.emit()
	print("Emitted player_left signal")

func _on_connected_to_server():
	print("=== NetworkManager: Successfully connected to server ===")
	connected_to_server.emit(true)
	
	# Don't automatically change scene - wait for server to tell us what scene to join
	print("Waiting for server to send scene information...")

func _on_connection_failed():
	print("=== NetworkManager: Failed to connect to server ===")
	connected_to_server.emit(false)

func _on_server_disconnected():
	print("Server disconnected")
	disconnect_from_server()

# RPC call to tell new clients what scene to join
@rpc("call_remote", "reliable")
func _notify_client_scene(scene_name: String, game_mode: String = ""):
	print("=== RECEIVED SCENE NOTIFICATION FROM SERVER ===")
	print("Scene: ", scene_name)
	print("Game Mode: ", game_mode)
	print("Current multiplayer ID: ", multiplayer.get_unique_id())
	print("Current scene controller exists: ", get_tree().get_first_node_in_group("scene_controller") != null)
	
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		print("Scene controller found, current scene: ", scene_controller.current_scene_name)
		print("Changing to requested scene...")
		if game_mode != "":
			print("Calling change_scene_with_game_mode(", scene_name, ", ", game_mode, ")")
			scene_controller.change_scene_with_game_mode(scene_name, game_mode)
		else:
			print("Calling change_scene(", scene_name, ")")
			scene_controller.change_scene(scene_name)
		print("Scene change call completed")
	else:
		print("ERROR: Could not find scene controller")

# RPC call to sync server info to client
@rpc("call_remote", "reliable")
func _sync_server_info_to_client(info: Dictionary):
	print("=== RECEIVED SERVER INFO FROM SERVER ===")
	print("Server info received: ", info)
	server_info = info
	print("Local server_info updated: ", server_info)
	# Emit signal so UI can update
	server_info_updated.emit()

# Call this when a new player connects to tell them what scene to join
func _send_scene_info_to_new_client(client_id: int):
	if not is_server:
		return
		
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		var current_scene_name = scene_controller.current_scene_name
		print("=== SENDING SCENE INFO TO NEW CLIENT ===")
		print("Client ID: ", client_id)
		print("Server current scene: ", current_scene_name)
		print("Server info: ", server_info)
		print("Scene controller current scene name: ", current_scene_name)
		
		# Check if we're in a game scene
		if current_scene_name.begins_with("map_"):
			# Send them to the active game with the current game mode
			var game_mode = server_info.get("game_mode", "FREE-FOR-ALL")
			print("Sending client to game scene: ", current_scene_name, " with mode: ", game_mode)
			_notify_client_scene.rpc_id(client_id, current_scene_name, game_mode)
		else:
			# Send them to lobby
			print("Sending client to lobby")
			_notify_client_scene.rpc_id(client_id, "lobby")

# === LOBBY CHAT FUNCTIONS ===

func send_lobby_chat(username: String, message: String):
	"""Send a lobby chat message to all connected clients"""
	print("NetworkManager: Sending lobby chat from ", username, ": ", message)
	print("Is server: ", is_server)
	print("Connected peers: ", multiplayer.get_peers())
	
	if is_server:
		# If we're the server, broadcast to all clients (including ourselves)
		print("Broadcasting lobby chat as server")
		_relay_lobby_chat.rpc(username, message)
	else:
		# If we're a client, send to server to relay
		print("Sending lobby chat to server for relay")
		_send_lobby_chat_to_server.rpc_id(1, username, message)

@rpc("authority", "call_local", "reliable")
func _relay_lobby_chat(username: String, message: String):
	"""Relay lobby chat message to all clients (called by server)"""
	print("=== NetworkManager: RELAY LOBBY CHAT ===")
	print("From: ", username)
	print("Message: ", message)
	print("My ID: ", multiplayer.get_unique_id())
	print("Is server: ", is_server)
	print("Looking for lobby scene...")
	
	# Find the lobby scene and send the message to it
	var lobby_scene = get_tree().get_first_node_in_group("lobby_scene")
	print("Found lobby scene by group: ", lobby_scene)
	
	if not lobby_scene:
		# Try to find the lobby scene by scanning current scene
		var scene_controller = get_tree().get_first_node_in_group("scene_controller")
		print("Found scene controller: ", scene_controller)
		if scene_controller and scene_controller.current_scene_name == "lobby":
			lobby_scene = scene_controller.current_scene
			print("Found lobby scene via scene controller: ", lobby_scene)
	
	if not lobby_scene:
		# Try to find it by scanning all nodes in the current scene
		var current_scene = get_tree().current_scene
		print("Scanning current scene for lobby: ", current_scene)
		if current_scene and current_scene.name.to_lower().contains("lobby"):
			lobby_scene = current_scene
			print("Found lobby scene by name: ", lobby_scene)
	
	if lobby_scene and lobby_scene.has_method("_add_lobby_chat_message"):
		print("SUCCESS: Calling _add_lobby_chat_message on lobby scene")
		lobby_scene._add_lobby_chat_message(username, message)
	else:
		print("ERROR: Could not find lobby scene to relay chat message")
		print("Available groups: ", get_tree().get_nodes_in_group("lobby_scene"))
		print("Current scene: ", get_tree().current_scene)
		print("Current scene name: ", get_tree().current_scene.name if get_tree().current_scene else "None")

@rpc("any_peer", "call_remote", "reliable")
func _send_lobby_chat_to_server(username: String, message: String):
	"""Send lobby chat message to server (called by clients)"""
	print("=== NetworkManager: RECEIVE LOBBY CHAT FROM CLIENT ===")
	print("From client: ", username)
	print("Message: ", message)
	print("Sender ID: ", multiplayer.get_remote_sender_id())
	print("Is server: ", is_server)
	
	if is_server:
		# Relay to all clients (including the server itself)
		print("Relaying message to all clients")
		_relay_lobby_chat.rpc(username, message)
	else:
		print("ERROR: Non-server received _send_lobby_chat_to_server")

# === USERNAME EXCHANGE FUNCTIONS ===

@rpc("call_remote", "reliable")
func _request_username():
	"""Server requests client's username"""
	print("Server requesting my username...")
	var user_manager = get_node("/root/UserManager")
	if user_manager:
		var current_user = user_manager.get_current_user()
		if current_user:
			print("Sending my username to server: ", current_user.username)
			_send_username.rpc_id(1, current_user.username)
		else:
			print("No current user found, sending default name")
			_send_username.rpc_id(1, "Player " + str(multiplayer.get_unique_id()))
	else:
		print("UserManager not found, sending default name")
		_send_username.rpc_id(1, "Player " + str(multiplayer.get_unique_id()))

@rpc("call_remote", "reliable")
func _send_username(username: String):
	"""Client sends username to server"""
	print("=== SEND USERNAME RPC CALLED ===")
	print("Username: ", username)
	print("Is server: ", is_server)
	print("Remote sender ID: ", multiplayer.get_remote_sender_id())
	
	if is_server:
		var sender_id = multiplayer.get_remote_sender_id()
		print("Received username from client ", sender_id, ": ", username)
		
		# Store the username
		connected_players[sender_id] = username
		print("Updated connected_players: ", connected_players)
		
		# Emit player_joined signal locally on server for server's lobby
		print("Emitting player_joined locally for server...")
		player_joined.emit(sender_id, username)
		
		# Send new player info to all other clients (excluding the new player)
		var all_peers = multiplayer.get_peers()
		print("Sending new player info to clients: ", all_peers)
		for peer_id in all_peers:
			if peer_id != sender_id:  # Don't send to the new player themselves
				print("Sending new player info to peer: ", peer_id)
				_notify_player_joined.rpc_id(peer_id, sender_id, username)
	else:
		print("ERROR: Non-server received _send_username")

@rpc("call_remote", "reliable")
func _notify_player_joined(player_id: int, username: String):
	"""Server notifies clients that a player joined"""
	print("=== NOTIFY PLAYER JOINED RPC ===")
	print("Player ID: ", player_id)
	print("Username: ", username)
	print("My ID: ", multiplayer.get_unique_id())
	print("Is server: ", is_server)
	player_joined.emit(player_id, username)

@rpc("call_remote", "reliable")
func _send_player_list_to_client(player_list: Dictionary):
	"""Server sends current player list to a new client"""
	print("=== RECEIVED PLAYER LIST FROM SERVER ===")
	print("Player list: ", player_list)
	print("My ID: ", multiplayer.get_unique_id())
	print("Is server: ", is_server)
	
	# Emit player_joined for each existing player
	for player_id in player_list:
		var username = player_list[player_id]
		print("Adding existing player: ", username, " (ID: ", player_id, ")")
		player_joined.emit(player_id, username)

@rpc("call_remote", "reliable")
func _request_player_list():
	"""Client requests current player list from server"""
	print("Client requesting player list...")
	if is_server:
		var sender_id = multiplayer.get_remote_sender_id()
		print("Sending player list to client ", sender_id, ": ", connected_players)
		_send_player_list_to_client.rpc_id(sender_id, connected_players)
	else:
		print("ERROR: Non-server received _request_player_list")

# === GETTER FUNCTIONS ===

func get_current_map() -> String:
	"""Get the current map from server info"""
	return server_info.get("map", "map_1")

func get_current_game_mode() -> String:
	"""Get the current game mode from server info"""
	return server_info.get("game_mode", "FREE-FOR-ALL")

func get_connected_players() -> Dictionary:
	"""Get the current connected players dictionary"""
	return connected_players.duplicate()

# === GAME STATE FUNCTIONS ===

func mark_game_started():
	"""Mark the game as started (called by GameManager)"""
	if is_server:
		server_info["status"] = "active"
		print("Game marked as started - server status: active")
		server_info_updated.emit()
	else:
		print("Client received mark_game_started - ignoring (not server)")

func mark_game_ended():
	"""Mark the game as ended"""
	if is_server:
		server_info["status"] = "ended"
		print("Game marked as ended - server status: ended")
		server_info_updated.emit()
	else:
		print("Client received mark_game_ended - ignoring (not server)")
