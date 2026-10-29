extends Node3D
## The ring. Lighting is all real-time and mobile-cheap: one shadowed spotlight over the ring,
## two small coloured corner lights and a dim fill, with depth fog darkening the stands.
## The crowd is generated here as one MultiMesh (a single draw call), from a fixed seed so it
## looks the same every time; its shader adds bobbing and camera flashes on the GPU.

const CROWD_SEED := 1280
const CROWD_PER_TIER := 90
const TIERS := 3
const FIRST_TIER_RADIUS := 7.0
const TIER_STEP := 1.6
const TIER_RISE := 0.7
const SHIRTS := [Color(0.55, 0.12, 0.1), Color(0.12, 0.2, 0.5), Color(0.8, 0.8, 0.78), Color(0.15, 0.15, 0.17),
	Color(0.6, 0.5, 0.15), Color(0.15, 0.4, 0.25), Color(0.4, 0.25, 0.45)]
const SKIN := [Color(0.85, 0.65, 0.5), Color(0.6, 0.42, 0.3), Color(0.35, 0.24, 0.17)]

const CROWD_SHADER := """
shader_type spatial;
render_mode unshaded;
// Instance colour = shirt; instance custom = (skin r, g, b, random seed).
varying vec3 tint;
varying float flash;
void vertex() {
	float seed = INSTANCE_CUSTOM.a;
	bool head = VERTEX.y > 0.92;
	tint = head ? INSTANCE_CUSTOM.rgb : COLOR.rgb;
	VERTEX.y += max(0.0, sin(TIME * (3.0 + seed * 3.0) + seed * 40.0)) * 0.05;
	float slot = floor(TIME * 4.0 + seed * 97.0);
	flash = head && fract(sin(slot * 78.233 + seed * 311.0) * 43758.5453) > 0.996 ? 1.0 : 0.0;
}
void fragment() {
	ALBEDO = tint * tint * 0.08 + vec3(flash * 4.0);  // tint * tint: rough sRGB to linear
}
"""


const SHAFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float strength = 0.012;
void fragment() {
	// Brightest near the lamp, fading toward the canvas; soft at the cone's silhouette.
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = color.rgb * strength * edge * (1.0 - UV.y * 0.7);
}
"""


func _ready() -> void:
	add_child(_make_crowd())
	add_child(_make_light_shaft())
	add_child(_make_dust())


## A faint cone of light under the ring lamp, as if the air were a little hazy.
static func _make_light_shaft() -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 3.2
	cone.height = 7.0
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHAFT_SHADER
	cone.material = mat
	var node := MeshInstance3D.new()
	node.name = "LightShaft"
	node.mesh = cone
	node.position = Vector3(0, 3.5, 0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Dust drifting slowly through the light.
static func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Dust"
	p.amount = 70
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.5, 2.5, 3.5)
	p.position = Vector3(0, 3.0, 0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft_dot()
	mesh.material = mat
	p.mesh = mesh
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	fade.colors = PackedColorArray([Color(1, 0.95, 0.85, 0), Color(1, 0.95, 0.85, 0.5), Color(1, 0.95, 0.85, 0)])
	p.color_ramp = fade
	return p


static func _make_crowd() -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = CROWD_SHADER

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _person_mesh()
	mm.mesh.surface_set_material(0, mat)
	mm.instance_count = CROWD_PER_TIER * TIERS
	var i := 0
	for tier in TIERS:
		var radius := FIRST_TIER_RADIUS + tier * TIER_STEP
		for n in CROWD_PER_TIER:
			var angle := TAU * (n + rng.randf_range(-0.3, 0.3)) / CROWD_PER_TIER
			var pos := Vector3(cos(angle) * radius, -1.2 + tier * TIER_RISE, sin(angle) * radius)
			var facing := Transform3D(Basis(), pos).looking_at(Vector3(0, pos.y, 0), Vector3.UP)
			mm.set_instance_transform(i, facing.scaled_local(Vector3.ONE * rng.randf_range(0.85, 1.15)))
			# Back rows sit further from the ring light, so they're a little darker.
			var shade := 1.0 - 0.2 * tier
			mm.set_instance_color(i, SHIRTS[rng.randi() % SHIRTS.size()] * shade)
			var skin: Color = SKIN[rng.randi() % SKIN.size()] * shade
			mm.set_instance_custom_data(i, Color(skin.r, skin.g, skin.b, rng.randf()))
			i += 1

	var node := MultiMeshInstance3D.new()
	node.name = "Crowd"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return node


## Torso plus head in one surface, feet at y = 0. The shader treats everything above 0.92 as head.
static func _person_mesh() -> ArrayMesh:
	var body := CapsuleMesh.new()
	body.radius = 0.24
	body.height = 0.9
	body.radial_segments = 6
	body.rings = 1
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.24
	head.radial_segments = 6
	head.rings = 3
	var st := SurfaceTool.new()
	st.append_from(body, 0, Transform3D(Basis(), Vector3(0, 0.45, 0)))
	st.append_from(head, 0, Transform3D(Basis(), Vector3(0, 1.06, 0)))
	return st.commit()


## A soft round dot, for particles that shouldn't look like squares.
static func soft_dot() -> GradientTexture2D:
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.gradient = Gradient.new()
	dot.gradient.set_color(0, Color.WHITE)
	dot.gradient.set_color(1, Color(1, 1, 1, 0))
	return dot
