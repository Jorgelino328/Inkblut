class_name Tank extends CharacterBody2D

# Tank health changed signal
signal health_changed(health: int, max_health: int)

@onready var anim = $AnimationPlayer
@export var max_hp = 3
@export var current_hp = 3
@export var SPEED = 300.0
@export var JUMP_VELOCITY = -400.0
@export var paintable_map: TileMap

var shot = preload("res://Scenes/Projectiles/inkshot.tscn")
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var player_id: int = 1
var is_local_player: bool = false  # Track if this is the local player's tank

# Network synchronized variables
var network_position: Vector2
var network_velocity: Vector2
var network_cannon_rotation: float
var network_body_flip: bool
var network_animation: String = "Idle"
var is_dead: bool = false
var damage_cooldown: float = 0.0
var damage_cooldown_time: float = 0.1  # 100ms cooldown between damage instances
var hit_flash_timer: float = 0.0
var hit_flash_duration: float = 0.2  # 200ms flash duration
var last_mouse_position: Vector2 = Vector2.ZERO  # Store window-specific mouse position

func _ready():
	# Add to tanks group for discovery
	add_to_group("tanks")
	
	# Set the player ID based on multiplayer authority
	player_id = get_multiplayer_authority()
	
	# Check if this is the local player's tank
	is_local_player = is_multiplayer_authority()
	
	# Disable animation tracks that control cannon rotation to allow manual control
	_disable_cannon_rotation_tracks()
	
	# Initialize health
	current_hp = max_hp
	
	# Ensure tank starts with full opacity
	modulate.a = 1.0
	
	# Initialize network variables
	network_position = global_position
	network_velocity = velocity
	network_cannon_rotation = $Body/Cannon.rotation
	network_body_flip = $Body.flip_h
	
	# Initialize mouse position for local player
	if is_local_player:
		last_mouse_position = get_viewport().get_mouse_position()

func _disable_cannon_rotation_tracks():
	"""Disable animation tracks that control cannon rotation"""
	if anim and anim.has_animation("RESET"):
		var reset_anim = anim.get_animation("RESET")
		for track_idx in range(reset_anim.get_track_count()):
			if reset_anim.track_get_path(track_idx) == NodePath("Body/Cannon:rotation"):
				reset_anim.track_set_enabled(track_idx, false)
	
	if anim and anim.has_animation("Boom"):
		var boom_anim = anim.get_animation("Boom")
		for track_idx in range(boom_anim.get_track_count()):
			if boom_anim.track_get_path(track_idx) == NodePath("Body/Cannon:rotation"):
				boom_anim.track_set_enabled(track_idx, false)

func _enforce_cannon_rotation():
	"""Ensure cannon rotation is controlled by code, not animations"""
	if is_local_player:
		# Local player: don't interfere, mouse tracking handles this in _handle_local_input
		pass
	else:
		# Remote player: enforce networked rotation
		if $Body/Cannon.rotation != network_cannon_rotation:
			$Body/Cannon.rotation = lerp_angle($Body/Cannon.rotation, network_cannon_rotation, 0.3)  # Faster lerp to overcome animation interference

func _physics_process(delta):
	# Update damage cooldown
	if damage_cooldown > 0:
		damage_cooldown -= delta
		
	# Handle hit flash effect
	if hit_flash_timer > 0:
		hit_flash_timer -= delta
		# Flash between transparent and opaque
		var flash_alpha = sin(hit_flash_timer * 20) * 0.5 + 0.5  # Oscillates between 0.0 and 1.0
		modulate.a = max(0.3, flash_alpha)  # Don't go completely transparent
		
		if hit_flash_timer <= 0:
			# Flash finished, return to full opacity
			modulate.a = 1.0
		
	if is_dead:
		return  # Don't process physics if dead
		
	if is_local_player:
		# Local player - process input and movement
		_handle_local_input(delta)
		
		# Update network variables for synchronization
		network_position = global_position
		network_velocity = velocity
		network_cannon_rotation = $Body/Cannon.rotation
		network_body_flip = $Body.flip_h
		network_animation = anim.current_animation if anim.current_animation else "Idle"
		
		# Send movement data to other clients
		_sync_movement.rpc(network_position, network_velocity, network_cannon_rotation, network_body_flip, network_animation)
	else:
		# Remote player - interpolate to network position
		_handle_remote_movement(delta)
	
	# FORCE cannon rotation control - override any animation interference
	_enforce_cannon_rotation()

func _handle_local_input(delta):
	# Only allow local player to track mouse
	if not is_local_player:
		return
		
	# Point cannon at mouse (only for local player)
	# Mouse tracking is handled in _input() and _update_cannon_aim()
	
	# Add the gravity.
	if not is_on_floor():
		velocity.y += gravity * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		jump()
		
	if Input.is_action_just_pressed("action_button"):
		shoot.rpc()
		
	# Get the input direction and handle the movement/deceleration.
	var direction = Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	
	# Play animations when moving/idle
	if(velocity.x != 0):
		if(velocity.x < 0):
			$Body.flip_h = true
		else:
			$Body.flip_h = false
		anim.play("Move")
	else:
		anim.play("Idle")
		
	move_and_slide()

func _handle_remote_movement(delta):
	# Smoothly interpolate to the network position
	global_position = global_position.lerp(network_position, delta * 10.0)
	velocity = velocity.lerp(network_velocity, delta * 10.0)
	
	# Update cannon rotation using networked data (DON'T track mouse for remote players)
	$Body/Cannon.rotation = lerp_angle($Body/Cannon.rotation, network_cannon_rotation, delta * 15.0)
	
	# Update body flip
	$Body.flip_h = network_body_flip
	
	# Update animation
	if anim.current_animation != network_animation and network_animation != "":
		anim.play(network_animation)

