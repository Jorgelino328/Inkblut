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

func _ready():
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = noise_frequency

func on_paint_splat(hit_pos, team_id, splat_radius):
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
					var current_tile_team_id = tile_data.get_custom_data("painted_team")

					if current_tile_team_id == null: 
						current_tile_team_id = -1 

					if current_tile_team_id != team_id:
						var new_color_to_set
						var team_id_to_set_on_tile 
						
						match team_id:
							1:
								team_id_to_set_on_tile = 1
								new_color_to_set = team1_color
							2:
								team_id_to_set_on_tile = 2
								new_color_to_set = team2_color
							_:
								team_id_to_set_on_tile = 0 
								new_color_to_set = unpainted_color
						
						var captured_color = new_color_to_set
						var captured_team = team_id_to_set_on_tile
						
						update_tile(0, cell_coords, func(td):
							td.modulate = captured_color
							td.set_custom_data("painted_team", captured_team)
						)
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
