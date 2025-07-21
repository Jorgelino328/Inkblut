extends Control

@onready var server_info_label: Label = $ServerInfoLabel
@onready var player_list: VBoxContainer = $PlayerListContainer/PlayerList
@onready var start_game_button: Button = $ButtonContainer/StartGameButton
@onready var leave_lobby_button: Button = $ButtonContainer/LeaveLobbyButton
@onready var chat_history: RichTextLabel = $ChatContainer/Panel/ChatHistory
@onready var message_input: LineEdit = $ChatContainer/Panel/ChatInputContainer/MessageInput
@onready var send_button: Button = $ChatContainer/Panel/ChatInputContainer/SendButton

var network_manager: NetworkManager
var user_manager: Node
var is_host: bool = false
var current_user: UserManager.UserData = null

func _ready():
	print("=== LOBBY READY ===")
	
	# Add to lobby_scene group so NetworkManager can find us
	add_to_group("lobby_scene")
	
	# Get reference to managers
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	user_manager = get_node("/root/UserManager")
	
	if scene_controller:
		network_manager = scene_controller.network_manager
		is_host = network_manager.is_server if network_manager else false
		
		print("Network Manager found: ", network_manager != null)
		print("Is Host: ", is_host)
		print("Multiplayer unique ID: ", multiplayer.get_unique_id())
		print("Connected peers: ", multiplayer.get_peers())
		
		# Connect to network manager signals
		if network_manager:
			network_manager.player_joined.connect(_on_player_joined)
			network_manager.player_left.connect(_on_player_left)
			network_manager.server_info_updated.connect(_update_server_info)
			
			var server_info = network_manager.server_info
			print("Server info: ", server_info)
	else:
		print("ERROR: No scene controller found!")
	
	# Get current user
	if user_manager:
		current_user = user_manager.get_current_user()
		if current_user:
			print("Current user in lobby: ", current_user.username)
	
	# Connect UI signals - with null checks
	if start_game_button:
		start_game_button.pressed.connect(_on_start_game_pressed)
	else:
		print("WARNING: start_game_button not found")
		
	if leave_lobby_button:
		leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	else:
		print("WARNING: leave_lobby_button not found")
		
	if send_button:
		send_button.pressed.connect(_on_send_message)
	else:
		print("WARNING: send_button not found")
		
	if message_input:
		message_input.text_submitted.connect(_on_message_submitted)
	else:
		print("WARNING: message_input not found")
	
	# Update UI based on role
	if start_game_button:
		start_game_button.visible = is_host
		print("Start game button visible: ", is_host)
	else:
		print("WARNING: Cannot update start_game_button visibility - button not found")
	
	# Initialize chat
	_initialize_chat()
	
	# Update server info
	_update_server_info()
	_update_player_list()

func _update_server_info():
	print("=== LOBBY: UPDATING SERVER INFO ===")
	if network_manager:
		var info = network_manager.server_info
		print("Server info from network manager: ", info)
		if info.size() > 0:
			var current_players = info.get("current_players", 1)
			var max_players = info.get("max_players", 4)
			var game_mode = info.get("game_mode", "Unknown")
			
			var status_text = ""
			
			# Add team balance info for team modes
			if game_mode == "TEAM DEATHMATCH":
				if current_players < 2:
					status_text = " - Waiting for players"
				elif current_players % 2 != 0:
					status_text = " - Waiting for balanced teams"
				else:
					status_text = " - Teams balanced, ready to start!"
			
			server_info_label.text = "Server: %s - %s - %s (%d/%d players)%s" % [
				info.get("name", "Unknown"),
				game_mode, 
				info.get("map", "Unknown"),
				current_players,
				max_players,
				status_text
			]
			
			# Update start button state
			if is_host and start_game_button:
				var can_start = _can_start_game()
				start_game_button.disabled = not can_start
				if not can_start and game_mode == "TEAM DEATHMATCH":
					if current_players < 2:
						start_game_button.text = "Need More Players"
					elif current_players % 2 != 0:
						start_game_button.text = "Need Balanced Teams"
				else:
					start_game_button.text = "Start Game"

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
	_update_server_info()  # Update server info to show new player count and team status
	_add_system_message(name + " joined the lobby.")

func _on_player_left(id: int):
	print("Player left lobby: ", id)
	_update_player_list()
	_update_server_info()  # Update server info to show new player count and team status
	_add_system_message("Player " + str(id) + " left the lobby.")

func _on_start_game_pressed():
	if is_host:
		# Check if game can start (team balance, etc.)
		if not _can_start_game():
			return
		
		# Announce that the game is starting
		_add_system_message("Game starting in 3 seconds...")
		
		# Wait a moment then start the game for all players
		await get_tree().create_timer(3.0).timeout
		_start_game.rpc()

