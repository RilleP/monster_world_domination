package main

import "core:math"
import "core:math/linalg"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:math/rand"

display_territory_debug_info := !true;
world_font: Font;

Vec2 :: [2]f32;
Vec3 :: [3]f32;
Vec4 :: [4]f32;
Matrix4 :: linalg.Matrix4f32;
Vec2i :: [2]i32;

TILE_SIZE :: 1;
ENTITY_SCALE :: f32(10);

MONSTER_MANA_COST :: 5;

ATTACK_RANGE := [Monster_Type]f32 {
	.Ghost = 10.0,
	.Archer = 25.0,
}
MONSTER_CAN_WALK := [Monster_Type]bool {
	.Ghost = true,
	.Archer = false,
}


ATTACK_PRE_DURATION := [Monster_Type]f32 {
	.Ghost = 0.2,
	.Archer = 0.1,
}

ATTACK_POST_DURATION := [Monster_Type]f32 {
	.Ghost = 0.5,
	.Archer = 0.3,
}

/*ATTACK_DURATION := [Monster_Type]f32 { // This does not work in WASM
	.Ghost = ATTACK_PRE_DURATION[.Ghost] + ATTACK_POST_DURATION[.Ghost],
	.Archer = ATTACK_PRE_DURATION[.Archer] + ATTACK_POST_DURATION[.Archer],
}*/

ATTACK_DAMAGE :: int(10);

MONSTER_COLLISION_RADIUS :: 4;
MONSTER_COLLISION_RADIUS2 :: MONSTER_COLLISION_RADIUS*MONSTER_COLLISION_RADIUS;

MOVE_SPEED :: f32(10);

MAX_TARGET_DISTANCE  :: 40;
MAX_TARGET_DISTANCE2 :: MAX_TARGET_DISTANCE*MAX_TARGET_DISTANCE;

MAX_TARGET_PRIORITY_OVERRIDE_DISTANCE :: 20;
MAX_TARGET_PRIORITY_OVERRIDE_DISTANCE2 :: MAX_TARGET_PRIORITY_OVERRIDE_DISTANCE*MAX_TARGET_PRIORITY_OVERRIDE_DISTANCE;
SPAWN_DURATION :: 3;

Direction :: enum {
	EAST,
	NORTH,
	WEST,
	SOUTH,
}

FDIR := [Direction]Vec2 {
	.EAST  = { 1,  0},
	.NORTH = { 0, -1},
	.WEST  = {-1,  0},
	.SOUTH = { 0,  1},
};


File_Data :: struct {
	memory: []u8,
	count: int,
}

Team_Id :: i8;
TEAM_COUNT :: Team_Id(4);
NO_TEAM : Team_Id : TEAM_COUNT;

TEAM_COLORS := [TEAM_COUNT+1]Vec4 {
	{0.2, 0.7, 0.2, 1},
	{0.55, 0.2, 0.6, 1},
	{0.6, 0.2, 0.2, 1},
	{0.7, 0.6, 0.2, 1},
	{0.7, 0.7, 0.7, 1},
}

TEAM_GROUND_COLORS := [TEAM_COUNT+1]Vec4 {
	{0.2, 0.4, 0.2, 1},
	{0.4, 0.2, 0.43, 1},
	{0.45, 0.2, 0.2, 1},
	{0.55, 0.45, 0.2, 1},
	{0.5, 0.5, 0.5, 1},
}

TERRITORY_DRAW_COLORS := []Vec4 {
	{1, 0, 0, 1},
	{0, 1, 0, 1},
	{0, 0, 1, 1},
	{1, 1, 0, 1},
	{1, 0, 1, 1},
	{0, 1, 1, 1},
};

Territory_Id :: u8;
NO_TERRITORY :: u8(0xff);
WATER_TERRITORY :: u8(254);
TEMPORARY_FLAG_TERRITORY :: u8(253);

Territory :: struct {
	flag_id: Entity_Id,
	team: Team_Id,	
}

Territory_Info :: struct {
	team_monsters_here:      [TEAM_COUNT]i16,
	team_monsters_dest:      [TEAM_COUNT]i16,
	next_team_monsters_here: [TEAM_COUNT]i16,
	next_team_monsters_dest: [TEAM_COUNT]i16,

	closest_point_to_flag: [MAX_TERRITORIES]Vec2,
	can_see_flag: [MAX_TERRITORIES]bool,
}

Monster_Flags :: enum {
	SPAWNING,
	ATTACKING,
}

Monster_Type :: enum {
	Ghost,
	Archer,
}

Monster :: struct {
	type: Monster_Type,
	flags: bit_set[Monster_Flags],
	target_entity_id: Entity_Id,
	target_position: Vec2,
	retarget_timer: f32,
	action_timer: f32,
	hp: int,
}

Flag :: struct {
	territory_id: Territory_Id,
	capturing_team: Team_Id,
	capturing_timer: f32,
}

Entity_Id :: u32;
NULL_ENTITY_ID :: 0;

Entity :: struct {
	id: Entity_Id,
	position: Vec2,
	team: Team_Id,
	subtype: union {
		Monster,
		Flag,
	},
}

Projectile :: struct {
	target: Entity_Id,
	position: Vec2,
	//velocity: Vec2,
	//lifetime: f32,
	damage: int,
}

Team_Data :: struct {
	mana: int,
}


