class_name NetworkTransport
extends Node
## Everything the game knows about the connection. Phase 1 is ENet on the local network
## (ENetTransport); a relay or dedicated-server transport can replace it later without touching
## gameplay code. Once connected, the scene tree's MultiplayerAPI carries the RPCs.

## Host: a player joined. Client: we connected to the host.
signal peer_joined(peer_id: int)
## The other side went away (left, timed out, or the host closed).
signal peer_left(peer_id: int)
## Client only: the connection attempt failed.
signal connect_failed

const DEFAULT_PORT := 24680


func host(_port: int) -> Error:
	return ERR_UNAVAILABLE


func join(_address: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


func close() -> void:
	pass


func is_connected_to_peer() -> bool:
	return false


## Peer id to send RPCs to: the client for the host, the host (1) for a client.
func remote_peer_id() -> int:
	return 0


## Simulated network conditions for testing (see LagPeer).
func set_lag(_latency_ms: int, _jitter_ms: int, _loss_percent: float) -> void:
	pass


## Addresses another device on the network can use to reach this one.
static func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			result.append(address)
		elif address.begins_with("172."):
			var second := address.get_slice(".", 1).to_int()
			if second >= 16 and second <= 31:
				result.append(address)
	return result
