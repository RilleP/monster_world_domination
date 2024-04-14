package main

color_program: u32;
textured_program: u32;
text_program: u32;
current_program: u32;
current_texture: ^Texture;
batch_vbo : u32;
draw_view_projection: Matrix4;
window_width: i32;
window_height: i32;
window_size: Vec2;
font: Font;
FONT_SIZE :: f32(30);

Rect :: struct {
	min, max: Vec2,
}

rect_min_size_vec :: proc(min, size: Vec2) -> Rect{
	return Rect{min, min+size};
}

rect_min_size_f :: proc(x, y, w, h: f32) -> Rect{
	return Rect{{x, y}, {x+w, y+h}};
}

rect_min_size :: proc {
	rect_min_size_vec,
	rect_min_size_f,
};

rect_shrink :: proc(rect: Rect, shrink: Vec2) -> Rect {
	result: Rect = rect;
	result.min.x += shrink.x*0.5;
	result.max.x -= shrink.x*0.5;
	result.min.y += shrink.y*0.5;
	result.max.y -= shrink.y*0.5;
	return result;
}

rect_grow :: proc(rect: Rect, grow: Vec2) -> Rect {
	result: Rect = rect;
	result.min.x -= grow.x*0.5;
	result.max.x += grow.x*0.5;
	result.min.y -= grow.y*0.5;
	result.max.y += grow.y*0.5;
	return result;
}

rect_move :: proc(rect: Rect, move: Vec2) -> Rect {
	return {
		min = rect.min + move,
		max = rect.max + move,
	};
}

rect_contains :: proc(rect: Rect, point: Vec2) -> bool {
	return point.x > rect.min.x && point.x < rect.max.x &&
			point.y > rect.min.y && point.y < rect.max.y;
}

Vertex :: struct {
	position : Vec2,
	color    : Vec4,
	uv       : Vec2,
}

BATCH_TRI_CAP :: 1000;
vertex_data : [BATCH_TRI_CAP*3]Vertex;
batch_vertex_count : i32 = 0;


// TODO: Use or remove program param
draw_tri :: proc(p0, p1, p2: Vec2, uv0, uv1, uv2: Vec2, color: Vec4, program : u32 = 0) {
	if(batch_vertex_count+3 > BATCH_TRI_CAP) {
		flush_batch()
	}

	vertex_data[batch_vertex_count+0] = {p0, color, uv0};
	vertex_data[batch_vertex_count+1] = {p1, color, uv1};
	vertex_data[batch_vertex_count+2] = {p2, color, uv2};
	batch_vertex_count += 3;
}

// TODO: Use or remove program param
draw_quad_corners :: proc(p0, p1, p2, p3: Vec2, uv0, uv1, uv2, uv3: Vec2, color: Vec4, program : u32 = 0) {
	if(batch_vertex_count+6 > BATCH_TRI_CAP) {
		flush_batch()
	}

	vertex_data[batch_vertex_count+0] = {p0, color, uv0};
	vertex_data[batch_vertex_count+1] = {p1, color, uv1};
	vertex_data[batch_vertex_count+2] = {p2, color, uv2};

	vertex_data[batch_vertex_count+3] = {p0, color, uv0};
	vertex_data[batch_vertex_count+4] = {p2, color, uv2};
	vertex_data[batch_vertex_count+5] = {p3, color, uv3};
	batch_vertex_count += 6;
}

draw_rect_min_max :: proc(min, max: Vec2, color: Vec4, min_uv : Vec2 = {0, 0}, max_uv: Vec2 = {1, 1}) {
	draw_quad_corners(min, {max.x, min.y}, max, {min.x, max.y}, min_uv, {max_uv.x, min_uv.y}, max_uv, {min_uv.x, max_uv.y}, color);
}

draw_rect_min_size :: proc(min, size: Vec2, color: Vec4, min_uv : Vec2 = {0, 0}, max_uv: Vec2 = {1, 1}) {
	draw_rect_min_max(min, min+size, color, min_uv, max_uv);
}

draw_colored_rect_min_max :: proc(min, max: Vec2, color: Vec4) {
	set_shader(color_program);
	draw_rect_min_max(min, max, color);
}

draw_colored_rect_min_size :: proc(min, size: Vec2, color: Vec4) {
	draw_colored_rect_min_max(min, min+size, color);
}

draw_colored_rect_center_size :: proc(center, size: Vec2, color: Vec4) {
	draw_colored_rect_min_max(center-size*0.5, center+size*0.5, color);
}

draw_textured_rect_min_max :: proc(texture: ^Texture, min, max: Vec2, color: Vec4 = {1, 1, 1, 1}) {
	set_shader(textured_program);
	set_texture(texture);
	draw_rect_min_max(min, max, color);
}

draw_textured_rect_min_size :: proc(texture: ^Texture, min, size: Vec2, color: Vec4 = {1, 1, 1, 1}) {
	draw_textured_rect_min_max(texture, min, min+size, color);
}

draw_textured_rect_center_size :: proc(texture: ^Texture, center, size: Vec2, color: Vec4 = {1, 1, 1, 1}) {
	draw_textured_rect_min_max(texture, center-size*0.5, center+size*0.5, color);
}

