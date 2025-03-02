class_name RaycastVehicle extends RigidBody3D

@export_category("Vehicle Properties")
@export var center_of_mass_offset: Node3D

@export var engine_power: float = 2
@export var suspension_rest_dist: float = 0.6
@export var spring_strength: float = 15
@export var spring_damper: float = 1

@export var front_wheel_radius: float = 0.33
@export var rear_wheel_radius: float = 0.33
@export var max_steer_angle: float = 35

@export var front_left_wheel: RaycastWheel
@export var front_right_wheel: RaycastWheel
@export var rear_left_wheel: RaycastWheel
@export var rear_right_wheel: RaycastWheel

@export_category("Anti-roll properties")
@export var stability_strength: float = 8.0  ## Strength of the anti-roll force
@export var max_tilt_angle: float = 45.0     ## Maximum angle (in degrees) before full stabilization kicks in
@export var angular_damping_factor: float = 1.0  ## Damping for angular velocity

@export_category("Slope handling parameters")
@export var hill_hold_strength: float = 15.0  ## Strength of force preventing downhill sliding when stopped
@export var hill_hold_angle_threshold: float = 3.0  ## Minimum slope angle (degrees) to activate hill hold
@export var hill_hold_speed_threshold: float = 2.0  ## Maximum speed to activate hill hold

@export_category("Debug")
@export var debug: bool = false

var acceleration_input: float = 0
var steering_input: float = 0
var current_steering_angle: float = 0 ## The real rotation of the wheels
var ground_slope_angle: float = 0.0  ## Store the current ground slope angle
var is_on_slope: bool = false  ## Whether the vehicle is on a significant slope
var slope_direction: Vector3 = Vector3.ZERO  ## Direction of the slope (downhill)

func _input(event):
	if Input.is_action_just_pressed("toggle_debug"):
		debug = !debug

func _ready() -> void:
	# Set the center of mass
	center_of_mass = center_of_mass_offset.position
	_assign_wheel_sizes()
	
func _assign_wheel_sizes() -> void:
	front_left_wheel.radius = front_wheel_radius
	front_right_wheel.radius = front_wheel_radius
	rear_left_wheel.radius = rear_wheel_radius
	rear_right_wheel.radius = rear_wheel_radius
	
func _process(_delta: float) -> void:
	acceleration_input = Input.get_axis("down", "up")
	steering_input = Input.get_axis("right", "left")

func _physics_process(delta: float) -> void:
	_apply_steering_angle_to_wheels()
	_update_slope_info()
	_apply_hill_hold(delta)
	_apply_anti_roll_forces(delta)
	
func _apply_steering_angle_to_wheels() -> void:
	# Calculate target steering angle based on input
	var target_steering_angle: float = clamp(steering_input * max_steer_angle, -max_steer_angle, max_steer_angle)
	
	# Smoothly interpolate toward the target angle
	current_steering_angle = lerp(current_steering_angle, target_steering_angle, 0.3)
	
	# Apply the steering angle to both front wheels
	front_left_wheel.rotation.y = deg_to_rad(current_steering_angle)
	front_right_wheel.rotation.y = deg_to_rad(current_steering_angle)

# Updates slope-related information
func _update_slope_info() -> void:
	var ground_normal: Vector3 = get_average_ground_normal()
	
	# Calculate angle between ground normal and up vector
	var angle_rad: float = acos(ground_normal.dot(Vector3.UP))
	ground_slope_angle = rad_to_deg(angle_rad)
	
	# Determine if we're on a significant slope
	is_on_slope = ground_slope_angle > hill_hold_angle_threshold
	# Calculate the downhill direction (perpendicular to normal, on horizontal plane)
	var slope_horizontal: Vector3 = Vector3(ground_normal.x, 0, ground_normal.z).normalized()
	slope_direction = Vector3.UP.cross(slope_horizontal).cross(ground_normal).normalized()

# Applies hill hold forces when on a slope and nearly stopped
func _apply_hill_hold(_delta: float) -> void:
	if not is_on_slope:
		apply_wheel_friction(false)
		return
	var velocity_magnitude: float = linear_velocity.length()
	# moving too fast or actively accelerating
	if velocity_magnitude >= hill_hold_speed_threshold or abs(acceleration_input) >= 0.1:
		apply_wheel_friction(false)
		return
	
	# Apply hill hold force
	var force_strength: float = hill_hold_strength * sin(deg_to_rad(ground_slope_angle))
	var hold_force: Vector3 = -slope_direction * force_strength * mass
	apply_central_force(hold_force)
	apply_wheel_friction(true)
	if debug:
		DebugDraw3D.draw_arrow(global_position, global_position + hold_force * 0.01, Color.DARK_ORANGE, 0.1, true)

# Sets wheel friction based on hill hold state
func apply_wheel_friction(use_hill_hold: bool) -> void:
	const wheel_high_friction: float = 10.0
	for wheel: RaycastWheel in [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]:
		if use_hill_hold:
			# Increase friction smoothly when hill hold is active
			wheel.rolling_friction = lerp(wheel.rolling_friction, wheel_high_friction, 0.1)
			wheel.side_friction = lerp(wheel.side_friction, wheel_high_friction, 0.1)
		else:
			# Return to default values when hill hold is inactive
			wheel.rolling_friction = lerp(wheel.rolling_friction, wheel.default_rolling_friction, 0.1)
			wheel.side_friction = lerp(wheel.side_friction, wheel.default_side_friction, 0.1)

# Applies forces to prevent excessive tilting
func _apply_anti_roll_forces(delta: float) -> void:
	var average_ground_normal: Vector3 = get_average_ground_normal()
	var vehicle_up: Vector3 = global_transform.basis.y
	
	var alignment: float = vehicle_up.dot(average_ground_normal)
	var correction_axis: Vector3 = vehicle_up.cross(average_ground_normal).normalized()
	
	var tilt_angle_rad: float = acos(clamp(alignment, -1.0, 1.0))
	var tilt_angle_deg: float = rad_to_deg(tilt_angle_rad)
	
	if tilt_angle_deg > 5.0:
		var force_strength: float = stability_strength * (tilt_angle_deg / max_tilt_angle)
		force_strength = clamp(force_strength, 0, stability_strength)
		
		var correction_force: Vector3 = correction_axis * force_strength
		apply_torque(correction_force)
		
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, angular_damping_factor * delta)
		
		if debug:
			DebugDraw3D.draw_arrow(global_position, global_position + vehicle_up * 2, Color.GREEN, 0.1, true)
			DebugDraw3D.draw_arrow(global_position, global_position + average_ground_normal * 2, Color.CYAN, 0.1, true)

# Computes the average ground normal from colliding wheels
func get_average_ground_normal() -> Vector3:
	var sum_normal: Vector3 = Vector3.ZERO
	var colliding_wheels: int = 0
	for wheel: RaycastWheel in [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]:
		if wheel.is_colliding():
			sum_normal += wheel.get_collision_normal()
			colliding_wheels += 1
	if colliding_wheels > 0:
		return sum_normal.normalized()
	else:
		return Vector3.UP  # Default to world up when airborne

func get_speed() -> float:
	var forward: Vector3 = basis.z
	return linear_velocity.dot(forward)

func get_travel_direction() -> float:
	return 1 if get_speed() > 0 else -1
