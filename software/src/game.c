#include "game.h"
#include "physics.h"
#include "mmio.h"

Tank g_p1;
Tank g_p2;
Bullet g_bullets[MAX_BULLETS];

//=============================================================================
// Hardware Delay / Frame Pacing
//=============================================================================
void game_delay(uint32_t count) {
    while (count--) {
        __asm__ volatile ("nop");
    }
}

//=============================================================================
// Initialize Game State
//=============================================================================
void game_init(void) {
    // Player 1: Top-Left (x=48, y=48), facing East (angle=0), 20 hearts
    g_p1.x_fp  = TO_FP(48);
    g_p1.y_fp  = TO_FP(48);
    g_p1.angle = 0;
    g_p1.hp    = 20;
    g_p1.score = 0;

    // Player 2: Bottom-Right (x=410, y=410), facing West (angle=8), 20 hearts
    g_p2.x_fp  = TO_FP(410);
    g_p2.y_fp  = TO_FP(410);
    g_p2.angle = 8;
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
    REG_TANK_ANGLES = TANK_ANGLES_PACK(0, 8);

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
// Update Tank Controls, Rotation, and Movement
//=============================================================================
void game_update_tanks(void) {
    uint32_t p1_keys = get_p1_input();
    uint32_t p2_keys = get_p2_input();

    // ---------------- Player 1 Controls ----------------
    if (g_p1.hp > 0) {
        if (p1_keys & BTN_LEFT)
            g_p1.angle = (g_p1.angle + 15) & 0xF;
        if (p1_keys & BTN_RIGHT)
            g_p1.angle = (g_p1.angle + 1) & 0xF;

        int32_t move_dir1 = 0;
        if (p1_keys & BTN_FWD) move_dir1 = 1;
        else if (p1_keys & BTN_BWD) move_dir1 = -1;

        if (move_dir1 != 0) {
            int32_t dx = (g_cos_fp[g_p1.angle] * move_dir1 * 2) << (FP_SHIFT - 8);
            int32_t dy = (g_sin_fp[g_p1.angle] * move_dir1 * 2) << (FP_SHIFT - 8);

            int32_t new_x = g_p1.x_fp + dx;
            int32_t new_y = g_p1.y_fp + dy;

            // Each axis is tested separately so a tank slides along a wall
            // instead of sticking to it. Maze walls and the other tank block it.
            if (FROM_FP(new_x) >= ARENA_MIN_X && FROM_FP(new_x) <= (ARENA_MAX_X - TANK_SIZE) &&
                !physics_tank_hits_wall(FROM_FP(new_x), FROM_FP(g_p1.y_fp)) &&
                !tank_move_blocked(FROM_FP(new_x), FROM_FP(g_p1.y_fp), &g_p2, &g_p1))
                g_p1.x_fp = new_x;
            if (FROM_FP(new_y) >= ARENA_MIN_Y && FROM_FP(new_y) <= (ARENA_MAX_Y - TANK_SIZE) &&
                !physics_tank_hits_wall(FROM_FP(g_p1.x_fp), FROM_FP(new_y)) &&
                !tank_move_blocked(FROM_FP(g_p1.x_fp), FROM_FP(new_y), &g_p2, &g_p1))
                g_p1.y_fp = new_y;
        }

        if ((p1_keys & BTN_SHOOT) && is_p1_shoot_ready()) {
            physics_spawn_bullet(1, 0);
            trigger_p1_shoot_cooldown();
        }

        if ((p1_keys & BTN_SPECIAL) && is_p1_spec_ready()) {
            physics_spawn_bullet(1, 1);
            trigger_p1_spec_cooldown();
        }
    }

    // ---------------- Player 2 Controls ----------------
    if (g_p2.hp > 0) {
        if (p2_keys & BTN_LEFT)
            g_p2.angle = (g_p2.angle + 15) & 0xF;
        if (p2_keys & BTN_RIGHT)
            g_p2.angle = (g_p2.angle + 1) & 0xF;

        int32_t move_dir2 = 0;
        if (p2_keys & BTN_FWD) move_dir2 = 1;
        else if (p2_keys & BTN_BWD) move_dir2 = -1;

        if (move_dir2 != 0) {
            int32_t dx2 = (g_cos_fp[g_p2.angle] * move_dir2 * 2) << (FP_SHIFT - 8);
            int32_t dy2 = (g_sin_fp[g_p2.angle] * move_dir2 * 2) << (FP_SHIFT - 8);

            int32_t new_x2 = g_p2.x_fp + dx2;
            int32_t new_y2 = g_p2.y_fp + dy2;

            // Each axis is tested separately so a tank slides along a wall
            // instead of sticking to it. Maze walls and the other tank block it.
            if (FROM_FP(new_x2) >= ARENA_MIN_X && FROM_FP(new_x2) <= (ARENA_MAX_X - TANK_SIZE) &&
                !physics_tank_hits_wall(FROM_FP(new_x2), FROM_FP(g_p2.y_fp)) &&
                !tank_move_blocked(FROM_FP(new_x2), FROM_FP(g_p2.y_fp), &g_p1, &g_p2))
                g_p2.x_fp = new_x2;
            if (FROM_FP(new_y2) >= ARENA_MIN_Y && FROM_FP(new_y2) <= (ARENA_MAX_Y - TANK_SIZE) &&
                !physics_tank_hits_wall(FROM_FP(g_p2.x_fp), FROM_FP(new_y2)) &&
                !tank_move_blocked(FROM_FP(g_p2.x_fp), FROM_FP(new_y2), &g_p1, &g_p2))
                g_p2.y_fp = new_y2;
        }

        if ((p2_keys & BTN_SHOOT) && is_p2_shoot_ready()) {
            physics_spawn_bullet(2, 0);
            trigger_p2_shoot_cooldown();
        }

        if ((p2_keys & BTN_SPECIAL) && is_p2_spec_ready()) {
            physics_spawn_bullet(2, 1);
            trigger_p2_spec_cooldown();
        }
    }
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

    if (bullet_mask && (p1_was_hit || p2_was_hit)) {
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
                else if (g_bullets[i].owner == 1) can_hit_p1 = 0;
                else can_hit_p2 = 0;
            }

            if (can_hit_p1) {
                if (g_p1.hp > dmg) g_p1.hp -= dmg;
                else g_p1.hp = 0;
                g_bullets[i].active = 0;
            } else if (can_hit_p2) {
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
    REG_TANK_ANGLES = TANK_ANGLES_PACK(g_p1.angle, g_p2.angle);

    for (int i = 0; i < MAX_BULLETS; i++) {
        REG_SPRITE_BULLET(i) = SPRITE_BULLET_PACK(FROM_FP(g_bullets[i].x_fp),
                                                  FROM_FP(g_bullets[i].y_fp),
                                                  g_bullets[i].active,
                                                  g_bullets[i].is_big);
    }

    REG_HUD_HEALTH = HUD_HEALTH_PACK(g_p1.hp, g_p2.hp);
}
