//+build windows
package main

import SDL "vendor:sdl2"
import Mixer "vendor:sdl2/mixer"
import GL "vendor:OpenGL"
import "core:os";
import "core:fmt"
import "core:math/linalg"
import "core:strings"
import "core:math"
import "core:math/rand"
import "core:c"
import "core:time"


/*import c "core:c/libc"
import "vendor:stb/image"*/
import "core:mem"

load_level_file_data :: proc(path: string, data_target: ^File_Data) { 
	data_target.count = 0;
	data, success := os.read_entire_file(path, context.temp_allocator);
	if !success do return;

	if(len(data_target.memory) >= len(data)) {
		mem.copy(&data_target.memory[0], &data[0], len(data));
		data_target.count = len(data);
	}
	else {		
		fmt.printf("Not enough memory for file data\n");
	}
}

sounds: map[string]^Mixer.Chunk;
music : ^Mixer.Music;

play_sound :: proc(path: string, volume: f32 = 1.0) {
	chunk, was_loaded := sounds[path];
	if !was_loaded {
		chunk = Mixer.LoadWAV(strings.clone_to_cstring(path, context.temp_allocator));
		sounds[path] = chunk;
		if chunk == nil {
			fmt.printf("Failed to load sound: %s\n", SDL.GetError());
		}
	}

	if chunk != nil {
		channel := Mixer.PlayChannel(-1, chunk, 0);
		Mixer.Volume(channel, c.int(volume*f32(Mixer.MAX_VOLUME)));
	}
}

platform_set_music_volume :: proc(volume: f32) {
	Mixer.VolumeMusic(c.int(volume*f32(Mixer.MAX_VOLUME)));
}

