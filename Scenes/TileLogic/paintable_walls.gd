extends TileMap

@export var team1_color:= Color.BLUE
@export var team2_color:= Color.ORANGE
@export var unpainted_color:= Color.WHITE

@export_group("Splat Noise")
@export var noise_enabled:= true
@export var noise_strength:= 2.0
@export var noise_frequency:= 0.1

var _update_fn: Dictionary = {}
var _noise: FastNoiseLite
var _painted_tiles: Dictionary = {}  # Track painted tile colors for coverage calculation

func _ready():
	# Add to group for discovery
	add_to_group("paintable_map")
	
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = noise_frequency

func on_paint_splat(hit_pos, paint_color: Color, splat_radius):
	print("Paint splat received at: ", hit_pos, " with color: ", paint_color, " radius: ", splat_radius)
	var hit_local_pos = to_local(hit_pos)
	var hit_coords = local_to_map(hit_local_pos)
	
	var max_offset
	if noise_enabled:
		max_offset = splat_radius + int(ceil(noise_strength))
	else:
		max_offset = splat_radius
	
	max_offset = max(0, max_offset)
	var updates_queued = false
	
	for y_offset in range(-max_offset, max_offset + 1):
		for x_offset in range(-max_offset, max_offset + 1):
			var current_offset_vec = Vector2(x_offset, y_offset)
			var distance_from_center = current_offset_vec.length()
			
			var final_splat_radius = float(splat_radius)
			if noise_enabled:
				var cell_world_x = float(hit_coords.x + x_offset)
				var cell_world_y = float(hit_coords.y + y_offset)
				var noise_value = _noise.get_noise_2d(cell_world_x, cell_world_y)
				final_splat_radius += noise_value * noise_strength
			
			final_splat_radius = max(0.0, final_splat_radius)
			
			if distance_from_center <= final_splat_radius:
				var cell_coords = hit_coords + Vector2i(x_offset, y_offset)
				var tile_data = get_cell_tile_data(0, cell_coords)
				
				if tile_data != null and tile_data.get_custom_data("is_paintable"):
					var current_tile_color = tile_data.modulate
					
					# Only paint if the color is different
					if current_tile_color != paint_color:
						update_tile(0, cell_coords, func(td):
							td.modulate = paint_color
						)
						# Track the painted color for coverage calculation
						_painted_tiles[cell_coords] = paint_color
						updates_queued = true
	
	if updates_queued:
		notify_runtime_tile_data_update(0)

func update_tile(layer: int, coords: Vector2i, fn: Callable):
	if not _update_fn.has(layer): _update_fn[layer] = {}
	_update_fn[layer][coords] = fn
	notify_runtime_tile_data_update(layer)

func _use_tile_data_runtime_update(layer: int, coords: Vector2i):
	if not _update_fn.has(layer): return false
	if not _update_fn[layer].has(coords): return false
	return true

func _tile_data_runtime_update(layer: int, coords: Vector2i, tile_data: TileData):
	if not _update_fn.has(layer): return false
	if not _update_fn[layer].has(coords): return false
	var fn: Callable = _update_fn[layer][coords]
	fn.call(tile_data)
	_update_fn[layer].erase(coords)

func set_noise_frequency(value: float):
	noise_frequency = value
	if _noise:
		_noise.frequency = noise_frequency

func get_coverage_data(player_colors: Dictionary) -> Dictionary:
	"""Calculate coverage data for each player color"""
	var coverage_count: Dictionary = {}
	var total_paintable_tiles = 0
	
	# Initialize counters for each player
	for player_id in player_colors:
		var color = player_colors[player_id]
		coverage_count[color] = 0
	
	print("PaintableWalls: Calculating coverage for ", player_colors.size(), " players")
	print("PaintableWalls: Painted tiles count: ", _painted_tiles.size())
	
	# Count total paintable tiles
	var used_rect = get_used_rect()
	for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
		for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
			var coords = Vector2i(x, y)
			var tile_data = get_cell_tile_data(0, coords)
			
			if tile_data and tile_data.get_custom_data("is_paintable"):
				total_paintable_tiles += 1
				
				# Check if this tile is painted
				if _painted_tiles.has(coords):
					var tile_color = _painted_tiles[coords]
					# Find matching player color
					for player_id in player_colors:
						var player_color = player_colors[player_id]
						if tile_color.is_equal_approx(player_color):
							coverage_count[player_color] += 1
							break
	
	print("PaintableWalls: Total paintable tiles: ", total_paintable_tiles)
	print("PaintableWalls: Coverage counts: ", coverage_count)
	
	# Calculate percentages
	var coverage_percentages: Dictionary = {}
	for color in coverage_count:
		if total_paintable_tiles > 0:
			coverage_percentages[color] = (coverage_count[color] * 100.0) / total_paintable_tiles
		else:
			coverage_percentages[color] = 0.0
	
	return {
		"counts": coverage_count,
		"percentages": coverage_percentages,
		"total_paintable": total_paintable_tiles
	}
