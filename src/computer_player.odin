package main

import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:fmt"

Computer_Player :: struct {
	team: Team_Id,
}

flag_can_be_seen_from_any_team_territory :: proc(game: ^Game, team: Team_Id, flag_territory_id: Territory_Id) -> (from_position: Vec2, yes: bool) {
	/*cx := i32(flag_position.x);
	cy := i32(flag_position.y);
	min_tx := math.max(0,                  cx-MAX_TARGET_DISTANCE);
	min_ty := math.max(0,                  cy-MAX_TARGET_DISTANCE);
	max_tx := math.min(game.level_dim.x-1, cx+MAX_TARGET_DISTANCE);
	max_ty := math.min(game.level_dim.y-1, cy+MAX_TARGET_DISTANCE);

	for ty in min_ty..=max_ty {
		for tx in min_tx..=max_tx {
			ti := game.tiles[tx + ty * game.level_dim.x];
			if (tx-cx)*(tx-cx) + (ty-cy)*(ty-cy) < MAX_TARGET_DISTANCE2 && 
				ti < game.territory_count && 
				game.territories[ti].team == team {

				return Vec2{f32(tx), f32(ty)}, true;
			}
		}
	}
	return;*/
	for ti in 0..<game.territory_count {
		if game.territories[ti].team == team && game.territory_infos[ti].can_see_flag[flag_territory_id] {
			return game.territory_infos[ti].closest_point_to_flag[flag_territory_id], true;
		}
	}
	return;
}

computer_player_tick :: proc(game: ^Game, player: ^Computer_Player) {
	if game.team_data[player.team].mana < MONSTER_MANA_COST do return;

	best_score: f32 = 0;
	best_placement_position: Vec2;
	best_monster_type: Monster_Type;

	for ti in 0..<game.territory_count {
		territory := &game.territories[ti];
		if territory.team != player.team {
			//flag_e := get_entity(game, territory.flag_id);
			if placement_position, yes := flag_can_be_seen_from_any_team_territory(game, player.team, ti); yes {
				mine_here := game.territory_infos[ti].team_monsters_here[player.team] 
				mine_going := game.territory_infos[ti].team_monsters_dest[player.team];

				they_here : i16;
				they_going: i16;
				for other_team in 0..<TEAM_COUNT {
					if player.team == other_team do continue;
					they_here += game.territory_infos[ti].team_monsters_here[other_team] 
					they_going += game.territory_infos[ti].team_monsters_dest[other_team];
				}

				//distance := linalg.length(get_entity(game, territory.flag_id).position - placement_position);

				score: f32;

				mine_combined := mine_here+mine_going;
				they_combined := they_here+they_going;
				monster_type := Monster_Type.Ghost;
				if(mine_combined == 0 && they_combined == 0) {
					//score = MAX_TARGET_PRIORITY_OVERRIDE_DISTANCE / distance * 8;
					score = 10;
				}
				else if(mine_combined < they_combined) {
					//score = MAX_TARGET_PRIORITY_OVERRIDE_DISTANCE / distance * 2 + f32(they_combined-mine_combined);
					if they_combined > mine_combined+5 {
						// They are overwhelming us, only place here if only option
						score = 0.5;
					}
					else {
						score = f32(they_combined-mine_combined);
					}
					monster_type = Monster_Type(rand.uint32()%2);
				}
				else if they_combined > 0 && mine_combined+5 < they_combined {
					score = f32(1);
				}
				score *= rand.float32()*0.5 + 0.5;
				if score > best_score {
					best_score = score;
					best_placement_position = placement_position;
					best_monster_type = monster_type;
				}
			
			}
		}
	}
	if best_score > 0.0 {
		place_monster_at_position(game, best_placement_position, player.team, best_monster_type);
		/*for ti in 0..<game.territory_count {
			fmt.printf("%v: %v, %v\n", ti, game.territory_infos[ti].team_monsters_here, game.territory_infos[ti].team_monsters_dest);
		}
		fmt.printf("%v: Mine here %d, going %d. They here %d, going %d, %v\n", ti, mine_here, mine_going, they_here, they_going, placement_position);*/
	}
}