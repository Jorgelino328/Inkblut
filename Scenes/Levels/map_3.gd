extends Node2D

@onready var game_manager: GameManager = $GameManager
@onready var game_hud = $UI/GameHUD
@ontml:parameter name="game_results = $UI/GameResults
@onready var paintable_map = $PaintableWalls

func _ready():
	# Connect GameManager signals to UI
	if game_manager:
		game_manager.game_started.connect(_on_game_started)
		game_manager.game_ended.connect(_on_game_ended)
		game_manager.game_timer_updated.connect(_on_game_timer_updated)
		game_manager.coverage_updated.connect(_on_coverage_updated)
		game_manager.player_died.connect(_on_player_died)
		game_manager.player_respawned.connect(_on_player_respawned)
		
		# Set the paintable tilemap reference
		game_manager.paintable_tilemap = paintable_map
		
		print("Map 3 loaded successfully with integrated UI")

func _on_game_started():
	"""Called when the game starts"""
	if game_hud:
		game_hud.show()
	if game_results:
		game_results.hide()

func _on_game_ended(game_end_data):
	"""Called when the game ends"""
	print("Game ended with data: ", game_end_data)
	
	if game_hud:
		game_hud.hide()
	if game_results:
		var winner = game_end_data.get("winner", {})
		var results = game_end_data.get("results", {})
		var mode = game_end_data.get("mode", "")
		var duration = game_end_data.get("duration", 0.0)
		game_results.show_results(results, winner, mode, duration)

func _on_game_timer_updated(time_left: float):
	"""Update the timer display"""
	if game_hud:
		game_hud.update_timer(time_left)

func _on_coverage_updated(coverage_data: Dictionary):
	"""Update the coverage display"""
	# Coverage updates are now handled directly by HUD via GameManager signals
	# No need to update HUD manually
	pass

func _on_player_died(player_id: int):
	"""Handle player death"""
	print("Player died: ", player_id)
	# HUD can handle this via direct GameManager connection if needed

func _on_player_respawned(player_id: int):
	"""Handle player respawn"""
	print("Player respawned: ", player_id)
	# HUD can handle this via direct GameManager connection if needed

func _on_results_back_to_lobby():
	"""Return to lobby when results screen back button is pressed"""
	get_tree().change_scene_to_file("res://Scenes/UI/main_menu.tscn")