MAX_TERRITORIES :: 100;
territory_shading: [MAX_TERRITORIES]f32 = {
	0.974, 0.921, 1.052, 1.134, 0.994, 1.012, 1.021, 1.120, 1.191, 0.938, 
0.934, 1.076, 0.994, 1.160, 0.971, 1.166, 1.072, 0.929, 1.080, 1.140, 
1.122, 1.036, 1.175, 0.915, 1.133, 1.127, 1.103, 1.008, 0.960, 1.143, 
1.156, 0.911, 0.974, 1.039, 1.080, 1.046, 1.119, 1.132, 0.986, 1.077, 
0.939, 1.025, 1.006, 1.172, 1.169, 1.103, 1.097, 1.101, 1.192, 0.923, 
1.045, 0.901, 1.140, 0.929, 0.985, 0.910, 0.948, 1.061, 1.163, 1.127, 
1.027, 0.970, 0.920, 0.952, 1.098, 1.093, 0.997, 1.164, 1.171, 1.098, 
1.114, 0.993, 1.080, 1.065, 0.997, 1.013, 0.950, 0.946, 1.174, 1.102, 
1.136, 1.131, 1.191, 1.176, 0.977, 1.120, 1.068, 1.145, 1.121, 0.974, 
1.192, 0.992, 1.049, 1.101, 1.134, 0.939, 1.013, 0.945, 1.126, 0.946
}

MAX_ENTITIES :: 2048;
MAX_PROJECTILES :: 2048;
Game :: struct {

	game_over: bool,
	victorious_team: Team_Id,

	team_flag_count: [TEAM_COUNT]int,
	team_monster_count: [TEAM_COUNT]int,
	paused: bool,
	territories: [MAX_TERRITORIES]Territory,
	territory_count: u8,

	territory_infos: [MAX_TERRITORIES]Territory_Info,



	entities: [MAX_ENTITIES]Entity,
	top_entity_index: Entity_Id,

	projectiles: [MAX_PROJECTILES]Projectile,
	projectile_count: int,

	placing_monster_type: Monster_Type,
	my_team: Team_Id,
	//enemy_team: Team_Id,

	team_data: [TEAM_COUNT]Team_Data,

	computer_players: [TEAM_COUNT]Computer_Player,

	level_dim: Vec2i,
	tiles: []u8,
	tiles_closest_flag: []u8,

	level_size: Vec2,
	view_center: Vec2,
	view_size: Vec2,

	second_tick_timer: f32,

	display_pause_menu: bool,
}

Entity_Iterator :: struct {
	game: ^Game,
	id: Entity_Id,
}

entity_iterator_start :: proc(game: ^Game) -> Entity_Iterator {
	return {
		game = game,
		id = 0,
	};
}

entity_iterator_all :: proc(it: ^Entity_Iterator) -> (e: ^Entity, result_index: int, ok: bool) {
	for {
		it.id += 1;
		if it.id >= it.game.top_entity_index {
			return nil, -1, false;
		}
		e = &it.game.entities[it.id];
		if e.id == it.id {
			return e, cast(int)it.id, true;
		}
	}
}

app: App;
time : f32;
MAX_DT :: 1.0 / 10.0;
dt : f32 = 0.0;
mouse_window_p: Vec2i;
mouse_p: Vec2;
mouse_ui: Vec2;
left_mouse_is_down: bool;
left_mouse_got_pressed: bool;

direction_input_is_down: [Direction][2]bool;

App_State :: enum {
	Menu,
	Game,
}

App :: struct {
	window: rawptr,
	is_fullscreen: bool,
	state: App_State,
	menu: Menu,
	game: Game,

	selected_player_index: int,
	selected_map_index: int,

	music_volume: f32,
}

assign_flag_territory :: proc(game: ^Game, flag_e: ^Entity, flag: ^Flag) {
	assert(game.territory_count < MAX_TERRITORIES);
	flag.territory_id = cast(u8)game.territory_count;
	game.territory_count += 1;

	game.territories[flag.territory_id].flag_id = flag_e.id;
}

init_game :: proc(game: ^Game) -> (success: bool) {	
	game.paused = true;
	game.game_over = false;
	game.victorious_team = NO_TEAM;


	game.top_entity_index = 1;
	game.projectile_count = 0;
	game.placing_monster_type = .Ghost;
	game.second_tick_timer = 0;
	game.display_pause_menu = false;

	game.my_team = Team_Id(app.selected_player_index);
	//game.enemy_team = 1;

	if !setup_map_from_bitmap(game, map_bitmaps[app.selected_map_index]) {
		fmt.printf("FAILED TO SETUP MAP\n");
		return false;
	}
	//if !setup_test_map(game) do return false;

	game.view_size.y = game.level_size.y;	
	level_center := game.level_size*0.5;
	game.view_center = level_center;
	
	for team in 0..<TEAM_COUNT {
		game.team_data[team] = {
			mana = 10,
		};
		
		game.computer_players[team] = {
			team = Team_Id(team),
		};
	}
	success = true;
	return;
}

deinit_game :: proc(game: ^Game) {
	
}

allocate_map :: proc(game: ^Game, dim: Vec2i) -> bool {
	if game.level_dim == dim {
		fmt.printf("Map was already allocated\n");
		slice.zero(game.tiles);
		slice.zero(game.tiles_closest_flag);
	}
	else {
		game.level_dim = dim;
		fmt.printf("Map dim %v\n", game.level_dim);
		game.level_size = linalg.array_cast(game.level_dim, f32);
		allocator_error: mem.Allocator_Error;
		tile_memory: rawptr;
		num_tiles := int(game.level_dim.x * game.level_dim.y);
		tile_memory, allocator_error = mem.alloc(num_tiles * size_of(game.tiles[0]));
		if allocator_error != .None {
			fmt.printf("Failed to allocate level\n");
			return false;
		}
		game.tiles = slice.from_ptr(cast(^u8)tile_memory, num_tiles);	

		game.tiles_closest_flag = make([]u8, num_tiles);
	}
	return true;
}

