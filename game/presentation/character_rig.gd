class_name CharacterRig
extends Node3D
## A Mixamo character posed straight from the sim state. Every frame AnimationPicker chooses a
## clip and an exact time in it, and the AnimationPlayer is seeked there (it never plays on its
## own), so animation stays locked to frame data and corrects itself instantly after a rollback.
## See res://art/boxer/README.md for which files to download and where they go.

const ART_DIR := "res://art/boxer/"
const ANIM_DIR := "res://art/boxer/anims/"
const EXTENSIONS := ["fbx", "glb", "gltf"]
## Mixamo bone names as Godot imports them (the "mixamorig:" prefix may vary per character).
const HEAD_BONES := ["mixamorig_Head", "mixamorig:Head", "Head"]
const HAND_BONES := ["mixamorig_RightHand", "mixamorig:RightHand", "RightHand"]

var timings: ClipTimings = preload("res://game/presentation/clip_timings.tres")

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _lengths := {}
var _anim_names := {}
var _current := ""


## Path of the model for `file_stem` (e.g. "boxer"), or "" if it hasn't been added yet.
static func find_model(file_stem: String) -> String:
	for ext: String in EXTENSIONS:
		var path := "%s%s.%s" % [ART_DIR, file_stem, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


## Loads the model and every clip found in ANIM_DIR. Returns false if nothing usable loaded.
func setup(model_path: String) -> bool:
	var scene := load(model_path) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.rotation.y = PI  # Mixamo characters face +Z; our boxers face -Z.
	add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	_player = AnimationPlayer.new()
	model.add_child(_player)
	_player.root_node = NodePath("..")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip: String in AnimationPicker.CLIPS:
		var lib := _load_clip(clip)
		if lib == null or lib.get_animation_list().is_empty():
			continue
		var anim_name: StringName = lib.get_animation_list()[0]
		var anim := lib.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if clip in AnimationPicker.LOOPING else Animation.LOOP_NONE
		_player.add_animation_library(clip, lib)
		_anim_names[clip] = "%s/%s" % [clip, anim_name]
		_lengths[clip] = anim.length
	if _lengths.is_empty():
		push_warning("CharacterRig: %s loaded but no clips were found in %s" % [model_path, ANIM_DIR])
	return not _lengths.is_empty()


func show_state(f: FighterState, tick: int, moves: MoveSet) -> void:
	var pick := AnimationPicker.pick(f, tick, moves, _lengths, timings)
	var anim: String = _anim_names.get(pick[0], "")
	if anim == "":
		return
	if anim != _current:
		_player.play(anim)
		_current = anim
	_player.seek(pick[1], true)


func head_position(fallback: Vector3) -> Vector3:
	return _bone_position(HEAD_BONES, fallback)


func hand_position(fallback: Vector3) -> Vector3:
	return _bone_position(HAND_BONES, fallback)


func _bone_position(names: Array, fallback: Vector3) -> Vector3:
	if _skeleton == null:
		return fallback
	for bone_name: String in names:
		var idx := _skeleton.find_bone(bone_name)
		if idx >= 0:
			return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx).origin
	return fallback


## An animation file can be imported either as an AnimationLibrary or (Godot's default) as a
## scene with an AnimationPlayer inside; accept both.
func _load_clip(clip: String) -> AnimationLibrary:
	for ext: String in EXTENSIONS:
		var path := "%s%s.%s" % [ANIM_DIR, clip, ext]
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if res is AnimationLibrary:
			return (res as AnimationLibrary).duplicate(true)
		if res is PackedScene:
			var temp := (res as PackedScene).instantiate()
			var players := temp.find_children("*", "AnimationPlayer", true, false)
			var lib: AnimationLibrary = null
			if not players.is_empty():
				var p := players[0] as AnimationPlayer
				var lib_names := p.get_animation_library_list()
				if not lib_names.is_empty():
					lib = p.get_animation_library(lib_names[0]).duplicate(true)
			temp.free()
			return lib
	return null