# RPC function to synchronize movement data
@rpc("any_peer", "unreliable", "call_remote")
func _sync_movement(pos: Vector2, vel: Vector2, cannon_rot: float, body_flip: bool, animation: String):
	network_position = pos
	network_velocity = vel
	network_cannon_rotation = cannon_rot
	network_body_flip = body_flip
	network_animation = animation
	
# Play jump animation and add jump velocity
func jump():
		velocity.y = JUMP_VELOCITY
		anim.play("Jump")
	
# Handle shooting.
@rpc("any_peer", "call_local")
func shoot():
	var shot_instance = shot.instantiate()
	
	# Calculate target position based on cannon rotation
	var cannon_direction = Vector2.RIGHT.rotated($Body/Cannon.rotation)
	var target_position = $Body/Cannon/GunPoint.global_position + cannon_direction * 1000  # Shoot far ahead
	
	shot_instance.setup(target_position, self)
	shot_instance.global_position = $Body/Cannon/GunPoint.global_position
	
	# Set the ink color to match tank color (slightly lighter)
	var ink_color = modulate.lightened(0.3)  # Make it 30% lighter
	shot_instance.set_ink_color(ink_color)
	
	get_tree().get_root().add_child(shot_instance)
	if paintable_map:
		shot_instance.connect("paint_splat", Callable(paintable_map, "on_paint_splat"))
	else:
		print("Warning: No paintable_map reference when shooting!")

func _on_animation_finished(anim_name):
	if (anim_name == "Jump"):
		anim.play("Jump_Fall")

func _on_hit(body):
	if is_dead:
		return  # Already dead
	
	# Inkshots handle their own collision and call take_damage.rpc() directly
	# This hitbox might be for other damage sources in the future
	# For now, disable to prevent spawn damage issues
	# TODO: Define what should actually trigger damage through this hitbox
	pass

@rpc("any_peer", "reliable", "call_local")
func take_damage(damage: int):
	if is_dead:
		return
		
	# Prevent double damage with cooldown
	if damage_cooldown > 0:
		print("Damage blocked by cooldown for player: ", player_id)
		return
		
	damage_cooldown = damage_cooldown_time
	
	current_hp -= damage
	# Use custom flash effect instead of animation to avoid transparency issues
	hit_flash_timer = hit_flash_duration
	
	# Emit health_changed signal
	emit_signal("health_changed", current_hp, max_hp)
	
	print("Player ", player_id, " took ", damage, " damage. HP: ", current_hp, "/", max_hp)
	
	if current_hp <= 0:
		die()

func die():
	if is_dead:
		return
		
	is_dead = true
	current_hp = 0
	
	print("Player ", player_id, " died")
	
	# Notify game manager
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		game_manager.handle_player_death(player_id)
	
	# Disable physics and input
	set_physics_process(false)
	set_process_input(false)
	
	# Hide the tank or play death animation
	visible = false

func respawn():
	"""Called when player respawns"""
	is_dead = false
	current_hp = max_hp
	visible = true
	damage_cooldown = 0.0  # Reset damage cooldown
	hit_flash_timer = 0.0  # Reset flash timer
	
	# Ensure tank has full opacity on respawn
	modulate.a = 1.0
	
	# Re-enable physics and input
	set_physics_process(true)
	set_process_input(true)
	
	# Emit health update signal
	emit_signal("health_changed", current_hp, max_hp)
	
	print("Player ", player_id, " respawned")

func _on_hit_floor(body):
	anim.play("Jump_Land")

func set_tank_color(color: Color):
	"""Set the tank's color"""
	# Preserve alpha channel when setting color to avoid transparency issues
	color.a = 1.0
	modulate = color

func _input(event):
	# Only process input for local player
	if not is_local_player or is_dead:
		return
		
	# Capture mouse motion events (these should be window-specific)
	if event is InputEventMouseMotion:
		last_mouse_position = event.position
		# Update cannon rotation immediately based on mouse position
		_update_cannon_aim()

func _update_cannon_aim():
	# Only for local player
	if not is_local_player or is_dead:
		return
		
	# Get camera and viewport info
	var viewport = get_viewport()
	var camera = viewport.get_camera_2d()
	
	var world_mouse_pos: Vector2
	
	if camera:
		# Convert the window-specific mouse position to world coordinates
		# Account for camera position and zoom
		var viewport_size = viewport.get_visible_rect().size
		var screen_center = viewport_size / 2
		var mouse_offset_from_center = last_mouse_position - screen_center
		
		# Apply camera zoom to the offset and add to camera position
		world_mouse_pos = camera.global_position + mouse_offset_from_center / camera.zoom
	else:
		# Fallback without camera
		var viewport_size = viewport.get_visible_rect().size
		var viewport_center = viewport_size / 2
		var mouse_offset = last_mouse_position - viewport_center
		world_mouse_pos = global_position + mouse_offset
	
	# Calculate desired rotation angle
	var cannon_position = $Body/Cannon.global_position
	var direction_to_mouse = world_mouse_pos - cannon_position
	var target_angle = direction_to_mouse.angle()
	
	
	while target_angle > PI:
		target_angle -= 2 * PI
	while target_angle < -PI:
		target_angle += 2 * PI
	
	# Now with the corrected angles:
	if target_angle > 0 and target_angle < PI:  # In the "down" quadrant
		if target_angle < PI/2:  # Closer to right
			target_angle = 0  # Snap to right
		else:  # Closer to left  
			target_angle = PI  # Snap to left
	
	# Set the cannon rotation
	$Body/Cannon.rotation = target_angle
