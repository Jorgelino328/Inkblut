extends Node

signal lobby_chat_message(username: String, message: String)
signal user_joined_lobby(username: String)
signal user_left_lobby(username: String)
signal match_created(match_data: Dictionary)
signal match_started(match_id: String)
signal match_ended(match_id: String)

class LobbyMatch:
	var id: String
	var creator_username: String
	var name: String
	var game_mode: String
	var map: String
	var max_players: int
	var current_players: Array = []
	var status: String = "created"  # "created", "started", "ended"
	var created_at: String
	
	func _init(creator: String, match_name: String, mode: String, map_name: String, max_p: int):
		creator_username = creator
		name = match_name
		game_mode = mode
		map = map_name
		max_players = max_p
		id = _generate_match_id()
		current_players.append(creator)
		created_at = Time.get_datetime_string_from_system()
		status = "created"
	
	func _generate_match_id() -> String:
		return "match_" + str(randi_range(1000, 9999)) + "_" + str(Time.get_ticks_msec())

# Lobby state
var lobby_users: Dictionary = {}  # username -> user_info
var lobby_matches: Dictionary = {}  # match_id -> LobbyMatch
var chat_history: Array = []

func _ready():
	print("=== LOBBY MANAGER READY ===")

func join_lobby(username: String):
	"""User joins the global lobby"""
	if lobby_users.has(username):
		print("User ", username, " already in lobby")
		return
	
	lobby_users[username] = {
		"username": username,
		"status": "lobby",  # "lobby", "in_match"
		"joined_at": Time.get_datetime_string_from_system()
	}
	
	print("User ", username, " joined lobby")
	user_joined_lobby.emit(username)
	
	# Set user status in UserManager
	var user_manager = get_node("/root/UserManager")
	if user_manager:
		user_manager.set_user_status(username, "lobby")

func leave_lobby(username: String):
	"""User leaves the global lobby"""
	if not lobby_users.has(username):
		return
	
	lobby_users.erase(username)
	print("User ", username, " left lobby")
	user_left_lobby.emit(username)

func send_chat_message(username: String, message: String):
	"""Send a chat message to the lobby"""
	if not lobby_users.has(username):
		print("User ", username, " not in lobby, cannot send message")
		return
	
	var chat_entry = {
		"username": username,
		"message": message,
		"timestamp": Time.get_datetime_string_from_system()
	}
	
	chat_history.append(chat_entry)
	
	# Keep only last 100 messages
	if chat_history.size() > 100:
		chat_history.pop_front()
	
	print("Lobby chat - ", username, ": ", message)
	lobby_chat_message.emit(username, message)

func get_lobby_users() -> Array:
	"""Get list of users currently in lobby"""
	var users_list = []
	for user_info in lobby_users.values():
		if user_info.status == "lobby":
			users_list.append(user_info.username)
	return users_list

func get_chat_history() -> Array:
	"""Get recent chat history"""
	return chat_history.slice(-20)  # Last 20 messages

func create_match(creator_username: String, match_name: String, game_mode: String, map: String, max_players: int) -> Dictionary:
	"""Create a new match in the lobby"""
	print("=== LOBBY MANAGER: CREATE_MATCH ===")
	print("Creator: ", creator_username)
	print("Match name: ", match_name)
	print("Game mode: ", game_mode)
	print("Map: ", map)
	print("Max players: ", max_players)
	
	if not lobby_users.has(creator_username):
		print("ERROR: User not in lobby: ", creator_username)
		print("Current lobby users: ", lobby_users.keys())
		return {"success": false, "message": "User not in lobby"}
	
	var new_match = LobbyMatch.new(creator_username, match_name, game_mode, map, max_players)
	lobby_matches[new_match.id] = new_match
	
	print("Match created with ID: ", new_match.id)
	print("Total matches now: ", lobby_matches.size())
	
	# Update user status
	lobby_users[creator_username].status = "in_match"
	
	print("Match created: ", match_name, " by ", creator_username)
	match_created.emit({
		"id": new_match.id,
		"name": new_match.name,
		"creator": new_match.creator_username,
		"game_mode": new_match.game_mode,
		"map": new_match.map,
		"max_players": new_match.max_players,
		"current_players": new_match.current_players.size(),
		"status": new_match.status
	})
	
	return {"success": true, "match_id": new_match.id}