calculate_territory_connections :: proc(game: ^Game) {
	game.territory_infos = {};

	for ty in 0..<game.level_dim.y {
	for tx in 0..<game.level_dim.x {
		tile_index := tx + ty * game.level_dim.x;
		ti := game.tiles[tile_index];
		tile_pos := Vec2{f32(tx), f32(ty)};
		if ti < game.territory_count {
			tinfo := &game.territory_infos[ti];

			closest_flag_distance2: f32;
			closest_flag_ti := NO_TERRITORY;
			for oi in 0..<game.territory_count {
				if oi == ti do continue;
				other_flag_position := get_entity(game, game.territories[oi].flag_id).position;

				d2 := linalg.length2(tile_pos - other_flag_position);
				/*if d2 <= MAX_TARGET_DISTANCE2 && (!tinfo.can_see_flag[oi] || d2 < linalg.length2(tile_pos - tinfo.closest_point_to_flag[oi])) {
					tinfo.closest_point_to_flag[oi] = tile_pos;
					tinfo.can_see_flag[oi] = true;
				}*/
				if closest_flag_ti == NO_TERRITORY || d2 < closest_flag_distance2 {
					closest_flag_ti = oi;
					closest_flag_distance2 = d2;
				}
			}
			game.tiles_closest_flag[tile_index] = closest_flag_ti;
			if closest_flag_ti != NO_TERRITORY {
				if closest_flag_distance2 < MAX_TARGET_DISTANCE2 && (!tinfo.can_see_flag[closest_flag_ti] || closest_flag_distance2 < linalg.length2(tile_pos - tinfo.closest_point_to_flag[closest_flag_ti])) {
					tinfo.closest_point_to_flag[closest_flag_ti] = tile_pos;
					tinfo.can_see_flag[closest_flag_ti] = true;
				}
			}
		}
		else {
			game.tiles_closest_flag[tile_index] = NO_TERRITORY;
		}
	}}			
}

setup_map_from_bitmap :: proc(game: ^Game, map_bitmap: Bitmap) -> bool {
	game.territory_count = 0;
	game.territories = {};

	WATER_PIXEL :: (63<<0) | (72<<8) | (204<<16) | (255<<24);
	FLAG_PIXEL  :: 0xff000000;
	TEAM_STARTING_TERRITORY_PIXELS := [4]u32 {
		(34<<0) | (177<<8) | (76<<16)  | (255<<24), // GREEN
		(163<<0) | (73<<8) | (164<<16) | (255<<24), // PURPLE
		(136<<0) | (0<<8) | (21<<16) | (255<<24), // RED
		(136<<0) | (194<<8) | (21<<16) | (255<<24), // ORANGE
	};
	#assert(len(TEAM_STARTING_TERRITORY_PIXELS) >= TEAM_COUNT);

	assert(map_bitmap.pixels != nil);

	if !allocate_map(game, {map_bitmap.width, map_bitmap.height}) {
		return false;
	}

	territory_colors: [MAX_TERRITORIES]u32;
	pixels32 := cast([^]u32)map_bitmap.pixels;
	for ty in 0..<game.level_dim.y {
		//fmt.printf("\nRow %d", ty);
	for tx in 0..<game.level_dim.x {
		p := pixels32[tx + ty * game.level_dim.x];
		//fmt.printf("%x ", p);
		tile_index := tx + ty * game.level_dim.x;
		if p == WATER_PIXEL {
			game.tiles[tile_index] = WATER_TERRITORY;
		}
		else if(p == FLAG_PIXEL) {
			game.tiles[tile_index] = TEMPORARY_FLAG_TERRITORY;

			flag_e, flag := add_entity(game, Flag);
			flag_e.position = {f32(tx), f32(ty)} + 0.5;
			flag_e.team = NO_TEAM;	
			flag.capturing_team = NO_TEAM;		
			//assign_flag_territory(game, flag_e, flag);
		}
		else {
			found := false;
			for ti in 0..<game.territory_count {
				if p == territory_colors[ti] {
					game.tiles[tile_index] = u8(ti);
					found = true;
					break;
				}
			}
			if !found {
				ti := u8(game.territory_count);
				game.territory_count += 1;

				territory_colors[ti] = p;
				game.tiles[tile_index] = ti;
			}
		}
	}}

	entity_it := entity_iterator_start(game);
	for e in entity_iterator_all(&entity_it) {
		if flag, is_flag := &e.subtype.(Flag); is_flag {
			cx, cy := i32(e.position.x), i32(e.position.y);
			if game.tiles[cx + cy * game.level_dim.x] != TEMPORARY_FLAG_TERRITORY {
				fmt.printf("The tile under a flag is not TEMPORARY_FLAG_TERRITORY, what???");
				assert(false);
				return false;
			}

			// Just take the territory one tile to the left
			flag.territory_id = game.tiles[(cx-1) + cy * game.level_dim.x];
			e.team = NO_TEAM;
			game.tiles[cx + cy * game.level_dim.x] = flag.territory_id;
			game.territories[flag.territory_id].flag_id = e.id;
			game.territories[flag.territory_id].team = NO_TEAM;
		}
	}
	
	for team in 0..<TEAM_COUNT {
		for ti in 0..<game.territory_count {
			if TEAM_STARTING_TERRITORY_PIXELS[team] == territory_colors[ti] {
				t := &game.territories[ti];
				flag_e := get_entity(game, t.flag_id);
				if flag_e != nil {
					flag_e.team = Team_Id(team);
					t.team = Team_Id(team);
				}
				break;
			}
		}
	}

	calculate_territory_connections(game);

	return true;
}

