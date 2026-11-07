#include "game.h"
#include "physics.h"
#include "mmio.h"

Tank g_p1;
Tank g_p2;
Bullet g_bullets[MAX_BULLETS];

// Per-player barrel turn rate-limiting counters (in game frames)
static uint8_t s_p1_turn_cd;
static uint8_t s_p2_turn_cd;

//=============================================================================
// Hardware Delay / Frame Pacing
//=============================================================================
void game_delay(uint32_t count) {
    while (count--) {
        __asm__ volatile ("nop");
    }
}

//=============================================================================
// Send both barrel direction vectors (cos, sin) to the sprite hardware.
// cos and sin of one tank share a single register so they always update together.
//=============================================================================
__attribute__((noinline))
static void write_tank_directions(void) {
    REG_TANK1_DIR = TANK_DIR_PACK(g_cos_fp[g_p1.angle], g_sin_fp[g_p1.angle]);
    REG_TANK2_DIR = TANK_DIR_PACK(g_cos_fp[g_p2.angle], g_sin_fp[g_p2.angle]);
}

//=============================================================================
// Initialize Game State
//=============================================================================
void game_init(void) {
    // Player 1: Top-Left (x=48, y=48), facing East, 20 hearts
    g_p1.x_fp  = TO_FP(48);
    g_p1.y_fp  = TO_FP(48);
    g_p1.angle = ANGLE_EAST;
    g_p1.hp    = 20;
    g_p1.score = 0;

    // Player 2: Bottom-Right (x=410, y=410), facing West, 20 hearts
    g_p2.x_fp  = TO_FP(410);
    g_p2.y_fp  = TO_FP(410);
    g_p2.angle = ANGLE_WEST;
    g_p2.hp    = 20;
    g_p2.score = 0;

    // Bring the maze back to its power-up state (bricks destroyed in a previous
    // game would otherwise stay gone after a reset).
    physics_reset_maze();

    for (int i = 0; i < MAX_BULLETS; i++) {
        g_bullets[i].active  = 0;
        g_bullets[i].is_big  = 0;
        g_bullets[i].bounces = 0;
        g_bullets[i].owner   = 0;
        g_bullets[i].x_fp    = 0;
        g_bullets[i].y_fp    = 0;
        g_bullets[i].vx_fp   = 0;
        g_bullets[i].vy_fp   = 0;
    }

    // Set initial HUD health and turret angles
    REG_HUD_HEALTH  = HUD_HEALTH_PACK(20, 20);
    write_tank_directions();

    s_p1_turn_cd = 0;
    s_p2_turn_cd = 0;

    // Clear any pending hardware collisions
    clear_collision_wall(0xFF);
    clear_collision_tank(0x3FF);
    clear_collision_bullet(0xFF);
}

//=============================================================================
// Tank vs Tank blocking
// A move of `self` to (nx, ny) is blocked when it would overlap `other`. If the
// tanks already overlap (e.g. after a spawn) the move is allowed so they can
// always drive apart instead of being stuck together.
//=============================================================================
static int tank_move_blocked(int nx, int ny, const Tank *other, const Tank *self) {
    int ox = FROM_FP(other->x_fp);
    int oy = FROM_FP(other->y_fp);
    if (!physics_tanks_overlap(nx, ny, ox, oy))
        return 0;
    return !physics_tanks_overlap(FROM_FP(self->x_fp), FROM_FP(self->y_fp), ox, oy);
}

