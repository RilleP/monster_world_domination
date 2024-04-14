package main

import "core:mem"
import "core:intrinsics"
import "core:math"
import "core:math/rand"
import "stb_image"
import "core:math/linalg"
import "core:strings"
import "core:fmt"
import "core:time"

main_allocator : mem.Allocator;
temp_allocator : mem.Allocator;

import "vendor:wasm/js" 
import GL "vendor:wasm/WebGL"

foreign import "env"
@(default_calling_convention="contextless")
foreign env {
	//js_printf :: proc(str: string) ---
	log :: proc(string) ---
	log_int :: proc(int) ---
	us_now :: proc() -> int ---
	ms_now :: proc() -> f32 ---
	fetch_file :: proc(path: string) -> int ---
	is_file_fetching_done :: proc(index: int) -> bool ---
	get_fetched_file_length :: proc(index: int) -> int ---
	get_fetched_file_data :: proc(index: int, buffer: rawptr) ---
}

foreign import "audio"
@(default_calling_convention="contextless")
foreign audio {
	play_sound :: proc(path: string, volume: f32 = 1.0) ---
	platform_set_music_volume :: proc(volume: f32) ---
}

start_time: int;
start_time_ms: f32;
prev_time_ms: f32;

WEB_PAGE_HEAD_SIZE :: 64; // Whatever as long as it fits
PAGE_SIZE :: js.PAGE_SIZE;

Web_Page :: struct {
	prev: ^Web_Page,
	used, cap: int,
}

web_allocator :: proc() -> mem.Allocator {
	push_page :: proc(min_size: int) -> ^Web_Page {
		page_count := math.max(1, (min_size+WEB_PAGE_HEAD_SIZE+PAGE_SIZE-1) / PAGE_SIZE)
		page_mem, err := js.page_alloc(page_count);
		assert(err == nil, "Failed to allocate pages for web_allocator");

		//log("Push page\n");
		//log_int(page_count);
		page := cast(^Web_Page)(&page_mem[0]);
		page.used = 0;
		page.cap = PAGE_SIZE*page_count - WEB_PAGE_HEAD_SIZE;
		page.prev = nil;
		return page;
	}

	procedure :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
	                  size, alignment: int,
	                  old_memory: rawptr, old_size: int,
	                  location := #caller_location) -> ([]byte, mem.Allocator_Error) {
		switch mode {
		case .Alloc, .Alloc_Non_Zeroed:
			assert(allocator_data != nil);
			//assert(size <= PAGE_SIZE - WEB_PAGE_HEAD_SIZE); // TODO: Handle multipage allocations

			first_page := cast(^Web_Page)allocator_data;
			page : ^Web_Page;
			for pp := first_page; ; pp = pp.prev {
				if pp.cap >= pp.used + size {
					page = pp;
					break;
				}

				if pp.prev == first_page || pp.prev == nil {
					page = nil;
					break;
				}
			}
			//page := first_page.prev != nil ? first_page.prev : first_page;

			if(page == nil) {
				new_page := push_page(size);
				assert(new_page != nil, "Failed to allocate page when growing web_allocator");

				new_page.prev = page;
				first_page.prev = new_page;

				//mem.copy(page, new_page, size_of(Web_Page));
				page = new_page;
				//log("Grew web page\n");
			} 

			assert(page.used + size <= page.cap);
			result := intrinsics.ptr_offset(cast(^u8)page, uintptr(WEB_PAGE_HEAD_SIZE + page.used));
			page.used += size;
			/*log("allocate bytes\n");
			log_int(size);*/
			if mode == .Alloc {
				mem.set(result, 0, size);
			}
			return mem.byte_slice(result, size), nil;
			//return js.page_alloc(size/PAGE_SIZE);
		case .Free_All: {
			assert(allocator_data != nil);
			
			first_page := cast(^Web_Page)allocator_data;
			for page := first_page; ; page = page.prev {
				page.used = 0;

				if page.prev == first_page || page.prev == nil {
					break;
				}
			}
			//log("Free all\n");
		}
		case .Resize_Non_Zeroed: {
			assert(false);
		}
		case .Resize: {
			first_page := cast(^Web_Page)allocator_data;
			page := first_page.prev != nil ? first_page.prev : first_page;
			
			end := intrinsics.ptr_offset(cast(^u8)page, uintptr(WEB_PAGE_HEAD_SIZE + page.used));
			old_alloc_end := intrinsics.ptr_offset(cast(^u8)old_memory, old_size);
			delta_size := size - old_size;
			/*if(delta_size < 0) {
				return mem.byte_slice()
			}
			else */if(end == old_alloc_end && (page.used + delta_size <= page.cap)) {
				//log("realloc continue\n");
				page.used += delta_size;
				return mem.byte_slice(intrinsics.ptr_offset(old_alloc_end, -old_size), size), nil;
			}
			else {
				//log("realloc new\n");
				result, err := procedure(allocator_data, .Alloc, size, alignment, nil, 0);
				assert(err == nil, "failed to realloc");
				if(old_memory != nil && old_size != 0) {
					mem.copy_non_overlapping(&result[0], old_memory, old_size);
				}
				return result, nil;
			}
		}
		case .Free, .Query_Info:
			return nil, .Mode_Not_Implemented;
		case .Query_Features:
			set := (^mem.Allocator_Mode_Set)(old_memory);
			if set != nil {
				set^ = {.Alloc, .Resize, .Query_Features};
			}
		}

		return nil, nil;
	}


	
	return {
		procedure = procedure,
		data = push_page(0),
	};
}

