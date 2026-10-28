class_name MergedSource
extends InputSource
## Several input sources acting as one player (keyboard + gamepad + touch).

var _sources: Array[InputSource] = []


func _init(sources: Array[InputSource]) -> void:
	_sources = sources


func observe(state: MatchState) -> void:
	for source in _sources:
		source.observe(state)


func sample() -> void:
	for source in _sources:
		source.sample()


func consume() -> int:
	var bits := 0
	for source in _sources:
		bits |= source.consume()
	return bits
