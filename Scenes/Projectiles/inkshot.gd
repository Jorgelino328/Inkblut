extends RigidBody2D

@export var speed = 300.0
@export var gravity_strength = 0.0

@onready var anim = $AnimationPlayer

var target_position = Vector2.ZERO
var splash_scene = preload("res://Scenes/Persistent/inksplash.tscn")
var shooter_node = null

func _ready():
	gravity_scale = gravity_strength

	anim.play("Shoot_Fire")

	look_at(target_position)
	linear_velocity = transform.x.normalized() * speed

	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_collision(body):
	if body is Tank and body != shooter_node:
		body.HP -= 1
		queue_free()
		return

	elif body != shooter_node:
		var splash_instance = splash_scene.instantiate()
		get_parent().add_child(splash_instance)

		splash_instance.global_position = self.global_position

		var impact_direction = global_transform.x.normalized()
		var surface_normal = -impact_direction
		splash_instance.rotation = surface_normal.angle()

		queue_free()

func _on_animation_finished(anim_name):
	if anim_name == "Shoot_Fire":
		anim.play("Shoot_Idle")

func setup(pos, shooter):
	target_position = pos
	shooter_node = shooter
