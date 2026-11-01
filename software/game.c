//=============================================================================
// Battle Tanks: Main Embedded C Game Engine
// Target: RV32IM Soft-Core Processor on Artix-7 FPGA
//
// Features:
// 1. Two-player steering with 16-angle trigonometry (accelerated via RV32M MUL/DIV).
// 2. Real-time 2D projectile tracking with angular wall reflection physics.
// 3. Hardware cooldown timers (0.5s shoot, 20s special attack).
// 4. Hardware collision engine polling with Write-1-to-Clear (W1C) handshake.
// 5. Dynamic maze destruction: destructible bricks shattered in mirrored BRAM.
// 6. Live MMIO update of all 12 Sprite, HUD, and Health registers.
//=============================================================================

#include "mmio.h"

#define ARENA_MIN_X         24
#define ARENA_MAX_X         456
#define ARENA_MIN_Y         24
#define ARENA_MAX_Y         456

#define TANK_SIZE           20
#define BULLET_NORM_SPEED   6   // pixels per frame
#define BULLET_BIG_SPEED    4   // pixels per frame
#define MAX_BOUNCES         5
#define MAX_BULLETS         8

#define P1_BULLET_START     0
#define P1_BULLET_END       3
#define P2_BULLET_START     4
#define P2_BULLET_END       7

// Fixed-point scaling (8 fractional bits)
#define FP_SHIFT            8
#define TO_FP(val)          ((int32_t)(val) << FP_SHIFT)
#define FROM_FP(val)        ((int32_t)(val) >> FP_SHIFT)

// 16-angle lookup table for cos(theta) * 256
static const int16_t cos_fp[16] = {
     256,  237,  181,   98,    0,  -98, -181, -237,
    -256, -237, -181,  -98,    0,   98,  181,  237
};

// 16-angle lookup table for sin(theta) * 256
static const int16_t sin_fp[16] = {
       0,   98,  181,  237,  256,  237,  181,   98,
       0,  -98, -181, -237, -256, -237, -181,  -98
};

// Tank Data Structure
typedef struct {
    int32_t x_fp;
    int32_t y_fp;
    uint8_t angle;      // 0..15
    uint8_t hp;         // 0..20 hearts
    uint16_t score;
} Tank;

// Bullet Data Structure
typedef struct {
    int32_t x_fp;
    int32_t y_fp;
    int32_t vx_fp;
    int32_t vy_fp;
    uint8_t active;
    uint8_t is_big;
    uint8_t bounces;
    uint8_t owner;      // 1 or 2
} Bullet;

static Tank p1, p2;
static Bullet bullets[MAX_BULLETS];

//=============================================================================
// Hardware Delay / Frame Pacing
//=============================================================================
static void frame_delay(volatile uint32_t count) {
    while (count--) {
        __asm__ volatile ("nop");
    }
}

//=============================================================================
// Maze RAM Helper: Check and Destroy Bricks
//=============================================================================
static int check_and_destroy_tile(int px, int py, int is_big) {
    if (px < 0 || px >= 480 || py < 0 || py >= 480)
        return 1; // Outside boundary is solid

    // Uses RV32M DIV instruction
    int col = px / 24;
    int row = py / 24;

    if (col < 0 || col >= 20 || row < 0 || row >= 20)
        return 1;

    uint32_t tile = MAZE_TILE(row, col);

    if (tile == TILE_EMPTY) {
        return 0; // Free space
    } else if (tile == TILE_BRICK_DESTRUCTIBLE) {
        // Destroy brick in hardware mirrored BRAM!
        MAZE_TILE(row, col) = TILE_EMPTY;
        return 1;
    } else {
        // Indestructible perimeter/steel wall
        return 1;
    }
}