@export _start :: proc() {
	rand.set_global_seed(cast(u64)time.now()._nsec);
	start_time = us_now();
	start_time_ms = ms_now();
	prev_time_ms = start_time_ms;
	GL.CreateCurrentContextById("glcanvas", {});
	
	main_allocator = web_allocator();	
	temp_allocator = web_allocator();
	context.allocator = main_allocator;
	context.temp_allocator = temp_allocator;

	major, minor: i32;
	GL.GetWebGLVersion(&major, &minor);
	log("GL Version ");
	log_int(int(major));
	log_int(int(minor));

	init_draw();

	window_width = GL.DrawingBufferWidth();
	window_height = GL.DrawingBufferHeight();
	window_size = {f32(window_width), f32(window_height)};
	
	load_assets();


	//load_playlist_file("playlist.txt");	

	/*file_queue[file_queue_count].index = fetch_file("main.odin");
	file_queue_count += 1;*/

	
	/*load_texture_js("res/textures/tree.png", &tree_texture);
	load_texture_js("res/textures/stone.png", &stone_texture);
	load_texture_js("res/textures/cow.png", &cow_texture);
	load_texture_js("res/textures/deer.png", &horse_texture);
	load_texture_js("res/textures/apple.png", &apple_texture);
	load_texture_js("res/textures/man.png", &man_texture);
	//load_animation_frames(&man_walking_south, 6, "res/textures/man/walk_south/man_walk_south", "_c.png");
	man_walking_south.frames = make([dynamic]Texture, 2);
	load_texture_js("res/textures/man/walk_south/man_walk_south03_cc.png", &man_walking_south.frames[0]);
	load_texture_js("res/textures/man/walk_south/man_walk_south06_cc.png", &man_walking_south.frames[1]);

	load_animation_frames(&man_idle, 1, "res/textures/man/idle/man_idle", "_cc_brown.png");
	load_texture_js("res/textures/grass.png", &grass_texture, true);*/


	js.add_window_event_listener(.Key_Down, nil, handle_key_event, true);
	js.add_window_event_listener(.Key_Up, nil, handle_key_event, true);
	js.add_event_listener("guicanvas", .Mouse_Down, nil, handle_mouse_up_down_event, true);
	js.add_event_listener("guicanvas", .Mouse_Up, nil, handle_mouse_up_down_event, true);
	js.add_event_listener("guicanvas", .Mouse_Move, nil, handle_mouse_move_event, true);

	js.event_prevent_default();
	js.event_stop_immediate_propagation();
	js.event_stop_propagation();

	app.music_volume = 0.25;
	platform_set_music_volume(app.music_volume);
}

