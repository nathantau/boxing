# PLAN — 1v1 PvP Boxing (Godot 4.7.2 + netfox 1.35.3)

## Stack (pinned)
| Piece | Version | Notes |
|---|---|---|
| Godot | 4.7.2-stable, standard build (not .NET) | Mobile renderer, GDScript only |
| netfox | v1.35.3 (`netfox` + `netfox.internals`) | Latest release. `main` has post-release fixes but no tag yet; we stay on the release unless we hit one of those bugs |
| GUT | 9.7.1 | The first release that supports Godot 4.7's stricter return typing |
| Xcode | 27.1 (installed), iOS SDK 27.1 | An Apple Development signing identity is already in the keychain |

**netfox ⇄ Godot 4.7 caveats (found in research):**
- On Godot 4.6+, a fresh import fails to compile netfox's autoloads if `project.godot` registers them by `uid://` (netfox PR #659). Workaround: keep the autoload paths as `res://` in `project.godot`, which we edit as text anyway. CI and headless runs need this.
- Four netfox float16 schema tests fail on 4.7. We don't use float16 schemas, so this doesn't affect us.
- netfox's built-in NetworkSimulator only runs inside the editor and only supports latency and loss, with no jitter. We build our own lag layer instead (see Netcode).

## Architecture

```
res://
  sim/            Pure deterministic core. No Nodes, no floats, no netfox.
    fixed.gd        integer helpers (clamp, mul/div in milli-units)
    move_data.gd    MoveData Resource (one row per move)
    moves.tres      ← ALL frame data and balance numbers live here (text, editable)
    fighter_state.gd  int fields only
    match_state.gd    two fighters + round/timer/score, to_array()/from_array(), hash()
    sim.gd          static step(state, in_a: int, in_b: int, data) -> state
    input_bits.gd   packed input (one int per tick)
  game/           Godot-side adapters
    match_runner.gd   drives sim.step: local loop (offline) or netfox _rollback_tick (online)
    input/            KeyboardSource, GamepadSource, TouchSource, AISource → InputBits
    presentation/     BoxerView, CameraRig, HUD, FX/Audio/Haptics (read sim state, never write it)
  net/
    network_transport.gd  interface: host(port), join(ip, port), close(), signals
    enet_transport.gd     Phase 1 implementation
    lag_peer.gd           MultiplayerPeerExtension that wraps the real peer: latency, jitter, loss
  ui/             menus, host/join, results, debug overlay
  tests/          GUT: unit tests for the sim + determinism replay test
```

### Deterministic sim
- Fixed 60 Hz tick. The netfox tickrate is 60, and offline play uses the same fixed-step accumulator. Rendering is decoupled from it.
- All simulated state is `int`. Distances are in milli-units, health and stamina use ×10 scaling, and timers count ticks. There are no `float`s, `Vector3`s, physics, or RNG in `sim/`. If we ever need randomness, it's a seeded LCG stored in state.
- Hit detection is rules-driven, not geometric. A move's active frame checks the defender's state against the move's flags (`blockable`, `dodged_by: L/R/both`, `parry_window`, `hits_dodge_recovery`, and so on). Spacing is a single int range check.
- `MatchState.hash()` is FNV-1a over the packed int array, which is the same on every platform.
- **One sim step for both fighters.** Each tick resolves both fighters at the same time (trades, parries) in a fixed order, so the result never depends on node order.

