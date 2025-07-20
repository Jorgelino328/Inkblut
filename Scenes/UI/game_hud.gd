extends Control

# UI References
@onready var timer_label: Label = $TopContainer/TimerContainer/TimerLabel
@onready var coverage_label: Label = $TopContainer/CoverageContainer/CoverageLabel
@onready var health_label: Label = $BottomContainer/HealthContainer/HealthLabel
@onready var health_bar: ProgressBar = $BottomContainer/HealthContainer/HealthBar
@onready var respawn_container: VBoxContainer = $BottomContainer/RespawnContainer
@onready var respawn_label: Label = $BottomContainer/RespawnContainer/RespawnLabel

var local_player: Tank = null
var game_manager: GameManager = null

func _ready():
	# Hide respawn UI initially
	respawn_container.visible = false
	
	# Find game manager
	game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		# Connect to game manager signals
		game_manager.game_timer_updated.connect(_on_timer_updated)
		game_manager.coverage_updated.connect(_on_coverage_updated)
		game_manager.player_died.connect(_on_player_died)
		game_manager.player_respawned.connect(_on_player_respawned)
	
	# Find local player tank
	_find_local_player()

func _find_local_player():
	"""Find the local player's tank"""
	await get_tree().process_frame  # Wait a frame for tanks to spawn
	
	var tanks = get_tree().get_nodes_in_group("tanks")
	for tank in tanks:
		if tank is Tank and tank.is_multiplayer_authority():
			local_player = tank
			print("Found local player tank: ", tank.name)
			return
	
	# If not found, try again later
	if local_player == null:
		await get_tree().create_timer(0.5).timeout
		_find_local_player()

func _process(_delta):
	# Update health display if we have a local player
	if local_player and is_instance_valid(local_player):
		_update_health_display()
	
	# Update respawn timer if player is dead
	if local_player and local_player.is_dead:
		_update_respawn_display()

func _update_health_display():
	"""Update health bar and label"""
	var current_hp = local_player.current_hp
	var max_hp = local_player.max_hp
	
	health_label.text = "HP: %d/%d" % [current_hp, max_hp]
	health_bar.value = current_hp
	health_bar.max_value = max_hp
	
	# Color health bar based on health level
	var health_percentage = float(current_hp) / float(max_hp)
	if health_percentage > 0.6:
		health_bar.modulate = Color.GREEN
	elif health_percentage > 0.3:
		health_bar.modulate = Color.YELLOW
	else:
		health_bar.modulate = Color.RED

func _update_respawn_display():
	"""Update respawn countdown display"""
	if not game_manager:
		return
		
	var player_id = local_player.player_id
	if player_id in game_manager.dead_players:
		var respawn_time = game_manager.dead_players[player_id]
		respawn_label.text = "RESPAWNING IN %ds" % int(ceil(respawn_time))

func _on_timer_updated(time_left: float):
	"""Update the game timer display"""
	var minutes = int(time_left) / 60
	var seconds = int(time_left) % 60
	timer_label.text = "%d:%02d" % [minutes, seconds]
	
	# Color timer based on remaining time
	if time_left > 60:
		timer_label.modulate = Color.WHITE
	elif time_left > 30:
		timer_label.modulate = Color.YELLOW
	else:
		timer_label.modulate = Color.RED

func _on_coverage_updated(coverage_data: Dictionary):
	"""Update coverage display for local player"""
	if not local_player or not coverage_data.has("percentages"):
		return
	
	var player_color = local_player.modulate
	var player_coverage = 0.0
	
	# Find coverage for our color
	for color in coverage_data.percentages:
		if color.is_equal_approx(player_color):
			player_coverage = coverage_data.percentages[color]
			break
	
	coverage_label.text = "Coverage: %.1f%%" % player_coverage
	
	# Color based on performance
	if player_coverage > 40:
		coverage_label.modulate = Color.GREEN
	elif player_coverage > 20:
		coverage_label.modulate = Color.YELLOW
	else:
		coverage_label.modulate = Color.RED

func _on_player_died(player_id: int):
	"""Handle player death"""
	if local_player and local_player.player_id == player_id:
		# Show respawn UI
		respawn_container.visible = true

func _on_player_respawned(player_id: int):
	"""Handle player respawn"""
	if local_player and local_player.player_id == player_id:
		# Hide respawn UI
		respawn_container.visible = false
		
		# Find the new tank instance
		_find_local_player()

func show_hud():
	"""Show the HUD"""
	visible = true

func hide_hud():
	"""Hide the HUD"""
	visible = false

# Public methods for external components to call
func update_timer(time_left: float):
	"""Update the match timer display"""
	var minutes = int(time_left) / 60
	var seconds = int(time_left) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]

func update_coverage(coverage_data: Dictionary):
	"""Update area coverage display"""
	if coverage_data.has("local_player"):
		var local_coverage = coverage_data["local_player"]
		coverage_label.text = "Coverage: %.1f%%" % (local_coverage * 100.0)
	else:
		coverage_label.text = "Coverage: 0.0%"

func update_health(health: int, max_health: int):
	"""Update health display"""
	health_label.text = "HP: %d/%d" % [health, max_health]
	health_bar.value = (float(health) / float(max_health)) * 100.0

func show_respawn_timer(respawn_time: float):
	"""Show respawn countdown"""
	respawn_container.visible = true

func hide_respawn_timer():
	"""Hide respawn countdown"""
	respawn_container.visible = false