setup_test_map :: proc(game: ^Game) -> bool {
	if !allocate_map(game, {200, 200}) {
		return false;
	}
	center_flag_e, center_flag := add_entity(game, Flag);
	center_flag_e.position = game.level_size * 0.5;
	center_flag_e.team = NO_TEAM;
	assign_flag_territory(game, center_flag_e, center_flag);

	my_flag_e, my_flag := add_entity(game, Flag);
	my_flag_e.position = {game.level_size.x * 0.1, game.level_size.y * 0.5};
	my_flag_e.team = 0;
	assign_flag_territory(game, my_flag_e, my_flag);

	enemy_flag_e, enemy_flag := add_entity(game, Flag);
	enemy_flag_e.position = {game.level_size.x * 0.9, game.level_size.y * 0.5};
	enemy_flag_e.team = 1;
	assign_flag_territory(game, enemy_flag_e, enemy_flag);

	for ty in 0..<game.level_dim.y {
	for tx in 0..<game.level_dim.x {
		tile_pos := Vec2{f32(tx), f32(ty)};
		entity_it := entity_iterator_start(game);
		closest_territory := NO_TERRITORY;
		closest_distance2: f32;
		for entity in entity_iterator_all(&entity_it) {
			#partial switch sub in entity.subtype {
				case Flag: {
					distance2 := linalg.length2(tile_pos - entity.position);
					if closest_territory == NO_TERRITORY || distance2 < closest_distance2 {
						closest_territory = sub.territory_id;
						closest_distance2 = distance2;
					}
				}
			}
		}
		game.tiles[tx + ty*game.level_dim.x] = closest_territory;
	}}
	return true;
}

pause_icon_texture: Texture;
MONSTER_TEXTURES: [Monster_Type]Texture;
SUMMON_ANIMATION_TEXTURES: [4]Texture;
MAP_COUNT :: 4;
map_bitmaps: [MAP_COUNT]Bitmap;
map_team_counts: [MAP_COUNT]int = {
	2, 3, 4, 4
};


map_team_index_difficulty := [MAP_COUNT][TEAM_COUNT]int {
	0 = {0, 2, 0, 0},
	1 = {1, 1, 1, 0},
	2 = {1, 2, 0, 0},
	3 = {1, 1, 2, 0},
}
load_assets :: proc() {
	load_texture("res/ghost.png", &MONSTER_TEXTURES[.Ghost]);
	load_texture("res/archer.png", &MONSTER_TEXTURES[.Archer]);
	for fi in 0..<len(SUMMON_ANIMATION_TEXTURES) {
		load_texture(fmt.tprintf("res/summon%02d.png", fi+1), &SUMMON_ANIMATION_TEXTURES[fi]);
	}
	load_texture("res/pause_icon2.png", &pause_icon_texture);
	load_bitmap("map2.png", &map_bitmaps[0]);
	load_bitmap("map3.png", &map_bitmaps[1]);
	load_bitmap("map4.png", &map_bitmaps[2]);
	load_bitmap("map_eu.png", &map_bitmaps[3]);
}

get_mouse_level_position :: proc(game: ^Game) -> Vec2 {
	return (mouse_p / window_size) * game.view_size + (game.view_center - game.view_size*0.5)
}

handle_move_key_event :: proc(pressed: bool, repeat: bool, secondary: bool, direction: Direction) {
	direction_input_is_down[direction][int(secondary)] = pressed;
}

input_direction_axis :: proc() -> Vec2 {
	result: Vec2;
	for direction in Direction {
		if direction_input_is_down[direction][0] || direction_input_is_down[direction][1] {
			result += FDIR[direction];
		}
	}

	return linalg.normalize0(result);
}

add_entity :: proc(game: ^Game, $T: typeid) -> (^Entity, ^T) {
	if game.top_entity_index < len(game.entities) {
		defer game.top_entity_index += 1;
		id := game.top_entity_index;
		result := &game.entities[id];
		result.id = id;
		result.subtype = T{};
		return result, &result.subtype.(T);
	}
	return nil, nil;
}

get_entity :: proc(game: ^Game, id: Entity_Id) -> ^Entity {
	if id == 0 {
		return nil;
	}
	e := &game.entities[id];
	if e.id != id {
		return nil;
	}
	return e;
}

find_monster_target :: proc(game: ^Game, e: ^Entity, monster: ^Monster) -> (target_id: Entity_Id, found: bool) {
	can_walk := MONSTER_CAN_WALK[monster.type];

	closest_distance2: f32 = can_walk ? MAX_TARGET_DISTANCE2 : (ATTACK_RANGE[monster.type]*ATTACK_RANGE[monster.type]);
	closest_priority: int = 100;

	entity_it := entity_iterator_start(game);
	for other in entity_iterator_all(&entity_it) {
		if other.team == e.team {
			continue;
		}
		priority := 10;
		_, other_is_monster := other.subtype.(Monster);
		if other_is_monster {
			priority = 1;
		}
		else if !can_walk {
			// Only target monsters if the finder can't walk
			continue;
		}
		distance2 := linalg.length2(other.position - e.position);
		if distance2 < closest_distance2 || (distance2 < MAX_TARGET_PRIORITY_OVERRIDE_DISTANCE2 && priority < closest_priority) {
			closest_priority = priority;
			closest_distance2 = distance2;
			target_id = other.id;
			found = true;
		}
	}
	return;
}

monster_look_for_target :: proc(game: ^Game, e: ^Entity, monster: ^Monster) {
	new_target, found := find_monster_target(game, e, monster);
	if found {
		monster.target_entity_id = new_target;
		monster.retarget_timer = 0;
	}
}


remove_entity :: proc(game: ^Game, e: ^Entity) {
	if game.entities[e.id].id == NULL_ENTITY_ID {
		panic("Tried to remove a null entity");
	}

	game.entities[e.id].id = NULL_ENTITY_ID;
	if e.id+1 == game.top_entity_index {
		game.top_entity_index -= 1;
	}
}


damage_monster :: proc(game: ^Game, e: ^Entity, monster: ^Monster, damage: int) {
	monster.hp -= damage;
	if monster.hp <= 0 {
		remove_entity(game, e);
		DEATH_SOUND_PATHS := []string{
			"res/sounds/death1.ogg",
			"res/sounds/death2.ogg",
			"res/sounds/death1.ogg"
		}
		play_sound(DEATH_SOUND_PATHS[rand.int_max(len(DEATH_SOUND_PATHS))], 0.25);
	}
}
attack_entity :: proc(game: ^Game, e: ^Entity, attacker: ^Entity, damage: int) {
	#partial switch &sub in e.subtype {
		case Monster: {
			damage_monster(game, e, &sub, damage);
		}
	}
}

