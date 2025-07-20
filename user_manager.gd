extends Node

signal user_registered(username: String)
signal user_login_success(username: String)
signal user_login_failed(reason: String)
signal user_logout(username: String)

# User data structure
class UserData:
	var username: String
	var email: String
	var password_hash: String
	var created_at: String
	var last_login: String
	
	func _init(user: String, mail: String, pass_hash: String):
		username = user
		email = mail
		password_hash = pass_hash
		created_at = Time.get_datetime_string_from_system()
		last_login = ""

# Storage
var users: Dictionary = {}  # username -> UserData
var logged_in_users: Dictionary = {}  # username -> session_data
var current_user: UserData = null
var users_file_path = "user://users.json"

func _ready():
	load_users_from_file()

func register_user(username: String, email: String, password: String) -> Dictionary:
	"""Register a new user. Returns {success: bool, message: String}"""
	
	# Validate input
	if username.strip_edges().is_empty():
		return {"success": false, "message": "Username cannot be empty"}
	
	if email.strip_edges().is_empty() or not _is_valid_email(email):
		return {"success": false, "message": "Invalid email address"}
	
	if password.length() < 6:
		return {"success": false, "message": "Password must be at least 6 characters"}
	
	# Check if username is unique
	if users.has(username.to_lower()):
		return {"success": false, "message": "Username already exists"}
	
	# Check if email is unique
	for user_data in users.values():
		if user_data.email.to_lower() == email.to_lower():
			return {"success": false, "message": "Email already registered"}
	
	# Create new user
	var password_hash = _hash_password(password)
	var new_user = UserData.new(username, email, password_hash)
	users[username.to_lower()] = new_user
	
	# Save to file
	save_users_to_file()
	
	print("User registered successfully: ", username)
	user_registered.emit(username)
	return {"success": true, "message": "User registered successfully"}

func login_user(username_or_email: String, password: String) -> Dictionary:
	"""Login user. Returns {success: bool, message: String, user_data: UserData}"""
	
	# Find user by username or email
	var user_data: UserData = null
	var lookup_key = username_or_email.to_lower()
	
	# First try username
	if users.has(lookup_key):
		user_data = users[lookup_key]
	else:
		# Try email
		for key in users:
			if users[key].email.to_lower() == lookup_key:
				user_data = users[key]
				break
	
	if not user_data:
		user_login_failed.emit("User not found")
		return {"success": false, "message": "Invalid username/email or password"}
	
	# Verify password
	if not _verify_password(password, user_data.password_hash):
		user_login_failed.emit("Invalid password")
		return {"success": false, "message": "Invalid username/email or password"}
	
	# Check if user is already logged in
	if logged_in_users.has(user_data.username.to_lower()):
		return {"success": false, "message": "User already logged in"}
	
	# Login successful
	current_user = user_data
	user_data.last_login = Time.get_datetime_string_from_system()
	logged_in_users[user_data.username.to_lower()] = {
		"username": user_data.username,
		"login_time": user_data.last_login,
		"status": "lobby"  # "lobby", "in_match", "offline"
	}
	
	save_users_to_file()
	print("User logged in successfully: ", user_data.username)
	user_login_success.emit(user_data.username)
	return {"success": true, "message": "Login successful", "user_data": user_data}

func logout_user():
	"""Logout current user"""
	if current_user:
		var username = current_user.username.to_lower()
		logged_in_users.erase(username)
		print("User logged out: ", current_user.username)
		user_logout.emit(current_user.username)
		current_user = null

func get_current_user() -> UserData:
	return current_user

func is_logged_in() -> bool:
	return current_user != null

func get_logged_in_users() -> Array:
	"""Get list of currently logged in users"""
	var users_list = []
	for session_data in logged_in_users.values():
		users_list.append(session_data)
	return users_list

func set_user_status(username: String, status: String):
	"""Set user status: 'lobby', 'in_match', 'offline'"""
	var key = username.to_lower()
	if logged_in_users.has(key):
		logged_in_users[key].status = status

func _is_valid_email(email: String) -> bool:
	"""Basic email validation"""
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$")
	return regex.search(email) != null

func _hash_password(password: String) -> String:
	"""Simple password hashing (in production use proper crypto)"""
	return password.sha256_text()

func _verify_password(password: String, hash: String) -> bool:
	"""Verify password against hash"""
	return password.sha256_text() == hash

func save_users_to_file():
	"""Save users to JSON file"""
	var file = FileAccess.open(users_file_path, FileAccess.WRITE)
	if not file:
		print("Error: Could not open users file for writing")
		return
	
	var users_data = {}
	for username in users:
		var user = users[username]
		users_data[username] = {
			"username": user.username,
			"email": user.email,
			"password_hash": user.password_hash,
			"created_at": user.created_at,
			"last_login": user.last_login
		}
	
	file.store_string(JSON.stringify(users_data))
	file.close()
	print("Users saved to file: ", users_file_path)

func load_users_from_file():
	"""Load users from JSON file"""
	if not FileAccess.file_exists(users_file_path):
		print("No users file found, starting fresh")
		return
	
	var file = FileAccess.open(users_file_path, FileAccess.READ)
	if not file:
		print("Error: Could not open users file for reading")
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		print("Error parsing users JSON file")
		return
	
	var users_data = json.data
	for username in users_data:
		var user_dict = users_data[username]
		var user = UserData.new(
			user_dict.username,
			user_dict.email,
			user_dict.password_hash
		)
		user.created_at = user_dict.get("created_at", "")
		user.last_login = user_dict.get("last_login", "")
		users[username] = user
	
	print("Loaded ", users.size(), " users from file")

func get_user_count() -> int:
	return users.size()

func get_all_usernames() -> Array:
	var usernames = []
	for user_data in users.values():
		usernames.append(user_data.username)
	return usernames
