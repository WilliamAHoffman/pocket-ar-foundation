extends Node3D
class_name ARBackend

## Platform-neutral contract. Implementations translate native/simulated AR data
## into PlaneData and ARHit objects before exposing them to the application.
signal plane_added(plane_data: PlaneData)
signal plane_updated(plane_data: PlaneData)
signal plane_removed(plane_id: String)
signal session_state_changed(state: String)

func start_session() -> void:
	push_warning("ARBackend.start_session() must be implemented by a backend")

func stop_session() -> void:
	push_warning("ARBackend.stop_session() must be implemented by a backend")

func get_detected_planes() -> Array[PlaneData]:
	return []

func raycast_from_screen(_screen_position: Vector2) -> ARHit:
	return null

func set_plane_visualization_enabled(_enabled: bool) -> void:
	pass