handle_key_event :: proc(e: js.Event) {
	//log(e.key.key);
	//log(e.key.code);
	context.allocator = main_allocator;
	context.temp_allocator = temp_allocator;
	assert(e.kind == .Key_Down || e.kind == .Key_Up);
	pressed := e.kind == .Key_Down;


	switch(e.key.code) {
		case "ArrowLeft":  handle_move_key_event(pressed, e.key.repeat, false, .WEST);
		case "ArrowRight": handle_move_key_event(pressed, e.key.repeat, false, .EAST);
		case "ArrowUp":    handle_move_key_event(pressed, e.key.repeat, false, .NORTH);
		case "ArrowDown":  handle_move_key_event(pressed, e.key.repeat, false, .SOUTH);
		
		case "KeyA": handle_move_key_event(pressed, e.key.repeat, true, .WEST);
		case "KeyD": handle_move_key_event(pressed, e.key.repeat, true, .EAST);
		case "KeyW": handle_move_key_event(pressed, e.key.repeat, true, .NORTH);
		case "KeyS": handle_move_key_event(pressed, e.key.repeat, true, .SOUTH);

		case "Digit1": {
			//app.game.my_team = 0;
			//app.game.enemy_team = 1;
			app.game.placing_monster_type = Monster_Type(0);
		}
		case "Digit2": {
			//app.game.my_team = 1;
			//app.game.enemy_team = 0;
			app.game.placing_monster_type = Monster_Type(1);
		}
	}
}

handle_mouse_up_down_event :: proc(e: js.Event) {
	//log("Mouse down!\n");
	//log(e.id);
	//log_int(cast(int)e.mouse.page.x);
	//log_int(cast(int)e.mouse.page.y);

	mouse_window_p.x = i32(e.mouse.page.x);
	mouse_window_p.y = i32(e.mouse.page.y);
	mouse_p = linalg.array_cast(mouse_window_p, f32);

	if(e.mouse.button == 0) {
		left_mouse_is_down = e.kind == .Mouse_Down;
		if(left_mouse_is_down) {
			left_mouse_got_pressed = true;
		}
	}
}

handle_mouse_move_event :: proc(e: js.Event) {
	mouse_window_p.x = i32(e.mouse.page.x);
	mouse_window_p.y = i32(e.mouse.page.y);
	mouse_p = linalg.array_cast(mouse_window_p, f32);
}

load_file :: proc(type: File_Type, path: string) -> ^Fetching_File {
	assert(file_queue_count < len(file_queue));


	result := &file_queue[file_queue_count];
	file_queue_count += 1;

	result.index = fetch_file(path);
	result.type = type;
	result.debug_path = strings.clone(path);

	return result;
}

load_texture :: proc(path: string, texture: ^Texture, repeat := false) {
	file := load_file(.TEXTURE, path);

	file.texture = texture;
	file.texture_repeat = repeat;
}

load_bitmap :: proc(path: string, bitmap: ^Bitmap) {
	file := load_file(.BITMAP, path);
	file.bitmap = bitmap;
}

file_queue: [128]Fetching_File;
file_queue_count: int = 0;

File_Type :: enum {
	TEXTURE,
	BITMAP,
	//LEVEL,
	//PLAYLIST,
}

Fetching_File :: struct {
	index: int,	
	type: File_Type,
	texture: ^Texture,
	texture_repeat: bool,
	bitmap: ^Bitmap,
	data_target: ^File_Data,
	debug_path: string,
}


@export _end :: proc() {

}

