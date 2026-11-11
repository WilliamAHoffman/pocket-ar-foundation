extends ARBackend
class_name DesktopARBackend

## Desktop simulation: camera rays intersect known room physics geometry.
const RAY_LENGTH := 30.0
const GRID_COLUMNS := 13
const GRID_ROWS := 9
const MIN_PLANE_POINTS := 3
const MIN_PLANE_EXTENT := 0.22
const POINT_MERGE_DISTANCE := 0.12
const SCAN_INTERVAL := 0.18
const PAUSE_AFTER_SECONDS := 2.5
const REMOVE_AFTER_SECONDS := 12.0

var camera: Camera3D
var player: CharacterBody3D
var planes_root: Node3D
var tracks: Dictionary = {}
var scan_timer := 0.0
var session_running := false
var visualization_enabled := true

func configure(camera_node: Camera3D, player_node: CharacterBody3D) -> void:
	camera = camera_node
	player = player_node
	if planes_root == null:
		planes_root = Node3D.new()
		planes_root.name = "DetectedPlanes"
		add_child(planes_root)

func start_session() -> void:
	if session_running:
		return
	session_running = true
	scan_timer = SCAN_INTERVAL
	session_state_changed.emit("tracking")

func stop_session() -> void:
	if not session_running:
		return
	session_running = false
	session_state_changed.emit("stopped")

func _process(delta: float) -> void:
	if not session_running or camera == null or not is_instance_valid(camera):
		return
	scan_timer += delta
	if scan_timer >= SCAN_INTERVAL:
		scan_timer = 0.0
		scan_camera_view()
	_update_track_lifetimes()

func scan_camera_view() -> void:
	if not session_running or camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var space_state := get_world_3d().direct_space_state
	for y in range(GRID_ROWS):
		for x in range(GRID_COLUMNS):
			var point := Vector2(viewport_size.x * (float(x) + 0.5) / GRID_COLUMNS, viewport_size.y * (float(y) + 0.5) / GRID_ROWS)
			var origin := camera.project_ray_origin(point)
			var direction := camera.project_ray_normal(point)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * RAY_LENGTH)
			if player != null and is_instance_valid(player):
				query.exclude = [player.get_rid()]
			var hit := space_state.intersect_ray(query)
			if hit.is_empty():
				continue
			var collider := hit.collider as Node
			if collider != null:
				_register_sample(collider, hit.position, hit.normal)

func _register_sample(collider: Node, point: Vector3, raw_normal: Vector3) -> void:
	var normal := raw_normal.normalized()
	var normal_key := "%d_%d_%d" % [roundi(normal.x * 4.0), roundi(normal.y * 4.0), roundi(normal.z * 4.0)]
	var key := "%d:%s" % [collider.get_instance_id(), normal_key]
	if not tracks.has(key):
		var stable_normal := Vector3(roundf(normal.x * 4.0) / 4.0, roundf(normal.y * 4.0) / 4.0, roundf(normal.z * 4.0) / 4.0).normalized()
		tracks[key] = {"id": key, "name": collider.name, "origin": point, "normal": stable_normal, "basis": Basis(Quaternion(Vector3.UP, stable_normal)), "points": [], "overlay": null, "last_seen": Time.get_ticks_msec() / 1000.0, "state": "tracked", "published": false}
	var track: Dictionary = tracks[key]
	track.last_seen = Time.get_ticks_msec() / 1000.0
	track.state = "tracked"
	var samples: Array = track.points
	for sample: Vector3 in samples:
		if sample.distance_to(point) < POINT_MERGE_DISTANCE:
			return
	samples.append(point)
	track.points = samples
	if samples.size() >= MIN_PLANE_POINTS and _update_plane_visual(track):
		var data := _plane_data(track)
		if not track.published:
			track.published = true
			plane_added.emit(data)
		else:
			plane_updated.emit(data)

func _update_track_lifetimes() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for key in tracks.keys():
		var track: Dictionary = tracks[key]
		var age: float = now - float(track.last_seen)
		if age >= REMOVE_AFTER_SECONDS:
			if track.published:
				plane_removed.emit(str(track.id))
			if track.overlay != null and is_instance_valid(track.overlay):
				track.overlay.queue_free()
			tracks.erase(key)
		elif age >= PAUSE_AFTER_SECONDS and track.state != "paused":
			track.state = "paused"
			if track.published:
				plane_updated.emit(_plane_data(track))

func _plane_data(track: Dictionary) -> PlaneData:
	var data := PlaneData.new()
	var overlay: MeshInstance3D = track.overlay
	data.id = str(track.id)
	data.name = str(track.name)
	data.transform = overlay.global_transform if overlay != null else Transform3D.IDENTITY
	data.extent = (overlay.mesh as PlaneMesh).size if overlay != null else Vector2.ZERO
	data.alignment = "horizontal" if absf(track.normal.y) > 0.8 else "vertical"
	data.tracking_state = str(track.state)
	data.normal = track.normal
	return data

func _update_plane_visual(track: Dictionary) -> bool:
	var basis: Basis = track.basis
	var origin: Vector3 = track.origin
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for sample: Vector3 in track.points:
		var local_point: Vector3 = basis.inverse() * (sample - origin)
		min_x = minf(min_x, local_point.x)
		max_x = maxf(max_x, local_point.x)
		min_z = minf(min_z, local_point.z)
		max_z = maxf(max_z, local_point.z)
	var width := max_x - min_x
	var depth := max_z - min_z
	if width < MIN_PLANE_EXTENT or depth < MIN_PLANE_EXTENT:
		return false
	var center := origin + basis * Vector3((min_x + max_x) * 0.5, 0.008, (min_z + max_z) * 0.5)
	var overlay := track.overlay as MeshInstance3D
	if overlay == null:
		overlay = _create_plane_visual(str(track.name))
		planes_root.add_child(overlay)
		track.overlay = overlay
	overlay.global_position = center
	overlay.basis = basis
	(overlay.mesh as PlaneMesh).size = Vector2(width, depth)
	overlay.visible = visualization_enabled
	return true

func _create_plane_visual(surface_name: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = surface_name + "_DetectedPlane"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.25, 0.25)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.85, 1.0, 0.18)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	var label := Label3D.new()
	label.text = surface_name + " plane"
	label.font_size = 32
	label.pixel_size = 0.0025
	label.position.y = 0.015
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_instance.add_child(label)
	return mesh_instance

func get_detected_planes() -> Array[PlaneData]:
	var result: Array[PlaneData] = []
	for track: Dictionary in tracks.values():
		if track.published:
			result.append(_plane_data(track))
	return result

func set_plane_visualization_enabled(enabled: bool) -> void:
	visualization_enabled = enabled
	if planes_root != null:
		planes_root.visible = enabled

func raycast_from_screen(screen_position: Vector2) -> ARHit:
	if not session_running or camera == null or not is_instance_valid(camera):
		return null
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * RAY_LENGTH)
	if player != null and is_instance_valid(player):
		query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit.collider as Node
	var plane_id := ""
	if collider != null:
		for key in tracks:
			var track: Dictionary = tracks[key]
			if key.begins_with("%d:" % collider.get_instance_id()) and track.normal.dot(hit.normal.normalized()) > 0.9 and track.published:
				plane_id = str(key)
				break
	var result := ARHit.new()
	result.position = hit.position
	result.normal = hit.normal.normalized()
	result.plane_id = plane_id
	result.collider = collider
	return result
