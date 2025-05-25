shader_type canvas_item;

uniform sampler2D paint_color_texture : hint_default_white; // We need the GDScript to set this

void fragment() {
    vec4 original_tile_color = texture(TEXTURE, UV);
    vec4 paint_data = texture(paint_color_texture, UV);

    if (paint_data.a > 0.01) {
        COLOR = mix(original_tile_color, paint_data, paint_data.a);
    } else {
        COLOR = original_tile_color;
    }
}