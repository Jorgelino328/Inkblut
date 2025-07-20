class_name GameManager extends Node

signal game_started
signal game_ended(winner)
signal player_spawned(player_id: int, player_node: Tank)

var spawn_areas: Array[Area2D] = []
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
	print("=== GAMEMANAGER _READY ===")
	print("GameManager script loaded successfully")
	print("Available methods include: set_game_mode, start_game, spawn_player")
	# Add to group for easy access
	add_to_group("game_manager")
	
	# Collect spawn areas from the current scene
	_collect_spawn_areas()
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Check if we're the host
	is_host = multiplayer.is_server()
	print("GameManager is_host: ", is_host)
	
	# Don't auto-start the game, wait for set_game_mode to be called

func _collect_spawn_areas():
	"""Collect all Area2D nodes marked as spawn areas from the current scene."""
	spawn_areas.clear()
	
	# Look for SpawnAreas node or any Area2D nodes with "spawn" in their name
	var scene_root = get_tree().current_scene
	var spawn_areas_node = scene_root.find_child("SpawnAreas", true, false)
	
	if spawn_areas_node:
		# Get all Area2D children from SpawnAreas node
		for child in spawn_areas_node.get_children():
			if child is Area2D:
				spawn_areas.append(child)
				print("Found spawn area: ", child.name)
	else:
		# Fallback: Look for any Area2D nodes with "spawn" in their name
		_find_spawn_areas_recursive(scene_root)
	
	print("Total spawn areas found: ", spawn_areas.size())
	
	# If no spawn areas found, create default fallback positions
	if spawn_areas.is_empty():
		print("Warning: No spawn areas found, using fallback positions")

func _find_spawn_areas_recursive(node: Node):
	"""Recursively find spawn areas in the scene."""
	if node is Area2D and "spawn" in node.name.to_lower():
		spawn_areas.append(node)
		print("Found spawn area: ", node.name)
	
	for child in node.get_children():
		_find_spawn_areas_recursive(child)

func set_game_mode(mode: String):
	print("=== GAMEMANAGER SET_GAME_MODE CALLED ===")
	print("Setting game mode to: ", mode)
	game_mode = mode
	print("Game mode set to: ", game_mode)
	
	# If we're the host and the game mode is set, start the game
	if is_host:
		print("Host detected, starting game with mode: ", game_mode)
		call_deferred("start_game")

func start_game():
	print("=== GAMEMANAGER START_GAME CALLED ===")
	print("Is host: ", is_host)
	print("Game mode: ", game_mode)
	if not is_host:
		print("Not host, skipping game start")
		return
	
	print("Starting game with mode: ", game_mode)
	
	# Get all connected players (including host)
	var connected_players = multiplayer.get_peers()
	connected_players.append(1) # Add host (server ID is always 1)
	
	print("Connected players for game start: ", connected_players)
	
	# Assign teams and colors based on game mode
	_assign_teams_and_colors(connected_players)
	
	# Spawn players
	print("=== SPAWNING PLAYERS ===")
	for player_id in connected_players:
		print("Spawning player: ", player_id)
		spawn_player(player_id)
		print("spawn_player called for player: ", player_id)
	
	# Sync game state to all clients
	print("=== SYNCING GAME STATE TO ALL CLIENTS ===")
	for client_id in multiplayer.get_peers():
		print("Syncing game state to client: ", client_id)
		_sync_game_state_to_client.rpc_id(client_id, players, game_mode)
	
	game_started.emit()

func _assign_teams_and_colors(player_ids: Array):
	print("=== _ASSIGN_TEAMS_AND_COLORS ===")
	print("Game mode: '", game_mode, "'")
	print("Player IDs: ", player_ids)
	match game_mode:
		"TEAM DEATHMATCH", "TEAM":
			print("Calling _assign_team_mode")
			_assign_team_mode(player_ids)
		"FREE-FOR-ALL":
			print("Calling _assign_ffa_mode")
			_assign_ffa_mode(player_ids)
		_:
			# Default to FFA
			print("Defaulting to FFA mode")
			_assign_ffa_mode(player_ids)

