class_name MainMenu
extends Control

@export var singleplayer_btn: Button
@export var host_btn: Button
@export var join_btn: Button
@export var ip_input: LineEdit
@export var port_input: LineEdit
@export var status_label: Label
@export var quit_btn: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if not singleplayer_btn:
		singleplayer_btn = find_child("SingleplayerBtn", true, false) as Button
	if not host_btn:
		host_btn = find_child("HostBtn", true, false) as Button
	if not join_btn:
		join_btn = find_child("JoinBtn", true, false) as Button
	if not ip_input:
		ip_input = find_child("IPInput", true, false) as LineEdit
	if not port_input:
		port_input = find_child("PortInput", true, false) as LineEdit
	if not status_label:
		status_label = find_child("StatusLabel", true, false) as Label
	if not quit_btn:
		quit_btn = find_child("QuitBtn", true, false) as Button

	if singleplayer_btn:
		singleplayer_btn.pressed.connect(_on_singleplayer_pressed)
	if host_btn:
		host_btn.pressed.connect(_on_host_pressed)
	if join_btn:
		join_btn.pressed.connect(_on_join_pressed)
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_pressed)

	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_signal("status_message"):
		nm.status_message.connect(_on_status_message)

func _get_port() -> int:
	if port_input and not port_input.text.strip_edges().is_empty():
		var val = port_input.text.to_int()
		if val > 0 and val <= 65535:
			return val
	return NetworkManagerClass.DEFAULT_PORT

func _get_ip() -> String:
	if ip_input and not ip_input.text.strip_edges().is_empty():
		return ip_input.text.strip_edges()
	return NetworkManagerClass.DEFAULT_IP

func _on_singleplayer_pressed() -> void:
	_set_status("Starting Singleplayer...", false)
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.start_singleplayer()

func _on_host_pressed() -> void:
	var port = _get_port()
	_set_status("Starting server on port %d..." % port, false)
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.host_game(port)

func _on_join_pressed() -> void:
	var ip = _get_ip()
	var port = _get_port()
	_set_status("Connecting to %s:%d..." % [ip, port], false)
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.join_game(ip, port)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_status_message(message: String, is_error: bool) -> void:
	_set_status(message, is_error)

func _set_status(message: String, is_error: bool) -> void:
	if status_label:
		status_label.text = message
		status_label.modulate = Color(0.45, 0.45, 0.45, 1.0) if is_error else Color(0.85, 0.85, 0.85, 1.0)
