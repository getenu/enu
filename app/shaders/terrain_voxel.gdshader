shader_type spatial;
render_mode blend_mix,depth_draw_always,cull_back,diffuse_burley,specular_schlick_ggx;

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color;
uniform float specular;
uniform float metallic;
uniform float draw_distance;
uniform float roughness : hint_range(0,1);
uniform float point_size : hint_range(0,128);
uniform sampler2D texture_emission : hint_default_black;
uniform vec4 emission : source_color;
uniform float emission_energy;
uniform sampler2D texture_normal : hint_normal;
uniform float normal_scale : hint_range(-16,16);
varying vec3 uv1_triplanar_pos;
uniform float uv1_blend_sharpness;
varying vec3 uv1_power_normal;
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;


void vertex() {
	TANGENT = vec3(0.0,0.0,-1.0) * abs(NORMAL.x);
	TANGENT+= vec3(1.0,0.0,0.0) * abs(NORMAL.y);
	TANGENT+= vec3(1.0,0.0,0.0) * abs(NORMAL.z);
	TANGENT = normalize(TANGENT);
	BINORMAL = vec3(0.0,-1.0,0.0) * abs(NORMAL.x);
	BINORMAL+= vec3(0.0,0.0,1.0) * abs(NORMAL.y);
	BINORMAL+= vec3(0.0,-1.0,0.0) * abs(NORMAL.z);
	BINORMAL = normalize(BINORMAL);
	uv1_power_normal=pow(abs(NORMAL),vec3(uv1_blend_sharpness));
	uv1_power_normal/=dot(uv1_power_normal,vec3(1.0));
	uv1_triplanar_pos = VERTEX * uv1_scale + uv1_offset;
	uv1_triplanar_pos *= vec3(1.0,-1.0, 1.0);

	float fade_distance = distance(VERTEX, INV_VIEW_MATRIX[3].xyz);
}


vec4 triplanar_texture(sampler2D p_sampler,vec3 p_weights,vec3 p_triplanar_pos) {
	vec4 samp=vec4(0.0);
	samp+= texture(p_sampler,p_triplanar_pos.xy) * p_weights.z;
	samp+= texture(p_sampler,p_triplanar_pos.xz) * p_weights.y;
	samp+= texture(p_sampler,p_triplanar_pos.zy * vec2(-1.0,1.0)) * p_weights.x;
	return samp;
}


void fragment() {
	vec4 albedo_tex = triplanar_texture(texture_albedo,uv1_power_normal,uv1_triplanar_pos);
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	NORMAL_MAP = triplanar_texture(texture_normal,uv1_power_normal,uv1_triplanar_pos).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	vec3 emission_tex = triplanar_texture(texture_emission,uv1_power_normal,uv1_triplanar_pos).rgb;
	EMISSION = (emission.rgb+emission_tex)*emission_energy;
	{
		float view_distance = distance(VERTEX, INV_VIEW_MATRIX[3].xyz);
		if (view_distance > draw_distance) {
			// Neat crystal effect for distance fade. Breaks shadows. Probably fixable.
			//ALPHA = 1.0 - (view_distance - draw_distance) / 20.0;
			discard;
		}
		/*float fade=clamp(smoothstep(distance_fade_min,distance_fade_max,fade_distance),0.0,1.0);
		int x = int(FRAGCOORD.x) % 4;
		int y = int(FRAGCOORD.y) % 4;
		int index = x + y * 4;
		float limit = 0.0;

		if (x < 8) {
			if (index == 0) limit = 0.0625;
			if (index == 1) limit = 0.5625;
			if (index == 2) limit = 0.1875;
			if (index == 3) limit = 0.6875;
			if (index == 4) limit = 0.8125;
			if (index == 5) limit = 0.3125;
			if (index == 6) limit = 0.9375;
			if (index == 7) limit = 0.4375;
			if (index == 8) limit = 0.25;
			if (index == 9) limit = 0.75;
			if (index == 10) limit = 0.125;
			if (index == 11) limit = 0.625;
			if (index == 12) limit = 1.0;
			if (index == 13) limit = 0.5;
			if (index == 14) limit = 0.875;
			if (index == 15) limit = 0.375;
		}

		if (fade < limit) {
			discard;
		}*/
	}
}