shoot_projectile :: proc(game: ^Game, target: ^Entity, attacker: ^Entity, damage: int) {
	if game.projectile_count >= MAX_PROJECTILES do return;

	proj := &game.projectiles[game.projectile_count];
	game.projectile_count += 1;

	proj^ = {
		position = attacker.position,
		target = target.id,
		damage = damage,
	}
}

tick_monster :: proc(game: ^Game, e: ^Entity, monster: ^Monster) {
	territory_index := get_territory_id_at_position(game, e.position);
	if territory_index < game.territory_count {
		info := &game.territory_infos[territory_index];
		info.next_team_monsters_here[e.team] += 1;		
	}

	avoidance_vector: Vec2;
	avoidance_denom: f32;
	entity_it := entity_iterator_start(game);
	for other_e in entity_iterator_all(&entity_it) {
		if other_e == e do continue;
		if _, is_monster := other_e.subtype.(Monster); !is_monster do continue;
		v := e.position - other_e.position;
		distance2 := linalg.length2(v);
		if distance2 < MONSTER_COLLISION_RADIUS2 {
			if distance2 < 0.01 {
				avoidance_vector += {rand.float32(), rand.float32()}; // Should it be normalized? Does it matter?
			}
			else {
				distance := math.sqrt(distance2);
				force := 1.0 - (distance / MONSTER_COLLISION_RADIUS);
				avoidance_vector += v * (force*force);
			}
			avoidance_denom += 1.0;
		}
	}
	if avoidance_denom > 0 {
		e.position += avoidance_vector / avoidance_denom;
	}

	if .SPAWNING in monster.flags {
		monster.action_timer += dt;
		if monster.action_timer > SPAWN_DURATION {
			monster.flags -= {.SPAWNING};
			monster.action_timer = 0;
		}
	}
	else {
		target: ^Entity = (monster.target_entity_id != NULL_ENTITY_ID) ? get_entity(game, monster.target_entity_id) : nil;
		if target != nil {
			monster.target_position = target.position;
		}
		else if monster.target_entity_id != NULL_ENTITY_ID {
			monster.retarget_timer = 9999.0; // Force
			monster.target_entity_id = NULL_ENTITY_ID;
		}

		if .ATTACKING in monster.flags {
			old_action_timer := monster.action_timer;
			monster.action_timer += dt;
			if monster.action_timer >= ATTACK_PRE_DURATION[monster.type] && old_action_timer < ATTACK_PRE_DURATION[monster.type] {
				if target != nil {
					if monster.type == .Archer {
						shoot_projectile(game, target, e, ATTACK_DAMAGE);
						SHOOT_SOUND_PATHS := []string{
							"res/sounds/archer_shoot1.ogg",
							"res/sounds/archer_shoot2.ogg",
							"res/sounds/archer_shoot4.ogg"
						}
						play_sound(SHOOT_SOUND_PATHS[rand.int_max(len(SHOOT_SOUND_PATHS))]);
					}
					else {
						attack_entity(game, target, e, ATTACK_DAMAGE);

						HIT_SOUND_PATHS := []string{
							"res/sounds/melee_hit1.ogg",
							"res/sounds/melee_hit2.ogg",
							"res/sounds/melee_hit3.ogg"
						}
						play_sound(HIT_SOUND_PATHS[rand.int_max(len(HIT_SOUND_PATHS))]);
					}
				}
			}
			if(monster.action_timer >= ATTACK_PRE_DURATION[monster.type]+ATTACK_POST_DURATION[monster.type]) {
				monster.flags -= {.ATTACKING};
			}
		}
		else if target != nil {
			target_position := target.position;
			v := target_position - e.position;
			distance := linalg.length(v);
			move_distance := dt * MOVE_SPEED;

			do_move := true;
			#partial switch sub in target.subtype {
				case Monster: {
					if(distance < ATTACK_RANGE[monster.type]) {
						do_move = false;
						monster.action_timer = 0.0;
						monster.flags += {.ATTACKING};
					}
				}
				case Flag: {
					if e.team == target.team {
						do_move = false;
						monster.target_entity_id = NULL_ENTITY_ID;
					}
				}
			}
			
			if do_move {
				direction := v / distance;
				e.position += direction * move_distance;

				territory_index := get_territory_id_at_position(game, target_position);
				if territory_index < game.territory_count {
					info := &game.territory_infos[territory_index];
					info.next_team_monsters_dest[e.team] += 1;
				}
			}

			monster.retarget_timer += dt;
			if monster.retarget_timer > 0.5 {
				monster_look_for_target(game, e, monster);
			}
		}
		else {
			monster.retarget_timer += dt;
			if monster.retarget_timer > 0.5 {
				monster_look_for_target(game, e, monster);
			}
		}
	}
	
}

draw_monster :: proc(e: ^Entity, monster: ^Monster) {
	draw_position := e.position;
	if monster.type != .Archer && .ATTACKING in monster.flags {
		v := monster.target_position - e.position;
		t := f32(0);
		if monster.action_timer < ATTACK_PRE_DURATION[monster.type] {
			t = monster.action_timer / ATTACK_PRE_DURATION[monster.type];
		}
		else {
			t = 1.0 - (monster.action_timer - ATTACK_PRE_DURATION[monster.type]) / ATTACK_POST_DURATION[monster.type];
		}
		draw_position += v * t * 0.5;
	}
	texture: ^Texture = &MONSTER_TEXTURES[monster.type];
	color := TEAM_COLORS[e.team];

	if .SPAWNING in monster.flags {
		t := monster.action_timer / SPAWN_DURATION;
		color.a = t;
		draw_textured_rect_center_size(texture, draw_position, {1, 1}*ENTITY_SCALE, color);
		light := math.cos(t*10)+2.0; 
		
		//particle_color := Vec4{light, light, light, math.min(1, t*5)};
		particle_color := TEAM_COLORS[e.team]*light
		particle_color.a = math.min(1, t*5);
		draw_textured_rect_center_size(&SUMMON_ANIMATION_TEXTURES[int(t*20)%len(SUMMON_ANIMATION_TEXTURES)], draw_position, {1, 1}*ENTITY_SCALE, particle_color);
	}
	else {
		draw_textured_rect_center_size(texture, draw_position, {1, 1}*ENTITY_SCALE, color);
	}
}

