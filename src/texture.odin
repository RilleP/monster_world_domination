package main

Bitmap :: struct {
	pixels: [^]u8,
	width, height: i32,
}

Texture :: struct {
	id: u32,
	width, height: i32,
}