class_name GameManager extends Node

signal game_started
signal game_ended(winner)
signal player_spawned(player_id: int, player_node: Tank)
signal player_died(player_id: int)
signal player_respawned(player_id: int)
signal game_timer_updated(time_left: float)
signal coverage_updated(coverage_data: Dictionary)
signal game_state_synced(players_data: Dictionary, mode: String)

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

# Manager references
var network_manager: NetworkManager

# Game state variables
var game_active: bool = false
@export var game_duration: float = 180.0  # 3 minutes default - can be adjusted in editor
var time_remaining: float = 0.0
var game_timer: Timer
var coverage_update_timer: Timer
var paintable_tilemap: TileMap

# Respawn system
var dead_players: Dictionary = {}  # player_id -> respawn_timer
var respawn_delay: float = 10.0

# Results tracking
var final_results: Dictionary = {}

func _ready():
	print("=== GAMEMANAGER _READY ===")
	print("GameManager script loaded successfully")
	print("Available methods include: set_game_mode, start_game, spawn_player")
	# Add to group for easy access
	add_to_group("game_manager")
	
	# Get network manager reference
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		network_manager = scene_controller.network_manager
	
	# Collect spawn areas from the current scene
	_collect_spawn_areas()
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Check if we're the host
	is_host = multiplayer.is_server()
	print("GameManager is_host: ", is_host)
	
	# Set up game timer
	_setup_game_timer()
	
	# Set up coverage tracking
	_setup_coverage_tracking()
	
	# Find paintable tilemap
	call_deferred("_find_paintable_tilemap")
	
	# Don't auto-start the game, wait for set_game_mode to be called

func _find_paintable_tilemap():
	"""Find and store reference to the paintable tilemap"""
	paintable_tilemap = get_tree().get_first_node_in_group("paintable_map")
	if paintable_tilemap:
		print("Found paintable tilemap: ", paintable_tilemap.name)
	else:
		print("Warning: Could not find paintable tilemap in group 'paintable_map'")
		# Try again in a bit
		await get_tree().create_timer(0.5).timeout
		paintable_tilemap = get_tree().get_first_node_in_group("paintable_map")
		if paintable_tilemap:
			print("Found paintable tilemap on retry: ", paintable_tilemap.name)
		else:
			print("Error: Still could not find paintable tilemap")

func _collect_spawn_areas():
	"""Collect all Area2D nodes marked as spawn areas from the current scene."""
	spawn_areas.clear()
	
	# Look for SpawnAreas node or any Area2D nodes with "spawn" in their name
	# Use the GameManager's parent (the actual game scene) as the root
	var scene_root = get_parent()
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
	
	# Sync game state to all clients FIRST
	print("=== SYNCING GAME STATE TO ALL CLIENTS ===")
	for client_id in multiplayer.get_peers():
		print("Syncing game state to client: ", client_id)
		_sync_game_state_to_client.rpc_id(client_id, players, game_mode)
	
	# Wait a frame for sync to complete
	await get_tree().process_frame
	
	# Host spawns all players locally (no RPC needed - clients spawn via sync)
	print("=== HOST SPAWNING PLAYERS LOCALLY ===")
	for player_id in connected_players:
		print("Host spawning player locally: ", player_id)
		spawn_player(player_id)
		print("spawn_player called locally for player: ", player_id)
	
	# Start the game timer
	start_game_timer(game_duration)
	
	# Mark game as started in network manager
	if network_manager:
		network_manager.mark_game_started()
	
	game_started.emit()

func _on_game_timer_timeout():
	"""Called when the game timer reaches zero."""
	time_remaining -= 1.0
	print("Time remaining: ", time_remaining)
	
	# Update timer display on all clients
	game_timer_updated.emit(time_remaining)
	
	if time_remaining <= 0:
		print("Game time is up!")
		_end_game()

