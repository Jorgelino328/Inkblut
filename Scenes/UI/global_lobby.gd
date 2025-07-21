extends Control

# UI References
@onready var match_list: VBoxContainer = $HSplitContainer/MatchListPanel/VBoxContainer/MatchListContainer/MatchList
@onready var online_count_label: Label = $HSplitContainer/MatchListPanel/VBoxContainer/HeaderContainer/OnlineCountLabel
@onready var logout_button: Button = $HSplitContainer/MatchListPanel/VBoxContainer/HeaderContainer/LogoutButton
@onready var back_button: Button = $HSplitContainer/MatchListPanel/VBoxContainer/HeaderContainer/BackButton
@onready var refresh_button: Button = $HSplitContainer/MatchListPanel/VBoxContainer/FilterContainer/RefreshButton
@onready var search_field: LineEdit = $HSplitContainer/MatchListPanel/VBoxContainer/SearchContainer/SearchField
@onready var create_match_button: Button = $HSplitContainer/MatchListPanel/VBoxContainer/CreateMatchButton
@onready var game_mode_filter: OptionButton = $HSplitContainer/MatchListPanel/VBoxContainer/FilterContainer/GameModeFilter
@onready var status_filter: OptionButton = $HSplitContainer/MatchListPanel/VBoxContainer/FilterContainer/StatusFilter

# Create Match Dialog
@onready var create_match_dialog: AcceptDialog = $CreateMatchDialog
@onready var match_name_input: LineEdit = $CreateMatchDialog/VBoxContainer3/MatchNameInput
@onready var game_mode_select: OptionButton = $CreateMatchDialog/VBoxContainer3/GameModeSelect
@onready var map_select: OptionButton = $CreateMatchDialog/VBoxContainer3/MapSelect
@onready var max_players_input: SpinBox = $CreateMatchDialog/VBoxContainer3/MaxPlayersInput
@onready var cancel_button: Button = $CreateMatchDialog/VBoxContainer3/ButtonContainer/CancelButton
@onready var create_button: Button = $CreateMatchDialog/VBoxContainer3/ButtonContainer/CreateButton

# Manager references
var lobby_manager: Node
var user_manager: Node
var network_manager: NetworkManager

# Local state
var current_matches: Array[Dictionary] = []
var all_servers: Array[Dictionary] = []
var current_user: UserManager.UserData = null

func _ready():
	print("=== GLOBAL LOBBY READY ===")
	
	# Get manager references
	lobby_manager = get_node("/root/LobbyManager")
	user_manager = get_node("/root/UserManager")
	
	# Get network manager from scene controller
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		network_manager = scene_controller.network_manager
	
	if not lobby_manager:
		show_message("Error: LobbyManager not found")
		return
	
	if not user_manager:
		show_message("Error: UserManager not found")
		return
	
	# Get current user
	current_user = user_manager.get_current_user()
	if current_user == null:
		show_message("Error: No user logged in")
		_go_to_login()
		return
	
	print("Current user: ", current_user.username)
	
	# Connect signals
	_connect_signals()
	
	# Start server discovery to find available servers
	if network_manager:
		print("Starting server discovery...")
		network_manager.start_server_discovery()
		# Connect to server list updates
		if not network_manager.server_list_updated.is_connected(_on_server_list_updated):
			network_manager.server_list_updated.connect(_on_server_list_updated)
	
	# Initial updates
	_update_matches()
	_update_online_count()

func _connect_signals():
	# UI signals - with null checks
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if logout_button:
		logout_button.pressed.connect(_on_logout_pressed)
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	if create_match_button:
		create_match_button.pressed.connect(_on_create_match_pressed)
	if game_mode_filter:
		game_mode_filter.item_selected.connect(_on_filter_changed)
	if status_filter:
		status_filter.item_selected.connect(_on_filter_changed)
	
	# Search functionality
	if search_field:
		search_field.text_changed.connect(_on_search_text_changed)
	
	# Create match dialog signals
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_create_match)
	if create_button:
		create_button.pressed.connect(_on_confirm_create_match)
	
	# LobbyManager signals
	if lobby_manager:
		lobby_manager.match_created.connect(_on_match_created)
		lobby_manager.match_started.connect(_on_match_updated)
		lobby_manager.match_ended.connect(_on_match_ended)