### Move data (`moves.tres`, text Resource)
Per move: `startup, active, recovery, damage, chip_damage, stamina_cost, hitstun, blockstun, block_stamina_drain, parry_window, on_parry_stagger, dodge_flags, …`
Global constants (stamina regen and exhaustion threshold, knockdown threshold, round length, counter-window length) live in the same file.
Moves: jab, hook (L/R), uppercut, block (hold), dodge L/R, parry (an attack swipe timed within `parry_window` ticks of the incoming punch's first active frame).

### Presentation (stays correct after rollback)
- Visuals are a pure function of `(state_id, ticks_in_state)`. Each render frame, the AnimationPlayer is *seeked* to the exact time, so a rollback fixes the pose on the next frame.
- One-shot effects (hit spark, sound, camera shake, haptic) come from **sim events keyed by `(tick, fighter, kind)`** and are deduped. A resimulation that produces the same event doesn't fire it twice. An event that rollback cancels is dropped before it plays, if it hasn't played yet.

### Netcode (how netfox actually works, and what that means)
netfox is **server-authoritative with client-side prediction and rollback**. It is not GGPO-style symmetric peer-to-peer. In Phase 1 the **host device is the server and also a player**:
- Each player owns an input node (`input_properties` = a single packed int). The host owns the `MatchState` node (`state_properties` = the packed int array).
- Clients predict with their own input plus the opponent's predicted input (the last held buttons repeat, and one-off taps aren't repeated). They roll back when the host's authoritative state arrives.
- What this means for you: the host plays with zero input latency, and the joiner gets corrections. On a LAN that's barely noticeable. A dedicated headless server (later) removes the asymmetry and needs no gameplay changes, because only `NetworkTransport` changes.
- **Spike at the start of M5:** confirm the cleanest way to give one shared `MatchState` node two input owners in netfox 1.35. One RollbackSynchronizer per fighter input plus a match-level synchronizer is the expected answer. The sim core doesn't change either way.
- Settings: tickrate 60, a small input delay (default 1–2 ticks, tunable), history limit about 64 ticks, and prediction enabled.
- Input gathering is buffered between ticks: one-off actions (swipes, dodge starts) are latched and cleared after one tick, as the netfox docs recommend.
- **Debug overlay:** ping (round-trip time), rollbacks per second (counted from `NetworkRollback.before_loop` when resim depth > 0), resim depth, fps, and sliders for latency, jitter, and loss. The sliders drive `lag_peer.gd`, so they also work on iPhone builds.
- **Disconnect and backgrounding:** on a disconnect or `NOTIFICATION_APPLICATION_PAUSED`, both sides pause the tick loop and show "Reconnecting… 10". The client auto-rejoins the last IP. A new peer ID means re-assigning input authority and calling `process_authority()` on both peers. When the countdown ends, both players return to the menu with a reason message.
- No broadcast or multicast. The host screen shows its LAN IPv4 address and port in large text, and the join screen remembers the last IP (`user://settings.cfg`). `NSLocalNetworkUsageDescription` goes in via the iOS export's additional plist content.

### Controls
- Touch (`TouchSource`) has three zones:
  - Center zone: a swipe picks the move (forgiving thresholds by angle and length). Up = jab, left/right diagonal = hook L/R, a down-then-up stroke = uppercut. If an attack swipe lands in the parry window, it counts as a parry.
  - Left and right edges: holding there dodges.
  - Shield button (≥ 88 pt) in the lower corner: block.
- Landscape only, with safe-area insets from `DisplayServer.get_display_safe_area()`.
- Haptics use `Input.vibrate_handheld(ms, amplitude)`, which is built in, so no plugin is needed.
- Keyboard: two key sets (P1 WASD+FGHR, P2 arrows+JKL;). Gamepad works through the InputMap. Every source outputs the same InputBits int.

### Rendering and performance
Mobile renderer, one small arena with baked lightmaps (LightmapGI), low-poly boxers, and a target of under 100 draw calls. The debug overlay shows fps, draw calls, and frame time, and we do a 15-minute soak test on device to check thermal throttling.

## Milestones (each one: run headless and check for errors → summary → hand-test list)
1. **Skeleton.** Project and autoload setup, the `sim/` core with a stub move set, capsule boxers, a local 1v1 on the Mac with two keyboard/gamepad sets, the GUT suite, and the determinism replay test.
2. **iOS early.** Export preset (landscape, safe area, plist entries), Xcode project generation, step-by-step signing with your Apple ID, then touch controls on device.
3. **Full combat.** All moves with frame data, health and stamina, exhaustion, parry, stagger and counter window, hitstun, blockstun, knockdown, best of 3, and the HUD.
4. **AI opponent.** An `AISource` that produces InputBits (reactive blocking and dodging, with tunable difficulty). It's deterministic because it reads sim state and uses no RNG unless that RNG is seeded.
5. **LAN rollback.** Spike, then `NetworkTransport`/ENet, `lag_peer`, overlay, and reconnect. Tested Mac↔Mac → Mac↔iPhone → iPhone↔iPhone.
6. **Menus.** Main menu, host and join screens, round results and rematch.
7. **Art and feel.** Mixamo characters and animations (with an exact download list and import steps), hit effects, sound hooks, camera shake, and haptics.

## Decisions I need from you
1. **netfox.extras**: it provides `BaseNetInput` and a rewindable state machine. It's from the same project as netfox, but it's a separate addon. My plan is to **skip it** (our input node and sim are small and custom), so the only addons are netfox core and GUT. Is that OK?
2. **Project folder**: `~/Documents/programming/boxing/`, with `git init` there. OK?
