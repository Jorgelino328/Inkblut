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
	# Add to group for easy access
	add_to_group("game_manager")
	
	# Collect spawn areas from the current scene
	_collect_spawn_areas()
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Check if we're the host
	is_host = multiplayer.is_server()
	
	if is_host:
		# Start the game for all players
		call_deferred("start_game")

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
	game_mode = mode
	print("Game mode set to: ", game_mode)

func start_game():
	if not is_host:
		return
	
	print("Starting game with mode: ", game_mode)
	
	# Get all connected players (including host)
	var connected_players = multiplayer.get_peers()
	connected_players.append(1) # Add host (server ID is always 1)
	
	print("Connected players for game start: ", connected_players)
	
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
	if is_host:
		print("Player ", id, " connected to active game")
		
		# First, sync all existing players to the new client
		for existing_player_id in players.keys():
			if existing_player_id != id and existing_player_id in players:
				var existing_data = players[existing_player_id]
				_sync_existing_player_to_client.rpc_id(id, existing_player_id, existing_data)
		
		# Assign team/color for the new player
		var color_index = players.size() % team_colors.size()
		
		var new_player_data
		match game_mode:
			"TEAM DEATHMATCH", "TEAM":
				var team = "Team A" if players.size() % 2 == 0 else "Team B"
				var team_color = team_colors[0] if team == "Team A" else team_colors[1]
				new_player_data = {
					"id": id,
					"team": team,
					"color": team_color,
					"tank_node": null
				}
			_:
				# Default to FFA
				new_player_data = {
					"id": id,
					"team": "Individual", 
					"color": team_colors[color_index],
					"tank_node": null
				}
		
		# Add to local players dict
		players[id] = new_player_data
		
		# Send the new player's data to the client so they can spawn themselves
		_sync_new_player_to_client.rpc_id(id, id, new_player_data)
		
		# Spawn the new player on the server and notify all OTHER clients
		spawn_player(id)
		print("Mid-game player ", id, " spawned with color ", players[id].color)

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

# RPC to sync new player data to the client so they can spawn themselves
@rpc("call_remote")
func _sync_new_player_to_client(player_id: int, player_data: Dictionary):
	print("Received my player data: ", player_id, " with color ", player_data.color)
	
	# Add to local players dict
	players[player_id] = player_data.duplicate()
	
	# Spawn myself locally
	_spawn_existing_player_locally(player_id, player_data)
	print("Spawned myself (", player_id, ") locally")

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
	# Get world from the current scene (which should be a Node2D)
	var scene_root = get_tree().current_scene
	if not scene_root is CanvasItem:
		print("Warning: Scene root is not a CanvasItem, cannot perform physics queries")
		return true
	
	var space_state = scene_root.get_world_2d().direct_space_state
	
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
	# Get world from the current scene (which should be a Node2D)
	var scene_root = get_tree().current_scene
	if not scene_root is CanvasItem:
		print("Warning: Scene root is not a CanvasItem, cannot perform physics queries")
		return position
	
	var space_state = scene_root.get_world_2d().direct_space_state
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
