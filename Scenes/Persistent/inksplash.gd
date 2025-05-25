extends Node2D

@onready var anim = $AnimationPlayer

func _ready():
	$Splash.flip_h = true
	anim.play("Splash")

func _on_animation_finished(anim_name):
	if anim_name == "Splash":
		var n = randi_range(4, 8)
		$Splash.set_frame(n)
