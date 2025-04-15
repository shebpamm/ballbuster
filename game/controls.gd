extends CharacterBody3D

var speed := 20.0
var jump_force := 10.0
var gravity := -30.0
var mouse_sensitivity := 0.001
var air_control_strength := 0.05

var twist_input := 0.0
var pitch_input := 0.0

var is_sliding := false
var slide_velocity := Vector3.ZERO
var slide_boost_multiplier := 4.0
var slide_speed_threshold := 6.0
var slide_timer := 0.0
var slide_duration_max := 0.5
var slide_hop_queued := false
var slide_jump_mult := 1.8

# Camera FOV adjustments
var normal_fov := 70.0
var slide_fov := 105.0
var current_fov := normal_fov
var fov_smooth_speed := 10.0

# Model tilt smoothing
var current_model_x_rot := 0.0
var tilt_smooth_speed := 10.0

var shoot_direction: Vector3 = Vector3.FORWARD # The default direction to shoot in (can be overridden)
var shoot_distance: float = 100.0
var ball_speed: float = 100

var lerp_duration := 1

@onready var twist_pivot := $TwistPivot
@onready var pitch_pivot := $TwistPivot/PitchPivot
@onready var velocity_label := $CanvasLayer/VelocityLabel
@onready var animation_player := $Model/AnimationPlayer
@onready var camera := $TwistPivot/PitchPivot/Camera3D
@onready var slide_particles = $SlideParticles

@onready var shoot_origin := $"Model/Left_Armed/Skeleton3D/HK USP 9"
@onready var world: Node3D = get_tree().get_first_node_in_group("world") # Assuming your main game world is in a "world" group

@export var bowling_ball_scene: PackedScene

func _ready() -> void:
	slide_particles.emitting = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.fov = normal_fov

func _physics_process(delta: float) -> void:
	var input_dir = get_input_direction()
	var direction = get_movement_direction(input_dir)

	handle_movement(direction, delta)
	handle_gravity_and_jump(delta)  # Prioritize jump over slide
	handle_sliding_logic(direction, delta)  # Handle sliding after jump logic

	move_and_slide()
	update_animation()

func _process(delta: float) -> void:
	update_camera_fov(delta)
	update_model_tilt(delta)
	handle_rotation_input()
	update_ui()
	check_mouse_unlock()
	check_shoot_input()

func _unhandled_input(event: InputEvent) -> void:
	handle_mouse_input(event)

# --- Helper Functions Below ---

func get_input_direction() -> Vector3:
	return Vector3(
		Input.get_axis("move_left", "move_right"),
		0,
		Input.get_axis("move_forward", "move_back")
	).normalized()

func get_movement_direction(input_dir: Vector3) -> Vector3:
	return (twist_pivot.basis * input_dir).normalized()

func handle_sliding_logic(direction: Vector3, delta: float) -> void:
	var horizontal_speed := Vector3(velocity.x, 0, velocity.z).length()

	# Queue slide-hop while airborne
	if not is_on_floor():
		if (Input.is_action_pressed("move_crouch") and not is_on_floor()) and horizontal_speed > slide_speed_threshold:
			slide_hop_queued = true

	if is_on_floor():
		if not is_sliding and horizontal_speed > slide_speed_threshold:
			if Input.is_action_just_pressed("move_crouch") or (slide_hop_queued and Input.is_action_pressed("move_crouch")):
				start_slide(direction)
				slide_hop_queued = false

		elif is_sliding and Input.is_action_just_released("move_crouch"):
			stop_slide()

	if is_sliding:
		slide_timer += delta
		velocity.x = slide_velocity.x
		velocity.z = slide_velocity.z

		if slide_timer >= slide_duration_max:
			stop_slide()

func start_slide(direction: Vector3) -> void:
	is_sliding = true
	slide_timer = 0.0
	var boost_dir = velocity
	boost_dir.y = 0
	if boost_dir.length() < 0.1:
		boost_dir = direction
	boost_dir = boost_dir.normalized()
	slide_velocity = boost_dir * speed * slide_boost_multiplier
	if animation_player:
		animation_player.play("Slide")
	slide_particles.emitting = true

func stop_slide() -> void:
	animation_player.stop()
	animation_player.play("Idle")
	is_sliding = false
	slide_particles.emitting = false