main :: proc() {

	if(SDL.Init(SDL.INIT_VIDEO|SDL.INIT_AUDIO) != 0) {
		fmt.printf("Failed to init SDL\n");
		return;
	}
	if Mixer.OpenAudio(Mixer.DEFAULT_FREQUENCY, Mixer.DEFAULT_FORMAT, 1, 0) != 0 {
		fmt.printf("Failed to open Audio: %s\n", SDL.GetError());
	}

	app.music_volume = 0.25;
	music = Mixer.LoadMUS("res/dominatione.ogg");
	if music != nil {
		platform_set_music_volume(app.music_volume);
		Mixer.PlayMusic(music, -1);
	}

	window_base_size : i32 = 100;
	window_width = 16*window_base_size;
	window_height = 9*window_base_size;
	window_flags : SDL.WindowFlags = {SDL.WindowFlag.OPENGL, SDL.WindowFlag.SHOWN};
	display_mode: SDL.DisplayMode;
	fullscreen := false;
	if(fullscreen && SDL.GetDesktopDisplayMode(0, &display_mode) == 0) {
		window_width = display_mode.w;
		window_height = display_mode.h;
		window_flags |= {SDL.WindowFlag.BORDERLESS};
	}
	else {
		fullscreen = false;
	}
	window := SDL.CreateWindow("Game", SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, window_width, window_height, window_flags);
	ww, wh: c.int;
	SDL.GetWindowSize(window, &ww, &wh);
	window_width = ww;
	window_height = wh;
	window_size = {f32(ww), f32(wh)};


	gl_context := SDL.GL_CreateContext(window);
	if(gl_context == nil) {
		fmt.printf("Failed to create GL context!\n");
		return;
	}
	GL.load_up_to(3, 3, SDL.gl_set_proc_address);
	SDL.GL_SetSwapInterval(1);
 
 	init_draw();

 	when false {
 		// Generate territory shading table
	 	for ii in 0..<MAX_TERRITORIES {
	 		if ii % 10 == 0 {
	 			fmt.printf("\n");
	 		}
	 		fmt.printf("%f, ", rand.float32_range(0.9, 1.2));
	 	}
 	}

	when ODIN_OS == .Windows {
		ok: bool;
		font, ok = read_font_from_file("C:\\windows\\fonts\\consolab.ttf", FONT_SIZE);
		world_font, ok = read_font_from_file("C:\\windows\\fonts\\consola.ttf", 17);
	}	
	rand.set_global_seed(cast(u64)time.now()._nsec);
	
	app.window = window;
	app.is_fullscreen = fullscreen;

	load_assets();
	app_init();
	//init_game(&app.game);

	frame_timer := timer_start();

	running := true;
	for running {
		dt = timer_restart(&frame_timer);
		if dt > MAX_DT do dt = MAX_DT;

		left_mouse_got_pressed = false;
		event: SDL.Event;
		for SDL.PollEvent(&event) {
			#partial switch event.type {
				case SDL.EventType.QUIT:
					running = false;

				case SDL.EventType.KEYDOWN, SDL.EventType.KEYUP: {
					key_mod := event.key.keysym.mod&{SDL.KeymodFlag.LCTRL, SDL.KeymodFlag.LSHIFT, SDL.KeymodFlag.LALT};
					pressed := event.key.type == SDL.EventType.KEYDOWN;
					#partial switch(event.key.keysym.sym) {
						case .Q:  
							if(key_mod == {.LCTRL}) {
								running = false;
							}

						case .D: handle_move_key_event(pressed, event.key.repeat > 0, true, .EAST);
						case .W: handle_move_key_event(pressed, event.key.repeat > 0, true, .NORTH);
						case .A: handle_move_key_event(pressed, event.key.repeat > 0, true, .WEST);
						case .S: handle_move_key_event(pressed, event.key.repeat > 0, true, .SOUTH);

						case .RIGHT: handle_move_key_event(pressed, event.key.repeat > 0, false, .EAST);
						case .UP:    handle_move_key_event(pressed, event.key.repeat > 0, false, .NORTH);
						case .LEFT:  handle_move_key_event(pressed, event.key.repeat > 0, false, .WEST);
						case .DOWN:  handle_move_key_event(pressed, event.key.repeat > 0, false, .SOUTH);

						case .NUM1: {
							app.game.placing_monster_type = Monster_Type(0);
							//app.game.my_team = 0;
							//app.game.enemy_team = 1;
						}
						case .NUM2: {
							app.game.placing_monster_type = Monster_Type(1);
							//app.game.my_team = 1;
							//app.game.enemy_team = 0;
						}
					}
				}
				case SDL.EventType.MOUSEBUTTONDOWN: {
					if(event.button.button == SDL.BUTTON_LEFT) {
						left_mouse_is_down = true;
						left_mouse_got_pressed = true;
					}
				}
				case SDL.EventType.MOUSEBUTTONUP: {
					if(event.button.button == SDL.BUTTON_LEFT) {
						left_mouse_is_down = false;
					}
				}
				case SDL.EventType.MOUSEMOTION: {
					mouse_window_p = {event.motion.x, event.motion.y};
					mouse_p = {auto_cast event.motion.x, auto_cast event.motion.y};
				}
			}
		}

		app_tick_and_draw();

		SDL.GL_SwapWindow(window);
	}

	SDL.GL_DeleteContext(gl_context);
	SDL.Quit();
}

startup_time : u64 = SDL.GetPerformanceCounter(); 
get_time :: proc() -> f32 {
	t := SDL.GetPerformanceCounter() - startup_time;
	f := SDL.GetPerformanceFrequency();
	return cast(f32)t / cast(f32)f;
}

Timer :: struct {
	ticks: u64,
}

timer_start :: proc() -> Timer {
	return {
		ticks = SDL.GetPerformanceCounter(),
	};
}

timer_elapsed :: proc(timer: Timer) -> f32 {
	t := SDL.GetPerformanceCounter() - timer.ticks;
	f := SDL.GetPerformanceFrequency();
	return cast(f32)t / cast(f32)f;	
}

timer_restart :: proc(timer: ^Timer) -> f32 {
	now := SDL.GetPerformanceCounter();
	t := now - timer.ticks;
	f := SDL.GetPerformanceFrequency();
	timer.ticks = now;
	return cast(f32)t / cast(f32)f;		
}
