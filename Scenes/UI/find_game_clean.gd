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
	
	# Start server discovery
	_refresh_server_list()

func _refresh_server_list():
	# Clear existing server containers
	for child in server_container.get_children():
		child.queue_free()
	
	# Start server discovery
	if network_manager:
		network_manager.start_server_discovery()
	else:
		print("Network manager not found!")

func _on_server_list_updated(servers: Array):
	print("Received ", servers.size(), " servers")
	all_servers = servers.duplicate()
	_apply_filters()

func _apply_filters():
	# Get filter values
	var search_text = search_field.text.to_lower() if search_field else ""
	var game_mode_selected = game_mode_filter.selected if game_mode_filter else 0
	var map_selected = map_filter.selected if map_filter else 0
	var show_only_joinable = is_joinable_checkbox.button_pressed if is_joinable_checkbox else false
	
	# Clear existing containers
	for child in server_container.get_children():
		child.queue_free()
	
	# Filter servers
	var filtered_servers = all_servers.filter(func(server): 
		return _server_matches_filters(server, search_text, game_mode_selected, map_selected, show_only_joinable)
	)
	
	# Create server buttons for filtered servers
	for server in filtered_servers:
		_create_server_button(server)
	
	# Handle "no servers" message
	if filtered_servers.is_empty():
		var no_servers_label = Label.new()
		no_servers_label.text = "No servers found matching your criteria"
		no_servers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		server_container.add_child(no_servers_label)

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

func _on_server_selected(server_info: Dictionary):
	print("Attempting to join server: ", server_info.get("name"))
	
	if network_manager:
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

func _on_search_text_changed(new_text: String):
	# Apply filters when search text changes
	_apply_filters()

func _on_filter_changed(index: int = 0):
	# Apply filters when any filter option changes
	_apply_filters()