draw_textured_rect_center_size_direction :: proc(texture: ^Texture, center, size: Vec2, forward: Vec2, color: Vec4 = {1, 1, 1, 1}) {
	cos := forward.x;
	sin := forward.y;
	pd := [4]Vec2 {
		{-1, -1},
		{1, -1},
		{1, 1},
		{-1, 1},
	};

	p : [4]Vec2;
	for pi in 0..<4 {
		p[pi] = center + Vec2{pd[pi].x*size.x * cos - pd[pi].y*size.y * sin, pd[pi].x*size.x * sin + pd[pi].y*size.y * cos} * 0.5;
	}
	set_shader(textured_program);
	set_texture(texture);
	min_uv := Vec2 {0, 0};
	max_uv := Vec2 {1, 1};
	draw_quad_corners(p[0], p[1], p[2], p[3], min_uv, {max_uv.x, min_uv.y}, max_uv, {min_uv.x, max_uv.y}, color);
}

draw_rect_border_min_max :: proc(min, max: Vec2, width: f32, color: Vec4) {
	set_shader(color_program);
	o0, o1, o2, o3 : Vec2 = min, {max.x, min.y}, max, {min.x, max.y};

	i0 := o0 - {-width, -width};
	i1 := o1 - {+width, -width};
	i2 := o2 - {+width, +width};
	i3 := o3 - {-width, +width};

	uv := Vec2{0, 0};

	draw_quad_corners(o0, o1, i1, i0, uv, uv, uv, uv, color);
	draw_quad_corners(o1, o2, i2, i1, uv, uv, uv, uv, color);
	draw_quad_corners(o2, o3, i3, i2, uv, uv, uv, uv, color);
	draw_quad_corners(o3, o0, i0, i3, uv, uv, uv, uv, color);
}

Align_X :: enum {
	Left,
	Center,
	Right,
};

Align_Y :: enum {
	Top,
	Center,
	Bottom,
}

draw_text :: proc(text: string, font: ^Font, position: Vec2, align_x: Align_X, align_y: Align_Y, color: Vec4, bounds: ^Rect = nil) {
	when ODIN_OS == .JS {
		js_draw_text(text, FONT_SIZE, position.x, position.y, int(align_x), int(align_y), color.r, color.g, color.b, color.a);
	}
	else {
		size := get_text_draw_size(text, font);

		p: Vec2;
		switch align_x {
			case .Left: p.x = position.x;
			case .Center: p.x = position.x - size.x*0.5;
			case .Right: p.x = position.x - size.x;
		}
		switch align_y {
			case .Top: p.y = position.y + size.y;
			case .Center: p.y = position.y + size.y*0.5;
			case .Bottom: p.y = position.y;
		}
		maybe_draw_text(text, font, p, color, true, bounds);
	}
}

get_text_bounds :: proc(text: string, font: ^Font, position: Vec2, bounds: ^Rect = nil) {
	maybe_draw_text(text, font, position, {}, false, bounds);
}

get_text_draw_size :: proc(text: string, font: ^Font) -> Vec2 {
	bounds: Rect;
	maybe_draw_text(text, font, 0, {}, false, &bounds);
	return bounds.max - bounds.min;
}

draw_char :: proc(c: int, font: ^Font, position: Vec2, color: Vec4) {
	glyph : ^GlyphInfo;

	if(c < font.first_char || c > font.last_char) {return;}

	glyph = &font.glyphs[c - font.first_char];

	draw_rect_min_size(position+glyph.offset, glyph.size, color, glyph.uv_min, glyph.uv_max);
}

set_view_projection :: proc(vp: Matrix4) {
	flush_batch();
	draw_view_projection = vp;
	if(current_program != 0) {
		_update_view_projection();
	}
}

set_shader :: proc(program: u32) {
	if(current_program != program) {
		flush_batch();
		current_program = program;
		_set_shader(program);
	}
}

set_texture :: proc(texture: ^Texture) {
	if(current_texture != texture) {
		flush_batch();
		_set_texture(texture);
		current_texture = texture;
	}
}

maybe_draw_text :: proc(text: string, font: ^Font, position: Vec2, color: Vec4, draw: bool, bounds: ^Rect = nil) {
	cursor := position;
	if(draw) {
		set_shader(text_program);
		set_texture(&font.texture);
	}

	bmin := position;
	bmax := position;
	for ii in 0..<len(text) {
		c := cast(int)text[ii];
		
		xadvance : f32;
		glyph : ^GlyphInfo;
		if(c == '\t') {
			xadvance = font.space_xadvance * 4;
		}
		else if(c == ' ') {
			xadvance = font.space_xadvance;	
		}
		else {
			if(c < font.first_char || c > font.last_char) {continue;}
			glyph = &font.glyphs[c - font.first_char];
			xadvance = glyph.xadvance;
		}


		if(glyph != nil) {
			p := cursor + glyph.offset;

			bmax.x = p.x + glyph.size.x;
			bmax.y = max(p.y + glyph.size.y, bmax.y);
			bmin.y = min(p.y, bmin.y);

			if(draw) {
				draw_rect_min_size(p, glyph.size, color, glyph.uv_min, glyph.uv_max);
				
				/*GL.BindBuffer(GL.ARRAY_BUFFER, vertex_buffer);
				GL.BufferData(GL.ARRAY_BUFFER, size_of(vertices), slice.as_ptr(vertices[:]), GL.DYNAMIC_DRAW);
				
				GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, index_buffer);
				GL.BufferData(GL.ELEMENT_ARRAY_BUFFER, size_of(indices), slice.as_ptr(indices[:]), GL.DYNAMIC_DRAW);		

				GL.DrawElements(GL.TRIANGLES, len(indices), GL.UNSIGNED_INT, rawptr(uintptr(0)));*/
			}
		}
		cursor.x += xadvance;
		bmax.x = cursor.x;
	}

	if(bounds != nil) {
		bmax.x = cursor.x;
		bounds.min = bmin;
		bounds.max = bmax;
	}
}




