extends Node

func _ready() -> void:
	if OS.get_name() in ["Android", "iOS"]:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/mobile/mobile_ar.tscn")
	else:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/desktop/desktop_simulator.tscn")
