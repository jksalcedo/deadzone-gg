class_name NetworkManagerClass
extends Node

signal server_created
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal status_message(message: String, is_error: bool)

const DEFAULT_PORT: int = 7777
const DEFAULT_IP: String = "127.0.0.1"
const DEFAULT_MAX_PLAYERS: int = 8
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const GAME_MAP_SCENE: String = "res://scenes/world.scn"

var peer: ENetMultiplayerPeer = null
var is_singleplayer: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT, max_players: int = DEFAULT_MAX_PLAYERS) -> Error:
	disconnect_peer()
	is_singleplayer = false

	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, max_players)
	if err != OK:
		peer = null
		status_message.emit("Failed to create server on port %d: %s" % [port, error_string(err)], true)
		return err

	multiplayer.multiplayer_peer = peer
	status_message.emit("Server started on port %d. Loading map..." % port, false)
	server_created.emit()
	_load_game_map()
	return OK

func join_game(address: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> Error:
	disconnect_peer()
	is_singleplayer = false

	if address.strip_edges().is_empty():
		address = DEFAULT_IP

	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address.strip_edges(), port)
	if err != OK:
		peer = null
		status_message.emit("Failed to initialize client connection: %s" % error_string(err), true)
		return err

	multiplayer.multiplayer_peer = peer
	status_message.emit("Connecting to %s:%d..." % [address, port], false)
	return OK

func start_singleplayer() -> void:
	disconnect_peer()
	is_singleplayer = true
	status_message.emit("Starting singleplayer mode...", false)
	_load_game_map()

func disconnect_game() -> void:
	disconnect_peer()
	is_singleplayer = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func disconnect_peer() -> void:
	if peer:
		peer.close()
		peer = null
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

func _load_game_map() -> void:
	var err = get_tree().change_scene_to_file(GAME_MAP_SCENE)
	if err != OK:
		status_message.emit("Failed to load map scene: %s" % error_string(err), true)

func _on_connected_to_server() -> void:
	status_message.emit("Connected to server! Loading map...", false)
	connection_succeeded.emit()
	_load_game_map()

func _on_connection_failed() -> void:
	disconnect_peer()
	status_message.emit("Connection to server failed.", true)
	connection_failed.emit()

func _on_server_disconnected() -> void:
	disconnect_peer()
	status_message.emit("Disconnected from server.", true)
	server_disconnected.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_peer_connected(id: int) -> void:
	player_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	player_left.emit(id)
