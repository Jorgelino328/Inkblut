extends Control

# UI References
@onready var winner_label: Label = $MainContainer/TitleContainer/WinnerLabel
@onready var score_list: VBoxContainer = $MainContainer/ResultsContainer/ScoreboardPanel/ScoreboardContainer/ScoreList
@onready var total_coverage_label: Label = $MainContainer/ResultsContainer/StatsPanel/StatsContainer/TotalCoverageLabel
@onready var match_duration_label: Label = $MainContainer/ResultsContainer/StatsPanel/StatsContainer/MatchDurationLabel
@onready var player_count_label: Label = $MainContainer/ResultsContainer/StatsPanel/StatsContainer/PlayerCountLabel
@onready var game_mode_label: Label = $MainContainer/ResultsContainer/StatsPanel/StatsContainer/GameModeLabel

@onready var rematch_button: Button = $MainContainer/ButtonContainer/RematchButton
@onready var lobby_button: Button = $MainContainer/ButtonContainer/LobbyButton
@onready var quit_button: Button = $MainContainer/ButtonContainer/QuitButton

var final_results: Dictionary = {}
var winner_data: Dictionary = {}
var game_mode: String = ""
var match_duration: float = 0.0

func _ready():
	# Connect button signals
	rematch_button.pressed.connect(_on_rematch_pressed)
	lobby_button.pressed.connect(_on_lobby_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func show_results(results: Dictionary, winner: Dictionary, mode: String, duration: float):
	"""Display the match results"""
	final_results = results
	winner_data = winner
	game_mode = mode
	match_duration = duration
	
	_update_winner_display()
	_update_scoreboard()
	_update_statistics()
	
	# Show the results screen
	show()

func _update_winner_display():
	"""Update the winner announcement"""
	match winner_data.get("type", ""):
		"player":
			var winner_id = winner_data.get("winner_id", -1)
			var coverage = winner_data.get("coverage", 0.0)
			winner_label.text = "WINNER: Player %d (%.1f%% coverage)" % [winner_id, coverage]
			winner_label.modulate = Color.GOLD
		"team":
			var winning_team = winner_data.get("winner", "")
			var coverage = winner_data.get("coverage", 0.0)
			winner_label.text = "WINNER: %s (%.1f%% coverage)" % [winning_team, coverage]
			winner_label.modulate = Color.GOLD if winning_team == "Team A" else Color.CYAN
		"tie":
			winner_label.text = "DRAW - " + winner_data.get("message", "No clear winner")
			winner_label.modulate = Color.WHITE
		_:
			winner_label.text = "MATCH COMPLETED"
			winner_label.modulate = Color.WHITE

func _update_scoreboard():
	"""Update the player scoreboard"""
	# Clear existing score entries
	for child in score_list.get_children():
		child.queue_free()
	
	if not final_results.has("percentages"):
		return
		
	var percentages = final_results.percentages
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	
	if not game_manager:
		return
	
	# Create score entries for each player
	var player_scores = []
	
	for player_id in game_manager.players:
		var player_data = game_manager.players[player_id]
		var color = player_data.color
		var coverage = percentages.get(color, 0.0)
		
		player_scores.append({
			"player_id": player_id,
			"team": player_data.team,
			"color": color,
			"coverage": coverage
		})
	
	# Sort players by coverage (highest first)
	player_scores.sort_custom(func(a, b): return a.coverage > b.coverage)
	
	# Create UI elements for each player
	for i in range(player_scores.size()):
		var player_info = player_scores[i]
		var rank = i + 1
		
		var score_entry = _create_score_entry(rank, player_info)
		score_list.add_child(score_entry)

func _create_score_entry(rank: int, player_info: Dictionary) -> Control:
	"""Create a score entry for a player"""
	var container = HBoxContainer.new()
	
	# Rank
	var rank_label = Label.new()
	rank_label.text = str(rank) + "."
	rank_label.custom_minimum_size.x = 30
	container.add_child(rank_label)
	
	# Player color indicator
	var color_rect = ColorRect.new()
	color_rect.color = player_info.color
	color_rect.custom_minimum_size = Vector2(20, 20)
	container.add_child(color_rect)
	
	# Player name
	var player_label = Label.new()
	player_label.text = "Player " + str(player_info.player_id)
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(player_label)
	
	# Team (if applicable)
	if game_mode == "TEAM DEATHMATCH" or game_mode == "TEAM":
		var team_label = Label.new()
		team_label.text = "(Team " + str(player_info.team) + ")"
		team_label.custom_minimum_size.x = 100
		container.add_child(team_label)
	
	# Coverage percentage
	var coverage_label = Label.new()
	coverage_label.text = "%.1f%%" % player_info.coverage
	coverage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	coverage_label.custom_minimum_size.x = 60
	container.add_child(coverage_label)
	
	# Highlight winner
	if rank == 1 and player_info.coverage > 0:
		rank_label.modulate = Color.GOLD
		player_label.modulate = Color.GOLD
		coverage_label.modulate = Color.GOLD
	
	return container

func _update_statistics():
	"""Update match statistics"""
	# Total coverage
	var total_covered = 0.0
	if final_results.has("percentages"):
		for coverage in final_results.percentages.values():
			total_covered += coverage
	
	total_coverage_label.text = "Total Area Covered: %.1f%%" % total_covered
	
	# Match duration
	var minutes = int(match_duration) / 60
	var seconds = int(match_duration) % 60
	match_duration_label.text = "Match Duration: %d:%02d" % [minutes, seconds]
	
	# Player count
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		player_count_label.text = "Players: " + str(game_manager.players.size())
	
	# Game mode
	game_mode_label.text = "Game Mode: " + game_mode

func _on_rematch_pressed():
	"""Start a new match with the same settings"""
	print("Rematch requested")
	
	# Hide results screen
	hide()
	
	# Reset game state and start new match
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.is_host:
		# Clear previous game state
		game_manager.game_active = false
		game_manager.time_remaining = 0.0
		game_manager.dead_players.clear()
		game_manager.final_results.clear()
		
		# Start new game
		game_manager.start_game()
	
	# TODO: For non-host players, send rematch request to host

func _on_lobby_pressed():
	"""Return to the match lobby"""
	print("Returning to lobby")
	
	# Transition to lobby scene
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("lobby")

func _on_quit_pressed():
	"""Quit to main menu"""
	print("Quitting to main menu")
	
	# Disconnect from multiplayer
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	
	# Go to main menu
	var scene_controller = get_tree().get_first_node_in_group("scene_controller")
	if scene_controller:
		scene_controller.change_scene("main_menu")
