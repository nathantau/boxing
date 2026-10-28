class_name MatchFx
extends Node3D
## One-shot feedback for MatchEvents: hit sparks, sounds, camera shake and haptics.
## Haptics and big shakes only fire for things that happen to or because of the viewer
## (the player holding this device).

const SPARK_POOL := 8
const HIT_COLOR := Color(1.0, 0.6, 0.2)
const COUNTER_COLOR := Color(1.0, 0.9, 0.3)
const BLOCK_COLOR := Color(0.6, 0.8, 1.0)
const PARRY_COLOR := Color(1.0, 1.0, 1.0)

@export var sounds: SoundBank = preload("res://game/presentation/sounds.tres")

var boxers: Array[BoxerView] = []
var camera: CameraRig
var viewer := 0
var haptics_enabled := true

var _events := MatchEvents.new()
var _sparks: Array[CPUParticles3D] = []
var _next_spark := 0
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0


func _ready() -> void:
	for i in SPARK_POOL:
		var spark := _make_spark()
		add_child(spark)
		_sparks.append(spark)
	for i in 6:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func reset() -> void:
	_events.reset()


func show_state(state: MatchState, moves: MoveSet) -> void:
	for e in _events.collect(state, moves):
		_play(e)


func _play(e: MatchEvents.Event) -> void:
	var mine := e.fighter == viewer
	var theirs := e.fighter == 1 - viewer
	match e.kind:
		MatchEvents.Kind.PUNCH:
			_sound(sounds.punch_whoosh, -6.0)
		MatchEvents.Kind.HIT, MatchEvents.Kind.COUNTER_HIT:
			var counter := e.kind == MatchEvents.Kind.COUNTER_HIT
			_spark(boxers[e.fighter].head_position(), COUNTER_COLOR if counter else HIT_COLOR, 0.6 + e.strength)
			_sound(sounds.counter_hit if counter and sounds.counter_hit else (sounds.hit_heavy if e.strength > 0.6 else sounds.hit_light))
			if mine:  # we got hit
				_shake(0.35 + 0.4 * e.strength)
				_haptic(40 + int(40 * e.strength), 0.8)
			elif theirs:  # we landed it
				_shake(0.12 + 0.2 * e.strength)
				_haptic(20, 0.5 if not counter else 0.9)
		MatchEvents.Kind.BLOCK:
			_spark(boxers[e.fighter].glove_position(), BLOCK_COLOR, 0.5)
			_sound(sounds.block)
			if mine:
				_shake(0.1)
				_haptic(15, 0.35)
		MatchEvents.Kind.PARRY:
			_spark(boxers[e.fighter].glove_position(), PARRY_COLOR, 1.3)
			_sound(sounds.parry)
			if mine or theirs:
				_haptic(30, 1.0)
				_shake(0.2)
		MatchEvents.Kind.STAGGER:
			_sound(sounds.stagger)
		MatchEvents.Kind.KNOCKDOWN:
			_sound(sounds.knockdown)
			_shake(0.6)
			if mine or theirs:
				_haptic(120, 1.0)
		MatchEvents.Kind.KO:
			_sound(sounds.ko)
			_shake(0.8)
			if mine or theirs:
				_haptic(200, 1.0)
		MatchEvents.Kind.ROUND_START, MatchEvents.Kind.ROUND_END:
			_sound(sounds.bell)


func _spark(pos: Vector3, color: Color, size: float) -> void:
	var spark := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	spark.global_position = pos
	spark.color = color
	spark.scale_amount_min = 0.6 * size
	spark.scale_amount_max = 1.2 * size
	spark.restart()


func _sound(stream: AudioStream, volume_db := 0.0) -> void:
	if stream == null:
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-sounds.pitch_variation, sounds.pitch_variation)
	player.play()


func _shake(amount: float) -> void:
	if camera != null:
		camera.add_trauma(amount)


func _haptic(duration_ms: int, amplitude: float) -> void:
	if haptics_enabled:
		Input.vibrate_handheld(duration_ms, amplitude)


static func _make_spark() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 20
	p.lifetime = 0.3
	p.local_coords = false
	p.direction = Vector3(0, 0.3, 1)
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -4, 0)
	p.damping_min = 4.0
	p.damping_max = 6.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = mat
	p.mesh = mesh
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	return p