//=============================================================================
// Initialize Game State
//=============================================================================
static void init_game(void) {
    // Player 1: Top-Left (x=48, y=48), facing East (angle=0), 20 hearts
    p1.x_fp  = TO_FP(48);
    p1.y_fp  = TO_FP(48);
    p1.angle = 0;
    p1.hp    = 20;
    p1.score = 0;

    // Player 2: Bottom-Right (x=410, y=410), facing West (angle=8), 20 hearts
    p2.x_fp  = TO_FP(410);
    p2.y_fp  = TO_FP(410);
    p2.angle = 8;
    p2.hp    = 20;
    p2.score = 0;

    for (int i = 0; i < MAX_BULLETS; i++) {
        bullets[i].active  = 0;
        bullets[i].is_big  = 0;
        bullets[i].bounces = 0;
        bullets[i].x_fp    = 0;
        bullets[i].y_fp    = 0;
        bullets[i].vx_fp   = 0;
        bullets[i].vy_fp   = 0;
    }

    // Set initial HUD health
    REG_HUD_HEALTH_1 = 20;
    REG_HUD_HEALTH_2 = 20;

    // Clear any pending hardware collisions
    clear_collision_wall(0xFF);
    clear_collision_tank(0xFFFF);
    clear_collision_bullet(0xFFFFFFFF);
}

//=============================================================================
// Spawn Projectile
//=============================================================================
static void spawn_bullet(int owner, int is_big) {
    int start_idx = (owner == 1) ? P1_BULLET_START : P2_BULLET_START;
    int end_idx   = (owner == 1) ? P1_BULLET_END   : P2_BULLET_END;
    Tank *t       = (owner == 1) ? &p1 : &p2;

    // Find free slot
    for (int i = start_idx; i <= end_idx; i++) {
        if (!bullets[i].active) {
            bullets[i].active  = 1;
            bullets[i].is_big  = is_big ? 1 : 0;
            bullets[i].bounces = 0;
            bullets[i].owner   = owner;

            // Spawn at center of tank + offset along gun barrel
            // Uses RV32M MUL instruction
            int32_t speed = is_big ? BULLET_BIG_SPEED : BULLET_NORM_SPEED;
            int32_t cos_val = cos_fp[t->angle];
            int32_t sin_val = sin_fp[t->angle];

            bullets[i].x_fp = t->x_fp + TO_FP(10) + ((cos_val * 14) << (FP_SHIFT - 8));
            bullets[i].y_fp = t->y_fp + TO_FP(10) + ((sin_val * 14) << (FP_SHIFT - 8));

            bullets[i].vx_fp = (cos_val * speed) << (FP_SHIFT - 8);
            bullets[i].vy_fp = (sin_val * speed) << (FP_SHIFT - 8);

            break;
        }
    }
}