func _on_coverage_update_timeout():
	"""Called periodically to update coverage data."""
	var coverage_data = _calculate_actual_coverage()
	
	# Emit coverage update signal
	coverage_updated.emit(coverage_data)

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
	print("=== ASSIGNING TEAM MODE ===")
	print("Player IDs to assign: ", player_ids)
	# Assign players to teams 1 and 2
	for i in range(player_ids.size()):
		var player_id = player_ids[i]
		# Use only red and blue colors for teams
		var team_color_index = i % 2  # Alternate between 0 (red) and 1 (blue)
		var color = team_colors[team_color_index]
		var team = 1 if team_color_index == 0 else 2  # Use integers 1 and 2
		
		players[player_id] = {
			"id": player_id,
			"team": team,
			"color": color,
			"tank_node": null,
			"score": 0,
			"is_alive": true,
			"spawn_position": Vector2.ZERO
		}
		print("Assigned player ", player_id, " to team ", team, " with color ", color)

func _assign_ffa_mode(player_ids: Array):
	print("=== ASSIGNING FFA MODE ===")
	print("Player IDs to assign: ", player_ids)
	# Each player gets their own color and is assigned to team 1 (for spawn purposes)
	for i in range(player_ids.size()):
		var player_id = player_ids[i]
		var color = team_colors[i % team_colors.size()]
		
		players[player_id] = {
			"id": player_id,
			"team": 1,  # Use team 1 for all FFA players for spawn logic
			"color": color,
			"tank_node": null,
			"score": 0,
			"is_alive": true,
			"spawn_position": Vector2.ZERO
		}
		print("Assigned player ", player_id, " to team 1 (FFA) with color ", color)
		
func _setup_game_timer():
	"""Set up the main game timer"""
	game_timer = Timer.new()
	game_timer.wait_time = 1.0  # Update every second
	game_timer.timeout.connect(_on_game_timer_tick)
	add_child(game_timer)

func _setup_coverage_tracking():
	"""Set up periodic coverage calculation"""
	coverage_update_timer = Timer.new()
	coverage_update_timer.wait_time = 2.0  # Update coverage every 2 seconds
	coverage_update_timer.timeout.connect(_calculate_and_broadcast_coverage)
	add_child(coverage_update_timer)

func start_game_timer(duration: float = 180.0):
	"""Start the game timer with specified duration"""
	if not is_host:
		return
		
	game_duration = duration
	time_remaining = duration
	game_active = true
	
	game_timer.start()
	coverage_update_timer.start()
	
	print("Game timer started: ", duration, " seconds")
	_sync_timer_start.rpc(duration)

@rpc("authority", "reliable", "call_local") 
func _sync_timer_start(duration: float):
	"""Sync game timer start to all clients"""
	time_remaining = duration
	game_active = true
	game_timer_updated.emit(time_remaining)

func _on_game_timer_tick():
	"""Handle game timer tick"""
	if not is_host or not game_active:
		return
		
	time_remaining -= 1.0
	
	if time_remaining <= 0:
		time_remaining = 0
		_end_game()
	
	# Broadcast timer update
	_sync_timer_update.rpc(time_remaining)
	game_timer_updated.emit(time_remaining)

@rpc("authority", "reliable", "call_local")
func _sync_timer_update(time_left: float):
	"""Sync timer updates to all clients"""
	time_remaining = time_left
	game_timer_updated.emit(time_remaining)

func _calculate_and_broadcast_coverage():
	"""Calculate ink coverage and broadcast to all players"""
	if not is_host or not paintable_tilemap:
		print("Coverage calculation skipped - is_host: ", is_host, ", tilemap: ", paintable_tilemap != null)
		return
		
	var coverage_data = _calculate_ink_coverage()
	print("Coverage calculation result: ", coverage_data)
	_sync_coverage_update.rpc(coverage_data)
	coverage_updated.emit(coverage_data)

@rpc("authority", "reliable", "call_local")
func _sync_coverage_update(coverage_data: Dictionary):
	"""Sync coverage data to all clients"""
	coverage_updated.emit(coverage_data)

