//+build windows
package main

import GL "vendor:OpenGL"
import "vendor:stb/truetype"
import "core:os"
import "core:slice"
import "core:mem"

read_font_from_file :: proc(path: string, font_size: f32) -> (Font, bool) {
	using truetype;
	result : Font;
	font_file_data_array, file_read_success := os.read_entire_file_from_filename(path);	
	
	if(!file_read_success) {
		return result, false;
	}
	defer delete(font_file_data_array);

	font_file_data := slice.as_ptr(font_file_data_array[:]);
	num_fonts := GetNumberOfFonts(font_file_data);
	if(num_fonts <= 0) {
		return result, false;
	}

	font_info : fontinfo;
	if(!InitFont(&font_info, font_file_data, GetFontOffsetForIndex(font_file_data, 0))) {
		return result, false;
	}

	ascent, descent, line_gap: f32;
	GetScaledFontVMetrics(font_file_data, 0, font_size, &ascent, &descent, &line_gap);

	first_char :: 0;
	last_char :: 255;
	char_count :: last_char-first_char+1;
	width :: 512;
	height :: 512;
	chars_mem_len := char_count * size_of(bakedchar);
	pixels_mem_len := width*height;
	mem, _ := mem.alloc_bytes(chars_mem_len + pixels_mem_len);
	chars := cast([^]bakedchar)raw_data(mem[:chars_mem_len]);

	pixels := cast([^]u8)raw_data(mem[chars_mem_len:]);


	BakeFontBitmap(font_file_data, GetFontOffsetForIndex(font_file_data, 0),
		font_size, pixels, width, height,
		first_char, char_count, chars);

	GL.PixelStorei(GL.UNPACK_ALIGNMENT, 1);
	texture := Texture {
		width = width,
		height = height,
	};
	GL.GenTextures(1, &texture.id);
	GL.BindTexture(GL.TEXTURE_2D, texture.id);
	GL.TexImage2D(GL.TEXTURE_2D, 0, GL.RED, width, height, 0, GL.RED, GL.UNSIGNED_BYTE, pixels);
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE);
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE);
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.NEAREST);
	GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.NEAREST);

	result = (Font) {
		first_char = first_char,
		last_char = last_char,
		glyphs = make([]GlyphInfo, char_count),
		texture = texture,
		line_height = cast(f32)(ascent - descent),
		line_advance = cast(f32)(ascent - descent + line_gap),
		descent = cast(f32)descent,
		ascent = cast(f32)ascent,		
	};
	for gi in 0..<char_count {
		bc := chars[gi];
		
		result.glyphs[gi] = (GlyphInfo) {
			uv_min = { cast(f32)bc.x0 / width, cast(f32)bc.y0 / height },
			uv_max = { cast(f32)bc.x1 / width, cast(f32)bc.y1 / height },
			xadvance = bc.xadvance,
			offset = { bc.xoff, bc.yoff },
			size   = { cast(f32)(bc.x1 - bc.x0), cast(f32)(bc.y1 - bc.y0) },			
		};
	}

	space_glyph := result.glyphs[' ' - first_char];
	result.space_xadvance = space_glyph.xadvance;

	return result, true;
}