func _update_matches():
	print("=== Updating matches display ===")
	
	# Get available servers from NetworkManager (the working system)
	if network_manager:
		all_servers = network_manager.available_servers
		print("Available servers from NetworkManager: ", all_servers.size())
		for server in all_servers:
			print("  - Server: ", server.get("name", "Unknown"), " | IP: ", server.get("ip", "Unknown"), ":", server.get("port", 0))
	else:
		print("NetworkManager not found - no servers available")
		all_servers = []
	
	# Apply filters to show relevant servers
	_apply_filters()

func _apply_filters():
	"""Apply search and filter criteria to show relevant servers"""
	print("=== Applying filters ===")
	
	# Clear existing match buttons
	for child in match_list.get_children():
		child.queue_free()
	
	# Get filter values
	var search_text = search_field.text.to_lower() if search_field else ""
	var game_mode_selected = game_mode_filter.selected if game_mode_filter else 0
	var status_selected = status_filter.selected if status_filter else 0
	
	print("Search text: '", search_text, "'")
	print("Game mode filter: ", game_mode_selected)
	print("Status filter: ", status_selected)
	
	# Filter servers
	var filtered_servers = all_servers.filter(func(server): 
		return _server_matches_filters(server, search_text, game_mode_selected, status_selected)
	)
	
	print("Filtered servers: ", filtered_servers.size(), " out of ", all_servers.size())
	
	# Create server buttons for filtered servers
	for server in filtered_servers:
		_create_server_button(server)
	
	# Handle "no servers" message
	if filtered_servers.is_empty():
		var no_servers_label = Label.new()
		if search_text != "":
			no_servers_label.text = "No servers found matching your search"
		else:
			no_servers_label.text = "No servers found"
		no_servers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		match_list.add_child(no_servers_label)
		print("No servers to display")

func _server_matches_filters(server_info: Dictionary, search_text: String, game_mode_selected: int, status_selected: int) -> bool:
	"""Check if a server matches the current filter criteria"""
	
	# Search text filter (matches server name)
	if search_text != "":
		var server_name = server_info.get("name", "").to_lower()
		if not server_name.contains(search_text):
			return false
	
	# Game mode filter
	if game_mode_selected > 0 and game_mode_filter:
		var selected_mode = game_mode_filter.get_item_text(game_mode_selected)
		var server_mode = server_info.get("game_mode", "")
		if server_mode != selected_mode:
			return false
	
	# Status filter (joinable vs all)
	if status_selected > 0:
		var current_players = server_info.get("current_players", 0)
		var max_players = server_info.get("max_players", 0)
		if status_selected == 1 and current_players >= max_players:  # "Joinable only"
			return false
	
	return true

func _create_server_button(server_info: Dictionary):
	"""Create a clickable button for a server, similar to find_game.gd"""
	# Create main server button
	var button = Button.new()
	
	# Get server status
	var status = server_info.get("status", "active")
	var current_players = server_info.get("current_players", 0)
	var max_players = server_info.get("max_players", 4)
	var is_full = current_players >= max_players
	var is_ended = status == "ended" or status == "finished"
	
	# Format button text with status indicators
	var status_text = ""
	if is_ended:
		status_text = " [ENDED]"
	elif is_full:
		status_text = " [FULL]"
	elif current_players > 0:
		status_text = " [ACTIVE]"
	else:
		status_text = " [WAITING]"
	
	# Format button text like find_game.gd
	var button_text = "%s - %s - %s - %d/%d%s" % [
		server_info.get("name", "Unknown Server"),
		server_info.get("game_mode", "Unknown Mode"),
		server_info.get("map", "Unknown Map"),
		current_players,
		max_players,
		status_text
	]
	
	button.text = button_text
	button.pressed.connect(_on_server_selected.bind(server_info))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Change button appearance based on status
	if is_ended:
		button.modulate = Color.GRAY
		button.disabled = false  # Keep clickable for error message
	elif is_full:
		button.modulate = Color.ORANGE
		button.disabled = false  # Keep clickable for error message
	else:
		button.modulate = Color.WHITE
		button.disabled = false
	
	# Add button to server list
	match_list.add_child(button)
	print("Created server button: ", button_text)