func _calculate_ink_coverage() -> Dictionary:
	"""Calculate ink coverage for each team/player using the paintable walls tracking"""
	if not paintable_tilemap:
		print("Coverage calc failed: no tilemap")
		return {}
	
	# Get player colors
	var player_colors: Dictionary = {}
	for player_id in players:
		player_colors[player_id] = players[player_id].color
	
	# Get coverage data from the paintable tilemap
	var coverage_data = paintable_tilemap.get_coverage_data(player_colors)
	
	print("GameManager: Coverage data received: ", coverage_data)
	
	return coverage_data

func _calculate_actual_coverage() -> Dictionary:
	"""Calculate actual coverage from painted tiles and convert to team-based data"""
	var coverage_data = _calculate_ink_coverage()
	
	if coverage_data.is_empty():
		return {}
	
	# Convert to team-based coverage for HUD display
	var team_coverage: Dictionary = {}
	for player_id in players:
		var team = players[player_id].team
		var color = players[player_id].color
		
		if not team_coverage.has(team):
			team_coverage[team] = 0.0
		
		if coverage_data.percentages.has(color):
			team_coverage[team] += coverage_data.percentages[color]
	
	print("GameManager: Team coverage data: ", team_coverage)
	return team_coverage

func handle_player_death(player_id: int):
	"""Handle when a player dies"""
	if player_id in dead_players:
		return  # Already dead
		
	print("Player ", player_id, " died")
	
	# Mark player data as dead (don't delete the tank - tank.die() already handles hiding)
	if player_id in players:
		players[player_id].is_alive = false
		players[player_id].health = 0
		# Tank is already hidden by tank.die() - don't delete it
	
	# Start respawn timer (will be synced to all clients)
	if is_host:
		dead_players[player_id] = respawn_delay
	
	player_died.emit(player_id)
	
	if is_host:
		_sync_player_death.rpc(player_id)

@rpc("authority", "reliable", "call_local")
func _sync_player_death(player_id: int):
	"""Sync player death to all clients"""
	print("_sync_player_death called for player: ", player_id)
	
	# Add to dead players list on all clients
	dead_players[player_id] = respawn_delay
	
	player_died.emit(player_id)

@rpc("authority", "reliable", "call_local")
func _sync_player_respawn(player_id: int):
	"""Sync player respawn to all clients"""
	print("_sync_player_respawn called for player: ", player_id)
	
	# Remove from dead players list on all clients
	if player_id in dead_players:
		dead_players.erase(player_id)
	
	# Find and respawn the tank on all clients
	if player_id in players and players[player_id].tank_node:
		var tank = players[player_id].tank_node
		if is_instance_valid(tank):
			# Move tank to new spawn position
			var spawn_pos = _get_spawn_position(players[player_id].team)
			tank.global_position = spawn_pos
			players[player_id].spawn_position = spawn_pos
			
			# Call tank's respawn method
			tank.respawn()
			players[player_id].is_alive = true
			players[player_id].health = tank.max_hp
			
			print("Tank respawned on client for player: ", player_id)
		else:
			print("Invalid tank reference for player: ", player_id)
	else:
		print("No tank found for player: ", player_id)
	
	player_respawned.emit(player_id)

func _process(delta):
	"""Update respawn timers"""
	# Update respawn timers for dead players (for UI display)
	var players_to_respawn = []
	
	for player_id in dead_players:
		dead_players[player_id] -= delta
		if dead_players[player_id] <= 0:
			if is_host:
				players_to_respawn.append(player_id)
			else:
				# On clients, just clamp to 0 for UI display
				dead_players[player_id] = 0.0
	
	# Only host actually triggers respawns
	if is_host:
		for player_id in players_to_respawn:
			_respawn_player(player_id)

