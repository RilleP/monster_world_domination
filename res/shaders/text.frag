#version 330

in vec4 v_color;
in vec2 v_uv;

uniform sampler2D image;

out vec4 color; 

void main() {

	color = texture(image, v_uv).r * v_color;
}