//=============================================================================
// Update Single Tank Controls, Rotation, Movement, and Weapons
//=============================================================================
__attribute__((noinline))
static void update_single_tank(Tank *self, const Tank *other, uint8_t *turn_cd,
                               uint32_t keys, int player,
                               uint32_t shoot_tmr, uint32_t spec_tmr) {
    if (self->hp == 0)
        return;

    if (keys & (BTN_LEFT | BTN_RIGHT)) {
        if (*turn_cd == 0) {
            if (keys & BTN_LEFT)
                self->angle = (self->angle + NUM_ANGLES - 1) & ANGLE_MASK;
            if (keys & BTN_RIGHT)
                self->angle = (self->angle + 1) & ANGLE_MASK;
            *turn_cd = TURN_STEP_FRAMES - 1;
        } else {
            (*turn_cd)--;
        }
    } else {
        *turn_cd = 0;
    }

    int32_t move_dir = 0;
    if (keys & BTN_FWD) move_dir = 1;
    else if (keys & BTN_BWD) move_dir = -1;

    if (move_dir != 0) {
        int32_t dx = (g_cos_fp[self->angle] * move_dir * 2) << (FP_SHIFT - 8);
        int32_t dy = (g_sin_fp[self->angle] * move_dir * 2) << (FP_SHIFT - 8);

        int32_t new_x = self->x_fp + dx;
        int32_t new_y = self->y_fp + dy;

        // Each axis is tested separately so a tank slides along a wall
        // instead of sticking to it. Maze walls and the other tank block it.
        if (FROM_FP(new_x) >= ARENA_MIN_X && FROM_FP(new_x) <= (ARENA_MAX_X - TANK_SIZE) &&
            !physics_tank_hits_wall(FROM_FP(new_x), FROM_FP(self->y_fp)) &&
            !tank_move_blocked(FROM_FP(new_x), FROM_FP(self->y_fp), other, self))
            self->x_fp = new_x;
        if (FROM_FP(new_y) >= ARENA_MIN_Y && FROM_FP(new_y) <= (ARENA_MAX_Y - TANK_SIZE) &&
            !physics_tank_hits_wall(FROM_FP(self->x_fp), FROM_FP(new_y)) &&
            !tank_move_blocked(FROM_FP(self->x_fp), FROM_FP(new_y), other, self))
            self->y_fp = new_y;
    }

    if ((keys & BTN_SHOOT) && (REG_TIMER_STATUS & shoot_tmr)) {
        physics_spawn_bullet(player, 0);
        REG_TIMER_TRIGGER = shoot_tmr;
    }

    if ((keys & BTN_SPECIAL) && (REG_TIMER_STATUS & spec_tmr)) {
        physics_spawn_bullet(player, 1);
        REG_TIMER_TRIGGER = spec_tmr;
    }
}

//=============================================================================
// Update Tank Controls, Rotation, and Movement
//=============================================================================
void game_update_tanks(void) {
    // Freeze tank steering, movement, and firing once any player's health is gone
    if (g_p1.hp == 0 || g_p2.hp == 0)
        return;

    uint32_t p1_keys = get_p1_input();
    uint32_t p2_keys = get_p2_input();

    update_single_tank(&g_p1, &g_p2, &s_p1_turn_cd, p1_keys, 1, TMR_P1_SHOOT, TMR_P1_SPECIAL);
    update_single_tank(&g_p2, &g_p1, &s_p2_turn_cd, p2_keys, 2, TMR_P2_SHOOT, TMR_P2_SPECIAL);
}

//=============================================================================
// Update Bullets & Wall Reflection Physics
//=============================================================================
void game_update_bullets(void) {
    uint32_t hw_wall_hits = REG_COLLISION_WALL;

    for (int i = 0; i < MAX_BULLETS; i++) {
        if (!g_bullets[i].active)
            continue;

        int prev_x = FROM_FP(g_bullets[i].x_fp);
        int prev_y = FROM_FP(g_bullets[i].y_fp);

        int32_t next_x_fp = g_bullets[i].x_fp + g_bullets[i].vx_fp;
        int32_t next_y_fp = g_bullets[i].y_fp + g_bullets[i].vy_fp;

        int next_x = FROM_FP(next_x_fp);
        int next_y = FROM_FP(next_y_fp);

        // Bricks MUST always break. The hardware wall flag is raised from the bullet
        // CENTRE while the software test below uses the bullet's top-left corner, so
        // the hardware usually reports the brick first. The old code used
        // `hw_flag || destroy_tile(...)`, which skipped the destroy call whenever the
        // hardware flag was set (the brick then only reflected the bullet and never
        // broke). Every probe is therefore evaluated unconditionally:
        //   - tile under the bullet centre now (what the hardware flagged),
        //   - tile under the top-left corner next frame,
        //   - tile under the centre next frame.
        int half = g_bullets[i].is_big ? 6 : 3;
        int hw_flag = (hw_wall_hits & (1U << i)) != 0;
        int hit_detected = hw_flag;
        if (hw_flag)
            physics_check_and_destroy_tile(prev_x + half, prev_y + half, g_bullets[i].is_big);
        hit_detected |= physics_check_and_destroy_tile(next_x, next_y, g_bullets[i].is_big);
        hit_detected |= physics_check_and_destroy_tile(next_x + half, next_y + half, g_bullets[i].is_big);

        if (hit_detected) {
            physics_reflect_bullet(&g_bullets[i], prev_x, prev_y, next_x, next_y);
        }

        // Advance position if still active
        if (g_bullets[i].active) {
            g_bullets[i].x_fp += g_bullets[i].vx_fp;
            g_bullets[i].y_fp += g_bullets[i].vy_fp;
        }
    }

    if (hw_wall_hits)
        clear_collision_wall(hw_wall_hits);
}