func _on_server_selected(server_info: Dictionary):
	"""Handle server selection - connect to the chosen server"""
	print("=== JOINING SERVER ===")
	print("Server name: ", server_info.get("name"))
	print("Server port: ", server_info.get("port"))
	print("Server info: ", server_info)
	
	# Check if match has ended
	var match_status = server_info.get("status", "unknown")
	if match_status == "ended" or match_status == "finished":
		show_message("Cannot join: This match has already ended")
		print("Attempted to join ended match")
		return
	
	# Check if match is full
	var current_players = server_info.get("current_players", 0)
	var max_players = server_info.get("max_players", 4)
	if current_players >= max_players:
		show_message("Cannot join: This match is full")
		print("Attempted to join full match")
		return
	
	if network_manager:
		# Connect to network manager signals for connection
		if not network_manager.connected_to_server.is_connected(_on_connected_to_server):
			network_manager.connected_to_server.connect(_on_connected_to_server)
		
		print("Initiating connection to server at 127.0.0.1:", server_info.get("port", 7000))
		# Connect to the server
		var success = network_manager.connect_to_server("127.0.0.1", server_info.get("port", 7000))
		if success:
			print("Connection initiation successful, waiting for result...")
		else:
			print("Failed to initiate connection to server")
			show_message("Failed to connect to server")
	else:
		print("ERROR: No network manager available")
		show_message("Network manager not available")

func _on_connected_to_server(success: bool):
	"""Handle connection result"""
	print("Connection attempt result: ", success)
	if success:
		print("Successfully joined server!")
		show_message("Successfully joined server!")
		# NetworkManager will automatically handle scene transition to lobby
	else:
		print("Failed to join server - connection unsuccessful")
		show_message("Failed to join server")

func _on_search_text_changed(new_text: String):
	"""Apply filters when search text changes"""
	_apply_filters()

func _on_filter_changed(index: int = 0):
	"""Apply filters when any filter option changes"""
	_apply_filters()

func _update_online_count():
	# For now, just show a static count since we don't have global lobby users
	if online_count_label:
		online_count_label.text = "Global Lobby"
	else:
		print("WARNING: online_count_label node not found")

func _on_logout_pressed():
	print("Logging out user: ", current_user.username)
	
	# Clean up lobby networking and state
	_cleanup_lobby()
	
	# Logout from user manager
	user_manager.logout_user()
	
	# Go to login screen
	_go_to_login()

func _on_refresh_pressed():
	print("=== REFRESH PRESSED - Starting server discovery ===")
	if network_manager:
		network_manager.start_server_discovery()
	_update_matches()
	_update_online_count()

func _on_create_match_pressed():
	print("=== CREATE MATCH BUTTON PRESSED ===")
	print("Going to custom match creation...")
	# Use the working custom match system instead of the broken lobby manager
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("custom_match")

func _on_back_pressed():
	print("=== BACK BUTTON PRESSED ===")
	print("Going back to main menu...")
	_cleanup_lobby()
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("main_menu")

func _cleanup_lobby():
	"""Clean up when leaving the lobby"""
	# No cleanup needed since we removed global lobby functionality
	pass

func _on_cancel_create_match():
	create_match_dialog.hide()

func _on_confirm_create_match():
	var match_name = match_name_input.text.strip_edges()
	if match_name.is_empty():
		show_message("Please enter a match name")
		return
	
	var game_mode_text = game_mode_select.get_item_text(game_mode_select.selected)
	var map_text = map_select.get_item_text(map_select.selected)
	var max_players = int(max_players_input.value)
	
	print("Creating match: ", match_name, " - ", game_mode_text, " - ", map_text, " - ", max_players)
	
	# Create match through lobby manager
	var result = lobby_manager.create_match(current_user.username, match_name, game_mode_text, map_text, max_players)
	
	create_match_dialog.hide()
	
	if result.get("success", false):
		show_message("Match created successfully!")
		_update_matches()
	else:
		show_message("Failed to create match: " + result.get("message", "Unknown error"))

# LobbyManager signal handlers
func _on_match_created(match_data: Dictionary):
	print("Match created: ", match_data)
	_update_matches()

func _on_match_updated(match_data: Dictionary):
	print("Match updated: ", match_data)
	_update_matches()

func _on_match_ended(match_id: String):
	print("Match ended: ", match_id)
	_update_matches()

func show_message(text: String):
	print("Global Lobby: ", text)
	# TODO: Show message in a proper notification system instead of chat

func _go_to_login():
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("login")

func _input(event):
	# Chat input handling removed - no chat in global lobby
	pass

func _on_server_list_updated(servers: Array):
	"""Called when NetworkManager updates the server list"""
	print("=== Server list updated! Found ", servers.size(), " servers ===")
	_update_matches()

func _exit_tree():
	"""Clean up when leaving the global lobby"""
	print("=== GLOBAL LOBBY: CLEANING UP ===")
	if lobby_manager and current_user:
		print("User leaving lobby: ", current_user.username)
