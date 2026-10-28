class_name SoundBank
extends Resource
## Sound hooks: one slot per game event. Empty slots are silent, so drop .wav/.ogg files into
## res://game/presentation/sounds.tres (inspector or text) whenever you have them.

@export var punch_whoosh: AudioStream
@export var hit_light: AudioStream
@export var hit_heavy: AudioStream
@export var counter_hit: AudioStream
@export var block: AudioStream
@export var parry: AudioStream
@export var stagger: AudioStream
@export var knockdown: AudioStream
@export var ko: AudioStream
@export var bell: AudioStream
## Random pitch spread so repeated sounds don't sound identical.
@export_range(0.0, 0.3) var pitch_variation := 0.08