//=============================================================================
// Tank Physics & Controls
//=============================================================================
static void update_tanks(void) {
    uint32_t p1_keys = get_p1_input();
    uint32_t p2_keys = get_p2_input();

    // ---------------- Player 1 Controls ----------------
    if (p1.hp > 0) {
        if (p1_keys & BTN_LEFT)
            p1.angle = (p1.angle + 15) & 0xF; // Rotate CCW
        if (p1_keys & BTN_RIGHT)
            p1.angle = (p1.angle + 1) & 0xF;  // Rotate CW

        int32_t move_dir = 0;
        if (p1_keys & BTN_FWD) move_dir = 1;
        else if (p1_keys & BTN_BWD) move_dir = -1;

        if (move_dir != 0) {
            // Velocity calculation using hardware multiplier
            int32_t dx = (cos_fp[p1.angle] * move_dir * 2) << (FP_SHIFT - 8);
            int32_t dy = (sin_fp[p1.angle] * move_dir * 2) << (FP_SHIFT - 8);

            int32_t new_x = p1.x_fp + dx;
            int32_t new_y = p1.y_fp + dy;

            // Boundary clamping
            if (FROM_FP(new_x) >= ARENA_MIN_X && FROM_FP(new_x) <= (ARENA_MAX_X - TANK_SIZE))
                p1.x_fp = new_x;
            if (FROM_FP(new_y) >= ARENA_MIN_Y && FROM_FP(new_y) <= (ARENA_MAX_Y - TANK_SIZE))
                p1.y_fp = new_y;
        }

        // Primary fire (0.5s cooldown check)
        if ((p1_keys & BTN_SHOOT) && is_p1_shoot_ready()) {
            spawn_bullet(1, 0);
            trigger_p1_shoot_cooldown();
        }

        // Special attack (20s cooldown check)
        if ((p1_keys & BTN_SPECIAL) && is_p1_spec_ready()) {
            spawn_bullet(1, 1);
            trigger_p1_spec_cooldown();
        }
    }

    // ---------------- Player 2 Controls ----------------
    if (p2.hp > 0) {
        if (p2_keys & BTN_LEFT)
            p2.angle = (p2.angle + 15) & 0xF;
        if (p2_keys & BTN_RIGHT)
            p2.angle = (p2.angle + 1) & 0xF;

        int32_t move_dir2 = 0;
        if (p2_keys & BTN_FWD) move_dir2 = 1;
        else if (p2_keys & BTN_BWD) move_dir2 = -1;

        if (move_dir2 != 0) {
            int32_t dx2 = (cos_fp[p2.angle] * move_dir2 * 2) << (FP_SHIFT - 8);
            int32_t dy2 = (sin_fp[p2.angle] * move_dir2 * 2) << (FP_SHIFT - 8);

            int32_t new_x2 = p2.x_fp + dx2;
            int32_t new_y2 = p2.y_fp + dy2;

            if (FROM_FP(new_x2) >= ARENA_MIN_X && FROM_FP(new_x2) <= (ARENA_MAX_X - TANK_SIZE))
                p2.x_fp = new_x2;
            if (FROM_FP(new_y2) >= ARENA_MIN_Y && FROM_FP(new_y2) <= (ARENA_MAX_Y - TANK_SIZE))
                p2.y_fp = new_y2;
        }

        if ((p2_keys & BTN_SHOOT) && is_p2_shoot_ready()) {
            spawn_bullet(2, 0);
            trigger_p2_shoot_cooldown();
        }

        if ((p2_keys & BTN_SPECIAL) && is_p2_spec_ready()) {
            spawn_bullet(2, 1);
            trigger_p2_spec_cooldown();
        }
    }
}

//=============================================================================
// Projectile Movement & Angular Wall Reflection Physics
//=============================================================================
static void update_bullets(void) {
    uint32_t hw_wall_hits = REG_COLLISION_WALL;

    for (int i = 0; i < MAX_BULLETS; i++) {
        if (!bullets[i].active)
            continue;

        // Predict next position
        int32_t next_x_fp = bullets[i].x_fp + bullets[i].vx_fp;
        int32_t next_y_fp = bullets[i].y_fp + bullets[i].vy_fp;

        int px = FROM_FP(next_x_fp);
        int py = FROM_FP(next_y_fp);

        int reflected = 0;

        // 1. Check perimeter wall boundary reflection
        if (px <= ARENA_MIN_X || px >= ARENA_MAX_X) {
            bullets[i].vx_fp = -bullets[i].vx_fp; // Specular reflection: invert Vx
            reflected = 1;
        }
        if (py <= ARENA_MIN_Y || py >= ARENA_MAX_Y) {
            bullets[i].vy_fp = -bullets[i].vy_fp; // Specular reflection: invert Vy
            reflected = 1;
        }

        // 2. Check inner maze wall tiles or hardware collision engine flag
        if (!reflected && ((hw_wall_hits & (1U << i)) || check_and_destroy_tile(px, py, bullets[i].is_big))) {
            // Determine incident wall face
            int prev_px = FROM_FP(bullets[i].x_fp);
            int prev_py = FROM_FP(bullets[i].y_fp);

            if ((prev_px / 24) != (px / 24))
                bullets[i].vx_fp = -bullets[i].vx_fp;
            else
                bullets[i].vy_fp = -bullets[i].vy_fp;

            reflected = 1;
        }

        if (reflected) {
            bullets[i].bounces++;
            if (bullets[i].bounces > MAX_BOUNCES) {
                bullets[i].active = 0;
                continue;
            }
        }

        // Advance bullet position
        bullets[i].x_fp += bullets[i].vx_fp;
        bullets[i].y_fp += bullets[i].vy_fp;
    }

    // Atomically clear hardware wall collision sticky bits (W1C)
    if (hw_wall_hits)
        clear_collision_wall(hw_wall_hits);
}

