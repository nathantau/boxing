shader_type canvas_item;
// A bright band sweeping across the logo every few seconds.
uniform float speed = 420.0;
uniform float period = 3600.0;
varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float x = local.x - local.y * 0.6;
	float t = mod(TIME * speed, period) - 300.0;
	float band = 1.0 - smoothstep(0.0, 70.0, abs(x - t));
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), band * 0.7);
}
