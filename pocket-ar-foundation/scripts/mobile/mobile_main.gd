extends Control

## Mobile-facing UI. AR work is delegated to MobileARBackend; placement is shared.
var backend: MobileARBackend
var placements: PlacementManager
@onready var panel: PanelContainer = $Panel
@onready var status: Label = $Panel/Controls/Status
@onready var start_button: Button = $Panel/Controls/Buttons/Start
@onready var reset_button: Button = $Panel/Controls/Buttons/Reset
@onready var planes_button: CheckButton = $Panel/Controls/Planes

func _ready() -> void:
	start_button.pressed.connect(_start)
	reset_button.pressed.connect(_reset)
	planes_button.toggled.connect(_on_planes_toggled)
	reset_button.disabled = true
	planes_button.disabled = true
	status.text = "Tap Start to initialize AR."

func _start() -> void:
	if backend == null:
		placements = PlacementManager.new()
		placements.name = "Placements"
		add_child(placements)
		backend = MobileARBackend.new()
		backend.name = "MobileARBackend"
		add_child(backend)
		backend.configure(self, placements)
		backend.session_state_changed.connect(_on_backend_state_changed)
		backend.start_session()
		await get_tree().process_frame
		if backend.ar_view != null:
			panel.reparent(backend.ar_view.hud)
			backend.ar_view.screen_pressed.connect(_on_screen_pressed)
			reset_button.disabled = false
			planes_button.disabled = false
			backend.set_plane_visualization_enabled(planes_button.button_pressed)
			_update_status()
	else:
		backend.start_session()
		if backend.ar_view != null:
			backend.ar_view.suspended = false
		_update_status()

func _on_screen_pressed(point: Vector2, _ray: Dictionary) -> void:
	var hit := backend.raycast_from_screen(point)
	if hit == null:
		return
	placements.place_cube(hit.get_pose(0.05))

func _on_planes_toggled(enabled: bool) -> void:
	if backend != null:
		backend.set_plane_visualization_enabled(enabled)

func _on_backend_state_changed(_state: String) -> void:
	_update_status()

func _update_status() -> void:
	if backend == null or backend.ar_view == null:
		status.text = "Tap Start to initialize AR."
		return
	var ar := backend.ar_view
	var state_names := ClassDB.class_get_enum_constants("PocketAR", "SessionState")
	var reason_names := ClassDB.class_get_enum_constants("PocketAR", "TrackingReason")
	var state_label := state_names[ar.session_state] if ar.session_state < state_names.size() else "UNKNOWN"
	var reason_label := reason_names[ar.tracking_reason] if ar.tracking_reason < reason_names.size() else "UNKNOWN"
	var instruction := "Move the phone slowly to find a plane."
	if ar.session_state == PocketAR.TRACKING:
		instruction = "Tap a detected plane to place a cube."
	elif ar.session_state == PocketAR.PERMISSION_DENIED:
		instruction = "Camera permission denied. Allow Camera in app settings."
	elif ar.session_state == PocketAR.NEEDS_INSTALL:
		instruction = "AR services need installation or an update."
	elif ar.session_state == PocketAR.UNSUPPORTED:
		instruction = "This device does not support AR."
	status.text = "Tracking: %s / %s\n%s" % [state_label, reason_label, instruction]
	start_button.text = "Retry setup"
	start_button.visible = OS.get_name() == "Android" and ar.session_state in [PocketAR.NEEDS_INSTALL, PocketAR.PERMISSION_DENIED, PocketAR.FAILED]

func _reset() -> void:
	if backend != null:
		backend.reset_session()
		placements.clear()
