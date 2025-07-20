extends Control

@onready var quick_game_button = $ModeContainer/QuickGameButton
@onready var find_game_button = $ModeContainer/FindGameButton
@onready var host_game_button = $ModeContainer/HostGameButton
@onready var back_button = $ModeContainer/BackButton

var scene_controller: Node
var network_manager: NetworkManager

func _ready():
	print("=== MODE SELECT READY ===")
	
	# Get scene controller and network manager
	scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		network_manager = scene_controller.network_manager
	
	# Connect buttons
	if quick_game_button:
		quick_game_button.pressed.connect(_on_quick_game_pressed)
	if find_game_button:
		find_game_button.pressed.connect(_on_find_game_pressed)
	if host_game_button:
		host_game_button.pressed.connect(_on_host_game_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _on_quick_game_pressed():
	print("Quick Play pressed - starting matchmaking...")
	if network_manager:
		network_manager.quick_play()
	else:
		print("ERROR: NetworkManager not found")

func _on_find_game_pressed():
	print("Find Game pressed - going to global lobby...")
	if scene_controller:
		scene_controller.change_scene("global_lobby")
	else:
		print("ERROR: SceneController not found")

func _on_host_game_pressed():
	print("Host Game pressed - going to custom match...")
	if scene_controller:
		scene_controller.change_scene("custom_match")
	else:
		print("ERROR: SceneController not found")

func _on_back_pressed():
	print("Back pressed - returning to main menu...")
	if scene_controller:
		scene_controller.change_scene("main_menu")
	else:
		print("ERROR: SceneController not found")
