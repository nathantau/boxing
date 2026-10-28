extends Node
## Online session glue (autoload "Net"): owns the NetworkTransport, the match start/resume
## handshake, the reconnect window and the RPCs. Gameplay code only sees signals.
##
## Start and resume are the same thing: the host picks a network tick a little in the future
## and sends both peers the state to start from (empty = a fresh match). After a reconnect,
## app backgrounding or a desync, that state is the host's newest confirmed state.

signal status_changed(text: String)
## Both peers: start simulating `state` (empty = new match) at NetworkTime tick `start_tick`.
signal match_ready(start_tick: int, state: PackedInt64Array)
signal inputs_received(first_tick: int, bits: PackedByteArray, ack: int, hash_tick: int, hash: int, sent_usec: int, echo_usec: int, hold_usec: int)
## The session is over (gave up reconnecting, opponent left, failed to connect). Show `reason`.
signal session_ended(reason: String)
signal rematch_votes_changed

enum Role { NONE, HOST, CLIENT }

const GRACE_USEC := 10_000_000
const RETRY_USEC := 1_000_000
## How far ahead the host schedules a (re)start, so the RPC arrives in time.
const START_DELAY_TICKS := 30
const SETTINGS_PATH := "user://settings.cfg"

var transport: NetworkTransport = ENetTransport.new()
var role := Role.NONE
var port := NetworkTransport.DEFAULT_PORT
var last_address := ""
## Incremented on every (re)start; packets from an older epoch are ignored.
var epoch := 0
var in_match := false
## Set by OnlineMatch: returns the newest confirmed packed state to resume from.
var confirmed_state_provider := Callable()
## Last reason a session ended, for the menu to show.
var end_reason := ""
var status := ""
## The last start/resume, kept until a match scene picks it up: [start_tick, state].
var pending_start: Array = []

var _rematch_votes := [false, false]

var _lost_at := 0
var _next_retry := 0
var _paused_at := 0


var local_player: int:
	get:
		return 1 if role == Role.CLIENT else 0


func _ready() -> void:
	add_child(transport)
	transport.peer_joined.connect(_on_peer_joined)
	transport.peer_left.connect(_on_peer_left)
	transport.connect_failed.connect(_on_connect_failed)
	NetworkTime.after_client_sync.connect(_on_client_synced)
	_load_settings()


func host(on_port := NetworkTransport.DEFAULT_PORT) -> Error:
	port = on_port
	var err := transport.host(port)
	if err != OK:
		return err
	role = Role.HOST
	in_match = false
	_lost_at = 0
	NetworkTime.start()
	_set_status("Waiting for an opponent on %s" % ", ".join(host_addresses()))
	return OK


func join(address: String, on_port := NetworkTransport.DEFAULT_PORT) -> Error:
	port = on_port
	last_address = address
	_save_settings()
	var err := transport.join(address, port)
	if err != OK:
		return err
	role = Role.CLIENT
	in_match = false
	_lost_at = 0
	_set_status("Connecting to %s:%d…" % [address, port])
	return OK


## End the session. Unless `notify` is false, tell the opponent first so they don't wait
## out the reconnect window.
func leave(reason := "", notify := true) -> void:
	if role == Role.NONE:
		return
	if notify and transport.is_connected_to_peer():
		_bye.rpc_id(transport.remote_peer_id())
		transport.flush()
	role = Role.NONE
	pending_start = []
	in_match = false
	_lost_at = 0
	transport.close()
	NetworkTime.stop()
	end_reason = reason
	_set_status("")
	session_ended.emit(reason)


func host_addresses() -> PackedStringArray:
	var addresses := PackedStringArray()
	for address in NetworkTransport.local_addresses():
		addresses.append("%s:%d" % [address, port])
	return addresses if not addresses.is_empty() else PackedStringArray(["127.0.0.1:%d" % port])


func send_inputs(first_tick: int, bits: PackedByteArray, ack: int, hash_tick: int, hash: int, sent_usec: int, echo_usec: int, hold_usec: int) -> void:
	if not transport.is_connected_to_peer() or not in_match:
		return
	_inputs.rpc_id(transport.remote_peer_id(), epoch, first_tick, bits, ack, hash_tick, hash, sent_usec, echo_usec, hold_usec)


func take_pending_start() -> Array:
	var p := pending_start
	pending_start = []
	return p


func vote_rematch() -> void:
	_vote_rematch.rpc(local_player)