func _assign_team_mode(player_ids: Array):
	print("=== ASSIGNING TEAM MODE (COPY OF FFA) ===")
	print("Player IDs to assign: ", player_ids)
	# Copy FFA logic exactly but with team colors
	for i in range(player_ids.size()):
		var player_id = player_ids[i]
		# Use only red and blue colors for teams
		var team_color_index = i % 2  # Alternate between 0 (red) and 1 (blue)
		var color = team_colors[team_color_index]
		var team = "Team A" if team_color_index == 0 else "Team B"
		
		players[player_id] = {
			"id": player_id,
			"team": team,
			"color": color,
			"tank_node": null
		}
		print("Assigned player ", player_id, " to ", team, " with color ", color)

func _assign_ffa_mode(player_ids: Array):
	print("=== ASSIGNING FFA MODE ===")
	print("Player IDs to assign: ", player_ids)
	# Each player gets their own color
	for i in range(player_ids.size()):
		var player_id = player_ids[i]
		var color = team_colors[i % team_colors.size()]
		
		players[player_id] = {
			"id": player_id,
			"team": "Individual",
			"color": color,
			"tank_node": null
		}
		print("Assigned player ", player_id, " to Individual team with color ", color)
		
@rpc("any_peer", "reliable", "call_local")
func spawn_player(player_id: int):
	print("=== SPAWN_PLAYER CALLED ===")
	print("Player ID: ", player_id)
	print("Is Host: ", is_host)
	print("Current Multiplayer ID: ", multiplayer.get_unique_id())
	print("Players dict has player: ", player_id in players)
	
	if player_id in players:
		var player_data = players[player_id]
		
		# Create tank instance
		var tank = tank_scene.instantiate()
		tank.name = "Player_" + str(player_id)
		
		# Set player authority
		tank.set_multiplayer_authority(player_id)
		
		# Apply team color
		tank.modulate = player_data.color
		
		# Find a safe spawn position
		var spawn_position = _find_safe_spawn_position()
		tank.global_position = spawn_position
		
		# Connect tank to paintable map
		var paintable_map = get_tree().get_first_node_in_group("paintable_map")
		if paintable_map:
			tank.paintable_map = paintable_map
		
		# Add tank to scene - use the game scene (parent of this GameManager)
		var game_scene = get_parent()
		if game_scene:
			game_scene.add_child(tank)
			print("Added tank to game scene: ", game_scene.name)
			print("Game scene children count: ", game_scene.get_child_count())
		else:
			# Fallback to current scene if no parent
			get_tree().current_scene.add_child(tank)
			print("Added tank to current scene (fallback): ", get_tree().current_scene.name)
		
		# Store reference
		players[player_id].tank_node = tank
		
		print("Spawned player ", player_id, " with color ", player_data.color, " at position ", spawn_position)
		player_spawned.emit(player_id, tank)

# RPC to sync existing players to a new client
@rpc("call_remote")
func _sync_existing_player_to_client(existing_player_id: int, player_data: Dictionary):
	print("Syncing existing player ", existing_player_id, " to this client")
	
	# Add the existing player to our local players dict
	players[existing_player_id] = player_data.duplicate()
	
	# Spawn the existing player locally
	_spawn_existing_player_locally(existing_player_id, player_data)

