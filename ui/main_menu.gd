extends Control
## Main menu plus the host and join screens (three panels, one visible at a time).

@onready var _main: Control = %MainPanel
@onready var _host: Control = %HostPanel
@onready var _join: Control = %JoinPanel
@onready var _message: Label = %Message
@onready var _difficulty: OptionButton = %Difficulty
@onready var _two_players: Button = %TwoPlayers
@onready var _host_address: Label = %HostAddress
@onready var _host_status: Label = %HostStatus
@onready var _join_address: LineEdit = %JoinAddress
@onready var _join_status: Label = %JoinStatus
@onready var _join_button: Button = %JoinButton
var _settings: SettingsPanel
var _how_to_play: HowToPlayPanel


const DETERMINISM_REQUEST := "user://determinism_check.request"
const DETERMINISM_RESULT := "user://determinism_result.txt"


func _ready() -> void:
	for level_name: String in AISource.LEVEL_NAMES:
		_difficulty.add_item(level_name.capitalize())
	_difficulty.selected = maxi(Game.p2_control, AISource.Level.NORMAL)
	_two_players.visible = not OS.has_feature("mobile")

	%FightCPU.pressed.connect(_on_fight_cpu)
	%Training.pressed.connect(Game.goto.bind(Game.TRAINING))
	%DeterminismCheck.pressed.connect(_on_determinism_check)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_main.get_parent().add_child(_settings)
	_settings.closed.connect(_show.bind(_main))
	%SettingsButton.pressed.connect(func() -> void: _show(_settings))
	_how_to_play = HowToPlayPanel.new()
	_how_to_play.visible = false
	_main.get_parent().add_child(_how_to_play)
	_how_to_play.closed.connect(_show.bind(_main))
	%HowToPlay.pressed.connect(func() -> void: _show(_how_to_play))
	_two_players.pressed.connect(_on_two_players)
	%HostGame.pressed.connect(_on_host)
	%JoinGame.pressed.connect(_show.bind(_join))
	%HostCancel.pressed.connect(_cancel_online)
	%JoinBack.pressed.connect(_cancel_online)
	_join_button.pressed.connect(_on_join)
	_join_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	_join_address.text = Net.last_address

	Net.status_changed.connect(_on_status)
	# Methods, not lambdas, on autoload signals: a method connection goes away with this menu.
	Net.match_ready.connect(_on_match_ready)
	Net.session_ended.connect(_on_session_ended)

	_message.text = Net.end_reason
	Net.end_reason = ""
	_show(_main)

	# Devices that don't take command-line arguments (iOS): drop this file in the app's data folder
	# to run the determinism check at launch; the result is written next to it.
	if FileAccess.file_exists(DETERMINISM_REQUEST):
		DirAccess.remove_absolute(DETERMINISM_REQUEST)
		_on_determinism_check.call_deferred()

	# Testing shortcuts: `-- --host` or `-- --join=ADDRESS` press the buttons for you.
	for arg in OS.get_cmdline_user_args():
		if arg == "--settings":
			_show(_settings)
		elif arg == "--how-to-play":
			_show(_how_to_play)
		elif arg == "--determinism-check":
			print("DETERMINISM ", DeterminismCheck.describe(DeterminismCheck.run(preload("res://sim/moves.tres"))))
			get_tree().quit()
		elif arg == "--host":
			_on_host.call_deferred()
		elif arg.begins_with("--join="):
			_show(_join)
			_join_address.text = arg.get_slice("=", 1)
			_on_join.call_deferred()


func _show(panel: Control) -> void:
	for p in [_main, _host, _join, _settings, _how_to_play]:
		if p != null:
			p.visible = p == panel
	# The controls screen needs the whole height.
	for node: Control in [$SafeMargin/Center/Column/Title, $SafeMargin/Center/Column/Tagline]:
		node.visible = panel != _how_to_play
	if panel == _main:
		%FightCPU.grab_focus.call_deferred()  # a highlighted item from the start, for pads and keys too
	if panel != null:
		_slide_in.call_deferred(panel)
	if panel == _join:
		_join_status.text = ""
		_join_address.grab_focus()


## Items fade and slide in one after another.
func _slide_in(panel: Control) -> void:
	await get_tree().process_frame  # let the containers lay the items out first
	var delay := 0.0
	for child in panel.get_children():
		var item := child as Control
		if item == null or not item.visible:
			continue
		var x := item.position.x
		item.modulate.a = 0.0
		item.position.x = x - 40.0
		var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(item, "modulate:a", 1.0, 0.3).set_delay(delay)
		tween.tween_property(item, "position:x", x, 0.35).set_delay(delay)
		delay += 0.045


func _on_match_ready(_start_tick: int, _state: PackedInt64Array) -> void:
	Game.goto(Game.ONLINE_MATCH)


func _on_determinism_check() -> void:
	_message.text = "Running five minutes of simulated fighting…"
	await get_tree().process_frame
	await get_tree().process_frame
	var result := DeterminismCheck.run(preload("res://sim/moves.tres"))
	_message.text = "Determinism: %s\nEvery device on this build must show the same numbers." % DeterminismCheck.describe(result)
	var out := FileAccess.open(DETERMINISM_RESULT, FileAccess.WRITE)
	if out:
		out.store_line(DeterminismCheck.describe(result))


func _on_fight_cpu() -> void:
	Game.p2_control = _difficulty.selected
	if not Settings.seen_how_to_play:
		Settings.seen_how_to_play = true
		_show(_how_to_play)
		_how_to_play.open_then(Game.goto.bind(Game.LOCAL_MATCH))
		return
	Game.goto(Game.LOCAL_MATCH)


func _on_two_players() -> void:
	Game.p2_control = -1
	Game.goto(Game.LOCAL_MATCH)


func _on_host() -> void:
	var err := Net.host()
	if err != OK:
		_message.text = "Couldn't host on port %d (%s). Is another copy already hosting?" % [Net.port, error_string(err)]
		return
	_host_address.text = "\n".join(Net.host_addresses())
	_on_status(Net.status)
	_show(_host)


func _on_join() -> void:
	var text := _join_address.text.strip_edges()
	if text == "":
		_join_status.text = "Type the address shown on the host's screen."
		return
	var address := text
	var port := NetworkTransport.DEFAULT_PORT
	if text.contains(":"):
		address = text.get_slice(":", 0)
		port = text.get_slice(":", 1).to_int()
	if not address.is_valid_ip_address():
		_join_status.text = "That doesn't look like an IP address (e.g. 192.168.1.20)."
		return
	var err := Net.join(address, port)
	if err != OK:
		_join_status.text = "Couldn't start connecting (%s)." % error_string(err)
		return
	_join_button.disabled = true


func _cancel_online() -> void:
	Net.leave()
	_join_button.disabled = false
	_show(_main)


func _on_status(text: String) -> void:
	if Net.role == Net.Role.HOST:
		_host_status.text = "Opponent joined — starting…" if text.begins_with("Opponent") else "Waiting for your opponent to join…"
	else:
		_join_status.text = text


func _on_session_ended(reason: String) -> void:
	_join_button.disabled = false
	if _join.visible and reason != "":
		_join_status.text = reason
		return
	_message.text = reason
	_show(_main)
