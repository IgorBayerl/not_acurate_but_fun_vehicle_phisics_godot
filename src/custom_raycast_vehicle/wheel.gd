class_name RaycastWheel extends RayCast3D

## Reference to parent vehicle
@onready var vehicle: RaycastVehicle = get_parent().get_parent() as RaycastVehicle
@onready var wheel_mesh: Node3D = $wheel_mesh

## Wheel properties
@export var radius: float = 0.35
@export var side_friction: float = 3.0  # Sideways friction (prevents drifting)
@export var rolling_friction: float = 0.1  # Forward/backward friction (natural slowdown)

var previous_suspension_length: float = 0.0

# Store default values for restoration
var default_side_friction: float = 2.0
var default_rolling_friction: float = 0.1

## Apply physics forces when wheel is in contact with ground
func _ready() -> void:
	# Store the default friction values
	default_side_friction = side_friction
	default_rolling_friction = rolling_friction

func _physics_process(delta: float) -> void:
	add_exception(vehicle)
	if is_colliding():
		var ground_contact_point: Vector3 = get_collision_point()
		var wheel_origin: Vector3 = Vector3(ground_contact_point.x, ground_contact_point.y + radius, ground_contact_point.z)
		
		_apply_suspension_forces(delta, wheel_origin, ground_contact_point)
		_apply_acceleration_forces(wheel_origin)
		_apply_side_friction(wheel_origin, ground_contact_point)
		_apply_rolling_friction(wheel_origin, ground_contact_point)
		
	_update_wheel_mesh_position()
	_rotate_wheel_mesh(delta)

func _rotate_wheel_mesh(delta: float) -> void:
	var rotation_direction: float = vehicle.get_travel_direction()
	var angle: float = rotation_direction * vehicle.linear_velocity.length() * delta
	wheel_mesh.rotate_x(angle)

func _update_wheel_mesh_position() -> void:
	var new_mesh_position: float = 0
	if is_colliding():
		new_mesh_position = to_local(get_collision_point()).y + radius
	else:
		new_mesh_position = -vehicle.suspension_rest_dist
	wheel_mesh.position.y = lerp(wheel_mesh.position.y, new_mesh_position, 0.6)

## Apply sideways friction to prevent excessive drifting
func _apply_side_friction(wheel_origin: Vector3, ground_contact_point: Vector3) -> void:
	var side_direction: Vector3 = global_basis.x
	var state:PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(vehicle.get_rid())
	var wheel_velocity: Vector3 = state.get_velocity_at_local_position(global_position - vehicle.global_position)
	var side_velocity: float = side_direction.dot(wheel_velocity)
	
	# Calculate and apply side friction force
	var friction_force: Vector3 = side_direction * (-side_velocity * side_friction)
	vehicle.apply_force(friction_force, ground_contact_point - vehicle.global_position)
	
	if vehicle.debug:
		DebugDraw3D.draw_arrow(wheel_origin, wheel_origin + friction_force * 2.0, Color.RED, 0.1, true)

## Apply forward/backward friction to slow the vehicle naturally
func _apply_rolling_friction(wheel_origin: Vector3, ground_contact_point: Vector3) -> void:
	var forward_direction: Vector3 = global_basis.z
	var state:PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(vehicle.get_rid())
	var wheel_velocity: Vector3 = state.get_velocity_at_local_position(global_position - vehicle.global_position)
	var forward_velocity: float = forward_direction.dot(wheel_velocity)
	
	var friction_force: Vector3 = forward_direction * (-forward_velocity * rolling_friction)
	vehicle.apply_force(friction_force, ground_contact_point - vehicle.global_position)
	
	if vehicle.debug:
		DebugDraw3D.draw_arrow(wheel_origin, wheel_origin + friction_force * 2.0, Color.BLUE_VIOLET, 0.1, true)

## Apply engine power to drive the vehicle forward/backward
func _apply_acceleration_forces(wheel_origin: Vector3) -> void:
	var acceleration_direction: Vector3 = -global_basis.z
	var propulsion_force: Vector3 = vehicle.acceleration_input * vehicle.engine_power * acceleration_direction
	
	vehicle.apply_force(propulsion_force, wheel_origin - vehicle.global_position)
	
	if vehicle.debug:
		DebugDraw3D.draw_arrow(wheel_origin, wheel_origin + propulsion_force, Color.BLUE, 0.1, true)

## Apply suspension forces to simulate shocks and springs
func _apply_suspension_forces(delta: float, wheel_origin: Vector3, ground_contact_point: Vector3) -> void:
	var suspension_direction: Vector3 = global_basis.y
	var raycast_origin: Vector3 = global_position
	
	var distance_to_ground: float = ground_contact_point.distance_to(raycast_origin)
	var suspension_length: float = clamp(distance_to_ground - radius, 0.0, vehicle.suspension_rest_dist)
	
	var spring_force: float = vehicle.spring_strength * (vehicle.suspension_rest_dist - suspension_length)
	var suspension_velocity: float = (previous_suspension_length - suspension_length) / delta
	var damper_force: float = vehicle.spring_damper * suspension_velocity
	
	var suspension_force: Vector3 = suspension_direction * (spring_force + damper_force)
	previous_suspension_length = suspension_length
	
	vehicle.apply_force(suspension_force, wheel_origin - vehicle.global_position)
	
	if vehicle.debug:
		DebugDraw3D.draw_sphere(wheel_origin, 0.1)
		var target_arrow_force: Vector3 = to_global(position + Vector3(-position.x, suspension_force.y / 2.0, -position.z))
		DebugDraw3D.draw_arrow(global_position, target_arrow_force, Color.GREEN, 0.1, true)
		var target_arrow_wheel: Vector3 = to_global(position + Vector3(-position.x, -1.0, -position.z))
		DebugDraw3D.draw_line_hit_offset(global_position, target_arrow_wheel, true, distance_to_ground, 0.2, Color.RED, Color.RED)
