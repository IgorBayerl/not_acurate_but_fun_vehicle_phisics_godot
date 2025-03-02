extends Camera3D

@export var camera_follow_speed: float = 5

@onready var camera_pivot: Node3D = $"../RaycastVehicle/CameraPivot"

func _physics_process(delta: float) -> void:
	_follow_vehicle(delta)


func _follow_vehicle(delta: float) -> void:
	transform = transform.interpolate_with(camera_pivot.global_transform, delta * camera_follow_speed)
