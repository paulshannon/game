extends Node
## Autoload "Net". Owns the transport; knows nothing about gameplay.
##
## WebSocket is used because it is the one transport that works in both
## native and web exports. Browsers cannot listen for connections, so the
## server is always a native (usually headless) build.

signal connected(peer_id: int)
## The connection attempt failed / the server went away. The dead peer stays
## installed: listeners must free every node that used RPC or replication
## first, and only then call close() (see close_socket()). main.gd does this.
signal connection_failed()
signal disconnected()

var _peer: WebSocketMultiplayerPeer = null


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int, bind_address: String = "*") -> Error:
	_peer = WebSocketMultiplayerPeer.new()
	var err: Error = _peer.create_server(port, bind_address)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	return OK


func join(url: String) -> Error:
	_peer = WebSocketMultiplayerPeer.new()
	var err: Error = _peer.create_client(url)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	return OK


## Starts the WebSocket close handshake but keeps the peer installed (no
## OfflineMultiplayerPeer swap). Safe to call more than once. Two uses:
## - A client leaving on purpose: the multiplayer API keeps polling the peer
##   until the handshake completes, so the server sees a clean disconnect.
## - Right before quitting: replacing multiplayer_peer after nodes have taken
##   part in RPC/replication makes Godot 4.7 release builds log "Attempt to
##   disconnect a nonexistent connection ... tree_exited". Harmless, but noisy.
## Use close() instead only once every node that used RPC/replication is gone.
func close_socket() -> void:
	if _peer != null:
		_peer.close()


func close() -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null


## True only once a real peer is active. Note: with the default offline peer
## Godot reports is_server() == true, which is why gameplay code should check
## the launch role, not this, before connecting.
func is_online() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _on_connected() -> void:
	connected.emit(multiplayer.get_unique_id())


func _on_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	disconnected.emit()
