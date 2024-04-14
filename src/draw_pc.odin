//+build windows
package main

import GL "vendor:OpenGL"
import "core:slice"
import "core:os"
import "core:fmt"

init_draw :: proc() {
	vertex_shader := compile_shader_from_file("res\\shaders\\basic.vert", GL.VERTEX_SHADER);
	color_fragment_shader := compile_shader_from_file("res\\shaders\\color.frag", GL.FRAGMENT_SHADER);
	textured_fragment_shader := compile_shader_from_file("res\\shaders\\textured.frag", GL.FRAGMENT_SHADER);
	text_fragment_shader := compile_shader_from_file("res\\shaders\\text.frag", GL.FRAGMENT_SHADER);

	color_program = GL.CreateProgram();
	GL.AttachShader(color_program, vertex_shader);
	GL.AttachShader(color_program, color_fragment_shader);
	GL.LinkProgram(color_program);

	textured_program = GL.CreateProgram();
	GL.AttachShader(textured_program, vertex_shader);
	GL.AttachShader(textured_program, textured_fragment_shader);
	GL.LinkProgram(textured_program);

	text_program = GL.CreateProgram();
	GL.AttachShader(text_program, vertex_shader);
	GL.AttachShader(text_program, text_fragment_shader);
	GL.LinkProgram(text_program);

	GL.DeleteShader(vertex_shader);
	GL.DeleteShader(color_fragment_shader);
	GL.DeleteShader(textured_fragment_shader);
	GL.DeleteShader(text_fragment_shader);

	GL.GenBuffers(1, &batch_vbo);
	GL.BindBuffer(GL.ARRAY_BUFFER, batch_vbo);
	GL.BufferData(GL.ARRAY_BUFFER, size_of(vertex_data), nil, GL.DYNAMIC_DRAW);	
}

start_draw_frame :: proc(bg: Vec3) {
	GL.Enable(GL.BLEND);
	GL.BlendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA);
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

	GL.BindBuffer(GL.ARRAY_BUFFER, batch_vbo);
	vertex_count := batch_vertex_count;
	GL.BufferSubData(GL.ARRAY_BUFFER, 0, size_of(Vertex)*cast(int)vertex_count, slice.as_ptr(vertex_data[:vertex_count]));

	GL.EnableVertexAttribArray(0);
	GL.EnableVertexAttribArray(1);
	GL.EnableVertexAttribArray(2);

	GL.VertexAttribPointer(0, 2, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, position));
	GL.VertexAttribPointer(1, 4, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, color));
	GL.VertexAttribPointer(2, 2, GL.FLOAT, false, size_of(Vertex), offset_of(Vertex, uv));

	GL.DrawArrays(GL.TRIANGLES, 0, vertex_count);
	batch_vertex_count = 0;
}

_update_view_projection :: proc() {
	GL.UniformMatrix4fv(GL.GetUniformLocation(current_program, "view_projection"), 1, false, cast(^f32	)(&draw_view_projection));
}

_set_texture :: proc(texture: ^Texture) {
	GL.BindTexture(GL.TEXTURE_2D, texture.id);
}

_set_shader :: proc(program: u32) {
	GL.UseProgram(program);
	_update_view_projection();
}

compile_shader_from_file :: proc(filepath: string, shader_type: u32) -> u32 {
	source_data, success := os.read_entire_file_from_filename(filepath);
	if(!success) {
		fmt.printf("Failed to read shader file %s!", filepath);
		return 0;
	}

	shader := GL.CreateShader(shader_type);
	source := cstring(slice.as_ptr(source_data[:]));
	source_len := i32(len(source));
	sources : [^]cstring = &source;
	source_lengths : [^]i32 = &source_len;
	GL.ShaderSource(shader, 1, sources, source_lengths);
	GL.CompileShader(shader);

	info_buffer : [1024]u8;
	info_length : i32;
	GL.GetShaderInfoLog(shader, size_of(info_buffer), &info_length, slice.as_ptr(info_buffer[:]));

	if(info_length > 0) {
		fmt.printf("Shader '%s' compilation info: '%s'\n", filepath, info_buffer[:info_length]);
	}

	delete(source_data);
	return shader;
}
