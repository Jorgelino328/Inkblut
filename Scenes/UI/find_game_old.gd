extends Control

@onready var server_container: VBoxContainer = $ServerPanel/ServerContainer
@onready var search_button: Button = $SearchButton
@onready var search_field: LineEdit = $SearchField
@onready var back_button: Button = $MenuContainerH/MenuContainerV/BackButton

# Filter controls
@onready var game_mode_filter: OptionButton = $MenuContainerH/MenuContainerV/GameModeButton
@onready var map_filter: OptionButton = $MenuContainerH/MenuContainerV/MapButton
@onready var is_joinable_checkbox: CheckBox = $MenuContainerH/MenuContainerV/CheckboxContainer/IsJoinable

var network_manager: NetworkManager
var all_servers: Array[Dictionary] = []

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
	print("=== FIND GAME DEBUG INFO ===")
	print("Network manager available: ", network_manager != null)
	if network_manager:
		print("Network manager is_server: ", network_manager.is_server)
		print("Multiplayer unique ID: ", multiplayer.get_unique_id())
	print("============================")
	
	# Start server discovery
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
		if child.name.begins_with("ServerButton_"):
			var port = child.name.get_slice("_", 1).to_int()
			current_ports[port] = true
	
	# Check for servers that no longer exist and remove them
	var server_ports = {}
	for server in servers:
		server_ports[server.get("port", 7000)] = true
	
	for child in server_container.get_children():
		if child.name.begins_with("ServerButton_"):
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
		if child.name.begins_with("ServerButton_"):
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
	
	# Add button to server list
	server_container.add_child(button)

func _update_server_container(container: Button, server_info: Dictionary):
	# Update the server button text
	var button_text = "%s - %s - %s - %d/%d" % [
		server_info.get("name", "Unknown Server"),
		server_info.get("game_mode", "Unknown Mode"),
		server_info.get("map", "Unknown Map"),
		server_info.get("current_players", 0),
		server_info.get("max_players", 10)
	]
	container.text = button_text

func _on_server_selected(server_info: Dictionary):
	print("Attempting to join server: ", server_info.get("name"))
	
	if network_manager:
		# Ensure we're disconnected from any previous connections
		if network_manager.is_hosting():
			print("Disconnecting from current server before joining new one")
			network_manager.disconnect_from_server()
			await get_tree().create_timer(1.0).timeout
		
		# Connect to network manager signals for connection
		if not network_manager.connected_to_server.is_connected(_on_connected_to_server):
			network_manager.connected_to_server.connect(_on_connected_to_server)
		
		print("Connecting to server at 127.0.0.1:", server_info.get("port", 7000))
		# Try to connect to the server (assuming local network for now)
		var success = network_manager.connect_to_server("127.0.0.1", server_info.get("port", 7000))
		if not success:
			print("Failed to initiate connection to server")

func _on_connected_to_server(success: bool):
	print("Connection attempt result: ", success)
	if success:
		print("Successfully joined server!")
		# Switch to lobby scene
		var scene_controller = get_tree().get_first_node_in_group("scene_controller")
		if scene_controller:
			print("Switching to lobby scene...")
			scene_controller.change_scene("lobby")
		else:
			print("ERROR: Could not find scene controller")
	else:
		print("Failed to join server - connection unsuccessful")

func _on_search_pressed():
	_refresh_server_list()

func _on_back_pressed():
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("mode_select")

func _on_create_test_server_pressed():
	print("Creating functional test server in background...")
	
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if not scene_controller:
		print("ERROR: Could not find scene controller")
		return
	
	# Generate randomized server data
	var game_modes = ["TEAM DEATHMATCH", "FREE-FOR-ALL"]
	var maps = ["MAP 1", "MAP 2", "MAP 3"]
	var max_players_options = [4, 6, 8]
	
	var game_mode = game_modes[randi() % game_modes.size()]
	var map_name = maps[randi() % maps.size()]
	var max_players = max_players_options[randi() % max_players_options.size()]
	var server_name = "Test Server " + str(randi() % 1000)
	var port = 7000 + randi() % 100  # Use different ports for multiple test servers
	
	print("Creating test server: ", server_name)
	print("  Game Mode: ", game_mode)
	print("  Map: ", map_name)
	print("  Max Players: ", max_players)
	print("  Port: ", port)
	
	# Create the server, but don't stay as host
	_create_background_server(server_name, game_mode, map_name, max_players, port)