func _spawn_existing_player_locally(player_id: int, player_data: Dictionary):
	print("Spawning existing player ", player_id, " locally")
	
	# Create tank instance
	var tank = tank_scene.instantiate()
	tank.name = "Player_" + str(player_id)
	
	# Set player authority
	tank.set_multiplayer_authority(player_id)
	
	# Apply team color
	tank.modulate = player_data.color
	
	# Find a safe spawn position
	var spawn_position = _find_safe_spawn_position()
	tank.global_position = spawn_position
	
	# Connect tank to paintable map
	var paintable_map = get_tree().get_first_node_in_group("paintable_map")
	if paintable_map:
		tank.paintable_map = paintable_map
	
	# Add tank to scene - use the game scene (parent of this GameManager)
	var game_scene = get_parent()
	if game_scene:
		game_scene.add_child(tank)
		print("Added existing player tank to game scene: ", game_scene.name)
		print("Game scene children count: ", game_scene.get_child_count())
	else:
		# Fallback to current scene if no parent
		get_tree().current_scene.add_child(tank)
		print("Added existing player tank to current scene (fallback): ", get_tree().current_scene.name)
	
	# Store reference
	players[player_id].tank_node = tank
	
	print("Locally spawned existing player ", player_id, " with color ", player_data.color, " at position ", spawn_position)

func _on_player_connected(id: int):
	print("=== GameManager: Player connected: ", id)
	if is_host:
		# If game is already active, add the new player and spawn them
		if is_game_active():
			print("Game in progress, adding new player to game: ", id)
			
			# Add new player to players dictionary with proper team assignment
			_assign_new_player_to_game(id)
			
			# Sync current state to new client (including existing players)
			_sync_game_state_to_client.rpc_id(id, players, game_mode)
			
			# Spawn the new player on the host
			print("Spawning new player on host: ", id)
			spawn_player(id)
			
			# Tell all existing clients to spawn the new player too
			print("Telling clients to spawn new player: ", id)
			for peer_id in multiplayer.get_peers():
				if peer_id != id:  # Don't tell the new client to spawn themselves again
					_spawn_new_player_for_client.rpc_id(peer_id, id, players[id])
		else:
			print("Game not active yet, player will be added when game starts")

func _on_player_disconnected(id: int):
	print("=== GameManager: Player disconnected: ", id)
	# Remove player from game if they existed
	if id in players:
		var player_data = players[id]
		if player_data.tank_node:
			player_data.tank_node.queue_free()
		players.erase(id)
		print("Removed player ", id, " from game")

# RPC to sync entire game state to new client
@rpc("call_remote", "reliable")
func _sync_game_state_to_client(player_data: Dictionary, mode: String):
	print("=== SYNCING GAME STATE FROM SERVER ===")
	print("Received players data: ", player_data)
	print("Game mode: ", mode)
	
	# Set our game mode
	game_mode = mode
	
	# Clear existing players
	players.clear()
	
	# Add all players from server and spawn them all
	for player_id in player_data:
		players[player_id] = player_data[player_id].duplicate()
		# Don't include tank_node reference as it's not serializable
		players[player_id].tank_node = null
		
		# Spawn ALL players locally (including self)
		print("Spawning player locally: ", player_id)
		call_deferred("spawn_player", player_id)
	
	print("Game state synchronized")


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

# RPC to sync new player data to the client so they can spawn themselves
@rpc("call_remote")
func _sync_new_player_to_client(player_id: int, player_data: Dictionary):
	print("Received my player data: ", player_id, " with color ", player_data.color)
	
	# Add to local players dict
	players[player_id] = player_data.duplicate()
	
	# Spawn myself locally
	_spawn_existing_player_locally(player_id, player_data)
	print("Spawned myself (", player_id, ") locally")

func can_start_game() -> bool:
	"""Check if the game can start based on current players and game mode"""
	var connected_players = [multiplayer.get_unique_id()]
	connected_players.append_array(multiplayer.get_peers())
	
	match game_mode:
		"TEAM", "TEAM DEATHMATCH":
			# For team modes, we need at least 2 players and equal teams
			if connected_players.size() < 2:
				print("Cannot start team game: Need at least 2 players")
				return false
			
			# Team games should have an even number of players for balanced teams
			if connected_players.size() % 2 != 0:
				print("Cannot start team game: Need even number of players for balanced teams")
				return false
			
			return true
		
		"FREE-FOR-ALL":
			# FFA can start with any number of players (minimum 1)
			return connected_players.size() >= 1
		
		_:
			return true

