class_name Tank extends CharacterBody2D

@onready var anim = $AnimationPlayer
@export var HP = 10
@export var SPEED = 300.0
@export var JUMP_VELOCITY = -400.0
var shot = preload("res://Scenes/Projectiles/inkshot.tscn")
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

func _physics_process(delta):
	
	# Point cannon at mouse
	$Body/Cannon.look_at(get_viewport().get_mouse_position())
	
	# Add the gravity.
	if not is_on_floor():
		velocity.y += gravity * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		jump()
		
	if Input.is_action_just_pressed("action_button"):
		shoot()
		
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
	
# Play jump animation and add jump velocity
func jump():
		velocity.y = JUMP_VELOCITY
		anim.play("Jump")
	
# Handle shooting.
func shoot():
	var shot_instance = shot.instantiate()
	shot_instance.setup(get_global_mouse_position(),self)
	shot_instance.global_position = $Body/Cannon/GunPoint.global_position
	get_tree().get_root().add_child(shot_instance)

func _on_animation_finished(anim_name):
	if (anim_name == "Jump"):
		anim.play("Jump_Fall")

func _on_hit(body):
	anim.play("Hit")

func _on_hit_floor(body):
	anim.play("Jump_Fall")
