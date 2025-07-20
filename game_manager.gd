class_name GameManager extends Node

signal game_started
signal game_ended(winner)
signal player_spawned(player_id: int, player_node: Tank)

@export var player_spawn_points: Array[Vector2] = []
@export var team_colors: Array[Color] = [
	Color.RED,
	Color.BLUE,
	Color.GREEN,
	Color.YELLOW,
	Color.PURPLE,
	Color.ORANGE,
	Color.CYAN,
	Color.PINK
]

var players: Dictionary = {}  # player_id -> player data
var game_mode: String = "FREE-FOR-ALL"
var is_host: bool = false
var tank_scene = preload("res://Scenes/Actors/tank.tscn")

func _ready():
	# Add to group for easy access
	add_to_group("game_manager")
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Check if we're the host
	is_host = multiplayer.is_server()
	
	if is_host:
		# Start the game for all players
		call_deferred("start_game")

func set_game_mode(mode: String):
	game_mode = mode
	print("Game mode set to: ", game_mode)

func start_game():
	if not is_host:
		return
	
	print("Starting game with mode: ", game_mode)
	
	# Get all connected players
	var connected_players = multiplayer.get_peers()
	connected_players.append(1) # Add host
	
	# Assign teams and colors based on game mode
	_assign_teams_and_colors(connected_players)
	
	# Spawn players
	for player_id in connected_players:
		spawn_player(player_id)
	
	game_started.emit()

func _assign_teams_and_colors(player_ids: Array):
	match game_mode:
		"TEAM DEATHMATCH", "TEAM":
			_assign_team_mode(player_ids)
		"FREE-FOR-ALL":
			_assign_ffa_mode(player_ids)
		_:
			# Default to FFA
			_assign_ffa_mode(player_ids)

func _assign_team_mode(player_ids: Array):
	# Divide players into two teams
	for i in range(player_ids.size()):
		var player_id = player_ids[i]
		var team = "Team A" if i % 2 == 0 else "Team B"
		var color = team_colors[0] if team == "Team A" else team_colors[1]
		
		players[player_id] = {
			"id": player_id,
			"team": team,
			"color": color,
			"spawn_point": i % player_spawn_points.size() if player_spawn_points.size() > 0 else 0,
			"tank_node": null
		}

func _assign_ffa_mode(player_ids: Array):
	# Each player gets their own color
	for i in range(player_ids.size()):
		var player_id = player_ids[i]
		var color = team_colors[i % team_colors.size()]
		
		players[player_id] = {
			"id": player_id,
			"team": "Individual",
			"color": color,
			"spawn_point": i % player_spawn_points.size() if player_spawn_points.size() > 0 else 0,
			"tank_node": null
		}

@rpc("any_peer", "call_local")
func spawn_player(player_id: int):
	if player_id in players:
		var player_data = players[player_id]
		
		# Create tank instance
		var tank = tank_scene.instantiate()
		tank.name = "Player_" + str(player_id)
		
		# Set player authority
		tank.set_multiplayer_authority(player_id)
		
		# Apply team color
		tank.modulate = player_data.color
		
		# Set spawn position
		if player_spawn_points.size() > 0:
			var spawn_index = player_data.spawn_point
			tank.global_position = player_spawn_points[spawn_index]
		
		# Connect tank to paintable map
		var paintable_map = get_tree().get_first_node_in_group("paintable_map")
		if paintable_map:
			tank.paintable_map = paintable_map
		
		# Add tank to scene
		get_tree().current_scene.add_child(tank)
		
		# Store reference
		players[player_id].tank_node = tank
		
		print("Spawned player ", player_id, " with color ", player_data.color)
		player_spawned.emit(player_id, tank)

func _on_player_connected(id: int):
	if is_host:
		print("Player ", id, " connected")
		# We'll handle spawning when the game starts

func _on_player_disconnected(id: int):
	print("Player ", id, " disconnected")
	
	# Remove player data and tank
	if id in players:
		var player_data = players[id]
		if player_data.tank_node and is_instance_valid(player_data.tank_node):
			player_data.tank_node.queue_free()
		players.erase(id)

func get_player_data(player_id: int) -> Dictionary:
	return players.get(player_id, {})

func get_all_players() -> Dictionary:
	return players

func end_game(winner = null):
	print("Game ended. Winner: ", winner)
	game_ended.emit(winner)
	
	# Clean up players
	for player_data in players.values():
		if player_data.tank_node and is_instance_valid(player_data.tank_node):
			player_data.tank_node.queue_free()
	
	players.clear()
	
	# Return to lobby or menu
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("game_over")
