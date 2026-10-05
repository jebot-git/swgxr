shader_type spatial;
render_mode unshaded, cull_back;
global uniform vec4 swg_environment_tint;
global uniform vec4 swg_indoor_tint;
instance uniform float swg_indoor = 0.0;

// Original material color operations with fixed vertex-baked irradiance.
uniform sampler2D main_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D hue_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 main_color : source_color = vec4(1.0);
uniform vec4 hue_color : source_color = vec4(1.0);
uniform int color_mode = 0;
uniform int normal_mode = 0;
uniform bool alpha_cutout = false;
uniform int layer_count = 0;
uniform sampler2D layer_0_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 layer_0_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_0_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_0_color : source_color = vec4(1.0);
uniform bool layer_0_copy = false;
uniform sampler2D layer_1_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 layer_1_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_1_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_1_color : source_color = vec4(1.0);
uniform bool layer_1_copy = false;
uniform sampler2D layer_2_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 layer_2_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_2_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_2_color : source_color = vec4(1.0);
uniform bool layer_2_copy = false;
uniform sampler2D layer_3_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 layer_3_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_3_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_3_color : source_color = vec4(1.0);
uniform bool layer_3_copy = false;
uniform sampler2D layer_4_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 layer_4_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_4_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_4_color : source_color = vec4(1.0);
uniform bool layer_4_copy = false;
uniform sampler2D layer_5_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 layer_5_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_5_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 layer_5_color : source_color = vec4(1.0);
uniform bool layer_5_copy = false;

vec4 compose_layer(vec4 previous, vec4 sampled, vec4 tint, bool copy_layer, vec2 local_uv) {
    if (any(lessThan(local_uv, vec2(0.0))) || any(greaterThan(local_uv, vec2(1.0)))) return previous;
    vec4 layer = sampled * tint;
    return copy_layer ? layer : vec4(mix(previous.rgb, layer.rgb, layer.a), layer.a + previous.a * (1.0 - layer.a));
}

void fragment() {
    vec4 main = texture(main_texture, UV);
    vec3 tint = main_color.rgb;
    float opacity = main.a;
    if (color_mode == 1) tint = mix(main_color.rgb, hue_color.rgb, main.a);
    if (color_mode == 2) {
        float second_mask = texture(hue_texture, UV).a;
        tint = mix(hue_color.rgb, main_color.rgb, clamp(main.a - second_mask, 0.0, 1.0));
        opacity = clamp(main.a + second_mask, 0.0, 1.0);
    }
    vec4 result = vec4(main.rgb * tint, opacity);
    if (layer_count > 0) {
        vec2 local_uv = (UV - layer_0_rect.xy) / layer_0_rect.zw;
        vec2 mapped_uv = layer_0_uv.xy + local_uv * layer_0_uv.zw;
        result = compose_layer(result, texture(layer_0_texture, mapped_uv), layer_0_color, layer_0_copy, local_uv);
    }
    if (layer_count > 1) {
        vec2 local_uv = (UV - layer_1_rect.xy) / layer_1_rect.zw;
        vec2 mapped_uv = layer_1_uv.xy + local_uv * layer_1_uv.zw;
        result = compose_layer(result, texture(layer_1_texture, mapped_uv), layer_1_color, layer_1_copy, local_uv);
    }
    if (layer_count > 2) {
        vec2 local_uv = (UV - layer_2_rect.xy) / layer_2_rect.zw;
        vec2 mapped_uv = layer_2_uv.xy + local_uv * layer_2_uv.zw;
        result = compose_layer(result, texture(layer_2_texture, mapped_uv), layer_2_color, layer_2_copy, local_uv);
    }
    if (layer_count > 3) {
        vec2 local_uv = (UV - layer_3_rect.xy) / layer_3_rect.zw;
        vec2 mapped_uv = layer_3_uv.xy + local_uv * layer_3_uv.zw;
        result = compose_layer(result, texture(layer_3_texture, mapped_uv), layer_3_color, layer_3_copy, local_uv);
    }
    if (layer_count > 4) {
        vec2 local_uv = (UV - layer_4_rect.xy) / layer_4_rect.zw;
        vec2 mapped_uv = layer_4_uv.xy + local_uv * layer_4_uv.zw;
        result = compose_layer(result, texture(layer_4_texture, mapped_uv), layer_4_color, layer_4_copy, local_uv);
    }
    if (layer_count > 5) {
        vec2 local_uv = (UV - layer_5_rect.xy) / layer_5_rect.zw;
        vec2 mapped_uv = layer_5_uv.xy + local_uv * layer_5_uv.zw;
        result = compose_layer(result, texture(layer_5_texture, mapped_uv), layer_5_color, layer_5_copy, local_uv);
    }
    ALBEDO = result.rgb * COLOR.rgb * mix(swg_environment_tint.rgb, swg_indoor_tint.rgb, clamp(swg_indoor, 0.0, 1.0));
    ROUGHNESS = 0.85;
    if (alpha_cutout && result.a < 0.5) discard;
    if (normal_mode != 0) {
        vec4 encoded = texture(normal_texture, UV);
        vec3 tangent_normal = encoded.rgb * 2.0 - 1.0;
        if (normal_mode == 2) {
            tangent_normal.xy = encoded.ag * 2.0 - 1.0;
            tangent_normal.z = sqrt(max(0.0, 1.0 - dot(tangent_normal.xy, tangent_normal.xy)));
        }
        vec3 dp1 = dFdx(VERTEX);
        vec3 dp2 = dFdy(VERTEX);
        vec2 duv1 = dFdx(UV);
        vec2 duv2 = dFdy(UV);
        float determinant = duv1.x * duv2.y - duv1.y * duv2.x;
        if (abs(determinant) > 0.00000001) {
            vec3 n = normalize(NORMAL);
            vec3 tangent = normalize((dp1 * duv2.y - dp2 * duv1.y) / determinant);
            tangent = normalize(tangent - n * dot(n, tangent));
            vec3 bitangent = normalize((-dp1 * duv2.x + dp2 * duv1.x) / determinant);
            bitangent = normalize(bitangent - n * dot(n, bitangent));
            NORMAL = normalize(tangent * tangent_normal.x + bitangent * tangent_normal.y + n * tangent_normal.z);
        }
    }
}
