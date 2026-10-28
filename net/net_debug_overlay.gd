class_name NetDebugOverlay
extends CanvasLayer
## Network debug panel: ping, rollbacks per second, prediction depth, stalls, desyncs, and
## sliders for simulated latency / jitter / packet loss (applied through LagPeer, so they work on
## device builds too). Toggle with F2 or the NET button in the top-right corner.

const SAMPLE_USEC := 1_000_000

## The OnlineMatch to report on.
var match: Node

var _panel: PanelContainer
var _info: Label
var _latency: HSlider
var _jitter: HSlider
var _loss: HSlider
var _lag_label: Label
var _toggle: Button
var _rollbacks_per_sec := 0.0
var _last_rollbacks := 0
var _last_sample := 0


func _ready() -> void:
	layer = 10
	_toggle = Button.new()
	_toggle.text = "NET"
	_toggle.custom_minimum_size = Vector2(64, 40)
	_toggle.pressed.connect(func() -> void: visible_panel(not _panel.visible))
	add_child(_toggle)

	_panel = PanelContainer.new()
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	_panel.add_child(box)
	_info = Label.new()
	box.add_child(_info)
	_lag_label = Label.new()
	box.add_child(_lag_label)
	_latency = _slider(box, 0, 300, 5)
	_jitter = _slider(box, 0, 100, 5)
	_loss = _slider(box, 0, 30, 1)
	var reset := Button.new()
	reset.text = "No simulated lag"
	reset.pressed.connect(func() -> void:
		_latency.value = 0
		_jitter.value = 0
		_loss.value = 0)
	box.add_child(reset)

	get_viewport().size_changed.connect(_layout)
	_layout()
	_apply_lag()


func visible_panel(show: bool) -> void:
	_panel.visible = show
	if match != null and match.has_node("MatchView"):
		var view: MatchView = match.get_node("MatchView")
		view.touch.visible = not show


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F2:
		visible_panel(not _panel.visible)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _panel.visible or match == null:
		return
	var session: RollbackSession = match.session
	var now := Time.get_ticks_usec()
	if session != null and now - _last_sample >= SAMPLE_USEC:
		_rollbacks_per_sec = (session.rollbacks - _last_rollbacks) * 1_000_000.0 / maxi(now - _last_sample, 1)
		_last_rollbacks = session.rollbacks
		_last_sample = now
	var lines := PackedStringArray()
	lines.append("%s   peer %d   epoch %d" % ["HOST" if Net.role == Net.Role.HOST else "CLIENT", Net.transport.remote_peer_id(), Net.epoch])
	lines.append("ping %s" % ("%d ms" % match.rtt_ms if match.rtt_ms >= 0.0 else "-"))
	if session != null:
		lines.append("rollbacks %.1f/s   last depth %d   total %d" % [_rollbacks_per_sec, session.last_rollback_depth, session.rollbacks])
		lines.append("predicting %d ticks ahead (max %d)   input delay %d" % [maxi(session.prediction_depth(), 0), RollbackSession.MAX_PREDICTION, session.input_delay])
		lines.append("stalls %d   desyncs %d   tick %d" % [session.stalls, session.desyncs, session.state.tick])
	_info.text = "\n".join(lines)


func _slider(parent: Control, lo: float, hi: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(300, 36)
	slider.value_changed.connect(func(_v: float) -> void: _apply_lag())
	parent.add_child(slider)
	return slider


func _apply_lag() -> void:
	Net.transport.set_lag(int(_latency.value), int(_jitter.value), _loss.value)
	_lag_label.text = "Simulated: +%d ms RTT, jitter %d ms, loss %d%%" % [_latency.value, _jitter.value, _loss.value]


func _layout() -> void:
	var safe := SafeArea.rect(get_viewport())
	_toggle.position = Vector2(safe.end.x - _toggle.custom_minimum_size.x - 8, safe.position.y + safe.size.y * 0.2)
	_panel.position = Vector2(safe.end.x - 360, safe.position.y + safe.size.y * 0.2 + 48)
