extends Node3D
## The ring. Static meshes (canvas, apron, posts, ropes, floor) are lightmap-baked with the
## LightmapGI node; the corner lights are bake-only, so baked lighting costs nothing per frame.
## The crowd is generated here as one MultiMesh (a single draw call), from a fixed seed so it
## looks the same every time.

const CROWD_SEED := 1280
const CROWD_PER_TIER := 90
const TIERS := 3
const FIRST_TIER_RADIUS := 7.0
const TIER_STEP := 1.6
const TIER_RISE := 0.7


func _ready() -> void:
	add_child(_make_crowd())


static func _make_crowd() -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 1.1
	mesh.radial_segments = 6
	mesh.rings = 1
	# Dark silhouettes so the crowd frames the fight without competing with it.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.13)
	mat.roughness = 1.0
	mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = CROWD_PER_TIER * TIERS
	var i := 0
	for tier in TIERS:
		var radius := FIRST_TIER_RADIUS + tier * TIER_STEP
		for n in CROWD_PER_TIER:
			var angle := TAU * (n + rng.randf_range(-0.3, 0.3)) / CROWD_PER_TIER
			var pos := Vector3(cos(angle) * radius, -0.6 + tier * TIER_RISE, sin(angle) * radius)
			var facing := Transform3D(Basis(), pos).looking_at(Vector3(0, pos.y, 0), Vector3.UP)
			mm.set_instance_transform(i, facing.scaled_local(Vector3.ONE * rng.randf_range(0.85, 1.15)))
			i += 1

	var node := MultiMeshInstance3D.new()
	node.name = "Crowd"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return node
