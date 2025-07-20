extends Control

@onready var play_button = $MenuContainer/PlayButton
@onready var settings_button = $MenuContainer/SettingButton
@onready var quit_button = $MenuContainer/QuitButton

var user_manager: Node
var scene_controller: Node

func _ready():
	print("=== MAIN MENU READY ===")
	
	# Get managers
	user_manager = get_node("/root/UserManager")
	scene_controller = get_tree().get_first_node_in_group("scene_controller")
	
	if not user_manager:
		print("Error: UserManager not found")
		return
	
	if not scene_controller:
		print("Error: SceneController not found")
		return
	
	# Check if user is logged in
	if not user_manager.is_logged_in():
		print("User not logged in, redirecting to login")
		scene_controller.change_scene("login")
		return
	
	# Connect buttons
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Update UI to show logged in user
	_update_ui_for_logged_user()

func _update_ui_for_logged_user():
	"""Update UI to show current user info"""
	var current_user = user_manager.get_current_user()
	if current_user:
		print("Welcome back: ", current_user.username)
		# You could add a welcome label here if needed
	
	# Add logout button to the menu
	var logout_button = Button.new()
	logout_button.text = "Logout"
	logout_button.add_theme_font_size_override("font_size", 44)
	logout_button.pressed.connect(_on_logout_pressed)
	$MenuContainer.add_child(logout_button)
	$MenuContainer.move_child(logout_button, 2)  # Place before quit button

func _on_play_pressed():
	# Set user status to lobby when entering multiplayer
	var current_user = user_manager.get_current_user()
	if current_user:
		user_manager.set_user_status(current_user.username, "lobby")
	
	scene_controller.change_scene("mode_select")

func _on_settings_pressed():
	# TODO: Implement settings menu
	print("Settings not implemented yet")

func _on_logout_pressed():
	print("Logging out user")
	user_manager.logout_user()
	scene_controller.change_scene("login")

func _on_quit_pressed():
	print("Quitting game")
	# Logout before quitting
	if user_manager and user_manager.is_logged_in():
		user_manager.logout_user()
	
	get_tree().quit()
