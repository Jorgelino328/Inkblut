class_name HealthPack extends Area2D

signal health_pack_collected(tank: Tank)

@onready var sprite = $Sprite2D
@onready var collision_shape = $CollisionShape2D

@export var heal_amount: int = 0  # 0 means full heal
@export var bob_amplitude: float = 10.0
@export var bob_speed: float = 3.0

var original_position: Vector2
var time_elapsed: float = 0.0

func _ready():
	# Store original position for bobbing animation
	original_position = global_position
	
	# Connect area entered signal
	body_entered.connect(_on_body_entered)
	
	# Add to items group for discovery
	add_to_group("items")
	add_to_group("health_packs")
	
	print("Health pack spawned at: ", global_position)

func _process(delta):
	# Create bobbing animation
	time_elapsed += delta
	var bob_offset = sin(time_elapsed * bob_speed) * bob_amplitude
	global_position.y = original_position.y + bob_offset

func _on_body_entered(body):
	if body is Tank and not body.is_dead:
		collect_health_pack(body)

func collect_health_pack(tank: Tank):
	"""Collect the health pack and heal the tank"""
	print("Health pack collected by player: ", tank.player_id)
	
	# Heal the tank
	if heal_amount <= 0:
		# Full heal
		tank.heal_full()
	else:
		# Heal by specific amount
		tank.heal(heal_amount)
	
	# Emit signal for any listeners
	emit_signal("health_pack_collected", tank)
	
	# Remove the health pack
	queue_free()