handle_fetched_file :: proc(ff: ^Fetching_File, buffer: []u8) {
	switch(ff.type) {
		case .TEXTURE: {
			assert(ff.texture != nil);
			width, height, channels_in_file: int;
			channels := 4;
			pixels := stb_image.stbi_load_png_from_memory(buffer, &width, &height, &channels_in_file, channels);

			if pixels == nil {
				log("Failed to load texture!\n");
				log(ff.debug_path);

				gen_pixels := make([]u8, width*height*channels, context.temp_allocator);
				for yy in 0..<height {
					for xx in 0..<width {
						gen_pixels[(xx + yy * width)*channels + 0] = cast(u8)(xx*255/width); 
						gen_pixels[(xx + yy * width)*channels + 1] = cast(u8)(yy*255/height); 
						gen_pixels[(xx + yy * width)*channels + 2] = xx > width/2 ? 255 : 0; 
						gen_pixels[(xx + yy * width)*channels + 3] = 255;
					}
				}
				pixels = raw_data(gen_pixels[:]);
			}
			else {
				texture := GL.CreateTexture();
				ff.texture^ = {
					id = cast(u32)texture,
					width = cast(i32)width,
					height = cast(i32)height,
				};

				GL.BindTexture(GL.TEXTURE_2D, texture);

				
				GL.TexImage2D(GL.TEXTURE_2D, 0, GL.RGBA, cast(i32)width, cast(i32)height, 0, GL.RGBA, GL.UNSIGNED_BYTE, int(width*height*channels), pixels);
				wrap := ff.texture_repeat ? i32(GL.REPEAT) : i32(GL.CLAMP_TO_EDGE);
				GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, wrap);
				GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, wrap);
				GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, i32(GL.LINEAR));
				GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, i32(GL.LINEAR));
			}
		}
		case .BITMAP: {
			assert(ff.bitmap != nil);
			width, height, channels_in_file: int;
			channels := 4;
			pixels := stb_image.stbi_load_png_from_memory(buffer, &width, &height, &channels_in_file, channels);

			if pixels == nil {
				fmt.printf("Failed to load bitmap: %s!\n", ff.debug_path);
			}
			else {
				ff.bitmap^ = {
					pixels = cast([^]u8)pixels,
					width = cast(i32)width,
					height = cast(i32)height,
				};
			}
		}
		/*case .LEVEL: {
			if ff.data_target != nil {
				if len(ff.data_target.memory) >= len(buffer) {
					ff.data_target.count = len(buffer);
					mem.copy(&ff.data_target.memory[0], &buffer[0], len(buffer));
				} 
				else {
					log("Not enough memory for level file data\n");
					ff.data_target.count = 0;
				}
			}
			else {
				//log(ff.debug_path);
				//log(transmute(string)buffer);
				if(!load_level_from_memory(&app.playing_level, buffer)) {
					app.playing_level = Level{dim = {7, 7}};
					log("Failed to load level!\n");
				}
				start_playing_level(&app);
			}
		}
		case .PLAYLIST: {
			app.playlist = load_playlist_from_memory(buffer);
			app.is_playing_playlist = true;
			load_level_file(app.playlist.levels[0]);
		}*/		
	}
}

app_initialized := false;

@export step :: proc(dt_arg: f32) {
	context.allocator = main_allocator;
	context.temp_allocator = temp_allocator;
	mem.free_all(temp_allocator);


	for ii := 0; ii < file_queue_count; ii += 1 {
		ff := &file_queue[ii];

		if is_file_fetching_done(ff.index) {

			length := get_fetched_file_length(ff.index);
			buffer := make([]u8, length, context.temp_allocator);
			get_fetched_file_data(ff.index, raw_data(buffer[:]));

			handle_fetched_file(ff, buffer);

			file_queue_count -= 1;
			if ii < file_queue_count {
				file_queue[ii] = file_queue[file_queue_count];
				ii -= 1;
			}
		}
	}
	if(file_queue_count > 0) do return;

	if !app_initialized {
		app_init();
		app_initialized = true;
	}

	time := ms_now();
	dt = math.min(MAX_DT, (time - prev_time_ms) * 0.001);

	prev_time_ms = time;
	
	new_window_width := GL.DrawingBufferWidth();
	new_window_height := GL.DrawingBufferHeight();
	if new_window_width != window_width || new_window_height != window_height {
		window_width = new_window_width;
		window_height = new_window_height;
		window_size = {f32(window_width), f32(window_height)};
	}

	app_tick_and_draw();

	left_mouse_got_pressed = false;
}

get_time :: proc() -> f32 {
	return ms_now()*0.001;
}

Timer :: struct {
	start_ms: f32,
}

timer_start :: proc() -> Timer {
	return {
		start_ms = ms_now(),
	};
}

timer_elapsed :: proc(timer: Timer) -> f32 {
	t := ms_now() - timer.start_ms;
	return t;	
}

timer_restart :: proc(timer: ^Timer) -> f32 {
	now := ms_now();
	t := now - timer.start_ms;
	timer.start_ms = now;
	return t;
}