tick_flag :: proc(game: ^Game, e: ^Entity, flag: ^Flag) {
	CAPTURE_RADIUS :: f32(5);
	CAPTURE_DURATION :: f32(3);
	team_inside := NO_TEAM;
	entity_it := entity_iterator_start(game);
	for other in entity_iterator_all(&entity_it) {
		if monster, ok := other.subtype.(Monster); ok {
			if .SPAWNING in monster.flags {
				continue;
			}
			distance2 := linalg.length2(other.position - e.position);
			if distance2 < CAPTURE_RADIUS*CAPTURE_RADIUS {
				if team_inside == NO_TEAM {
					team_inside = other.team;
				}
				else if team_inside != other.team {
					// Another team is also capturing, so no one is capturing
					team_inside = NO_TEAM;
					break;
				}
			}
		}
	}
	if team_inside != e.team {
		if flag.capturing_team != team_inside {
			flag.capturing_team = team_inside;
			flag.capturing_timer = 0;
		}
	}
	else {
		flag.capturing_team = NO_TEAM;
	}

	if flag.capturing_team != NO_TEAM {
		flag.capturing_timer += dt;
		if flag.capturing_timer >= CAPTURE_DURATION {
			e.team = flag.capturing_team;
		}
	}
	game.territories[flag.territory_id].team = e.team;
}

game_second_tick :: proc(game: ^Game) {
	{ // Tick entities for second
		team_flag_count: [TEAM_COUNT]int;
		entity_it := entity_iterator_start(game);
		for e in entity_iterator_all(&entity_it) {
			#partial switch &sub in e.subtype {				
				case Monster: {
					damage_monster(game, e, &sub, 2);
				}
				case Flag: {
					if e.team != NO_TEAM {
						team_flag_count[e.team] += 1;
					}
				}
			}
		}

		for team in 0..<TEAM_COUNT {
			MANA_SCALE_NUMBER :: 7;
			game.team_data[team].mana += cast(int)math.ceil(math.log_f32(1.0 + f32(team_flag_count[team])/MANA_SCALE_NUMBER, math.E) * MANA_SCALE_NUMBER);
		}
	}
}

draw_tiles :: proc(game: ^Game) {
	for ty in 0..<game.level_dim.y {
	for tx in 0..<game.level_dim.x {
		tile_pos := Vec2{f32(tx), f32(ty)};
		territory_id := game.tiles[tx + ty * game.level_dim.x];
		color: Vec4;
		if territory_id == WATER_TERRITORY {
			color = {0.3, 0.4, 1.0, 1.0};
		}
		else if territory_id == TEMPORARY_FLAG_TERRITORY {
			color = {0, 0, 0, 1};
		}
		else {
			territory := game.territories[territory_id];
			color = TEAM_GROUND_COLORS[territory.team];// * territory_shading[territory_id];
			//color = TERRITORY_DRAW_COLORS[int(territory_id) % len(TERRITORY_DRAW_COLORS)];
		}
		draw_colored_rect_min_size(tile_pos, 1, color);
	}}
}

get_territory_id_at_position :: proc(game: ^Game, position: Vec2) -> Territory_Id {
	tx := i32(position.x);
	ty := i32(position.y);

	if tx >= 0 && ty >= 0 && tx < game.level_dim.x && ty < game.level_dim.y {
		id := game.tiles[tx + ty * game.level_dim.x];
		return id;		
	}
	return NO_TERRITORY;
}

get_territory_at_position :: proc(game: ^Game, position: Vec2) -> ^Territory {
	id := get_territory_id_at_position(game, position);
	if id < game.territory_count {
		return &game.territories[id];
	}
	else {
		return nil;
	}	
}

place_monster_at_position :: proc(game: ^Game, placement_position: Vec2, team: Team_Id, type: Monster_Type) -> bool {
	territory := get_territory_at_position(game, placement_position);
	if game.team_data[team].mana >= MONSTER_MANA_COST && territory != nil && territory.team == team {
		e, monster := add_entity(game, Monster);
		if e != nil { 
			monster.type = type;
			e.position = placement_position;
			e.team = team;
			monster.hp = 30;
			monster.flags += {.SPAWNING};
		
			game.team_data[team].mana -= MONSTER_MANA_COST
			return true;
		}
	}
	return false;
}