//=============================================================================
// Hardware Collision Engine Processing: Tank Hits & Bullet Annihilation
//=============================================================================
static void process_collisions(void) {
    // 1. Process Bullet-Tank Collisions
    uint32_t tank_hits = REG_COLLISION_TANK;
    uint32_t p1_hit_mask = tank_hits & 0xFFU;
    uint32_t p2_hit_mask = (tank_hits >> 8) & 0xFFU;

    if (p1_hit_mask) {
        for (int i = 0; i < MAX_BULLETS; i++) {
            if (p1_hit_mask & (1U << i)) {
                if (bullets[i].active) {
                    uint8_t dmg = bullets[i].is_big ? 6 : 2;
                    if (p1.hp > dmg) p1.hp -= dmg;
                    else p1.hp = 0;

                    bullets[i].active = 0;
                }
            }
        }
    }

    if (p2_hit_mask) {
        for (int i = 0; i < MAX_BULLETS; i++) {
            if (p2_hit_mask & (1U << i)) {
                if (bullets[i].active) {
                    uint8_t dmg = bullets[i].is_big ? 6 : 2;
                    if (p2.hp > dmg) p2.hp -= dmg;
                    else p2.hp = 0;

                    bullets[i].active = 0;
                }
            }
        }
    }

    if (tank_hits)
        clear_collision_tank(tank_hits);

    // 2. Process Bullet-Bullet Pair Collisions
    uint32_t bullet_hits = REG_COLLISION_BULLET;
    if (bullet_hits) {
        // Destroy colliding bullets
        int cell = 0;
        for (int i = 0; i < 7; i++) {
            for (int j = i + 1; j < 8; j++) {
                if (bullet_hits & (1U << cell)) {
                    bullets[i].active = 0;
                    bullets[j].active = 0;
                }
                cell++;
            }
        }
        clear_collision_bullet(bullet_hits);
    }
}

//=============================================================================
// Update Hardware MMIO Display Registers (Fig 5)
//=============================================================================
static void sync_hardware_display(void) {
    // Update Tank coordinates and angles
    update_tank_sprite(1, FROM_FP(p1.x_fp), FROM_FP(p1.y_fp), p1.angle);
    update_tank_sprite(2, FROM_FP(p2.x_fp), FROM_FP(p2.y_fp), p2.angle);

    // Update Bullet positions
    uint32_t act_mask = 0;
    uint32_t big_mask = 0;

    for (int i = 0; i < MAX_BULLETS; i++) {
        REG_SPRITE_BULLET_X(i) = FROM_FP(bullets[i].x_fp);
        REG_SPRITE_BULLET_Y(i) = FROM_FP(bullets[i].y_fp);

        if (bullets[i].active)
            act_mask |= (1U << i);
        if (bullets[i].is_big)
            big_mask |= (1U << i);
    }

    REG_SPRITE_BULLET_ACT = act_mask;
    REG_SPRITE_BULLET_BIG = big_mask;

    // Update Player Health in HUD
    REG_HUD_HEALTH_1 = p1.hp;
    REG_HUD_HEALTH_2 = p2.hp;
}

//=============================================================================
// Main Game Loop Entry Point
//=============================================================================
int main(void) {
    init_game();

    while (1) {
        // 1. Process User Inputs & Move Tanks
        update_tanks();

        // 2. Advance Projectiles with Angular Reflection Physics
        update_bullets();

        // 3. Handle Hardware Collision Status (Tank Damage & Annihilation)
        process_collisions();

        // 4. Push Live Frame Data to Hardware MMIO Registers
        sync_hardware_display();

        // 5. Pace Game Loop (~60 FPS at 50 MHz CPU clock)
        frame_delay(4000);
    }

    return 0;
}
