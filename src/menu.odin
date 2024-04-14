package main

import "core:math/linalg"
import "core:math"

Menu_State :: enum {
	Main,
	Picking_Map,
	Picking_Player,
	Help,
}
Menu :: struct {
	state: Menu_State,
	button_size: Vec2,
	button_theme: Button_Theme,
}


menu_picking_map :: proc(menu: ^Menu) {
	y := window_size.y * 0.1;

	draw_text("Pick map", &font, {window_size.x*0.5, y}, .Center, .Top, {1, 1, 1, 1});

	y += window_size.y * 0.1;

	map_texts := [4]string {
		"2",
		"3",
		"4",
		"EU"
	};
	map_count := len(map_texts);
	map_button_size: Vec2 = window_size.y * 0.15;
	map_button_x_spacing := window_size.x * 0.05;
	map_button_x := (window_size.x - f32(map_count)*map_button_size.x - f32(map_count-1)*map_button_x_spacing) * 0.5;
	for pi in 0..<map_count {		
		map_button_theme := Button_Theme {
			bg_color_normal = {0.3, 0.3, 0.3, 1.0},
			bg_color_hovered = {0.4, 0.4, 0.4, 1.0},
			bd_color_normal = {0.7, 0.7, 0.7, 1.0},
			bd_color_hovered = {0.9, 0.9, 0.9, 1.0},
		};

		if app.selected_map_index == pi {
			map_button_theme.bd_width = map_button_size.x * 0.1;
		}	
		rect := rect_min_size({map_button_x, y}, map_button_size);
		if text_button(rect, map_button_theme, map_texts[pi]) {
			app.selected_map_index = pi;
		}
		map_button_x += map_button_size.x + map_button_x_spacing;
	}
	y += map_button_size.y * 1.1;

	y = window_size.y*0.5;
	back_button_rect := rect_min_size({window_size.x*0.5 - menu.button_size.x*1.1, y}, menu.button_size);
	if text_button(back_button_rect, menu.button_theme, "Back") {
		menu.state = .Main;
	}
	start_button_rect := rect_min_size({window_size.x*0.5 + menu.button_size.x*0.1, y}, menu.button_size);
	if text_button(start_button_rect, menu.button_theme, "Next") {
		menu.state = .Picking_Player;
	}
}

menu_picking_player :: proc(menu: ^Menu) {
	y := window_size.y * 0.1;
	map_index := app.selected_map_index;
	team_count := map_team_counts[map_index];
	if app.selected_player_index >= team_count {
		app.selected_player_index = 0;
	}
	draw_text("Pick color", &font, {window_size.x*0.5, y}, .Center, .Top, {1, 1, 1, 1});

	y += window_size.y * 0.1;

	player_button_size: Vec2 = window_size.y * 0.15;
	player_button_x_spacing := window_size.x * 0.05;
	player_button_x := (window_size.x - f32(team_count)*player_button_size.x - f32(team_count-1)*player_button_x_spacing) * 0.5;
	player_difficulty_text := [3]string {
		"Easy",
		"Medium",
		"Hard",
	};
	for pi in 0..<team_count {
		player_button_theme := Button_Theme {
			bg_color_normal = TEAM_COLORS[pi],
			bg_color_hovered = linalg.lerp(TEAM_COLORS[pi], Vec4{1, 1, 1, 1}, 0.5),
			bd_color_normal = {0.7, 0.7, 0.7, 1.0},
			bd_color_hovered = {0.9, 0.9, 0.9, 1.0},
		};

		if app.selected_player_index == pi {
			player_button_theme.bd_width = player_button_size.x * 0.1;
		}
		rect := rect_min_size({player_button_x, y}, player_button_size);
		difficulty := map_team_index_difficulty[map_index][pi];
		if text_button(rect, player_button_theme, player_difficulty_text[difficulty]) {
			app.selected_player_index = pi;
		}
		player_button_x += player_button_size.x + player_button_x_spacing;
	}
	y += player_button_size.y * 1.1;

	y = window_size.y*0.5;

	back_button_rect := rect_min_size({window_size.x*0.5 - menu.button_size.x*1.1, y}, menu.button_size);
	if text_button(back_button_rect, menu.button_theme, "Back") {
		menu.state = .Picking_Map;
	}
	start_button_rect := rect_min_size({window_size.x*0.5 + menu.button_size.x*0.1, y}, menu.button_size);
	if text_button(start_button_rect, menu.button_theme, "Start") {
		app.state = .Game;
		init_game(&app.game);
	}
}