func _respawn_player(player_id: int):
	"""Respawn a dead player"""
	if player_id not in dead_players:
		print("Cannot respawn player ", player_id, " - not in dead_players list")
		return
		
	print("Respawning player ", player_id)
	print("Player data exists: ", player_id in players)
	if player_id in players:
		print("Player data: ", players[player_id])
	
	# Remove from dead players
	dead_players.erase(player_id)
	
	# Try to respawn existing tank first
	var player_data = players[player_id]
	if player_data.tank_node and is_instance_valid(player_data.tank_node):
		# Respawn existing tank
		print("Respawning existing tank for player: ", player_id)
		var tank = player_data.tank_node
		
		# Move tank to new spawn position
		var spawn_pos = _get_spawn_position(player_data.team)
		tank.global_position = spawn_pos
		player_data.spawn_position = spawn_pos
		
		# Call tank's respawn method
		tank.respawn()
		player_data.is_alive = true
		player_data.health = tank.max_hp
		
		print("Existing tank respawned for player ", player_id, " at position ", spawn_pos)
	else:
		# Tank doesn't exist or is invalid, create new one
		print("Creating new tank for respawn: ", player_id)
		spawn_player.rpc(player_id)
	
	player_respawned.emit(player_id)
	_sync_player_respawn.rpc(player_id)

@rpc("any_peer", "reliable")
func spawn_player(player_id: int):
	"""Spawn a tank for the given player"""
	print("=== SPAWN_PLAYER CALLED ===")
	print("Player ID: ", player_id)
	print("My multiplayer ID: ", multiplayer.get_unique_id())
	print("Is host: ", is_host)
	print("Player data exists: ", player_id in players)
	
	# If player data doesn't exist yet, wait for it
	if not players.has(player_id):
		print("Player data not found for ", player_id, ", waiting for sync...")
		var max_wait_time = 3.0  # Wait up to 3 seconds
		var wait_time = 0.0
		while not players.has(player_id) and wait_time < max_wait_time:
			await get_tree().create_timer(0.1).timeout
			wait_time += 0.1
		
		if not players.has(player_id):
			print("Error: Player ", player_id, " data still not found after waiting")
			return
		else:
			print("Player data found for ", player_id, " after waiting")
	
	# Get player data
	var player_data = players[player_id]
	
	# Find a spawn position
	var spawn_pos = _get_spawn_position(player_data.team)
	
	# Load tank scene
	var tank_scene = preload("res://Scenes/Actors/tank.tscn")
	var tank_instance = tank_scene.instantiate()
	
	# Set up the tank
	tank_instance.name = "Tank_" + str(player_id)
	tank_instance.set_multiplayer_authority(player_id)
	tank_instance.global_position = spawn_pos
	tank_instance.player_id = player_id
	
	# Connect tank signals
	tank_instance.health_changed.connect(_on_tank_health_changed.bind(player_id))
	
	# Set paintable map reference
	if paintable_tilemap:
		tank_instance.paintable_map = paintable_tilemap
	
	# Set tank color
	tank_instance.set_tank_color(player_data.color)
	print("Set tank ", player_id, " color to: ", player_data.color)
	
	# Add tank to scene - use the current game scene, not the root scene
	# The GameManager is a child of the actual game scene (map_1, map_2, etc.)
	get_parent().add_child(tank_instance)
	
	# Update player spawn position
	player_data.spawn_position = spawn_pos
	player_data.is_alive = true
	
	# Store tank reference
	player_data.tank_node = tank_instance
	
	print("Tank spawned for player ", player_id, " at position ", spawn_pos)
	player_spawned.emit(player_id, tank_instance)

func _get_spawn_position(team: int) -> Vector2:
	"""Get a spawn position for the given team"""
	# Use available spawn areas if they exist
	if spawn_areas.size() > 0:
		var area = spawn_areas[randi() % spawn_areas.size()]
		return area.global_position
	else:
		# Default spawn positions if no spawn areas defined
		if team == 1:
			return Vector2(100, 300)
		else:
			return Vector2(1000, 300)

func _on_tank_health_changed(player_id: int, health: int, max_health: int):
	"""Handle tank health changes"""
	if players.has(player_id):
		players[player_id].health = health
		
	# Update HUD if this is the local player
	if player_id == multiplayer.get_unique_id():
		# The tank itself should handle HUD updates via signals
		pass

