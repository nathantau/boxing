class_name ENetTransport
extends NetworkTransport
## LAN transport: one device hosts an ENet server for exactly one opponent, the other joins by IP.
## Wrapped in a LagPeer so the debug overlay can simulate bad networks.

## ENet's own timeout: notice a dead connection within a few seconds instead of 30.
const TIMEOUT_MIN_MS := 2000
const TIMEOUT_MAX_MS := 4000

var _enet: ENetMultiplayerPeer
var _lag: LagPeer
var _is_host := false
var _remote_id := 0
var _latency_ms := 0
var _jitter_ms := 0
var _loss_percent := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(func() -> void: connect_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: _on_peer_disconnected(1))


func host(port: int) -> Error:
	close()
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_server(port, 1)
	if err != OK:
		_enet = null
		return err
	_is_host = true
	_install()
	return OK


func join(address: String, port: int) -> Error:
	close()
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_client(address, port)
	if err != OK:
		_enet = null
		return err
	_is_host = false
	_install()
	return OK


func close() -> void:
	# Forget the peer first so the disconnect signals this causes aren't reported as a drop.
	_remote_id = 0
	if _lag != null:
		_lag.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_enet = null
	_lag = null


func is_connected_to_peer() -> bool:
	return _remote_id != 0


func remote_peer_id() -> int:
	return _remote_id


func set_lag(latency_ms: int, jitter_ms: int, loss_percent: float) -> void:
	_latency_ms = latency_ms
	_jitter_ms = jitter_ms
	_loss_percent = loss_percent
	if _lag != null:
		_lag.latency_ms = latency_ms
		_lag.jitter_ms = jitter_ms
		_lag.loss_percent = loss_percent


func _install() -> void:
	_lag = LagPeer.new(_enet)
	set_lag(_latency_ms, _jitter_ms, _loss_percent)
	multiplayer.multiplayer_peer = _lag


func _on_peer_connected(id: int) -> void:
	# A host accepts one opponent; a client only ever sees the host (id 1).
	if _remote_id != 0:
		return
	_remote_id = id
	var enet_peer := _enet.get_peer(id) if _enet != null else null
	if enet_peer != null:
		enet_peer.set_timeout(0, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if id != _remote_id:
		return
	_remote_id = 0
	if not _is_host:
		close()
	peer_left.emit(id)
