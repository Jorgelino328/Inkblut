extends Control

@onready var server_container: VBoxContainer = $ServerPanel/ServerContainer
@onready var search_button: Button = $SearchButton
@onready var search_field: LineEdit = $SearchField
@onready var back_button: Button = $MenuContainerH/MenuContainerV/BackButton
@onready var create_test_server_button: Button = $MenuContainerH/MenuContainerV/CreateTestServerButton
@onready var create_full_server_button: Button = $MenuContainerH/MenuContainerV/CreateFullServerButton

# Filter controls
@onready var game_mode_filter: OptionButton = $MenuContainerH/MenuContainerV/GameModeButton
@onready var map_filter: OptionButton = $MenuContainerH/MenuContainerV/MapButton
@onready var is_joinable_checkbox: CheckBox = $MenuContainerH/MenuContainerV/CheckboxContainer/IsJoinable

var network_manager: NetworkManager
var all_servers: Array[Dictionary] = []
var background_test_servers: Array[NetworkManager] = []

func _ready():
	# Get reference to network manager
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		network_manager = scene_controller.network_manager
		
		# Connect to network manager signals
		if network_manager and not network_manager.server_list_updated.is_connected(_on_server_list_updated):
			network_manager.server_list_updated.connect(_on_server_list_updated)
	
	# Connect UI signals
	if search_button:
		search_button.pressed.connect(_on_search_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if create_test_server_button:
		create_test_server_button.pressed.connect(_on_create_test_server_pressed)
	if create_full_server_button:
		create_full_server_button.pressed.connect(_on_create_full_server_pressed)
	
	# Connect filter controls
	if search_field:
		search_field.text_changed.connect(_on_search_text_changed)
	if game_mode_filter:
		game_mode_filter.item_selected.connect(_on_filter_changed)
	if map_filter:
		map_filter.item_selected.connect(_on_filter_changed)
	if is_joinable_checkbox:
		is_joinable_checkbox.toggled.connect(_on_filter_changed)
	
	# Start discovering servers
	_refresh_server_list()

func _refresh_server_list():
	# Only clear and recreate when doing a full refresh
	for child in server_container.get_children():
		child.queue_free()
	
	# Start server discovery
	if network_manager:
		network_manager.start_server_discovery()
	else:
		print("Network manager not found!")

func _on_server_list_updated(servers: Array):
	print("Received ", servers.size(), " servers")
	
	# Check if we have any new servers that require container creation
	var current_ports = {}
	for child in server_container.get_children():
		if child.name.begins_with("ServerContainer_"):
			var port = child.name.get_slice("_", 1).to_int()
			current_ports[port] = true
	
	# Check for servers that no longer exist and remove them
	var server_ports = {}
	for server in servers:
		server_ports[server.get("port", 7000)] = true
	
	for child in server_container.get_children():
		if child.name.begins_with("ServerContainer_"):
			var port = child.name.get_slice("_", 1).to_int()
			if not port in server_ports:
				child.queue_free()
	
	all_servers = servers.duplicate()
	_apply_filters()

func _apply_filters():
	# Get filter values
	var search_text = search_field.text.to_lower() if search_field else ""
	var game_mode_selected = game_mode_filter.selected if game_mode_filter else 0
	var map_selected = map_filter.selected if map_filter else 0
	var show_only_joinable = is_joinable_checkbox.button_pressed if is_joinable_checkbox else false
	
	# Get existing server containers
	var existing_containers = {}
	var no_servers_label = null
	
	for child in server_container.get_children():
		if child.name.begins_with("ServerContainer_"):
			var port = child.name.get_slice("_", 1).to_int()
			existing_containers[port] = child
		elif child.name == "NoServersLabel":
			no_servers_label = child
	
	# Filter servers
	var filtered_servers = all_servers.filter(func(server): 
		return _server_matches_filters(server, search_text, game_mode_selected, map_selected, show_only_joinable)
	)
	
	# Hide all existing containers first
	for container in existing_containers.values():
		container.visible = false
	
	# Show/update containers for filtered servers
	for server in filtered_servers:
		var port = server.get("port", 7000)
		if port in existing_containers:
			# Update existing container
			_update_server_container(existing_containers[port], server)
			existing_containers[port].visible = true
		else:
			# Create new container
			_create_server_button(server)
	
	# Handle "no servers" message
	if filtered_servers.is_empty():
		if not no_servers_label:
			no_servers_label = Label.new()
			no_servers_label.name = "NoServersLabel"
			no_servers_label.text = "No servers found matching your criteria"
			no_servers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			server_container.add_child(no_servers_label)
		else:
			no_servers_label.visible = true
	else:
		if no_servers_label:
			no_servers_label.visible = false

func _server_matches_filters(server_info: Dictionary, search_text: String, game_mode_selected: int, map_selected: int, show_only_joinable: bool) -> bool:
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
	
	# Map filter
	if map_selected > 0 and map_filter:
		var selected_map = map_filter.get_item_text(map_selected)
		var server_map = server_info.get("map", "")
		if server_map != selected_map:
			return false
	
	# Joinable filter (only show servers with available slots)
	if show_only_joinable:
		var current_players = server_info.get("current_players", 0)
		var max_players = server_info.get("max_players", 0)
		if current_players >= max_players:
			return false
	
	return true

func _create_server_button(server_info: Dictionary):
	# Create a horizontal container for server info and actions
	var server_row_container = HBoxContainer.new()
	server_row_container.name = "ServerContainer_" + str(server_info.get("port", 7000))
	
	# Create main server button
	var button = Button.new()
	button.name = "ServerButton_" + str(server_info.get("port", 7000))
	
	# Format button text
	var button_text = "%s - %s - %s - %d/%d" % [
		server_info.get("name", "Unknown Server"),
		server_info.get("game_mode", "Unknown Mode"),
		server_info.get("map", "Unknown Map"),
		server_info.get("current_players", 0),
		server_info.get("max_players", 10)
	]
	
	button.text = button_text
	button.pressed.connect(_on_server_selected.bind(server_info))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create "Add Player" button for testing
	var add_player_button = Button.new()
	add_player_button.text = "Add Player"
	add_player_button.pressed.connect(_on_add_player_to_server.bind(server_info))
	add_player_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	
	# Disable button if server is full
	var current_players = server_info.get("current_players", 0)
	var max_players = server_info.get("max_players", 10)
	if current_players >= max_players:
		add_player_button.disabled = true
		add_player_button.text = "Full"
	
	# Add buttons to container
	server_row_container.add_child(button)
	server_row_container.add_child(add_player_button)
	
	# Add container to server list
	server_container.add_child(server_row_container)

func _update_server_container(container: HBoxContainer, server_info: Dictionary):
	# Update the server button text
	var server_button = container.get_node("ServerButton_" + str(server_info.get("port", 7000)))
	if server_button:
		var button_text = "%s - %s - %s - %d/%d" % [
			server_info.get("name", "Unknown Server"),
			server_info.get("game_mode", "Unknown Mode"),
			server_info.get("map", "Unknown Map"),
			server_info.get("current_players", 0),
			server_info.get("max_players", 10)
		]
		server_button.text = button_text
	
	# Update the "Add Player" button
	var add_player_button = container.get_child(1) as Button  # Second child should be the add player button
	if add_player_button:
		var current_players = server_info.get("current_players", 0)
		var max_players = server_info.get("max_players", 10)
		if current_players >= max_players:
			add_player_button.disabled = true
			add_player_button.text = "Full"
		else:
			add_player_button.disabled = false
			add_player_button.text = "Add Player"

func _on_server_selected(server_info: Dictionary):
	print("Attempting to join server: ", server_info.get("name"))
	
	if network_manager:
		# Connect to network manager signals for connection
		if not network_manager.connected_to_server.is_connected(_on_connected_to_server):
			network_manager.connected_to_server.connect(_on_connected_to_server)
		
		# Try to connect to the server (assuming local network for now)
		network_manager.connect_to_server("127.0.0.1", server_info.get("port", 7000))

func _on_connected_to_server(success: bool):
	if success:
		print("Successfully joined server!")
		# Switch to lobby scene
		var scene_controller = get_tree().get_first_node_in_group("scene_controller")
		if scene_controller:
			scene_controller.change_scene("lobby")
	else:
		print("Failed to join server")

func _on_search_pressed():
	_refresh_server_list()

func _on_back_pressed():
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("mode_select")

func _on_create_test_server_pressed():
	print("Creating test server...")
	
	# Create a new NetworkManager instance for the background test server
	var test_network_manager = NetworkManager.new()
	background_test_servers.append(test_network_manager)
	
	# Add it to the scene tree so it can function
	get_tree().current_scene.add_child(test_network_manager)
	
	# Create server with randomized test data
	var server_name = "Test Server " + str(background_test_servers.size())
	var port = 7000 + background_test_servers.size()
	
	# Random game modes and maps for testing filters
	var game_modes = ["TEAM DEATHMATCH", "FREE-FOR-ALL"]
	var maps = ["MAP 1", "MAP 2", "MAP 3"]
	var max_players_options = [4, 6, 8, 10]
	
	var game_mode = game_modes[randi() % game_modes.size()]
	var map_name = maps[randi() % maps.size()]
	var max_players = max_players_options[randi() % max_players_options.size()]
	
	# Random starting player count (0 to max_players - 1)
	var starting_players = randi() % max_players
	
	print("Creating test server: ", server_name, " on port ", port)
	print("  Game Mode: ", game_mode)
	print("  Map: ", map_name)
	print("  Players: ", starting_players, "/", max_players)
	
	test_network_manager.create_server(server_name, game_mode, map_name, max_players, port)
	
	# Set random starting player count
	if starting_players > 0:
		test_network_manager.server_info.current_players = starting_players
	
	# Trigger server discovery to show the new server smoothly
	await get_tree().create_timer(1.0).timeout  # Wait a bit for server to start
	if network_manager:
		network_manager.start_server_discovery()

func _on_create_full_server_pressed():
	print("Creating full test server...")
	
	# Create a new NetworkManager instance for the background test server
	var test_network_manager = NetworkManager.new()
	background_test_servers.append(test_network_manager)
	
	# Add it to the scene tree so it can function
	get_tree().current_scene.add_child(test_network_manager)
	
	# Create server with randomized test data
	var server_name = "Full Server " + str(background_test_servers.size())
	var port = 7000 + background_test_servers.size()
	
	# Random game modes and maps for testing filters
	var game_modes = ["TEAM DEATHMATCH", "FREE-FOR-ALL"]
	var maps = ["MAP 1", "MAP 2", "MAP 3"]
	var max_players_options = [4, 6, 8, 10]
	
	var game_mode = game_modes[randi() % game_modes.size()]
	var map_name = maps[randi() % maps.size()]
	var max_players = max_players_options[randi() % max_players_options.size()]
	
	print("Creating full test server: ", server_name, " on port ", port)
	print("  Game Mode: ", game_mode)
	print("  Map: ", map_name)
	print("  Players: ", max_players, "/", max_players, " (FULL)")
	
	test_network_manager.create_server(server_name, game_mode, map_name, max_players, port)
	
	# Set server to full capacity
	test_network_manager.server_info.current_players = max_players
	
	# Trigger server discovery to show the new server smoothly
	await get_tree().create_timer(1.0).timeout  # Wait a bit for server to start
	if network_manager:
		network_manager.start_server_discovery()

func _on_search_text_changed(new_text: String):
	# Apply filters when search text changes
	_apply_filters()

func _on_filter_changed(index: int = 0):
	# Apply filters when any filter option changes
	_apply_filters()

func _exit_tree():
	# Clean up background test servers when leaving the scene
	for test_server in background_test_servers:
		if is_instance_valid(test_server):
			test_server.queue_free()
	background_test_servers.clear()

func _on_add_player_to_server(server_info: Dictionary):
	# Find the corresponding NetworkManager and increase player count
	var server_port = server_info.get("port", 7000)
	var current_players = server_info.get("current_players", 0)
	var max_players = server_info.get("max_players", 10)
	
	if current_players >= max_players:
		print("Server is already full!")
		return
	
	# Find the test server NetworkManager instance
	for test_server in background_test_servers:
		if test_server.is_hosting() and test_server.server_info.get("port") == server_port:
			test_server.server_info.current_players += 1
			print("Added player to ", server_info.get("name"), " (", test_server.server_info.current_players, "/", max_players, ")")
			
			# Update the server info in our local list and refresh filters smoothly
			for i in range(all_servers.size()):
				if all_servers[i].get("port") == server_port:
					all_servers[i] = test_server.server_info.duplicate()
					break
			
			# Apply filters which will update the UI smoothly
			_apply_filters()
			return
	
	print("Could not find server to add player to")
