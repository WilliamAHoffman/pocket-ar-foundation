extends RefCounted
class_name PlaneData

## Platform-neutral description of a detected surface.
var id: String = ""
var name: String = ""
var transform: Transform3D = Transform3D.IDENTITY
var extent: Vector2 = Vector2.ZERO
var alignment: String = "unknown"
var tracking_state: String = "tracked"
var normal: Vector3 = Vector3.UP

func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"transform": transform,
		"extent": extent,
		"alignment": alignment,
		"tracking_state": tracking_state,
		"normal": normal
	}