func handle_movement(direction: Vector3, delta: float) -> void:
	if is_sliding:
		return  # Let sliding logic control velocity

	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	var desired_velocity = direction * speed

	if is_on_floor():
		# Full control on ground
		velocity.x = desired_velocity.x
		velocity.z = desired_velocity.z
	else:
		# Air control: blend current direction with input direction
		var current_speed = horizontal_velocity.length()
		if current_speed > 0:
			  # Tweak this value for stronger/weaker air control
			var new_direction = (horizontal_velocity.normalized().lerp(direction.normalized(), air_control_strength)).normalized()
			var new_velocity = new_direction * current_speed
			velocity.x = new_velocity.x
			velocity.z = new_velocity.z


func handle_gravity_and_jump(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	elif Input.is_action_just_pressed("move_jump"):
		if is_sliding:
			stop_slide()
			velocity.y = jump_force * slide_jump_mult
		else:
			velocity.y = jump_force

func update_animation() -> void:
	var run_velocity := velocity
	run_velocity.y = 0
	if not animation_player.is_playing():
		if run_velocity.length() > 0.1:
			animation_player.play("Idle")  # Replace with "Run" when ready
		else:
			animation_player.play("Idle")

func update_camera_fov(delta: float) -> void:
	var target_fov = slide_fov if is_sliding else normal_fov
	current_fov = lerp(current_fov, target_fov, fov_smooth_speed * delta)
	camera.fov = current_fov

func update_model_tilt(delta: float) -> void:
	var target_rot_x = deg_to_rad(-60) if is_sliding else 0.0
	current_model_x_rot = lerp(current_model_x_rot, target_rot_x, tilt_smooth_speed * delta)
	$Model.rotation.x = current_model_x_rot

func handle_rotation_input() -> void:
	twist_pivot.rotate_y(twist_input)
	$Model.rotate_y(twist_input)
	pitch_pivot.rotate_x(pitch_input)
	pitch_pivot.rotation.x = clamp(pitch_pivot.rotation.x, -0.75, 0.4)

	twist_input = 0.0
	pitch_input = 0.0

func update_ui() -> void:
	if is_instance_valid(velocity_label):
		var speed := velocity.length()
		velocity_label.text = "Speed: %.2f" % speed

func check_mouse_unlock() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func check_shoot_input() -> void:
	if Input.is_action_just_pressed("gun_shoot"):
		shoot()

func shoot() -> void:
	if animation_player:
		animation_player.stop()
		animation_player.play("Shoot")

	# Get the viewport
	var viewport = get_viewport()
	# Get the size of the viewport
	var viewport_size = viewport.get_visible_rect().size
	# Calculate the center of the viewport
	var viewport_center = viewport_size / 2.0

	# Get the ray origin from the camera
	var ray_origin = camera.project_ray_origin(viewport_center)
	# Get the ray direction from the camera through the viewport center
	var ray_direction = camera.project_ray_normal(viewport_center)

	# Calculate the target position for the raycast
	var ray_end = ray_origin + ray_direction * shoot_distance

	var query = PhysicsRayQueryParameters3D.new()
	query.from = ray_origin
	query.to = ray_end
	query.exclude = [self] # Don't hit the player/shooter itself

	# Get the PhysicsDirectSpaceState3D
	var space_state = get_world_3d().get_direct_space_state()
	if space_state:
		# Perform the raycast
		var result = space_state.intersect_ray(query)

		var target_position: Vector3
		if result and result.has("position"):
			target_position = result["position"] # Use the hit position
			print("Raycast hit at:", target_position) # Optional debug
			spawn_and_launch_ball(target_position)
	else:
		printerr("Error: Could not get the PhysicsDirectSpaceState3D.")

func spawn_and_launch_ball(target: Vector3) -> void:
	if bowling_ball_scene:
		var ball_instance = bowling_ball_scene.instantiate()
		if world:
			world.add_child(ball_instance)
			ball_instance.global_position = target
			# Directly apply impulse for physics-based movement
			var direction = (target - shoot_origin.global_position).normalized()
			if ball_instance is RigidBody3D:
				ball_instance.apply_impulse(direction * ball_speed) # Adjust the impulse strength as needed
		else:
			printerr("Error: No node found in the 'world' group to add the ball to.")
			ball_instance.queue_free()
	else:
		printerr("Error: Bowling ball scene not assigned.")

func queue_free_ball(ball: Node, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(ball):
		ball.queue_free()

func handle_mouse_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		twist_input = -event.relative.x * mouse_sensitivity
		pitch_input = -event.relative.y * mouse_sensitivity