world_tick_and_draw :: proc(game: ^Game) {
	if left_mouse_got_pressed && !game.game_over && !game.display_pause_menu {
		place_monster_at_position(game, get_mouse_level_position(game), game.my_team, game.placing_monster_type);
		game.paused = false;
	}

	if !game.paused && !game.game_over && !game.display_pause_menu {

		game.second_tick_timer += dt;
		for game.second_tick_timer >= 1.0 {
			game.second_tick_timer -= 1.0;

			game_second_tick(game);
		}

		for ti in 0..<game.territory_count {
			game.territory_infos[ti].team_monsters_here = game.territory_infos[ti].next_team_monsters_here;
			game.territory_infos[ti].team_monsters_dest = game.territory_infos[ti].next_team_monsters_dest;

			game.territory_infos[ti].next_team_monsters_here = {};
			game.territory_infos[ti].next_team_monsters_dest = {};

			//fmt.printf("%v: %v, %v\n", ti, game.territory_infos[ti].team_monsters_here, game.territory_infos[ti].team_monsters_dest);
		}

		game.team_flag_count = {};
		game.team_monster_count = {};

		{ // Tick entities
			entity_it := entity_iterator_start(game);
			for e in entity_iterator_all(&entity_it) {
				#partial switch &sub in e.subtype {
					case Monster: {
						game.team_monster_count[e.team] += 1;
						tick_monster(game, e, &sub);
					}
					case Flag: {
						if e.team != NO_TEAM {
							game.team_flag_count[e.team] += 1;
						}
						tick_flag(game, e, &sub);
					}
				}
			}
		}

		winner := NO_TEAM;
		for team in 0..<TEAM_COUNT {
			if game.team_flag_count[team] + game.team_monster_count[team] > 0 {
				if winner == NO_TEAM {
					winner = team;
				}
				else {
					winner = NO_TEAM;
					break;
				}
			}
		}
		if winner != NO_TEAM {
			game.game_over = true;
			game.victorious_team = winner;
		}

		tick_projectiles :: proc(game: ^Game) { // Tick projectiles
			max_move_distance := 100.0 * dt;
			for pi := 0; pi < game.projectile_count; pi += 1 {
				proj := &game.projectiles[pi];
				target := get_entity(game, proj.target);
				do_remove := false;
				if target != nil {
					v := target.position - proj.position;
					distance := linalg.length(v);
					if distance < max_move_distance {
						#partial switch &sub in target.subtype {
							case Monster: {
								damage_monster(game, target, &sub, proj.damage)
							}
						}
						do_remove = true;
					}
					else {
						direction := v / distance;
						proj.position += direction * max_move_distance;
					}
				}
				else {
					do_remove = true;
				}
				if do_remove {
					game.projectile_count -= 1;
					if pi < game.projectile_count {
						game.projectiles[pi] = game.projectiles[game.projectile_count];
					}
					pi -= 1;
				}
			}
		}
		tick_projectiles(game);
	}

	draw_rect_border_min_max({0, 0}, game.level_size, 0.1, {0, 0, 0, 1});

	draw_tiles(game);

	hovered_ti := get_territory_id_at_position(game, get_mouse_level_position(game));

	entity_it := entity_iterator_start(game);
	for e in entity_iterator_all(&entity_it) {
		//e := &game.entities[ei];
		switch &sub in e.subtype {
			case Monster: {
				draw_monster(e, &sub);
			}
			case Flag:    {
				pole_size := Vec2{0.1, 1.5} * ENTITY_SCALE;
				pole_base := e.position;

				draw_colored_rect_min_size(pole_base - pole_size, pole_size, {0.3, 0.26, 0.1, 1});

				flag_color := TEAM_COLORS[e.team];
				if sub.capturing_team != NO_TEAM {
					flag_color = linalg.lerp(flag_color, TEAM_COLORS[sub.capturing_team], math.cos((sub.capturing_timer-math.PI*1.5)*4.0)*0.5+0.5);
				}
				draw_colored_rect_min_size(pole_base - {0, pole_size.y}, {1, 0.8}*ENTITY_SCALE, flag_color);

				if display_territory_debug_info && hovered_ti == sub.territory_id {
					draw_text(fmt.tprintf("%d", sub.territory_id), &world_font, pole_base, .Center, .Center, {1, 1, 1, 1});
				}
			}
		}
	}	

	if display_territory_debug_info && hovered_ti < game.territory_count {
		for ti in 0..<game.territory_count {
			tinfo := game.territory_infos[hovered_ti];
			if tinfo.can_see_flag[ti] {
				draw_text(fmt.tprintf("%d", ti), &world_font, tinfo.closest_point_to_flag[ti], .Center, .Center, {1,1,0,1});
			}
		}
	}

	for pi := 0; pi < game.projectile_count; pi += 1 {
		proj := game.projectiles[pi];
		draw_colored_rect_center_size(proj.position, 3, {0, 0, 0, 1});
	}

	for ii in 0..<len(game.computer_players) {
		if game.computer_players[ii].team != game.my_team {
			computer_player_tick(game, &game.computer_players[ii]);
		}
	}

	//game.view_center += input_direction_axis() * dt * 50;
}

do_volume_slider :: proc(slider_rect: Rect) {	
	slider_size := slider_rect.max - slider_rect.min;
	hovered := rect_contains(slider_rect, mouse_p);

	handle_size: Vec2 = slider_size.y;

	draw_text("Music volume", &font, {slider_rect.min.x, slider_rect.min.y-5}, .Left, .Bottom, {1, 1, 1, 1});
	draw_colored_rect_min_max(slider_rect.min, slider_rect.max, hovered ? {0.4, 0.4, 0.4, 1.0} : {0.3, 0.3, 0.3, 1.0});
	inside_width := slider_size.x - handle_size.x;
	inside_left := slider_rect.min.x + handle_size.x*0.5;
	slider_t := app.music_volume;
	draw_colored_rect_center_size({inside_left + inside_width*slider_t, slider_rect.min.y + slider_size.y*0.5}, handle_size, {0, 0, 0, 0.5});

	if left_mouse_is_down && hovered && inside_width >= 1 {
		slider_t = math.min(1, math.max(0, (mouse_p.x - inside_left) / inside_width));
	}

	if app.music_volume != slider_t {			
		set_music_volume(slider_t);
	}
}

