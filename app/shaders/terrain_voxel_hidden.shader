// Hidden (god-mode ghost) variant of terrain_voxel: flat vertex color,
// alpha from the material's albedo uniform.
shader_type spatial;
render_mode async_visible,blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
uniform vec4 albedo : hint_color;

uniform float specular;
uniform float metallic;
uniform float roughness : hint_range(0,1);
uniform float point_size : hint_range(0,128);
uniform sampler2D texture_emission : hint_black_albedo;
uniform vec4 emission : hint_color;
uniform float emission_energy;
uniform bool tint_emission = true;
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;


void vertex() {
	UV=UV*uv1_scale.xy+uv1_offset.xy;
}




vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 color = srgb_to_linear(clamp(COLOR.rgb, 0.0, 1.0));
	ALBEDO = color * albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	EMISSION = (tint_emission ? emission.rgb * mix(color, vec3(1.0), 0.2) : emission.rgb) * emission_energy;
	ALPHA = albedo.a;
}
