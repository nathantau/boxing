extends GutTest
## Two RollbackSessions wired through a fake network with latency and packet loss.
## Whatever the network does, both peers must end up with exactly the state an offline
## replay of the same inputs produces.

var moves: MoveSet = preload("res://sim/moves.tres")


class Result:
	var sessions: Array[RollbackSession] = []
	## player -> {tick: input bits that player actually used}
	var inputs: Array[Dictionary] = [{}, {}]


## Runs both peers for `ticks` network ticks, then `settle` more with a perfect network so
## every input arrives. Inputs are pseudo-random presses and holds.
func play(ticks: int, latency: int, loss_pct: int, delay: int, settle := 60) -> Result:
	var r := Result.new()
	for p in 2:
		r.sessions.append(RollbackSession.new(MatchState.create(moves), moves, p, delay))
	var queues: Array[Array] = [[], []]  # packets in flight *to* each player: [arrive_tick, packet]
	var x := 12345 + latency * 7 + loss_pct
	var held := [0, 0]
	for t in ticks + settle:
		var settling := t >= ticks
		for p in 2:
			var session := r.sessions[p]
			# Deliver packets that have arrived.
			var pending: Array = queues[p]
			while not pending.is_empty() and pending[0][0] <= t:
				var pkt: Array = pending.pop_front()[1]
				session.receive(pkt[0], pkt[1], pkt[2])
				session.check_remote_hash(pkt[3], pkt[4])
			# Pick this tick's input.
			x = (x * 1664525 + 1013904223) & 0xFFFFFFFF
			var roll := (x >> 8) % 100
			if settling:
				held[p] = 0
			elif roll < 6:
				held[p] = 1 << ((x >> 16) % 7)
			elif roll < 30:
				held[p] = 0
			if session.advance(held[p]):
				r.inputs[p][session._last_input[p]] = held[p]
			# Send.
			var out := session.outgoing()
			var h := session.latest_hash()
			x = (x * 1664525 + 1013904223) & 0xFFFFFFFF
			if not settling and (x >> 8) % 100 < loss_pct:
				continue
			queues[1 - p].append([t + (0 if settling else latency), [out[0], out[1], out[2], h[0], h[1]]])
	return r


## Offline replay of the inputs both players used: tick -> hash of the state at that tick.
func offline_hashes(r: Result, upto: int) -> Dictionary:
	var s := MatchState.create(moves)
	var hashes := {0: s.state_hash()}
	for t in upto:
		Sim.step(s, r.inputs[0].get(t, 0), r.inputs[1].get(t, 0), moves)
		hashes[s.tick] = s.state_hash()
	return hashes


func assert_matches_offline(r: Result, min_confirmed := 1000) -> void:
	var upto: int = r.sessions[0].state.tick
	var offline := offline_hashes(r, maxi(upto, r.sessions[1].state.tick))
	for p in 2:
		var confirmed := r.sessions[p].confirmed_state()
		var tick := confirmed[0]
		assert_gt(tick, min_confirmed, "player %d confirmed most of the match" % p)
		assert_eq(MatchState.hash_packed(confirmed), offline.get(tick), "player %d state at tick %d matches offline replay" % [p, tick])
		assert_eq(r.sessions[p].desyncs, 0)


func test_lan_conditions() -> void:
	var r := play(1800, 1, 0, 1)
	assert_matches_offline(r)


func test_latency_causes_rollbacks_but_stays_correct() -> void:
	var r := play(1800, 5, 0, 2)
	assert_gt(r.sessions[0].rollbacks + r.sessions[1].rollbacks, 10)
	assert_matches_offline(r)


func test_packet_loss_is_recovered() -> void:
	var r := play(1800, 4, 25, 1)
	assert_matches_offline(r)


func test_high_latency_stalls_instead_of_overpredicting() -> void:
	var r := play(1200, RollbackSession.MAX_PREDICTION + 8, 0, 0)
	assert_gt(r.sessions[0].stalls, 0)
	for p in 2:
		assert_lte(r.sessions[p].last_rollback_depth, RollbackSession.MAX_PREDICTION + 1)
	assert_matches_offline(r, 500)  # stalling means fewer sim ticks than network ticks


func test_desync_is_detected() -> void:
	var a := RollbackSession.new(MatchState.create(moves), moves, 0, 1)
	var b := RollbackSession.new(MatchState.create(moves), moves, 1, 1)
	for t in 400:
		if t == 100:
			b.state.fighters[0].health -= 1  # corrupt one peer
		a.advance(0)
		b.advance(0)
		var out_a := a.outgoing()
		var out_b := b.outgoing()
		b.receive(out_a[0], out_a[1], out_a[2])
		a.receive(out_b[0], out_b[1], out_b[2])
		var ha := a.latest_hash()
		var hb := b.latest_hash()
		a.check_remote_hash(hb[0], hb[1])
		b.check_remote_hash(ha[0], ha[1])
	assert_gt(a.desyncs + b.desyncs, 0)


func test_resume_from_confirmed_state() -> void:
	var r := play(900, 3, 10, 1)
	var resume := r.sessions[0].confirmed_state()
	var state_a := MatchState.new()
	state_a.unpack(resume)
	var state_b := MatchState.new()
	state_b.unpack(resume)
	var a := RollbackSession.new(state_a, moves, 0, 2)
	var b := RollbackSession.new(state_b, moves, 1, 2)
	for t in 300:
		a.advance(InputBits.JAB if t % 40 == 0 else 0)
		b.advance(InputBits.HOOK_L if t % 55 == 0 else 0)
		var out_a := a.outgoing()
		var out_b := b.outgoing()
		b.receive(out_a[0], out_a[1], out_a[2])
		a.receive(out_b[0], out_b[1], out_b[2])
	for t in 20:
		a.advance(0)
		b.advance(0)
		var out_a := a.outgoing()
		var out_b := b.outgoing()
		b.receive(out_a[0], out_a[1], out_a[2])
		a.receive(out_b[0], out_b[1], out_b[2])
	var ca := a.confirmed_state()
	var cb := b.confirmed_state()
	var tick := mini(ca[0], cb[0])
	assert_gt(tick, resume[0] + 250)
	# Both resumed sessions agree on their hashes at every shared checkpoint.
	for t: int in a._hashes:
		if b._hashes.has(t):
			assert_eq(a._hashes[t], b._hashes[t], "checkpoint %d" % t)
	assert_eq(a.desyncs + b.desyncs, 0)