func i_want_rematch() -> bool:
	return _rematch_votes[local_player]


func opponent_wants_rematch() -> bool:
	return _rematch_votes[1 - local_player]


## Ask the host to restart both peers from its confirmed state (after a desync).
func request_resync() -> void:
	if role == Role.HOST:
		_send_start()
	elif transport.is_connected_to_peer():
		_request_resync.rpc_id(1)


func _process(_delta: float) -> void:
	if _lost_at == 0:
		return
	var now := Time.get_ticks_usec()
	var left := GRACE_USEC - (now - _lost_at)
	if left <= 0:
		leave("Opponent disconnected." if role == Role.HOST else "Lost connection to the host.")
		return
	_set_status("Connection lost — reconnecting… %d" % ceili(left / 1_000_000.0))
	if role == Role.CLIENT and not transport.is_connected_to_peer() and now >= _next_retry:
		_next_retry = now + RETRY_USEC
		transport.join(last_address, port)


func _notification(what: int) -> void:
	if role == Role.NONE:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_paused_at = Time.get_ticks_usec()
	elif what == NOTIFICATION_APPLICATION_RESUMED and in_match:
		# iOS suspends sockets in the background, so treat every resume as a reconnect,
		# with the grace window counted from when we were paused.
		_lost_at = _paused_at if _paused_at > 0 else Time.get_ticks_usec()
		NetworkTime.stop()
		if role == Role.HOST:
			transport.host(port)
			NetworkTime.start()
		else:
			transport.close()
			_next_retry = 0


func _on_peer_joined(_peer_id: int) -> void:
	if role == Role.CLIENT:
		_set_status("Syncing clocks…")
		NetworkTime.start()  # The host starts the match once our clock is synced.
	else:
		_set_status("Opponent joined — syncing…")


func _on_client_synced(_peer_id: int) -> void:
	if role == Role.HOST:
		_send_start()


func _on_peer_left(_peer_id: int) -> void:
	if role == Role.NONE:
		return
	if not in_match:
		if role == Role.CLIENT:
			leave("The host closed the game.")
		else:
			_set_status("Waiting for an opponent on %s" % ", ".join(host_addresses()))
		return
	if _lost_at == 0:
		_lost_at = Time.get_ticks_usec()
		_next_retry = _lost_at + RETRY_USEC
	if role == Role.CLIENT:
		NetworkTime.stop()


func _on_connect_failed() -> void:
	if role != Role.CLIENT:
		return
	if _lost_at == 0:
		leave("Couldn't connect to %s:%d." % [last_address, port])


func _send_start(fresh := false) -> void:
	var state := PackedInt64Array()
	if in_match and not fresh and confirmed_state_provider.is_valid():
		state = confirmed_state_provider.call()
	_start.rpc(NetworkTime.tick + START_DELAY_TICKS, state, epoch + 1)


@rpc("authority", "call_local", "reliable")
func _start(start_tick: int, state: PackedInt64Array, new_epoch: int) -> void:
	epoch = new_epoch
	in_match = true
	_lost_at = 0
	_paused_at = 0
	_rematch_votes = [false, false]
	_set_status("")
	pending_start = [start_tick, state]
	match_ready.emit(start_tick, state)


@rpc("any_peer", "call_local", "reliable")
func _vote_rematch(player: int) -> void:
	_rematch_votes[player] = true
	rematch_votes_changed.emit()
	if role == Role.HOST and _rematch_votes[0] and _rematch_votes[1]:
		_send_start(true)


@rpc("any_peer", "call_remote", "reliable")
func _bye() -> void:
	leave("Your opponent left the match.", false)


@rpc("any_peer", "call_remote", "reliable")
func _request_resync() -> void:
	if role == Role.HOST:
		_send_start()


@rpc("any_peer", "call_remote", "unreliable")
func _inputs(packet_epoch: int, first_tick: int, bits: PackedByteArray, ack: int, hash_tick: int, hash: int, sent_usec: int, echo_usec: int, hold_usec: int) -> void:
	if packet_epoch == epoch:
		inputs_received.emit(first_tick, bits, ack, hash_tick, hash, sent_usec, echo_usec, hold_usec)


func _set_status(text: String) -> void:
	if text != status:
		status = text
		status_changed.emit(text)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		last_address = cfg.get_value("net", "last_address", "")


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("net", "last_address", last_address)
	cfg.save(SETTINGS_PATH)
