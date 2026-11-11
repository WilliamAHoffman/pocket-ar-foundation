extends Node3D
class_name PlacementManager
## Shared object placement for desktop simulation and PocketAR mobile tracking.

func place_cube(pose: Transform3D, size: float = 0.1, color: Color = Color.CORAL) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	marker.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	marker.material_override = material
	add_child(marker)
	marker.global_transform = pose
	return marker

func clear() -> void:
	for child in get_children():
		child.queue_free()
