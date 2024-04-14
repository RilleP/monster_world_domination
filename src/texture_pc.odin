//+build windows
package main

import GL "vendor:OpenGL"
import "vendor:stb/image"
import c "core:c/libc"
import "core:strings"
import "core:os"
import "core:fmt"

bitmap_from_memory :: proc(memory: []u8) -> Bitmap {
	w, h, channels_in_file : c.int;

	pixels := image.load_from_memory(raw_data(memory), cast(c.int)len(memory), &w, &h, &channels_in_file, 4);
	return {
		pixels = pixels,
		width = i32(w),
		height = i32(h),
	};
}

texture_from_memory :: proc(memory: []u8, repeat: bool = false) -> (texture: Texture, success: bool) {
	bitmap := bitmap_from_memory(memory);
	if(bitmap.pixels == nil) {
		return texture, false;	
	} 

	texture.width = bitmap.width;
	texture.height = bitmap.height;
	GL.GenTextures(1, &texture.id);
	GL.BindTexture(GL.TEXTURE_2D, texture.id);
	GL.TexImage2D(GL.TEXTURE_2D, 0, GL.RGBA, texture.width, texture.height, 0, GL.RGBA, GL.UNSIGNED_BYTE, bitmap.pixels);
	if(repeat) {
		GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.REPEAT);
		GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.REPEAT);
	}
	else {
		GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE);
		GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE);
	}
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR);
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR);
	GL.BindTexture(GL.TEXTURE_2D, 0);

	return texture, true;	
}

texture_from_file :: proc(path: string, repeat: bool = false) -> (texture: Texture, success: bool) {
	//strings.clone_to_cstring(path, context.temp_allocator)
	file_data, file_success := os.read_entire_file(path);
	if !file_success do return texture, false;

	return texture_from_memory(file_data, repeat);
}

load_texture :: proc(path: string, texture: ^Texture, repeat := false) {
	success: bool;
	texture^, success = texture_from_file(path, repeat);
	if !success {
		fmt.printf("Failed to load texture '%s'\n", path);
		assert(false);
	}	
}

load_bitmap :: proc(path: string, bitmap: ^Bitmap) {
	file_data, file_success := os.read_entire_file(path);
	if !file_success do return;

	bitmap^ = bitmap_from_memory(file_data);
	if bitmap.pixels == nil {
		fmt.printf("Failed to load bitmap '%s'\n", path);
		assert(false);
	}
}