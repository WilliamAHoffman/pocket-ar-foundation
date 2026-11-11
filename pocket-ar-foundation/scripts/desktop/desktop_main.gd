extends Node3D
## Desktop AR room simulator with camera-driven, accumulated plane detection.
## WASD: move, mouse: look, left click: place on a detected plane,
## P: toggle plane visualization, R: clear placed objects, Esc: release mouse.

const ROOM_SIZE := Vector2(12.0, 10.0)
const WALL_HEIGHT := 3.2
const MOVE_SPEED := 4.0
const MOUSE_SENSITIVITY := 0.0025
const RAY_LENGTH := 30.0
const SCAN_INTERVAL := 0.18
const GRID_COLUMNS := 13
const GRID_ROWS := 9
const MIN_PLANE_POINTS := 3
const MIN_PLANE_EXTENT := 0.22
const POINT_MERGE_DISTANCE := 0.12

var camera: Camera3D
var placements: PlacementManager
var ar_backend: ARBackend
var hud: Label
var help_label: Label
var planes_visible := true
var mouse_captured := false

func _ready() -> void:
	_build_room()
	_build_camera()
	_build_detection_root()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_room() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.30, 0.46)
	sky_mat.sky_horizon_color = Color(0.68, 0.73, 0.78)
	sky_mat.ground_bottom_color = Color(0.12, 0.13, 0.15)
	sky_mat.ground_horizon_color = Color(0.48, 0.50, 0.51)
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.82)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	_add_static_box("Floor", Vector3(0, -0.12, 0), Vector3(ROOM_SIZE.x, 0.24, ROOM_SIZE.y), Color(0.42, 0.39, 0.34))
	_add_static_box("BackWall", Vector3(0, WALL_HEIGHT / 2.0, -ROOM_SIZE.y / 2.0), Vector3(ROOM_SIZE.x, WALL_HEIGHT, 0.18), Color(0.76, 0.78, 0.80))
	_add_static_box("LeftWall", Vector3(-ROOM_SIZE.x / 2.0, WALL_HEIGHT / 2.0, 0), Vector3(0.18, WALL_HEIGHT, ROOM_SIZE.y), Color(0.68, 0.73, 0.78))
	_add_static_box("RightWall", Vector3(ROOM_SIZE.x / 2.0, WALL_HEIGHT / 2.0, 0), Vector3(0.18, WALL_HEIGHT, ROOM_SIZE.y), Color(0.68, 0.73, 0.78))
	_add_static_box("FrontWall", Vector3(0, WALL_HEIGHT / 2.0, ROOM_SIZE.y / 2.0), Vector3(ROOM_SIZE.x, WALL_HEIGHT, 0.18), Color(0.76, 0.78, 0.80))
	_add_static_box("TableTop", Vector3(0.0, 0.78, -1.0), Vector3(2.8, 0.12, 1.7), Color(0.36, 0.22, 0.13))
	for x in [-1.2, 1.2]:
		for z in [-1.65, -0.35]:
			_add_static_box("TableLeg", Vector3(x, 0.38, z), Vector3(0.12, 0.76, 0.12), Color(0.22, 0.15, 0.11))
	_add_static_box("Cabinet", Vector3(-3.5, 0.9, -2.7), Vector3(1.3, 1.8, 0.75), Color(0.32, 0.37, 0.40))
	_add_static_box("LowPlatform", Vector3(3.0, 0.35, -2.2), Vector3(1.8, 0.7, 1.2), Color(0.48, 0.43, 0.34))

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

func _add_static_box(label: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)

func _build_camera() -> void:
	var rig := CharacterBody3D.new()
	rig.name = "Player"
	rig.position = Vector3(0, 1.65, 3.8)
	add_child(rig)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.1
	collision.shape = capsule
	collision.position.y = -0.35
	rig.add_child(collision)
	camera = Camera3D.new()
	camera.name = "SimulatedCamera"
	camera.current = true
	camera.fov = 70.0
	rig.add_child(camera)
	rig.set_meta("is_player", true)

func _build_detection_root() -> void:
	var desktop_backend := DesktopARBackend.new()
	ar_backend = desktop_backend
	desktop_backend.name = "DesktopARBackend"
	add_child(desktop_backend)
	desktop_backend.configure(camera, _get_player())
	ar_backend.start_session()
	ar_backend.plane_added.connect(_on_plane_detected)
	ar_backend.plane_updated.connect(_on_plane_updated)
	ar_backend.plane_removed.connect(_on_plane_removed)
	placements = PlacementManager.new()
	placements.name = "PlacedObjects"
	add_child(placements)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(350, 0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	hud = Label.new()
	hud.text = "AR SIMULATOR  |  Scanning room..."
	hud.add_theme_font_size_override("font_size", 16)
	column.add_child(hud)
	help_label = Label.new()
	help_label.text = "WASD: move   Mouse: look\nLeft click: place   P: planes on/off\nR: clear objects   Esc: release mouse"
	help_label.add_theme_font_size_override("font_size", 13)
	column.add_child(help_label)
	var note := Label.new()
	note.text = "Planes appear as the camera scans visible surfaces."
	note.add_theme_font_size_override("font_size", 12)
	column.add_child(note)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not mouse_captured:
			mouse_captured = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_place_object_at_screen_center()
	elif event is InputEventMouseMotion and mouse_captured:
		var player := _get_player()
		player.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				mouse_captured = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_P:
				planes_visible = not planes_visible
				ar_backend.set_plane_visualization_enabled(planes_visible)
			KEY_R:
				placements.clear()

func _physics_process(delta: float) -> void:
	var player := _get_player()
	var input_dir := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var direction := (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	player.velocity.x = direction.x * MOVE_SPEED
	player.velocity.z = direction.z * MOVE_SPEED
	player.velocity.y = 0.0
	player.move_and_slide()
	player.position.x = clamp(player.position.x, -5.65, 5.65)
	player.position.z = clamp(player.position.z, -4.65, 4.65)
	player.position.y = 1.65


func _place_object_at_screen_center() -> void:
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := ar_backend.raycast_from_screen(center)
	if hit == null:
		hud.text = "No surface hit. Aim at a room surface."
		return
	var surface_name := "surface"
	if hit.collider is Node:
		surface_name = (hit.collider as Node).name
	placements.place_cube(hit.get_pose(0.095), 0.18, Color(1.0, 0.38, 0.12))
	if hit.plane_id != "":
		hud.text = "Placed on detected surface: %s" % surface_name
	else:
		hud.text = "Surface hit; scanning it now: %s" % surface_name

func _on_plane_detected(_plane_data: PlaneData) -> void:
	_update_plane_count()

func _on_plane_updated(_plane_data: PlaneData) -> void:
	_update_plane_count()

func _on_plane_removed(_plane_id: String) -> void:
	_update_plane_count()

func _update_plane_count() -> void:
	var count := ar_backend.get_detected_planes().size()
	hud.text = "AR SIMULATOR  |  Detected planes: %d" % count

func _get_player() -> CharacterBody3D:
	return get_node("Player") as CharacterBody3D
