class_name LagPeer
extends MultiplayerPeerExtension
## Wraps a real MultiplayerPeer and adds artificial latency, jitter and packet loss, so
## worse-than-LAN conditions can be tested on any build, including iPhone. With everything at
## zero it is a pass-through.
##
## latency_ms is added to the round trip (half on send, half on receive). jitter_ms adds up to
## that much extra random delay per packet. loss_percent drops that share of unreliable packets
## on receive (reliable packets are only delayed: dropping them would break ENet's guarantees).
## Reliable and ordered packets are never reordered.

var latency_ms := 0
var jitter_ms := 0
var loss_percent := 0.0

var _inner: MultiplayerPeer
var _rng := RandomNumberGenerator.new()
## Received packets waiting for their release time, sorted by it.
var _incoming: Array[Packet] = []
## Sent packets waiting for their release time, sorted by it.
var _outgoing: Array[Packet] = []
## Latest release time per ordered stream, so ordered packets keep their order.
var _stream_release := {}
var _target_peer := 0
var _transfer_mode := TRANSFER_MODE_RELIABLE
var _transfer_channel := 0


class Packet:
	var data: PackedByteArray
	var peer: int
	var channel: int
	var mode: int
	var release_usec: int


func _init(inner: MultiplayerPeer) -> void:
	_inner = inner
	_rng.randomize()
	# Bound methods, not lambdas: a lambda would keep this peer alive through the inner peer.
	_inner.peer_connected.connect(_on_inner_peer_connected)
	_inner.peer_disconnected.connect(_on_inner_peer_disconnected)


func _on_inner_peer_connected(id: int) -> void:
	peer_connected.emit(id)


func _on_inner_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)


func _poll() -> void:
	_inner.poll()
	var now := Time.get_ticks_usec()
	while _inner.get_available_packet_count() > 0:
		var p := Packet.new()
		p.peer = _inner.get_packet_peer()
		p.channel = _inner.get_packet_channel()
		p.mode = _inner.get_packet_mode()
		p.data = _inner.get_packet()
		if p.mode != TRANSFER_MODE_RELIABLE and loss_percent > 0.0 and _rng.randf() * 100.0 < loss_percent:
			continue
		p.release_usec = _release_time(now, p, "in")
		_insert(_incoming, p)
	_flush_outgoing(now)


func _get_available_packet_count() -> int:
	var now := Time.get_ticks_usec()
	var count := 0
	for p in _incoming:
		if p.release_usec > now:
			break
		count += 1
	return count


func _get_packet_script() -> PackedByteArray:
	return _incoming.pop_front().data if not _incoming.is_empty() else PackedByteArray()


func _get_packet_peer() -> int:
	return _incoming[0].peer if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return _incoming[0].channel if not _incoming.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return (_incoming[0].mode if not _incoming.is_empty() else TRANSFER_MODE_RELIABLE) as TransferMode


func _put_packet_script(buffer: PackedByteArray) -> Error:
	var p := Packet.new()
	p.data = buffer
	p.peer = _target_peer
	p.channel = _transfer_channel
	p.mode = _transfer_mode
	var now := Time.get_ticks_usec()
	p.release_usec = _release_time(now, p, "out")
	_insert(_outgoing, p)
	_flush_outgoing(now)
	return OK


func _get_max_packet_size() -> int:
	return 1 << 20


func _set_transfer_mode(mode: TransferMode) -> void:
	_transfer_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _transfer_mode as TransferMode


func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_target_peer(peer: int) -> void:
	_target_peer = peer


func _get_unique_id() -> int:
	return _inner.get_unique_id()


func _is_server() -> bool:
	return _inner.get_unique_id() == 1


func _is_server_relay_supported() -> bool:
	return _inner.is_server_relay_supported()


func _set_refuse_new_connections(enable: bool) -> void:
	_inner.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _inner.refuse_new_connections


func _get_connection_status() -> ConnectionStatus:
	return _inner.get_connection_status()


func _disconnect_peer(peer: int, force: bool) -> void:
	_inner.disconnect_peer(peer, force)


func _close() -> void:
	_inner.close()
	_incoming.clear()
	_outgoing.clear()


func _release_time(now: int, p: Packet, direction: String) -> int:
	var delay_ms := latency_ms * 0.5
	if jitter_ms > 0:
		delay_ms += _rng.randf() * jitter_ms * 0.5
	var release := now + int(delay_ms * 1000.0)
	if p.mode != TRANSFER_MODE_UNRELIABLE:
		var stream := "%s:%d:%d" % [direction, p.peer, p.channel]
		release = maxi(release, _stream_release.get(stream, 0))
		_stream_release[stream] = release
	return release


func _flush_outgoing(now: int) -> void:
	while not _outgoing.is_empty() and _outgoing[0].release_usec <= now:
		var p: Packet = _outgoing.pop_front()
		_inner.set_target_peer(p.peer)
		_inner.transfer_mode = p.mode as TransferMode
		_inner.transfer_channel = p.channel
		_inner.put_packet(p.data)


static func _insert(queue: Array[Packet], p: Packet) -> void:
	var i := queue.size()
	while i > 0 and queue[i - 1].release_usec > p.release_usec:
		i -= 1
	queue.insert(i, p)
