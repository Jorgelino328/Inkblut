class_name Tank extends CharacterBody2D

@onready var anim = $AnimationPlayer
@export var HP = 10
@export var SPEED = 300.0
@export var JUMP_VELOCITY = -400.0
@export var paintable_map: TileMap

var shot = preload("res://Scenes/Projectiles/inkshot.tscn")
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var player_id: int = 1

# Network synchronized variables
var network_position: Vector2
var network_velocity: Vector2
var network_cannon_rotation: float
var network_body_flip: bool
var network_animation: String = "Idle"

func _ready():
	# Set the player ID based on multiplayer authority
	player_id = get_multiplayer_authority()
	
	# Initialize network variables
	network_position = global_position
	network_velocity = velocity
	network_cannon_rotation = $Body/Cannon.rotation
	network_body_flip = $Body.flip_h

func _physics_process(delta):
	if is_multiplayer_authority():
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

func _handle_local_input(delta):
	# Point cannon at mouse
	$Body/Cannon.look_at(get_viewport().get_mouse_position())
	
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
	
	# Update cannon rotation
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
	shot_instance.setup(get_global_mouse_position(),self)
	shot_instance.global_position = $Body/Cannon/GunPoint.global_position
	get_tree().get_root().add_child(shot_instance)
	if paintable_map:
		shot_instance.connect("paint_splat", Callable(paintable_map, "on_paint_splat"))

func _on_animation_finished(anim_name):
	if (anim_name == "Jump"):
		anim.play("Jump_Fall")

func _on_hit(body):
	HP -= 1
	anim.play("Hit")
	if HP <= 0:
		die()

func die():
	# Get reference to the main scene and show game over
	var main_scene = get_tree().get_first_node_in_group("main")
	if main_scene:
		main_scene.show_game_over()
	else:
		# Fallback - just reload the scene
		get_tree().reload_current_scene()

func _on_hit_floor(body):
	anim.play("Jump_Land")