pause_menu :: proc(game: ^Game) {
	button_size := Vec2{window_size.y * 0.5, window_size.y * 0.1};
	button_theme := Button_Theme{
		bg_color_normal = {0.8, 0.8, 0.8, 1.0},
		bg_color_hovered = {1, 1, 0.95, 1},
		bd_color_normal = {0.2, 0.15, 0.15, 1.0},
		bd_color_hovered = {0.32, 0.27, 0.27, 1.0},
		bd_width = button_size.y * 0.1,
	};


	Menu_Button :: enum {
		Play,
		Restart,
		Main_Menu,
	}
	button_texts := [Menu_Button]string {
		.Play = "Continue",
		.Restart = "Restart",
		.Main_Menu = "Back to Main Menu",
	}

	slider_size := Vec2{window_size.y*0.4, window_size.y*0.05};
	slider_rect := rect_min_size({(window_size.x-slider_size.x)*0.5, window_size.y*0.2}, slider_size);
	do_volume_slider(slider_rect);

	button_rect := rect_min_size(window_size*0.5 - button_size*0.5, button_size);
	pressed_button := Menu_Button(-1);
	for bi in Menu_Button {
		if text_button(button_rect, button_theme, button_texts[bi]) {
			pressed_button = bi;
		}

		button_rect = rect_move(button_rect, {0, button_size.y * 1.1});
	}

	switch pressed_button {
		case .Play: {
			game.display_pause_menu = false;
		}
		case .Restart: {
			deinit_game(game);
			init_game(game);
		}
		case .Main_Menu: {
			deinit_game(game);
			app.state = .Menu;

		}
		case: {

		}
	}
}

set_music_volume :: proc(new_volume: f32) {
	app.music_volume = new_volume;
	platform_set_music_volume(new_volume);
}

game_gui_tick_and_draw :: proc(game: ^Game) {
	left_pad := window_size.y*0.05;
	my_team_data := &game.team_data[game.my_team];
	draw_text(fmt.tprintf("Mana: %d", my_team_data.mana), &font, {left_pad, 40}, .Left, .Bottom, TEAM_COLORS[game.my_team], nil);
	if display_territory_debug_info do draw_text(fmt.tprintf("%v", get_mouse_level_position(game)), &font, {10, window_size.y}, .Left, .Bottom, {1, 1, 0, 1}, nil);


	{
		normal_theme := Button_Theme {
			bg_color_normal = {0.8, 0.8, 0.8, 1.0},
			bg_color_hovered = {1, 1, 0.95, 1},
			bd_color_normal = {0.2, 0.15, 0.15, 1.0},
			bd_color_hovered = {0.32, 0.27, 0.27, 1.0},
		};
		selected_theme := Button_Theme {
			bg_color_normal = {1, 1, 1, 1},
			bg_color_hovered = {1, 1, 0.95, 1},
			bd_color_normal = {0.7, 0.6, 0.5, 1.0},
			bd_color_hovered = {0.7, 0.6, 0.5, 1.0},
		};


		button_size: Vec2 = window_size.y * 0.15;
		button_min := Vec2{left_pad, window_size.y * 0.1};
		for type in Monster_Type {
			hovered := rect_contains(rect_min_size(button_min, button_size), mouse_p);

			if hovered && left_mouse_got_pressed {
				game.placing_monster_type = type;
			}
			selected := type == game.placing_monster_type;

			theme := selected ? selected_theme : normal_theme;
			draw_colored_rect_min_size(button_min, button_size, 
				hovered ? theme.bg_color_hovered : theme.bg_color_normal);
			draw_textured_rect_min_size(&MONSTER_TEXTURES[type], button_min, button_size, TEAM_COLORS[game.my_team]);
			draw_rect_border_min_max(button_min, button_min+button_size, button_size.x*0.05, 
				hovered ? theme.bd_color_hovered : theme.bd_color_normal);
			button_min.y += button_size.y + window_size.y * 0.05;
		}
	}

	{
		button_size: Vec2 = window_size.y * 0.10;
		normal_theme := Button_Theme {
			bg_color_normal = {0.3, 0.3, 0.3, 1.0},
			bg_color_hovered = {0.35, 0.35, 0.35, 1},
			bd_color_normal = {0.6, 0.55, 0.55, 1.0},
			bd_color_hovered = {0.7, 0.6, 0.6, 1.0},
			bd_width = button_size.x * 0.05,
		};
		button_rect := rect_min_size(window_size.x - left_pad - button_size.x, window_size.y*0.1, button_size.x, button_size.y);
		if button(button_rect, normal_theme) {
			game.display_pause_menu = true;
		}
		draw_textured_rect_min_max(&pause_icon_texture, button_rect.min, button_rect.max);
	}


	if game.game_over {
		/*rect: 
		draw_colored_rect_center_size()*/
		draw_text(game.victorious_team == game.my_team ? "You Won!" : "You lost", &font, window_size*0.5, .Center, .Center, {1, 1, 1, 1});
	}

	if game.display_pause_menu {
		pause_menu(game);
	}
}

game_tick_and_draw :: proc(game: ^Game) {
	{ // Draw and tick the world
		game.view_size.x = game.view_size.y * (window_size.x / window_size.y);
		//game.view_size.y = game.view_size.x * (window_size.y / window_size.x);
		view_min := game.view_center - game.view_size*0.5;
		view_projection := linalg.matrix_ortho3d_f32(view_min.x, view_min.x + game.view_size.x, view_min.y + game.view_size.y, view_min.y, -1.0, 1.0);	
		set_view_projection(view_projection);

		world_tick_and_draw(&app.game);
		//draw_colored_rect_min_size(get_mouse_level_position(game), .1, {0.3, 0.8, 0.4, 1.0}); //MOUSE POSITION DEBUG 
	}
	flush_batch();

	{	// DO the GUI
		view_projection := linalg.matrix_ortho3d_f32(0, window_size.x, window_size.y, 0, -1.0, 1.0);	
		set_view_projection(view_projection);

		game_gui_tick_and_draw(game);
	}
	flush_batch();
}




app_tick_and_draw :: proc() {
	bg := Vec3{0.22, 0.17, 0.12}
	start_draw_frame(bg);

	set_draw_viewport(0, 0, window_width, window_height);

	switch app.state {
		case .Menu: menu_tick_and_draw();
		case .Game: game_tick_and_draw(&app.game);
	}
	flush_batch();
}

app_init :: proc() {	
	when false && ODIN_DEBUG {
		app.state = .Game;
		init_game(&app.game);
		app.game.display_pause_menu = true;
	}
	else {
		app.state = .Menu;
	}
}