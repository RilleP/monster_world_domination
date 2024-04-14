package main

GlyphInfo :: struct {
	uv_min, uv_max : Vec2,
	offset: Vec2,
	size : Vec2,
	xadvance: f32,
}

Font :: struct {
	first_char, last_char: int,
	glyphs: []GlyphInfo,

	line_height, line_advance: f32,
	descent, ascent: f32,
	space_xadvance: f32,
	texture: Texture,
}
