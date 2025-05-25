extends RigidBody2D

@export var speed = 300.0
@export var gravity_strength = 0.0

@onready var anim = $AnimationPlayer

var target_position = Vector2.ZERO
var shooter_node = null

signal paint_splat(global_pos, team_id, splat_radius)

func _ready():
	gravity_scale = gravity_strength

	anim.play("Shoot_Fire")

	look_at(target_position)
	linear_velocity = transform.x.normalized() * speed
	
	body_entered.connect(_on_collision)
	$AnimationPlayer.animation_finished.connect(_on_animation_finished)

func _on_collision(body):
	if body is Tank and body != shooter_node:
		body.HP -= 1
		queue_free()
		return
	elif body != shooter_node:
		linear_velocity = Vector2.ZERO
		anim.play("Shoot_Splatter")
		emit_signal("paint_splat", global_position, 1, 10)

func _on_animation_finished(anim_name):
	if anim_name == "Shoot_Fire":
		anim.play("Shoot_Idle")
	elif anim_name == "Shoot_Splatter":
		queue_free()

func setup(pos, shooter):
	target_position = pos
	shooter_node = shooter
