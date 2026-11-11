extends RefCounted
class_name ARHit

## Platform-neutral result of a screen-space surface query.
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var plane_id: String = ""
var collider: Object

func get_pose(offset: float = 0.0) -> Transform3D:
	var up := normal.normalized()
	return Transform3D(Basis(Quaternion(Vector3.UP, up)), position + up * offset)

func to_dictionary() -> Dictionary:
	return {"position": position, "normal": normal, "plane_id": plane_id, "collider": collider}
