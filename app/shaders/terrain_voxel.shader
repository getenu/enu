// Build voxels: the mesher bakes each library entry's color (and its ambient
// occlusion) into vertex COLOR, so albedo tints per voxel instead of per
// material. The material's `albedo` scales every voxel's brightness to suit
// the environments' lighting. Emission follows the voxel color so
// glow/highlight stay colored.
shader_type spatial;
render_mode blend_mix,depth_draw_always,cull_back,diffuse_burley,specular_schlick_ggx;
uniform vec4 albedo : hint_color;
uniform sampler2D texture_albedo : hint_albedo;
uniform float specular;
uniform float metallic;
uniform float draw_distance;
uniform float roughness : hint_range(0,1);
uniform float point_size : hint_range(0,128);
uniform sampler2D texture_emission : hint_black_albedo;
uniform vec4 emission : hint_color;
uniform float emission_energy;
uniform bool tint_emission = true;
  // false: glow in `emission` as given (the error flash), not the voxel's color
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
}


vec4 triplanar_texture(sampler2D p_sampler,vec3 p_weights,vec3 p_triplanar_pos) {
  vec4 samp=vec4(0.0);
  samp+= texture(p_sampler,p_triplanar_pos.xy) * p_weights.z;
  samp+= texture(p_sampler,p_triplanar_pos.xz) * p_weights.y;
  samp+= texture(p_sampler,p_triplanar_pos.zy * vec2(-1.0,1.0)) * p_weights.x;
  return samp;
}


vec3 srgb_to_linear(vec3 c) {
  // Vertex colors arrive as authored (sRGB); material colors are converted
  // by the engine, so do the same here.
  return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec3 glow_color(vec3 color) {
  // Lifted, so dark voxels still visibly glow.
  return mix(color, vec3(1.0), 0.2);
}

void fragment() {
  vec4 albedo_tex = triplanar_texture(texture_albedo,uv1_power_normal,uv1_triplanar_pos);
  vec3 color = srgb_to_linear(clamp(COLOR.rgb, 0.0, 1.0));
  ALBEDO = color * albedo.rgb * albedo_tex.rgb;
  METALLIC = metallic;
  ROUGHNESS = roughness;
  SPECULAR = specular;
  NORMALMAP = triplanar_texture(texture_normal,uv1_power_normal,uv1_triplanar_pos).rgb;
  NORMALMAP_DEPTH = normal_scale;
  EMISSION = (tint_emission ? emission.rgb * glow_color(color) : emission.rgb) * emission_energy;
  {
    float view_distance = distance(VERTEX, CAMERA_MATRIX[2].xyz);
    if (view_distance > draw_distance) {
      discard;
    }
  }
}
