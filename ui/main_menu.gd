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


func _ready() -> void:
	for level_name: String in AISource.LEVEL_NAMES:
		_difficulty.add_item(level_name.capitalize())
	_difficulty.selected = maxi(Game.p2_control, AISource.Level.NORMAL)
	_two_players.visible = not OS.has_feature("mobile")

	%FightCPU.pressed.connect(_on_fight_cpu)
	%Training.pressed.connect(Game.goto.bind(Game.TRAINING))
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

	# Testing shortcuts: `-- --host` or `-- --join=ADDRESS` press the buttons for you.
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host.call_deferred()
		elif arg.begins_with("--join="):
			_show(_join)
			_join_address.text = arg.get_slice("=", 1)
			_on_join.call_deferred()


func _show(panel: Control) -> void:
	for p in [_main, _host, _join]:
		p.visible = p == panel
	if panel == _join:
		_join_status.text = ""
		_join_address.grab_focus()


func _on_match_ready(_start_tick: int, _state: PackedInt64Array) -> void:
	Game.goto(Game.ONLINE_MATCH)


func _on_fight_cpu() -> void:
	Game.p2_control = _difficulty.selected
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
