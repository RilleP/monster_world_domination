package main

Button_Theme :: struct {
	bg_color_normal: Vec4,
	bg_color_hovered: Vec4,
	
	bd_color_normal: Vec4,
	bd_color_hovered: Vec4,
	bd_width: f32,
}

button :: proc(rect: Rect, theme: Button_Theme) -> bool {
	hovered := rect_contains(rect, mouse_p);
		
	draw_colored_rect_min_max(rect.min, rect.max, 
		hovered ? theme.bg_color_hovered : theme.bg_color_normal);
	//draw_textured_rect_min_size(&MONSTER_TEXTURES[type], button_min, button_size);
	if theme.bd_width > 0 do draw_rect_border_min_max(rect.min, rect.max, theme.bd_width, 
		hovered ? theme.bd_color_hovered : theme.bd_color_normal);
	return hovered && left_mouse_got_pressed;
}

text_button :: proc(rect: Rect, theme: Button_Theme, text: string) -> bool {
	pressed := button(rect, theme);

	draw_text(text, &font, (rect.min + rect.max) * 0.5, .Center, .Center, {0, 0, 0, 1});

	return pressed;
} 