func get_team_balance_info() -> Dictionary:
	"""Get information about current team balance"""
	var connected_players = [multiplayer.get_unique_id()]
	connected_players.append_array(multiplayer.get_peers())
	var total_players = connected_players.size()
	
	match game_mode:
		"TEAM", "TEAM DEATHMATCH":
			var team_a_count = (total_players + 1) / 2  # Ceiling division
			var team_b_count = total_players / 2        # Floor division
			
			return {
				"total_players": total_players,
				"team_a_count": team_a_count,
				"team_b_count": team_b_count,
				"is_balanced": total_players % 2 == 0,
				"needs_more_players": total_players < 2
			}
		
		"FREE-FOR-ALL":
			return {
				"total_players": total_players,
				"can_start": total_players >= 1
			}
		
		_:
			return {"total_players": total_players}

func _find_safe_spawn_position() -> Vector2:
	"""Find a safe spawn position from available spawn areas."""
	if spawn_areas.is_empty():
		print("Warning: No spawn areas available, using fallback position")
		return Vector2(500, 400)  # Fallback position
	
	var max_attempts = 50
	var attempts = 0
	
	while attempts < max_attempts:
		# Pick a random spawn area
		var spawn_area = spawn_areas[randi() % spawn_areas.size()]
		
		# Get a random position within this area
		var spawn_position = _get_random_position_in_area(spawn_area)
		
		# Check if this position is safe (no walls, no other players)
		if _is_spawn_position_safe(spawn_position):
			return spawn_position
		
		attempts += 1
	
	# If we couldn't find a safe position, try to push out of walls
	print("Could not find safe spawn position after ", max_attempts, " attempts, trying to push out of walls")
	var fallback_area = spawn_areas[0]
	var fallback_position = _get_random_position_in_area(fallback_area)
	return _push_out_of_walls(fallback_position)

func _get_random_position_in_area(area: Area2D) -> Vector2:
	"""Get a random position within an Area2D."""
	# Get the collision shape
	var collision_shape = null
	for child in area.get_children():
		if child is CollisionShape2D:
			collision_shape = child
			break
	
	if not collision_shape:
		print("Warning: Spawn area ", area.name, " has no CollisionShape2D")
		return area.global_position
	
	var shape = collision_shape.shape
	if shape is RectangleShape2D:
		# Get rectangle bounds
		var rect_shape = shape as RectangleShape2D
		var size = rect_shape.size
		var half_size = size * 0.5
		
		# Generate random position within rectangle
		var local_pos = Vector2(
			randf_range(-half_size.x, half_size.x),
			randf_range(-half_size.y, half_size.y)
		)
		
		# Transform to world position
		return area.global_position + collision_shape.position + local_pos
	elif shape is CircleShape2D:
		# Get circle bounds
		var circle_shape = shape as CircleShape2D
		var radius = circle_shape.radius
		
		# Generate random position within circle
		var angle = randf() * 2 * PI
		var distance = randf() * radius
		var local_pos = Vector2(cos(angle), sin(angle)) * distance
		
		# Transform to world position
		return area.global_position + collision_shape.position + local_pos
	else:
		print("Warning: Unsupported collision shape type for spawn area ", area.name)
		return area.global_position