func _end_game():
	"""End the game and determine winner"""
	if not is_host:
		return
		
	print("Game ending...")
	game_active = false
	game_timer.stop()
	coverage_update_timer.stop()
	
	# Calculate final coverage
	final_results = _calculate_ink_coverage()
	
	# Determine winner
	var winner_data = _determine_winner()
	
	print("Game ended. Winner: ", winner_data)
	
	# Mark game as ended in network manager
	if network_manager:
		network_manager.mark_game_ended()
	
	# Broadcast game end
	_sync_game_end.rpc(final_results, winner_data)
	game_ended.emit({
		"winner": winner_data,
		"results": final_results,
		"mode": game_mode,
		"duration": game_duration - time_remaining
	})

@rpc("authority", "reliable", "call_local")
func _sync_game_end(results: Dictionary, winner: Dictionary):
	"""Sync game end to all clients"""
	final_results = results
	game_ended.emit({
		"winner": winner,
		"results": results,
		"mode": game_mode,
		"duration": game_duration - time_remaining
	})

func _determine_winner() -> Dictionary:
	"""Determine the winner based on coverage"""
	if final_results.is_empty():
		return {"type": "tie", "message": "No data available"}
	
	var percentages = final_results.get("percentages", {})
	
	if game_mode == "TEAM DEATHMATCH":
		return _determine_team_winner(percentages)
	else:
		return _determine_ffa_winner(percentages)

func _determine_team_winner(percentages: Dictionary) -> Dictionary:
	"""Determine winner for team mode"""
	var team_totals = {1: 0.0, 2: 0.0}
	
	# Sum coverage for each team
	for player_id in players:
		var player_data = players[player_id]
		var team = player_data.team
		var color = player_data.color
		
		if color in percentages:
			if team in team_totals:
				team_totals[team] += percentages[color]
	
	# Find winning team
	if team_totals[1] > team_totals[2]:
		return {"type": "team", "winner": "Team 1", "coverage": team_totals[1]}
	elif team_totals[2] > team_totals[1]:
		return {"type": "team", "winner": "Team 2", "coverage": team_totals[2]}
	else:
		return {"type": "tie", "message": "Teams tied!"}

func _determine_ffa_winner(percentages: Dictionary) -> Dictionary:
	"""Determine winner for free-for-all mode"""
	var highest_coverage = 0.0
	var winner_player_id = -1
	
	# Find player with highest coverage
	for player_id in players:
		var color = players[player_id].color
		if color in percentages:
			var coverage = percentages[color]
			if coverage > highest_coverage:
				highest_coverage = coverage
				winner_player_id = player_id
	
	if winner_player_id != -1:
		return {
			"type": "player", 
			"winner_id": winner_player_id,
			"coverage": highest_coverage
		}
	else:
		return {"type": "tie", "message": "No clear winner"}

func get_time_remaining() -> float:
	"""Get remaining game time"""
	return time_remaining

func get_coverage_data() -> Dictionary:
	"""Get current coverage data"""
	if is_host and paintable_tilemap:
		return _calculate_ink_coverage()
	else:
		return {}

func force_end_game():
	"""Force end the current game (admin function)"""
	if is_host:
		_end_game()

# Multiplayer connection handlers
func _on_player_connected(peer_id: int):
	"""Called when a player connects to the multiplayer session"""
	print("=== GAMEMANAGER: _on_player_connected CALLED ===")
	print("=== GAMEMANAGER: Player connected: ", peer_id)
	print("Game active: ", game_active)
	print("Is host: ", is_host)
	
	# Add the new player to our tracking
	if not players.has(peer_id):
		var assigned_team = _assign_team(peer_id)
		var assigned_color = _get_team_color(assigned_team)
		if game_mode == "FREE-FOR-ALL":
			# For FFA, assign unique colors
			assigned_color = team_colors[len(players) % team_colors.size()]
		
		players[peer_id] = {
			"id": peer_id,
			"team": assigned_team,
			"color": assigned_color,
			"score": 0,
			"is_alive": true,
			"spawn_position": Vector2.ZERO
		}
		print("Added new player ", peer_id, " with team ", assigned_team, " and color ", assigned_color)
	
	# If game is running, sync game state to the new client and spawn the new player on host
	if game_active:
		print("=== HOST: HANDLING NEW PLAYER CONNECTION ===")
		# First, sync game state to the new client (client will spawn all players including themselves)
		print("Syncing game state to new client: ", peer_id)
		_sync_game_state_to_client.rpc_id(peer_id, players, game_mode)
		
		# Then spawn the new player locally on the host (host doesn't receive the sync)
		print("Host spawning new player locally: ", peer_id)
		spawn_player(peer_id)