//=============================================================================
// Handle Hardware Collision Engine Results: Tank Damage & Annihilation
//=============================================================================
void game_process_collisions(void) {
    // HIT_MASK: [7:0] = bullet i overlapped a tank, [8] = P1 tank hit, [9] = P2 tank hit.
    // A bullet never damages the tank that fired it (its muzzle spawn point can
    // overlap the shooter's own hit box), so owner 1 bullets can only hurt P2 and
    // owner 2 bullets can only hurt P1.
    uint32_t tank_hits = REG_COLLISION_TANK;
    uint32_t bullet_mask = tank_hits & 0xFFU;
    int p1_was_hit = (tank_hits & COLL_TANK_P1_HIT) != 0;
    int p2_was_hit = (tank_hits & COLL_TANK_P2_HIT) != 0;
    int match_active = (g_p1.hp > 0 && g_p2.hp > 0);

    if (match_active && bullet_mask && (p1_was_hit || p2_was_hit)) {
        for (int i = 0; i < MAX_BULLETS; i++) {
            if (!(bullet_mask & (1U << i)) || !g_bullets[i].active)
                continue;

            uint8_t dmg = g_bullets[i].is_big ? 6 : 2;

            // Bullet can hit P1 if: fired by P2, OR fired by P1 and reflected (bounces > 0)
            int can_hit_p1 = p1_was_hit && (g_bullets[i].owner != 1 || g_bullets[i].bounces > 0);
            // Bullet can hit P2 if: fired by P1, OR fired by P2 and reflected (bounces > 0)
            int can_hit_p2 = p2_was_hit && (g_bullets[i].owner != 2 || g_bullets[i].bounces > 0);

            if (can_hit_p1 && can_hit_p2) {
                // Both tanks flagged: disambiguate using AABB overlap
                int bx = FROM_FP(g_bullets[i].x_fp);
                int by = FROM_FP(g_bullets[i].y_fp);
                int bsize = g_bullets[i].is_big ? 12 : 6;
                int p1x = FROM_FP(g_p1.x_fp), p1y = FROM_FP(g_p1.y_fp);
                int p2x = FROM_FP(g_p2.x_fp), p2y = FROM_FP(g_p2.y_fp);

                int ovl1 = (bx < p1x + TANK_SIZE) && (p1x < bx + bsize) &&
                           (by < p1y + TANK_SIZE) && (p1y < by + bsize);
                int ovl2 = (bx < p2x + TANK_SIZE) && (p2x < bx + bsize) &&
                           (by < p2y + TANK_SIZE) && (p2y < by + bsize);

                if (ovl1 && !ovl2) can_hit_p2 = 0;
                else if (ovl2 && !ovl1) can_hit_p1 = 0;
                else if (!ovl1 && !ovl2) {
                    if (g_bullets[i].owner == 1) can_hit_p1 = 0;
                    else can_hit_p2 = 0;
                }
            }

            if (can_hit_p1) {
                if (g_p1.hp > dmg) g_p1.hp -= dmg;
                else g_p1.hp = 0;
                g_bullets[i].active = 0;
            }
            if (can_hit_p2) {
                if (g_p2.hp > dmg) g_p2.hp -= dmg;
                else g_p2.hp = 0;
                g_bullets[i].active = 0;
            }
        }
    }

    if (tank_hits)
        clear_collision_tank(tank_hits);

    // Bullet-Bullet mutual annihilation.
    // Hardware reports one sticky bit per bullet: bit i = bullet i overlapped
    // another active bullet. Both bullets of an overlapping pair are flagged.
    uint32_t bullet_hits = REG_COLLISION_BULLET & 0xFFU;
    if (bullet_hits) {
        for (int i = 0; i < MAX_BULLETS; i++) {
            if (bullet_hits & (1U << i))
                g_bullets[i].active = 0;
        }
        clear_collision_bullet(bullet_hits);
    }
}

//=============================================================================
// Output Live Game State to Hardware MMIO Display Registers
//=============================================================================
void game_sync_display(void) {
    update_tank_sprite(1, FROM_FP(g_p1.x_fp), FROM_FP(g_p1.y_fp));
    update_tank_sprite(2, FROM_FP(g_p2.x_fp), FROM_FP(g_p2.y_fp));
    write_tank_directions();

    for (int i = 0; i < MAX_BULLETS; i++) {
        REG_SPRITE_BULLET(i) = SPRITE_BULLET_PACK(FROM_FP(g_bullets[i].x_fp),
                                                  FROM_FP(g_bullets[i].y_fp),
                                                  g_bullets[i].active,
                                                  g_bullets[i].is_big);
    }

    REG_HUD_HEALTH = HUD_HEALTH_PACK(g_p1.hp, g_p2.hp);
}