menu_main :: proc(menu: ^Menu) {
	cover_size := math.min(window_size.x, window_size.y);
	rotation := get_time()*0.5;

	draw_textured_rect_center_size_direction(&cover_texture, window_size*0.5, cover_size, {math.cos(rotation), math.sin(rotation)});
	Menu_Button :: enum {
		Play,
		Help,
	}
	button_texts := [Menu_Button]string {
		.Play = "Play",
		.Help = "Help",
	}

	slider_size := Vec2{window_size.y*0.4, window_size.y*0.05};
	slider_rect := rect_min_size({(window_size.x-slider_size.x)*0.5, window_size.y*0.2}, slider_size);
	do_volume_slider(slider_rect);

	button_rect := rect_min_size(window_size*0.5 - menu.button_size*0.5, menu.button_size);
	pressed_button := Menu_Button(-1);
	for bi in Menu_Button {
		if text_button(button_rect, menu.button_theme, button_texts[bi]) {
			pressed_button = bi;
		}

		button_rect = rect_move(button_rect, {0, menu.button_size.y * 1.1});
	}

	switch pressed_button {
		case .Play: {
			menu.state = .Picking_Map;
		}
		case .Help: {
			menu.state = .Help;
		}
		case: {

		}
	}
}

HELP_TEXT_LINES := []string {
	"Monster World Domination",
	"",
	//"How to play",
	"You can summon monters by left clicking somewhere inside",
	"your territory. Every monster costs 5 mana.",
	"",
	"There are two type of monsters:",
	"-Ghost: Mobile melee fighter, can capture flags.",
	"-Skeleton: Stationary killing machine with a ranged attack.",
	"",
	
	"Territories give mana every second to the owner.",
	"",
	"Monsters take damage over time, slowly dying for no reason.",
	"Monsters always target the closest enemy monster or flag.",

	"Controls:",
	"	Num1: Select Ghost for placing",
	"	Num2: Select Skeleton for placing",
	"	Left mouse: Summon monster",
};

menu_help :: proc(menu: ^Menu) {
	y := window_size.y * 0.05;

	for line in HELP_TEXT_LINES {
		draw_text(line, &font, {window_size.x*0.1, y}, .Left, .Top, {1, 1, 1, 1});
		y += FONT_SIZE*1.2;
	}

	//y := window_size.y*0.8;
	y = math.min(y, window_size.y - menu.button_size.y*1.2);
	back_button_rect := rect_min_size({window_size.x*0.5 - menu.button_size.x*0.5, y}, menu.button_size);
	if text_button(back_button_rect, menu.button_theme, "Back") {
		menu.state = .Main;
	}
}

menu_tick_and_draw :: proc() {
	bg := Vec3{16.0/255.0, 17.0/255.0, 48.0/255.0};
	start_draw_frame(bg);

	view_projection := linalg.matrix_ortho3d_f32(0, window_size.x, window_size.y, 0, -1.0, 1.0);	
		set_view_projection(view_projection);

	menu := &app.menu;
	menu.button_size = Vec2{FONT_SIZE*10, FONT_SIZE*3};
	menu.button_theme = {
		bg_color_normal = {0.8, 0.8, 0.8, 1.0},
		bg_color_hovered = {1, 1, 0.95, 1},
		bd_color_normal = {0.2, 0.15, 0.15, 1.0},
		bd_color_hovered = {0.32, 0.27, 0.27, 1.0},
		bd_width = menu.button_size.y * 0.1,
	};


	switch app.menu.state {
		case .Main: menu_main(menu);
		case .Picking_Map: menu_picking_map(menu);
		case .Picking_Player: menu_picking_player(menu);
		case .Help: menu_help(menu);
	}
}