func _on_player_disconnected(peer_id: int):
	"""Called when a player disconnects from the multiplayer session"""
	print("Player disconnected: ", peer_id)
	
	# Remove player from tracking
	if players.has(peer_id):
		players.erase(peer_id)
	
	# Remove any spawned tank for this player
	var tank_node = get_node_or_null("Tank_" + str(peer_id))
	if tank_node:
		tank_node.queue_free()

func _assign_team(player_id: int) -> int:
	"""Assign a team to a new player"""
	# Simple alternating team assignment
	var team1_count = 0
	var team2_count = 0
	
	for player_data in players.values():
		if player_data.team == 1:
			team1_count += 1
		elif player_data.team == 2:
			team2_count += 1
	
	# Assign to the team with fewer players
	return 1 if team1_count <= team2_count else 2

func _get_team_color(team_id: int) -> Color:
	"""Get the color for a team"""
	match team_id:
		1:
			return Color.BLUE
		2:
			return Color.ORANGE
		_:
			return Color.WHITE

@rpc("any_peer", "call_local", "reliable")
func _sync_game_state_to_client(players_data: Dictionary, mode: String):
	"""Sync game state to a specific client"""
	if not multiplayer.is_server():
		print("Received game state sync - Players: ", players_data.size(), ", Mode: ", mode)
		print("My multiplayer ID: ", multiplayer.get_unique_id())
		
		# Update local players data
		players = players_data
		game_mode = mode
		
		# Spawn ALL existing players on this client EXCEPT ourselves 
		print("About to spawn players from sync. Players list:")
		for player_id in players.keys():
			print("  - Player ", player_id, " (team: ", players[player_id].team, ", color: ", players[player_id].color, ")")
		
		for player_id in players.keys():
			if player_id != multiplayer.get_unique_id():
				print("Spawning from sync: Player ", player_id)
				spawn_player(player_id)
			else:
				print("Skipping self spawn from sync: Player ", player_id)
		
		# Now spawn ourselves (the new client)
		print("New client spawning self: ", multiplayer.get_unique_id())
		spawn_player(multiplayer.get_unique_id())
		
		# Update UI if needed
		game_state_synced.emit(players_data, mode)

func _exit_tree():
	"""Clean up when the GameManager is being destroyed"""
	print("=== GAMEMANAGER CLEANUP ===")
	cleanup_all_tanks()

func cleanup_all_tanks():
	"""Explicitly clean up all tank references and nodes"""
	print("Cleaning up all tanks from GameManager...")
	var tanks_cleaned = 0
	
	for player_id in players.keys():
		var player_data = players[player_id]
		if player_data.has("tank_node") and is_instance_valid(player_data.tank_node):
			print("Cleaning up tank for player ", player_id, ": ", player_data.tank_node.name)
			player_data.tank_node.queue_free()
			player_data.tank_node = null
			tanks_cleaned += 1
	
	# Clear respawn timers
	for timer in dead_players.values():
		if is_instance_valid(timer):
			timer.queue_free()
	dead_players.clear()
	
	print("Cleaned up ", tanks_cleaned, " tank(s) from GameManager")
	players.clear()

func cleanup_game_state():
	"""Public method to clean up game state when transitioning scenes"""
	print("=== CLEANING GAME STATE ===")
	game_active = false
	
	# Stop timers
	if is_instance_valid(game_timer):
		game_timer.stop()
	if is_instance_valid(coverage_update_timer):
		coverage_update_timer.stop()
	
	# Clean up tanks
	cleanup_all_tanks()
	
	print("Game state cleaned up")