func _on_create_full_server_pressed():
	print("Creating full test server in background...")
	
	# Create a server that's immediately full for testing filters
	var game_modes = ["TEAM DEATHMATCH", "FREE-FOR-ALL"]
	var maps = ["MAP 1", "MAP 2", "MAP 3"]
	
	var game_mode = game_modes[randi() % game_modes.size()]
	var map_name = maps[randi() % maps.size()]
	var server_name = "Full Server " + str(randi() % 1000)
	var max_players = 1  # Very small so it appears full immediately
	var port = 7100 + randi() % 100  # Use different port range
	
	print("Creating full test server: ", server_name)
	print("  Game Mode: ", game_mode)
	print("  Map: ", map_name)
	print("  Max Players: ", max_players, " (will appear full)")
	print("  Port: ", port)
	
	# Create background server (will be full with just the host)
	_create_background_server(server_name, game_mode, map_name, max_players, port)

func _on_search_text_changed(new_text: String):
	# Apply filters when search text changes
	_apply_filters()

func _on_filter_changed(index: int = 0):
	# Apply filters when any filter option changes
	_apply_filters()

func _exit_tree():
	# Leave background servers running - they'll be cleaned up when the application exits
	# This allows users to join them from other screens or after returning to Find Game
	pass

func _on_add_player_to_server(server_info: Dictionary):
	print("Adding simulated player to server: ", server_info.get("name"))
	
	var port = server_info.get("port", 7000)
	var background_server_name = "BackgroundServer_" + str(port)
	
	print("Looking for background server with name: ", background_server_name)
	
	# Debug: List all children in root to see what's available
	print("Available nodes in root:")
	for child in get_tree().root.get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
	
	# Find the background server NetworkManager
	var background_server = get_tree().root.get_node_or_null(background_server_name)
	if background_server:
		print("Found background server: ", background_server.name)
		print("Background server class: ", background_server.get_class())
		print("Background server has add_simulated_player method: ", background_server.has_method("add_simulated_player"))
		
		if background_server.has_method("add_simulated_player"):
			print("Calling add_simulated_player...")
			var success = background_server.add_simulated_player()
			
			if success:
				# Update just this server's info in our local list and UI
				var updated_server_info = background_server.get_server_info()
				print("Updated server info received: ", updated_server_info)
				
				# Update the server in our all_servers array
				for i in range(all_servers.size()):
					if all_servers[i].get("port", 7000) == port:
						all_servers[i] = updated_server_info
						break
				
				# Update just this server's UI container
				var container_name = "ServerContainer_" + str(port)
				var container = server_container.get_node_or_null(container_name)
				if container:
					_update_server_container(container, updated_server_info)
					print("Updated server UI: ", updated_server_info.get("current_players"), "/", updated_server_info.get("max_players"))
				else:
					print("Could not find server container to update: ", container_name)
			else:
				print("Failed to add simulated player")
		else:
			print("Background server does not have add_simulated_player method")
	else:
		print("Could not find background server: ", background_server_name)
		print("Available NetworkManager nodes:")
		for nm in get_tree().get_nodes_in_group("network_manager"):
			print("  - ", nm.name, " (hosting: ", nm.is_hosting(), ")")

# Creates a server in background using a separate NetworkManager instance
func _create_background_server(server_name: String, game_mode: String, map_name: String, max_players: int, port: int):
	print("Creating background server on port ", port)
	
	# Create a separate NetworkManager instance for the background server
	var background_network_manager = preload("res://network_manager.gd").new()
	background_network_manager.name = "BackgroundServer_" + str(port)
	
	# Add it to the scene tree so it persists
	get_tree().root.add_child(background_network_manager)
	
	# Wait a frame for _ready to be called and group membership to be established
	await get_tree().process_frame
	
	print("Background NetworkManager added to scene tree, groups: ", background_network_manager.get_groups())
	
	# Create the server using the background NetworkManager
	var success = background_network_manager.create_server(server_name, game_mode, map_name, max_players, port)
	
	if not success:
		print("Failed to create background server")
		background_network_manager.queue_free()
		return
	
	print("Background server created successfully on port ", port)
	print("Server info: ", background_network_manager.get_server_info())
	print("Server is running independently in the background")
	
	# Refresh the server list to show the new background server
	await get_tree().create_timer(1.0).timeout
	_refresh_server_list()