func join_match(username: String, match_id: String) -> Dictionary:
	"""Join an existing match"""
	if not lobby_users.has(username):
		return {"success": false, "message": "User not in lobby"}
	
	if not lobby_matches.has(match_id):
		return {"success": false, "message": "Match not found"}
	
	var lobby_match = lobby_matches[match_id]
	
	if lobby_match.status != "created":
		return {"success": false, "message": "Match already started"}
	
	if lobby_match.current_players.size() >= lobby_match.max_players:
		return {"success": false, "message": "Match is full"}
	
	if username in lobby_match.current_players:
		return {"success": false, "message": "Already in this match"}
	
	lobby_match.current_players.append(username)
	lobby_users[username].status = "in_match"
	
	print("User ", username, " joined match ", lobby_match.name)
	return {"success": true}

func leave_match(username: String, match_id: String) -> Dictionary:
	"""Leave a match"""
	if not lobby_matches.has(match_id):
		return {"success": false, "message": "Match not found"}
	
	var lobby_match = lobby_matches[match_id]
	
	if not username in lobby_match.current_players:
		return {"success": false, "message": "Not in this match"}
	
	lobby_match.current_players.erase(username)
	
	if lobby_users.has(username):
		lobby_users[username].status = "lobby"
	
	# If creator left and match not started, delete match
	if username == lobby_match.creator_username and lobby_match.status == "created":
		lobby_matches.erase(match_id)
		print("Match ", lobby_match.name, " deleted (creator left)")
	
	print("User ", username, " left match ", lobby_match.name)
	return {"success": true}

func start_match(username: String, match_id: String) -> Dictionary:
	"""Start a match (only creator can do this)"""
	if not lobby_matches.has(match_id):
		return {"success": false, "message": "Match not found"}
	
	var lobby_match = lobby_matches[match_id]
	
	if username != lobby_match.creator_username:
		return {"success": false, "message": "Only match creator can start the match"}
	
	if lobby_match.status != "created":
		return {"success": false, "message": "Match already started"}
	
	if lobby_match.current_players.size() < 2:
		return {"success": false, "message": "Need at least 2 players to start"}
	
	lobby_match.status = "started"
	print("Match ", lobby_match.name, " started by ", username)
	match_started.emit(match_id)
	
	return {"success": true}

func end_match(match_id: String):
	"""End a match and return players to lobby"""
	if not lobby_matches.has(match_id):
		return
	
	var lobby_match = lobby_matches[match_id]
	
	# Return all players to lobby
	for player_username in lobby_match.current_players:
		if lobby_users.has(player_username):
			lobby_users[player_username].status = "lobby"
	
	# Remove match
	lobby_matches.erase(match_id)
	print("Match ", lobby_match.name, " ended")
	match_ended.emit(match_id)

func get_available_matches() -> Array[Dictionary]:
	"""Get list of matches that can be joined"""
	print("=== LOBBY MANAGER: GET_AVAILABLE_MATCHES ===")
	print("Total lobby matches: ", lobby_matches.size())
	for match_id in lobby_matches.keys():
		var lobby_match = lobby_matches[match_id]
		print("  - Match ID: ", match_id, " | Name: ", lobby_match.name, " | Status: ", lobby_match.status)
	
	var available_matches: Array[Dictionary] = []
	for lobby_match in lobby_matches.values():
		if lobby_match.status == "created":
			available_matches.append({
				"id": lobby_match.id,
				"name": lobby_match.name,
				"creator": lobby_match.creator_username,
				"game_mode": lobby_match.game_mode,
				"map": lobby_match.map,
				"max_players": lobby_match.max_players,
				"current_players": lobby_match.current_players.size(),
				"player_list": lobby_match.current_players
			})
	
	print("Available matches to return: ", available_matches.size())
	return available_matches

func get_match_info(match_id: String) -> Dictionary:
	"""Get detailed info about a specific match"""
	if not lobby_matches.has(match_id):
		return {}
	
	var match = lobby_matches[match_id]
	return {
		"id": match.id,
		"name": match.name,
		"creator": match.creator_username,
		"game_mode": match.game_mode,
		"map": match.map,
		"max_players": match.max_players,
		"current_players": match.current_players,
		"status": match.status,
		"created_at": match.created_at
	}
