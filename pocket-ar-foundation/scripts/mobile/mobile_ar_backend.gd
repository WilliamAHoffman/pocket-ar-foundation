extends ARBackend
class_name MobileARBackend

## Adapter around PocketAR's ARView. PocketAR retains ownership of the native
## ARCore/ARKit session; this class translates its public facade into our contract.
var ar_view: ARView
var plane_visualizer: ARPlaneVisualizer
var host: Control
var placement_manager: PlacementManager
var visualization_enabled := true
var _known_planes: Dictionary = {}

func configure(host_control: Control, shared_placements: PlacementManager) -> void:
	host = host_control
	placement_manager = shared_placements

func start_session() -> void:
	if host == null:
		push_error("MobileARBackend.configure() must be called before start_session()")
		return
	if ar_view != null:
		if OS.get_name() == "Android" and Engine.has_singleton("PocketARPlugin"):
			Engine.get_singleton("PocketARPlugin").requestSession()
		return
	ar_view = preload("res://addons/pocketar/ar_view.tscn").instantiate() as ARView
	ar_view.name = "PocketARView"
	ar_view.plane_finding_mode = PocketAR.PLANE_FINDING_HORIZONTAL_AND_VERTICAL
	match OS.get_name():
		"iOS": ar_view.backend = ARView.Backend.ARKIT
		"Android": ar_view.backend = ARView.Backend.ARCORE
		_:
			ar_view.backend = ARView.Backend.SYNTHETIC
	ar_view.composition = ARView.Composition.IN_SCENE
	ar_view.handle_presses = true
	ar_view.session_state_changed.connect(_on_session_state_changed)
	ar_view.session_generation_changed.connect(_on_session_generation_changed)
	ar_view.planes_changed.connect(_sync_planes)
	host.add_child(ar_view)
	ar_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if placement_manager != null:
		placement_manager.reparent(ar_view.scene_root)
	plane_visualizer = ARPlaneVisualizer.new()
	plane_visualizer.name = "PlaneVisualizer"
	plane_visualizer.ar_view = ar_view
	ar_view.scene_root.add_child(plane_visualizer)
	plane_visualizer.visible = visualization_enabled
	_sync_planes()

func stop_session() -> void:
	if ar_view == null:
		return
	ar_view.suspended = true
	session_state_changed.emit("stopped")

func reset_session() -> void:
	if ar_view != null:
		ar_view.reset()

func get_detected_planes() -> Array[PlaneData]:
	_sync_planes()
	var result: Array[PlaneData] = []
	for value: PlaneData in _known_planes.values():
		result.append(value)
	return result

func raycast_from_screen(screen_position: Vector2) -> ARHit:
	if ar_view == null:
		return null
	var hits: Array[ARRaycastHit] = ar_view.raycast(screen_position)
	if hits.is_empty():
		return null
	var native_hit: ARRaycastHit = hits[0]
	var result := ARHit.new()
	result.position = native_hit.pose.origin
	result.normal = native_hit.pose.basis.y.normalized()
	result.plane_id = str(native_hit.get("plane_id")) if native_hit.get("plane_id") != null else ""
	return result

func set_plane_visualization_enabled(enabled: bool) -> void:
	visualization_enabled = enabled
	if plane_visualizer != null:
		plane_visualizer.visible = enabled

func _on_session_state_changed(state: int) -> void:
	var state_names := ClassDB.class_get_enum_constants("PocketAR", "SessionState")
	var label := state_names[state] if state >= 0 and state < state_names.size() else "unknown"
	session_state_changed.emit(str(label).to_lower())
	_sync_planes()

func _on_session_generation_changed(_generation: int) -> void:
	_known_planes.clear()
	if placement_manager != null:
		placement_manager.clear()
	_sync_planes()

func _sync_planes() -> void:
	if ar_view == null:
		return
	var packet: ARFramePacket = ar_view.applied_packet
	var seen: Dictionary = {}
	if packet != null:
		for native_plane: Dictionary in packet.planes:
			if native_plane.subsumed_by != 0:
				continue
			var id := str(native_plane.plane_id)
			var data := PlaneData.new()
			data.id = id
			data.name = "Plane " + id
			data.transform = native_plane.transform
			data.normal = native_plane.transform.basis.y.normalized()
			data.alignment = "horizontal" if absf(data.normal.y) > 0.8 else "vertical"
			data.tracking_state = "tracked" if native_plane.tracking_state == ARPlaneTracker.TRACKING else "paused"
			data.extent = native_plane.extents
			seen[id] = true
			if not _known_planes.has(id):
				_known_planes[id] = data
				plane_added.emit(data)
			else:
				var previous: PlaneData = _known_planes[id]
				var changed := previous.transform != data.transform or previous.extent != data.extent or previous.tracking_state != data.tracking_state or previous.normal != data.normal
				_known_planes[id] = data
				if changed:
					plane_updated.emit(data)
	for old_id in _known_planes.keys():
		if not seen.has(old_id):
			_known_planes.erase(old_id)
			plane_removed.emit(str(old_id))
