package main

import GL "vendor:wasm/WebGL"
import "core:slice"

foreign import gui_lib "gui";
@(default_calling_convention="contextless")
foreign gui_lib {
	js_draw_text :: proc(s: string, FONT_SIZE, x, y: f32, align_x: int, align_y: int, r, g, b, a: f32) ---; 
}

compile_shader :: proc(source: string, type: GL.Enum) -> GL.Shader {
	
	result := GL.CreateShader(type);
	GL.ShaderSource(result, {source});
	GL.CompileShader(result);
	info_buf: [512]byte;
	vertex_error := GL.GetShaderInfoLog(result, info_buf[:]);
	if(len(vertex_error) > 0) {
		log("Failed to compile shader\n");
		log(vertex_error);
		return 0;
	}
	return result;
}

create_and_link_program :: proc(vertex_shader, fragment_shader: GL.Shader) -> GL.Program {
	result := GL.CreateProgram();
	GL.AttachShader(result, vertex_shader);
	GL.AttachShader(result, fragment_shader);
	GL.LinkProgram(result);
	info_buf: [512]byte;
	program_error := GL.GetProgramInfoLog(result, info_buf[:]);
	if len(program_error) > 0 {
		log("Failed to link shader program\n");
		log(program_error);
		assert(false);
		return 0;
	}
	return result;
}

init_draw :: proc() {
	font = {

	}
	vertex_shader := compile_shader(VERTEX_SHADER_SRC, GL.VERTEX_SHADER);
	colored_fragment_shader := compile_shader(COLORED_FRAGMENT_SHADER_SRC, GL.FRAGMENT_SHADER);
	textured_fragment_shader := compile_shader(TEXTURED_FRAGMENT_SHADER_SRC, GL.FRAGMENT_SHADER);

	color_program = cast(u32)create_and_link_program(vertex_shader, colored_fragment_shader);	
	textured_program = cast(u32)create_and_link_program(vertex_shader, textured_fragment_shader);

	GL.DeleteShader(vertex_shader);
	GL.DeleteShader(colored_fragment_shader);
	GL.DeleteShader(textured_fragment_shader);

	batch_vbo = cast(u32)GL.CreateBuffer();
	GL.BindBuffer(GL.ARRAY_BUFFER, cast(GL.Buffer)batch_vbo);
	GL.BufferData(GL.ARRAY_BUFFER, size_of(vertex_data), nil, GL.DYNAMIC_DRAW);	

	GL.EnableVertexAttribArray(0);
	GL.EnableVertexAttribArray(1);
	GL.EnableVertexAttribArray(2);
	GL.VertexAttribPointer(0, 2, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, position));
	GL.VertexAttribPointer(1, 4, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, color));
	GL.VertexAttribPointer(2, 2, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, uv));
}

start_draw_frame :: proc(bg: Vec3) {
	GL.Enable(GL.BLEND);
	GL.BlendFunc(GL.ONE, GL.ONE_MINUS_SRC_ALPHA);
	GL.Disable(GL.CULL_FACE);

	GL.ClearColor(bg.x, bg.y, bg.z, 1);
	GL.Clear(GL.COLOR_BUFFER_BIT);

}

set_draw_viewport :: proc(x, y, w, h: i32) {
	GL.Viewport(x, y, w, h);
}

flush_batch :: proc() {
	if batch_vertex_count == 0 {
	 	return;	
	}

	GL.BindBuffer(GL.ARRAY_BUFFER, cast(GL.Buffer)batch_vbo);
	vertex_count := batch_vertex_count;
	GL.BufferSubData(GL.ARRAY_BUFFER, 0, size_of(Vertex)*cast(int)vertex_count, slice.as_ptr(vertex_data[:vertex_count]));

	GL.EnableVertexAttribArray(0);
	GL.VertexAttribPointer(0, 2, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, position));

	GL.EnableVertexAttribArray(1);
	GL.VertexAttribPointer(1, 4, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, color));

	GL.EnableVertexAttribArray(2);
	GL.VertexAttribPointer(2, 2, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, uv));


	GL.DrawArrays(GL.TRIANGLES, 0, cast(int)vertex_count);
	batch_vertex_count = 0;
}

_update_view_projection :: proc() {
	if(current_program != 0) {
		GL.UniformMatrix4fv(GL.GetUniformLocation(cast(GL.Program)current_program, "view_projection"), draw_view_projection);
	}
}

_set_texture :: proc(texture: ^Texture) {
	GL.BindTexture(GL.TEXTURE_2D, cast(GL.Texture)texture.id);
}

_set_shader :: proc(program: u32) {
	GL.UseProgram(cast(GL.Program)program);
	_update_view_projection();
}

VERTEX_SHADER_SRC :: `#version 300 es
layout(location = 0) in vec2 position;
layout(location = 1) in vec4 color;
layout(location = 2) in vec2 uv;

uniform mat4 view_projection;

out vec4 v_color;
out vec2 v_uv;

void main() {
	gl_Position = view_projection * vec4(position, 0, 1);
	v_color = color;
	v_uv = uv;
}

`;

TEXTURED_FRAGMENT_SHADER_SRC :: `#version 300 es

in highp vec4 v_color;
in highp vec2 v_uv;

uniform sampler2D image;

out highp vec4 color; 

void main() {
	color = texture(image, v_uv) * v_color;
	color.rgb *= color.a;	
}

`;

COLORED_FRAGMENT_SHADER_SRC :: `#version 300 es

in highp vec4 v_color;
in highp vec2 v_uv;

out highp vec4 color; 

void main() {
	color = v_color;
	color.rgb *= color.a;
}

`;