func _can_start_game() -> bool:
	"""Check if the game can start based on current conditions"""
	if not network_manager:
		return false
	
	var info = network_manager.server_info
	var game_mode = info.get("game_mode", "FREE-FOR-ALL")
	var current_players = info.get("current_players", 1)
	
	match game_mode:
		"TEAM DEATHMATCH":
			if current_players < 2:
				print("Cannot start team game: Need at least 2 players")
				return false
			if current_players % 2 != 0:
				print("Cannot start team game: Need even number of players for balanced teams")
				return false
			return true
		"FREE-FOR-ALL":
			return current_players >= 1
		_:
			return true

func _on_leave_lobby_pressed():
	# Disconnect from server
	if network_manager:
		network_manager.disconnect_from_server()
	
	# Go back to global lobby
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("global_lobby")

# === LOBBY CHAT FUNCTIONS ===

func _initialize_chat():
	"""Initialize lobby chat system"""
	print("Initializing lobby chat...")
	_add_system_message("Welcome to the lobby! Chat with other players while waiting for the match to start.")
	
	# If we're the host, announce it
	if is_host and current_user:
		_add_system_message(current_user.username + " created this lobby.")

func _add_system_message(message: String):
	"""Add a system message to the chat"""
	if not chat_history:
		print("WARNING: chat_history not found, cannot add system message: ", message)
		return
		
	var timestamp = Time.get_datetime_string_from_system()
	chat_history.append_text("[%s] [color=yellow][SYSTEM][/color]: %s\n" % [timestamp, message])
	call_deferred("_scroll_chat_to_bottom")

func _on_send_message():
	_send_chat_message()

func _on_message_submitted(text: String):
	_send_chat_message()

func _send_chat_message():
	var message = ""
	
	if message_input:
		message = message_input.text.strip_edges()
		if message.is_empty():
			return
		# Clear input first
		message_input.text = ""
		message_input.grab_focus()
	else:
		print("WARNING: message_input not found, but continuing with chat functionality")
		return  # Can't send without input
	
	if not current_user:
		print("ERROR: No current user, cannot send message")
		return
	
	print("Sending lobby chat message: ", message)
	
	# Always use NetworkManager relay system for lobby chat
	if network_manager and network_manager.has_method("send_lobby_chat"):
		print("Using NetworkManager relay system for lobby chat")
		network_manager.send_lobby_chat(current_user.username, message)
	else:
		# Fallback: show message locally only
		print("Fallback: showing message locally only")
		if chat_history:
			var timestamp = Time.get_datetime_string_from_system()
			chat_history.append_text("[%s] [color=cyan]%s[/color]: %s\n" % [timestamp, current_user.username, message])
			call_deferred("_scroll_chat_to_bottom")
		else:
			print("ERROR: chat_history also not found, cannot display message locally")
			print("WARNING: chat_history not found, cannot show fallback message")

@rpc("any_peer", "call_local", "reliable")
func _broadcast_lobby_chat(username: String, message: String):
	"""Broadcast a chat message to all players in the lobby"""
	print("=== LOBBY CHAT RPC RECEIVED ===")
	print("From: ", username)
	print("Message: ", message)
	print("Sender ID: ", multiplayer.get_remote_sender_id())
	print("My ID: ", multiplayer.get_unique_id())
	
	var timestamp = Time.get_datetime_string_from_system()
	if chat_history:
		chat_history.append_text("[%s] [color=cyan]%s[/color]: %s\n" % [timestamp, username, message])
		call_deferred("_scroll_chat_to_bottom")
	else:
		print("WARNING: chat_history not found, cannot display message")

func _scroll_chat_to_bottom():
	"""Scroll chat history to the bottom"""
	if chat_history:
		chat_history.scroll_to_line(chat_history.get_line_count() - 1)

@rpc("call_local", "reliable")
func _start_game():
	"""Start the game for all players"""
	print("Starting game for all players...")
	
	# Add system message
	_add_system_message("Game starting now!")
	
	# Get scene controller and start the game
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller and network_manager:
		var map_name = network_manager.get_current_map()
		if map_name:
			print("Starting game with map: ", map_name)
			scene_controller.change_scene_with_game_mode(map_name, network_manager.get_current_game_mode())
		else:
			print("No map set, defaulting to map_1")
			scene_controller.change_scene_with_game_mode("map_1", network_manager.get_current_game_mode())
	else:
		print("ERROR: Could not start game - scene controller or network manager not found")

func _add_lobby_chat_message(username: String, message: String):
	"""Add a lobby chat message to the chat history (called by NetworkManager)"""
	print("=== LOBBY CHAT MESSAGE RECEIVED ===")
	print("From: ", username)
	print("Message: ", message)
	print("Multiplayer ID: ", multiplayer.get_unique_id())
	print("Is in lobby_scene group: ", is_in_group("lobby_scene"))
	
	var timestamp = Time.get_datetime_string_from_system()
	if chat_history:
		chat_history.append_text("[%s] [color=cyan]%s[/color]: %s\n" % [timestamp, username, message])
		call_deferred("_scroll_chat_to_bottom")
	else:
		print("WARNING: chat_history not found, cannot display lobby chat message")
