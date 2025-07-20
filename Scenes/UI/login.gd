extends Control

# UI References
@onready var tab_container = $CenterContainer/LoginPanel/VBoxContainer/TabContainer
@onready var action_button = $CenterContainer/LoginPanel/VBoxContainer/ActionButton
@onready var message_dialog = $MessageDialog
@onready var message_label = $MessageDialog/MessageLabel

# Login Form
@onready var login_tab = $CenterContainer/LoginPanel/VBoxContainer/TabContainer/Login
@onready var username_input = $CenterContainer/LoginPanel/VBoxContainer/TabContainer/Login/UsernameInput
@onready var password_input = $CenterContainer/LoginPanel/VBoxContainer/TabContainer/Login/PasswordInput

# Register Form
@onready var register_tab = $CenterContainer/LoginPanel/VBoxContainer/TabContainer/Register
@onready var reg_username_input = $CenterContainer/LoginPanel/VBoxContainer/TabContainer/Register/RegUsernameInput
@onready var reg_email_input = $CenterContainer/LoginPanel/VBoxContainer/TabContainer/Register/RegEmailInput
@onready var reg_password_input = $CenterContainer/LoginPanel/VBoxContainer/TabContainer/Register/RegPasswordInput
@onready var reg_password_confirm_input = $CenterContainer/LoginPanel/VBoxContainer/TabContainer/Register/RegPasswordConfirmInput

var is_register_mode = false
var user_manager: Node

func _ready():
	print("=== LOGIN SCREEN READY ===")
	
	# Get user manager
	user_manager = get_node("/root/UserManager")
	if not user_manager:
		show_message("Error: UserManager not found", true)
		return
	
	# Connect signals
	tab_container.tab_changed.connect(_on_tab_changed)
	action_button.pressed.connect(_on_action_button_pressed)
	
	# Connect user manager signals
	user_manager.user_registered.connect(_on_user_registered)
	user_manager.user_login_success.connect(_on_user_login_success)
	user_manager.user_login_failed.connect(_on_user_login_failed)
	
	# Set initial mode (Login tab)
	tab_container.current_tab = 0
	_set_login_mode()
	
	# Focus first input
	username_input.grab_focus()

func _on_tab_changed(tab: int):
	if tab == 0:
		_set_login_mode()
	else:
		_set_register_mode()

func _set_login_mode():
	is_register_mode = false
	action_button.text = "Login"
	clear_message()
	username_input.grab_focus()

func _set_register_mode():
	is_register_mode = true
	action_button.text = "Register"
	clear_message()
	reg_username_input.grab_focus()

func _on_action_button_pressed():
	if is_register_mode:
		_handle_register()
	else:
		_handle_login()

func _handle_login():
	var username = username_input.text.strip_edges()
	var password = password_input.text
	
	if username.is_empty():
		show_message("Please enter your username or email", true)
		return
	
	if password.is_empty():
		show_message("Please enter your password", true)
		return
	
	show_message("Logging in...", false)
	action_button.disabled = true
	
	var result = user_manager.login_user(username, password)
	
	action_button.disabled = false
	
	if result.success:
		show_message("Login successful! Welcome back!", false)
		# Wait a moment then go to main menu
		await get_tree().create_timer(1.0).timeout
		_go_to_main_menu()
	else:
		# Provide more specific error messages
		var error_msg = result.message
		if error_msg.contains("not found"):
			error_msg = "Account not found. Please check your username/email or register a new account."
		elif error_msg.contains("password"):
			error_msg = "Incorrect password. Please try again."
		
		show_message(error_msg, true)

func _handle_register():
	var username = reg_username_input.text.strip_edges()
	var email = reg_email_input.text.strip_edges()
	var password = reg_password_input.text
	var confirm_password = reg_password_confirm_input.text
	
	# Validate input fields
	if username.is_empty():
		show_message("Please enter a username", true)
		return
	
	if email.is_empty():
		show_message("Please enter an email address", true)
		return
	
	if password.is_empty():
		show_message("Please enter a password", true)
		return
	
	if confirm_password.is_empty():
		show_message("Please confirm your password", true)
		return
	
	# Validate email format (basic check)
	if not email.contains("@") or not email.contains("."):
		show_message("Please enter a valid email address", true)
		return
	
	# Validate password length
	if password.length() < 6:
		show_message("Password must be at least 6 characters long", true)
		return
	
	# Check if passwords match
	if password != confirm_password:
		show_message("Passwords do not match", true)
		return
	
	show_message("Creating account...", false)
	action_button.disabled = true
	
	var result = user_manager.register_user(username, email, password)
	
	action_button.disabled = false
	
	if result.success:
		show_message("Account created successfully! You can now login.", false)
		# Clear register form and switch to login
		_clear_register_form()
		# Switch to login tab after successful registration
		tab_container.current_tab = 0
		_set_login_mode()
	else:
		show_message(result.message, true)

func _clear_register_form():
	reg_username_input.text = ""
	reg_email_input.text = ""
	reg_password_input.text = ""
	reg_password_confirm_input.text = ""

func show_message(text: String, is_error: bool = false):
	message_label.text = text
	if is_error:
		message_dialog.title = "Error"
		message_label.modulate = Color.RED
		print("LOGIN ERROR: ", text)
	else:
		message_dialog.title = "Info"
		message_label.modulate = Color.WHITE
		print("LOGIN INFO: ", text)
	
	message_dialog.popup_centered()

func clear_message():
	# No visual message to clear, just for compatibility
	pass

func _on_user_registered(username: String):
	print("User registered: ", username)

func _on_user_login_success(username: String):
	print("User login success: ", username)

func _on_user_login_failed(reason: String):
	print("User login failed: ", reason)

func _go_to_main_menu():
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("main_menu")
	else:
		print("Error: Scene controller not found")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER:
			_on_action_button_pressed()
		elif event.keycode == KEY_TAB:
			# Handle tab navigation
			if is_register_mode:
				if reg_username_input.has_focus():
					reg_email_input.grab_focus()
				elif reg_email_input.has_focus():
					reg_password_input.grab_focus()
				elif reg_password_input.has_focus():
					reg_password_confirm_input.grab_focus()
			else:
				if username_input.has_focus():
					password_input.grab_focus()
				elif password_input.has_focus():
					username_input.grab_focus()
