extends Control

# UI References
@onready var match_list: VBoxContainer = $HSplitContainer/MatchListPanel/VBoxContainer/MatchListContainer/MatchList
@onready var chat_history: RichTextLabel = $HSplitContainer/ChatPanel/VBoxContainer2/ChatContainer/ChatHistory
@onready var message_input: LineEdit = $HSplitContainer/ChatPanel/VBoxContainer2/MessageContainer/MessageInput
@onready var send_button: Button = $HSplitContainer/ChatPanel/VBoxContainer2/MessageContainer/SendButton
@onready var online_count_label: Label = $HSplitContainer/ChatPanel/VBoxContainer2/ChatTitleContainer/OnlineCountLabel
@onready var logout_button: Button = $HSplitContainer/MatchListPanel/VBoxContainer/HeaderContainer/LogoutButton
@onready var refresh_button: Button = $HSplitContainer/MatchListPanel/VBoxContainer/FilterContainer/RefreshButton
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
	
	# Join the global lobby
	lobby_manager.join_lobby(current_user.username)
	
	# Initial updates
	_update_matches()
	_update_chat()
	_update_online_count()

func _connect_signals():
	# UI signals
	logout_button.pressed.connect(_on_logout_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	create_match_button.pressed.connect(_on_create_match_pressed)
	send_button.pressed.connect(_on_send_message)
	message_input.text_submitted.connect(_on_message_submitted)
	game_mode_filter.item_selected.connect(_on_filter_changed)
	status_filter.item_selected.connect(_on_filter_changed)
	
	# Create match dialog signals
	cancel_button.pressed.connect(_on_cancel_create_match)
	create_button.pressed.connect(_on_confirm_create_match)
	
	# LobbyManager signals
	lobby_manager.user_joined_lobby.connect(_on_user_joined_lobby)
	lobby_manager.user_left_lobby.connect(_on_user_left_lobby)
	lobby_manager.lobby_chat_message.connect(_on_chat_message_received)
	lobby_manager.match_created.connect(_on_match_created)
	lobby_manager.match_started.connect(_on_match_updated)
	lobby_manager.match_ended.connect(_on_match_ended)

func _update_matches():
	print("Updating matches display")
	
	# Clear existing match buttons
	for child in match_list.get_children():
		child.queue_free()
	
	# Get matches from lobby manager
	var matches = lobby_manager.get_available_matches()
	current_matches = matches
	
	# Apply filters
	var filtered_matches = _apply_match_filters(matches)
	
	if filtered_matches.is_empty():
		var no_matches_label = Label.new()
		no_matches_label.text = "No matches found"
		no_matches_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		match_list.add_child(no_matches_label)
		return
	
	# Create match buttons
	for game_match in filtered_matches:
		_create_match_button(game_match)

func _apply_match_filters(matches: Array[Dictionary]) -> Array[Dictionary]:
	var filtered = matches.duplicate()
	
	# Game mode filter
	var mode_filter = game_mode_filter.selected
	if mode_filter > 0:
		var mode_text = game_mode_filter.get_item_text(mode_filter)
		filtered = filtered.filter(func(m): return m.get("game_mode", "") == mode_text)
	
	# Status filter
	var status_filter_val = status_filter.selected
	if status_filter_val > 0:
		var status_text = status_filter.get_item_text(status_filter_val).to_lower()
		filtered = filtered.filter(func(m): return m.get("status", "").to_lower() == status_text)
	
	return filtered

func _create_match_button(game_match: Dictionary):
	var container = HBoxContainer.new()
	
	# Match info label
	var info_label = Label.new()
	var status = game_match.get("status", "waiting")
	var players = game_match.get("current_players", 0)
	var max_players = game_match.get("max_players", 4)
	var game_mode = game_match.get("game_mode", "Free-for-All")
	var map_name = game_match.get("map", "Map 1")
	
	info_label.text = "%s - %s - %s (%d/%d) - %s" % [
		game_match.get("name", "Unknown Match"),
		game_mode,
		map_name,
		players,
		max_players,
		status.capitalize()
	]
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	container.add_child(info_label)
	
	# Join button (only if match is waiting and has space)
	if status == "waiting" and players < max_players:
		var join_button = Button.new()
		join_button.text = "Join"
		join_button.pressed.connect(_on_join_match.bind(game_match))
		container.add_child(join_button)
	
	match_list.add_child(container)

func _update_chat():
	var messages = lobby_manager.get_chat_history()
	chat_history.clear()
	
	for message in messages:
		var timestamp = Time.get_datetime_string_from_unix_time(message.get("timestamp", 0))
		var username = message.get("username", "Unknown")
		var text = message.get("message", "")
		
		chat_history.append_text("[%s] [color=cyan]%s[/color]: %s\n" % [timestamp, username, text])

func _update_online_count():
	var users = lobby_manager.get_lobby_users()
	var count = users.size()
	online_count_label.text = "%d users online" % count

func _on_logout_pressed():
	print("Logging out user: ", current_user.username)
	
	# Leave lobby
	lobby_manager.leave_lobby(current_user.username)
	
	# Logout from user manager
	user_manager.logout_user()
	
	# Go to login screen
	_go_to_login()

func _on_refresh_pressed():
	_update_matches()
	_update_chat()
	_update_online_count()

func _on_create_match_pressed():
	# Set default values
	match_name_input.text = "%s's Match" % current_user.username
	game_mode_select.selected = 0
	map_select.selected = 0
	max_players_input.value = 4
	
	# Show dialog
	create_match_dialog.popup_centered()

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
	var success = lobby_manager.create_match(current_user.username, match_name, game_mode_text, map_text, max_players)
	
	create_match_dialog.hide()
	
	if success:
		show_message("Match created successfully!")
		_update_matches()
	else:
		show_message("Failed to create match")

func _on_join_match(game_match: Dictionary):
	var match_id = game_match.get("id", "")
	print("Attempting to join match: ", match_id)
	
	if match_id.is_empty():
		show_message("Invalid match ID")
		return
	
	# Join match through lobby manager
	var success = lobby_manager.join_match(current_user.username, match_id)
	
	if success:
		show_message("Joined match successfully!")
		
		# Start hosting/connecting to the actual game server
		if network_manager:
			var match_creator = game_match.get("creator", "")
			
			# If we're the creator, host the server
			if match_creator == current_user.username:
				print("We are the creator, starting server...")
				var server_name = game_match.get("name", "Match")
				var game_mode = game_match.get("game_mode", "Free-for-All")
				var map_name = game_match.get("map", "Map 1")
				var max_players = game_match.get("max_players", 4)
				
				network_manager.create_server(server_name, game_mode, map_name, max_players)
			else:
				print("Joining as client...")
				# In a real implementation, we'd need the server's IP/port
				# For now, assume localhost
				network_manager.connect_to_server("127.0.0.1", 7000)
	else:
		show_message("Failed to join match")

func _on_send_message():
	_send_chat_message()

func _on_message_submitted(text: String):
	_send_chat_message()

func _send_chat_message():
	var message = message_input.text.strip_edges()
	if message.is_empty():
		return
	
	print("Sending chat message: ", message)
	lobby_manager.send_chat_message(current_user.username, message)
	message_input.text = ""
	message_input.grab_focus()

func _on_filter_changed(index: int):
	_update_matches()

# LobbyManager signal handlers
func _on_user_joined_lobby(username: String):
	print("User joined lobby: ", username)
	_update_online_count()
	_update_chat()  # Refresh to see join message if any

func _on_user_left_lobby(username: String):
	print("User left lobby: ", username)
	_update_online_count()

func _on_chat_message_received(username: String, message: String, timestamp: float):
	print("Chat message from ", username, ": ", message)
	_update_chat()

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
	# In a real implementation, you might want to show this in a popup or status bar

func _go_to_login():
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("login")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and message_input.has_focus():
			_send_chat_message()