func _is_spawn_position_safe(position: Vector2) -> bool:
	"""Check if a spawn position is safe (no walls, no other players)."""
	# Get world from the map scene (parent of GameManager)
	var map_scene = get_parent()
	if not map_scene is CanvasItem:
		print("Warning: Map scene is not a CanvasItem, cannot perform physics queries")
		return true
	
	var space_state = map_scene.get_world_2d().direct_space_state
	
	# Check for walls using physics raycast in multiple directions
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
					  Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
					  Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]
	
	var tank_radius = 32.0  # Approximate tank size
	
	for direction in directions:
		var query = PhysicsRayQueryParameters2D.create(position, position + direction * tank_radius)
		query.collision_mask = 1  # Assuming walls are on collision layer 1
		var result = space_state.intersect_ray(query)
		if result:
			return false  # Found a wall nearby
	
	# Check for overlapping with existing players
	for player_data in players.values():
		if player_data.tank_node and is_instance_valid(player_data.tank_node):
			var other_pos = player_data.tank_node.global_position
			var distance = position.distance_to(other_pos)
			if distance < tank_radius * 2:
				return false  # Too close to another player
	
	return true

func _push_out_of_walls(position: Vector2) -> Vector2:
	"""Try to push a position out of walls if it's inside them."""
	# Get world from the map scene (parent of GameManager)
	var map_scene = get_parent()
	if not map_scene is CanvasItem:
		print("Warning: Map scene is not a CanvasItem, cannot perform physics queries")
		return position
	
	var space_state = map_scene.get_world_2d().direct_space_state
	var tank_radius = 32.0
	var max_push_attempts = 10
	var push_distance = 16.0
	
	var current_pos = position
	
	for attempt in range(max_push_attempts):
		var is_in_wall = false
		var push_direction = Vector2.ZERO
		
		# Check all directions for walls
		var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
						  Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
						  Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]
		
		for direction in directions:
			var query = PhysicsRayQueryParameters2D.create(current_pos, current_pos + direction * tank_radius)
			query.collision_mask = 1
			var result = space_state.intersect_ray(query)
			if result:
				is_in_wall = true
				# Push away from the wall
				push_direction -= direction
		
		if not is_in_wall:
			break
		
		# Normalize and apply push
		if push_direction.length() > 0:
			push_direction = push_direction.normalized()
			current_pos += push_direction * push_distance
		else:
			# Random push if we can't determine direction
			var random_angle = randf() * 2 * PI
			current_pos += Vector2(cos(random_angle), sin(random_angle)) * push_distance
	
	return current_pos

func is_game_active() -> bool:
	"""Check if the game is currently active (players have been spawned)"""
	return players.size() > 0 and players.values().any(func(p): return p.tank_node != null)

# RPC to tell existing clients to spawn a new player
@rpc("call_remote", "reliable")
func _spawn_new_player_for_client(player_id: int, player_data: Dictionary):
	print("=== SPAWNING NEW PLAYER FOR CLIENT ===")
	print("Player ID: ", player_id)
	print("Player data: ", player_data)
	
	# Add new player to local players dict
	players[player_id] = player_data.duplicate()
	players[player_id].tank_node = null
	
	# Spawn the new player locally
	spawn_player(player_id)

func _assign_new_player_to_game(player_id: int):
	"""Assign a new player to the appropriate team based on current game mode"""
	print("Assigning new player ", player_id, " to game mode: ", game_mode)
	
	match game_mode:
		"TEAM DEATHMATCH", "TEAM":
			# For team modes, assign alternating teams
			var team_color_index = players.size() % 2
			var assigned_team = "Team A" if team_color_index == 0 else "Team B"
			var assigned_color = team_colors[team_color_index]
			
			players[player_id] = {
				"id": player_id,
				"team": assigned_team,
				"color": assigned_color,
				"tank_node": null
			}
			
			print("Assigned new player ", player_id, " to ", assigned_team, " with color ", assigned_color)
			
		_:
			# For FFA and default, assign individual team with unique color
			var color = team_colors[players.size() % team_colors.size()]
			players[player_id] = {
				"id": player_id,
				"team": "Individual",
				"color": color,
				"tank_node": null
			}
			
			print("Assigned new player ", player_id, " to Individual with color ", color)
