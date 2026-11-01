//=============================================================================
// Battle Tanks: Host-Based C Software Unit Test Suite
// Verifies all core game mechanics, physics, and MMIO drivers natively
//=============================================================================

#define HOST_TEST 1
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

#include "game.h"
#include "physics.h"
#include "mmio.h"

// Define mock MMIO memory space
uint32_t g_mock_mmio_space[1024];

// Test statistics
static int g_tests_run = 0;
static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define TEST_ASSERT(cond, msg) do { \
    g_tests_run++; \
    if (cond) { \
        g_tests_passed++; \
    } else { \
        g_tests_failed++; \
        printf("  [FAIL] Line %d: %s\n", __LINE__, msg); \
    } \
} while(0)

#define RUN_SUITE(suite_fn, name) do { \
    printf("\n=== Running Suite: %s ===\n", name); \
    suite_fn(); \
} while(0)

static void reset_mock_mmio(void) {
    memset(g_mock_mmio_space, 0, sizeof(g_mock_mmio_space));
    // Default timers ready: P1 shoot, P2 shoot, P1 spec, P2 spec
    REG_TIMER_STATUS = TMR_P1_SHOOT | TMR_P2_SHOOT | TMR_P1_SPECIAL | TMR_P2_SPECIAL;
}

//=============================================================================
// Suite 1: Trigonometric Tables & Fixed-Point Conversion
//=============================================================================
static void test_suite_trig_and_fixed_point(void) {
    // 1. Check cardinal angles
    // Angle 0: East (cos=256, sin=0)
    TEST_ASSERT(g_cos_fp[0] == 256, "cos(0 deg) == 256");
    TEST_ASSERT(g_sin_fp[0] == 0,   "sin(0 deg) == 0");

    // Angle 4: South (cos=0, sin=256)
    TEST_ASSERT(g_cos_fp[4] == 0,   "cos(90 deg) == 0");
    TEST_ASSERT(g_sin_fp[4] == 256, "sin(90 deg) == 256");

    // Angle 8: West (cos=-256, sin=0)
    TEST_ASSERT(g_cos_fp[8] == -256, "cos(180 deg) == -256");
    TEST_ASSERT(g_sin_fp[8] == 0,    "sin(180 deg) == 0");

    // Angle 12: North (cos=0, sin=-256)
    TEST_ASSERT(g_cos_fp[12] == 0,    "cos(270 deg) == 0");
    TEST_ASSERT(g_sin_fp[12] == -256, "sin(270 deg) == -256");

    // 2. Pythagorean theorem test for all 16 angles: cos^2 + sin^2 ~= 256^2 (65536)
    for (int i = 0; i < 16; i++) {
        int32_t c = g_cos_fp[i];
        int32_t s = g_sin_fp[i];
        int32_t mag_sq = c * c + s * s;
        // Check within 2% margin due to integer rounding
        int diff = abs(mag_sq - 65536);
        TEST_ASSERT(diff < 2000, "cos^2 + sin^2 approximately equals 256^2");
    }

    // 3. Fixed point conversions
    int val = 42;
    int32_t fp = TO_FP(val);
    TEST_ASSERT(fp == (42 << 8), "TO_FP(42) shifts left by 8");
    TEST_ASSERT(FROM_FP(fp) == 42, "FROM_FP round-trip equals 42");

    int negative_val = -15;
    int32_t neg_fp = TO_FP(negative_val);
    TEST_ASSERT(FROM_FP(neg_fp) == -15, "Negative FP round-trip equals -15");
}

//=============================================================================
// Suite 2: Game Initialization
//=============================================================================
static void test_suite_game_init(void) {
    reset_mock_mmio();
    game_init();

    // Verify Player 1 starting values
    TEST_ASSERT(FROM_FP(g_p1.x_fp) == 48, "P1 initial X is 48");
    TEST_ASSERT(FROM_FP(g_p1.y_fp) == 48, "P1 initial Y is 48");
    TEST_ASSERT(g_p1.angle == 0,          "P1 initial angle is 0 (East)");
    TEST_ASSERT(g_p1.hp == 20,            "P1 initial HP is 20");
    TEST_ASSERT(g_p1.score == 0,         "P1 initial score is 0");

    // Verify Player 2 starting values
    TEST_ASSERT(FROM_FP(g_p2.x_fp) == 410, "P2 initial X is 410");
    TEST_ASSERT(FROM_FP(g_p2.y_fp) == 410, "P2 initial Y is 410");
    TEST_ASSERT(g_p2.angle == 8,           "P2 initial angle is 8 (West)");
    TEST_ASSERT(g_p2.hp == 20,             "P2 initial HP is 20");
    TEST_ASSERT(g_p2.score == 0,          "P2 initial score is 0");

    // Verify all 8 bullets inactive
    for (int i = 0; i < MAX_BULLETS; i++) {
        TEST_ASSERT(g_bullets[i].active == 0, "Bullet is initially inactive");
    }

    // Verify MMIO registers
    TEST_ASSERT(HUD_HEALTH_P1(REG_HUD_HEALTH) == 20, "HUD Health 1 field initialized to 20");
    TEST_ASSERT(HUD_HEALTH_P2(REG_HUD_HEALTH) == 20, "HUD Health 2 field initialized to 20");
}

//=============================================================================
// Suite 3: Tank Steering & Rotation
//=============================================================================
static void test_suite_tank_steering(void) {
    reset_mock_mmio();
    game_init();

    // Player 1 turns Right (+1)
    REG_P1_KEYS = BTN_RIGHT;
    game_update_tanks();
    TEST_ASSERT(g_p1.angle == 1, "P1 angle rotates right: 0 -> 1");

    // Turn Right again
    game_update_tanks();
    TEST_ASSERT(g_p1.angle == 2, "P1 angle rotates right: 1 -> 2");

    // Player 1 turns Left (-1)
    REG_P1_KEYS = BTN_LEFT;
    game_update_tanks();
    TEST_ASSERT(g_p1.angle == 1, "P1 angle rotates left: 2 -> 1");

    // Player 1 turns Left past 0 (wrap-around to 15)
    game_update_tanks(); // 1 -> 0
    game_update_tanks(); // 0 -> 15
    TEST_ASSERT(g_p1.angle == 15, "P1 angle wraps cleanly: 0 -> 15");

    // Full 360 degree rotation (16 steps)
    for (int i = 0; i < 16; i++) {
        game_update_tanks();
    }
    TEST_ASSERT(g_p1.angle == 15, "P1 full 360-degree rotation returns to same angle");

    // Player 2 rotation test
    REG_P1_KEYS = 0;
    REG_P2_KEYS = BTN_RIGHT;
    game_update_tanks();
    TEST_ASSERT(g_p2.angle == 9, "P2 angle rotates right: 8 -> 9");
}

//=============================================================================
// Suite 4: Tank Movement & Arena Bounds Clamping
//=============================================================================
static void test_suite_tank_movement_and_bounds(void) {
    reset_mock_mmio();
    game_init();

    // Facing East (angle 0): cos=256, sin=0 -> moves in +X
    int initial_x = FROM_FP(g_p1.x_fp);
    int initial_y = FROM_FP(g_p1.y_fp);

    REG_P1_KEYS = BTN_FWD;
    game_update_tanks();

    int moved_x = FROM_FP(g_p1.x_fp);
    int moved_y = FROM_FP(g_p1.y_fp);
    TEST_ASSERT(moved_x > initial_x, "P1 moves forward in +X when facing East");
    TEST_ASSERT(moved_y == initial_y, "P1 Y unchanged when moving East");

    // Moving backward in reverse
    REG_P1_KEYS = BTN_BWD;
    game_update_tanks();
    TEST_ASSERT(FROM_FP(g_p1.x_fp) == initial_x, "P1 backward movement reverses X");

    // Test arena wall clamping: Drive backwards towards left boundary (x < 24)
    g_p1.x_fp = TO_FP(25);
    g_p1.angle = 8; // Facing West: forward goes towards x=0
    REG_P1_KEYS = BTN_FWD;
    for (int step = 0; step < 10; step++) {
        game_update_tanks();
    }
    TEST_ASSERT(FROM_FP(g_p1.x_fp) >= ARENA_MIN_X, "P1 X clamped at ARENA_MIN_X (24)");

    // Test arena max clamping: Drive towards right boundary
    g_p1.x_fp = TO_FP(430);
    g_p1.angle = 0; // Facing East
    REG_P1_KEYS = BTN_FWD;
    for (int step = 0; step < 20; step++) {
        game_update_tanks();
    }
    TEST_ASSERT(FROM_FP(g_p1.x_fp) <= (ARENA_MAX_X - TANK_SIZE), "P1 X clamped at ARENA_MAX_X - TANK_SIZE (436)");

    // Maze walls block tanks: steel pillar at tile (4,4) = pixels 96..119
    MAZE_TILE(4, 4) = TILE_STEEL_SOLID;
    g_p1.x_fp = TO_FP(60);
    g_p1.y_fp = TO_FP(100);
    g_p1.angle = 0; // East, straight into the pillar
    REG_P1_KEYS = BTN_FWD;
    for (int step = 0; step < 40; step++) {
        game_update_tanks();
    }
    TEST_ASSERT(FROM_FP(g_p1.x_fp) + TANK_SIZE <= 96, "P1 stopped by maze wall (no driving through pillars)");
    TEST_ASSERT(physics_tank_hits_wall(FROM_FP(g_p1.x_fp), FROM_FP(g_p1.y_fp)) == 0, "P1 never ends up overlapping a wall");
    MAZE_TILE(4, 4) = TILE_EMPTY;
    REG_P1_KEYS = 0;
}

//=============================================================================
// Suite 5: Bullet Spawning & Capacity Limits
//=============================================================================
static void test_suite_bullet_spawning(void) {
    reset_mock_mmio();
    game_init();

    // 1. Primary Fire
    REG_P1_KEYS = BTN_SHOOT;
    game_update_tanks();

    // Slot 0 should be active
    TEST_ASSERT(g_bullets[0].active == 1, "P1 primary fire spawns bullet in slot 0");
    TEST_ASSERT(g_bullets[0].owner == 1,  "Bullet 0 owner is Player 1");
    TEST_ASSERT(g_bullets[0].is_big == 0, "Bullet 0 is normal projectile");
    TEST_ASSERT(g_bullets[0].vx_fp > 0,   "Bullet 0 velocity is positive X (facing East)");

    // Trigger cooldown register must be written
    TEST_ASSERT((REG_TIMER_TRIGGER & TMR_P1_SHOOT) != 0, "P1 shoot cooldown triggered in MMIO");

    // 2. Cooldown blocking test: If timer status reports cooling down (0), cannot shoot again
    REG_TIMER_STATUS &= ~TMR_P1_SHOOT; // Simulate timer busy
    REG_P1_KEYS = BTN_SHOOT;
    game_update_tanks();
    TEST_ASSERT(g_bullets[1].active == 0, "P1 cannot shoot while cooldown timer active");

    // Re-enable timer
    REG_TIMER_STATUS |= TMR_P1_SHOOT;

    // 3. Special Attack Fire
    REG_TIMER_STATUS |= TMR_P1_SPECIAL;
    REG_P1_KEYS = BTN_SPECIAL;
    game_update_tanks();

    TEST_ASSERT(g_bullets[1].active == 1, "P1 special attack spawns bullet in slot 1");
    TEST_ASSERT(g_bullets[1].is_big == 1, "Bullet 1 is a BIG projectile");
    TEST_ASSERT(g_bullets[1].owner == 1,  "Bullet 1 owner is Player 1");
    TEST_ASSERT((REG_TIMER_TRIGGER & TMR_P1_SPECIAL) != 0, "P1 special cooldown triggered in MMIO");

    // 4. Player 2 Bullet Pool Independence
    REG_P1_KEYS = 0;
    REG_P2_KEYS = BTN_SHOOT;
    REG_TIMER_STATUS |= TMR_P2_SHOOT;
    game_update_tanks();

    TEST_ASSERT(g_bullets[4].active == 1, "P2 shoot spawns into dedicated slot 4 (P2 pool)");
    TEST_ASSERT(g_bullets[4].owner == 2,  "Bullet 4 owner is Player 2");
    TEST_ASSERT(g_bullets[4].vx_fp < 0,   "Bullet 4 velocity is negative X (facing West)");
}

//=============================================================================
// Suite 6: 2D Wall Reflection Physics & Ricochets
//=============================================================================
static void test_suite_reflection_physics(void) {
    reset_mock_mmio();
    game_init();

    Bullet b;
    b.active = 1;
    b.is_big = 0;
    b.bounces = 0;
    b.owner = 1;
    b.vx_fp = TO_FP(6);
    b.vy_fp = TO_FP(3);

    // Bounce off right arena wall (new_x >= 456)
    int ref = physics_reflect_bullet(&b, 450, 100, 458, 103);
    TEST_ASSERT(ref == 1, "physics_reflect_bullet detected arena boundary hit");
    TEST_ASSERT(b.vx_fp == -TO_FP(6), "Horizontal velocity inverted on vertical wall hit");
    TEST_ASSERT(b.vy_fp == TO_FP(3),  "Vertical velocity unchanged on vertical wall hit");
    TEST_ASSERT(b.bounces == 1,       "Bounce count incremented to 1");

    // Bounce off bottom arena wall (new_y >= 456)
    ref = physics_reflect_bullet(&b, 300, 450, 294, 458);
    TEST_ASSERT(ref == 1, "physics_reflect_bullet detected bottom boundary hit");
    TEST_ASSERT(b.vy_fp == -TO_FP(3), "Vertical velocity inverted on horizontal wall hit");
    TEST_ASSERT(b.bounces == 2,       "Bounce count incremented to 2");

    // Exceeding MAX_BOUNCES (5 bounces allowed)
    b.bounces = MAX_BOUNCES; // 5
    ref = physics_reflect_bullet(&b, 20, 100, 18, 100);
    TEST_ASSERT(b.bounces == 6,   "Bounce count reaches 6");
    TEST_ASSERT(b.active == 0,    "Bullet deactivates after exceeding MAX_BOUNCES");
}

//=============================================================================
// Suite 7: Dynamic Maze Destruction
//=============================================================================
static void test_suite_maze_destruction(void) {
    reset_mock_mmio();

    // Place a destructible brick at tile row=5, col=5 (pixel coords: 5*24 = 120)
    MAZE_TILE(5, 5) = TILE_BRICK_DESTRUCTIBLE;
    TEST_ASSERT(MAZE_TILE(5, 5) == TILE_BRICK_DESTRUCTIBLE, "Maze tile (5,5) set to DESTRUCTIBLE");

    // Check collision with projectile at (125, 125)
    int hit = physics_check_and_destroy_tile(125, 125, 0);
    TEST_ASSERT(hit == 1, "Hit detected on destructible brick");
    TEST_ASSERT(MAZE_TILE(5, 5) == TILE_EMPTY, "Destructible brick shattered to TILE_EMPTY in MMIO RAM!");

    // Empty space check
    int empty_hit = physics_check_and_destroy_tile(125, 125, 0);
    TEST_ASSERT(empty_hit == 0, "No hit on now-empty floor tile");

    // Indestructible steel wall check
    MAZE_TILE(6, 6) = TILE_STEEL_SOLID;
    int steel_hit = physics_check_and_destroy_tile(6*24 + 10, 6*24 + 10, 0);
    TEST_ASSERT(steel_hit == 1, "Hit detected on steel wall");
    TEST_ASSERT(MAZE_TILE(6, 6) == TILE_STEEL_SOLID, "Steel wall remains intact (not destroyed)");
}

//=============================================================================
// Suite 8: Collision Resolution & Combat Damage
//=============================================================================
static void test_suite_collision_and_damage(void) {
    reset_mock_mmio();
    game_init();

    // Setup active bullets (owner 1 = P1 shot, owner 2 = P2 shot)
    g_bullets[0].active = 1;
    g_bullets[0].is_big = 0; // Normal bullet: deals 2 damage
    g_bullets[0].owner  = 1;

    g_bullets[1].active = 1;
    g_bullets[1].is_big = 1; // Big bullet: deals 6 damage
    g_bullets[1].owner  = 2;

    // 1. Hardware reports: bullet 0 overlapped tank 2 -> HIT_MASK = P2 hit | bullet 0
    REG_COLLISION_TANK = COLL_TANK_P2_HIT | (1U << 0);

    game_process_collisions();

    TEST_ASSERT(g_p2.hp == 18,    "P2 took 2 damage from normal bullet (20 -> 18)");
    TEST_ASSERT(g_p1.hp == 20,    "P1 untouched when only P2 was hit");
    TEST_ASSERT(g_bullets[0].active == 0, "Bullet 0 deactivated upon hitting tank");

    // 2. Big bullet (fired by P2) hits Player 1
    REG_COLLISION_TANK = COLL_TANK_P1_HIT | (1U << 1);
    game_process_collisions();

    TEST_ASSERT(g_p1.hp == 14,    "P1 took 6 damage from big special bullet (20 -> 14)");
    TEST_ASSERT(g_bullets[1].active == 0, "Big bullet deactivated upon hitting tank");

    // 2b. Friendly fire: a fresh bullet fired by P1 overlapping P1's own box does nothing
    g_bullets[3].active = 1;
    g_bullets[3].is_big = 0;
    g_bullets[3].owner  = 1;
    g_bullets[3].bounces = 0;
    REG_COLLISION_TANK = COLL_TANK_P1_HIT | (1U << 3);
    game_process_collisions();
    TEST_ASSERT(g_p1.hp == 14,    "Shooter is not damaged by its own fresh bullet");
    TEST_ASSERT(g_bullets[3].active == 1, "Own fresh bullet keeps flying through the shooter");
    g_bullets[3].active = 0;

    // 2c. Reflected bullet self-damage: a bullet fired by P1 that bounced (bounces > 0)
    // CAN damage P1 and disappears upon collision!
    g_bullets[3].active = 1;
    g_bullets[3].is_big = 0;
    g_bullets[3].owner  = 1;
    g_bullets[3].bounces = 1;
    REG_COLLISION_TANK = COLL_TANK_P1_HIT | (1U << 3);
    game_process_collisions();
    TEST_ASSERT(g_p1.hp == 12,    "Shooter takes 2 damage from own reflected bullet (14 -> 12)");
    TEST_ASSERT(g_bullets[3].active == 0, "Own reflected bullet deactivates upon hitting shooter");

    // 3. Damage saturation at zero
    g_p1.hp = 3;
    g_bullets[2].active = 1;
    g_bullets[2].is_big = 1; // 6 damage on 3 HP
    g_bullets[2].owner  = 2;
    REG_COLLISION_TANK = COLL_TANK_P1_HIT | (1U << 2);
    game_process_collisions();
    TEST_ASSERT(g_p1.hp == 0, "P1 HP saturated at 0 without underflow");

    // 4. Bullet-to-Bullet mutual annihilation
    g_bullets[0].active = 1;
    g_bullets[1].active = 1;
    // Hardware flags BOTH bullets of an overlapping pair (one bit per bullet)
    REG_COLLISION_BULLET = (1U << 0) | (1U << 1);
    game_process_collisions();
    TEST_ASSERT(g_bullets[0].active == 0, "Bullet 0 annihilated in mutual collision");
    TEST_ASSERT(g_bullets[1].active == 0, "Bullet 1 annihilated in mutual collision");
}

//=============================================================================
// Suite 9: MMIO Display Synchronization
//=============================================================================
static void test_suite_display_sync(void) {
    reset_mock_mmio();
    game_init();

    g_p1.x_fp = TO_FP(120);
    g_p1.y_fp = TO_FP(85);
    g_p1.angle = 7;
    g_p1.hp = 17;

    g_p2.x_fp = TO_FP(300);
    g_p2.y_fp = TO_FP(250);
    g_p2.angle = 14;
    g_p2.hp = 9;

    g_bullets[2].active = 1;
    g_bullets[2].is_big = 1;
    g_bullets[2].x_fp = TO_FP(200);
    g_bullets[2].y_fp = TO_FP(150);

    game_sync_display();

    // Verify Tank 1 packed sprite register: {y[25:16], x[9:0]} (10-bit coords)
    uint32_t expected_p1_reg = (85U << 16) | 120U;
    TEST_ASSERT(REG_SPRITE_P1_TANK == expected_p1_reg, "REG_SPRITE_P1_TANK correctly packed");

    // Verify Tank 2 packed sprite register (x=300 needs > 8 bits)
    uint32_t expected_p2_reg = (250U << 16) | 300U;
    TEST_ASSERT(REG_SPRITE_P2_TANK == expected_p2_reg, "REG_SPRITE_P2_TANK correctly packed (10-bit x)");

    // Verify turret angles register: {ang2[7:4], ang1[3:0]}
    TEST_ASSERT(REG_TANK_ANGLES == ((14U << 4) | 7U), "REG_TANK_ANGLES packs both turret angles");

    // Verify Bullet register: {big[21], act[20], y[19:10], x[9:0]}
    uint32_t expected_b2 = (1U << 21) | (1U << 20) | (150U << 10) | 200U;
    TEST_ASSERT(REG_SPRITE_BULLET(2) == expected_b2, "Bullet 2 register packs x/y/active/big");
    TEST_ASSERT((REG_SPRITE_BULLET(0) & (1U << 20)) == 0, "Bullet 0 inactive bit clear");

    // Verify HUD Health
    TEST_ASSERT(HUD_HEALTH_P1(REG_HUD_HEALTH) == 17, "HUD health field matches P1 HP");
    TEST_ASSERT(HUD_HEALTH_P2(REG_HUD_HEALTH) == 9,  "HUD health field matches P2 HP");
}

//=============================================================================
// Suite 10: Brick destruction by bullets, maze reset, tank-vs-tank blocking
//=============================================================================
static void test_suite_bricks_reset_and_tank_blocking(void) {
    // --- Bricks always break, even when the hardware wall flag is already set ---
    reset_mock_mmio();
    game_init();
    MAZE_TILE(6, 9) = TILE_BRICK_DESTRUCTIBLE;       // pixels x 216..239, y 144..167
    g_bullets[0].active  = 1;
    g_bullets[0].is_big  = 0;
    g_bullets[0].bounces = 0;
    g_bullets[0].owner   = 1;
    g_bullets[0].x_fp  = TO_FP(222);                 // centre (225, 153) is inside the brick
    g_bullets[0].y_fp  = TO_FP(150);
    g_bullets[0].vx_fp = 0;
    g_bullets[0].vy_fp = TO_FP(1);
    REG_COLLISION_WALL = 1U << 0;                    // hardware already flagged it
    game_update_bullets();
    TEST_ASSERT(MAZE_TILE(6, 9) == TILE_EMPTY, "Brick breaks even when hardware wall flag was set");

    // Brick approached from the left: hardware flag (centre) fires before the corner
    MAZE_TILE(6, 9) = TILE_BRICK_DESTRUCTIBLE;
    g_bullets[0].active = 1;
    g_bullets[0].bounces = 0;
    g_bullets[0].x_fp  = TO_FP(190);
    g_bullets[0].y_fp  = TO_FP(150);
    g_bullets[0].vx_fp = TO_FP(6);
    g_bullets[0].vy_fp = 0;
    REG_COLLISION_WALL = 0;
    for (int f = 0; f < 10; f++) {
        // emulate the hardware: it flags the bullet when its centre is on a non-floor tile
        int cx = FROM_FP(g_bullets[0].x_fp) + 3, cy = FROM_FP(g_bullets[0].y_fp) + 3;
        if (MAZE_TILE(cy / 24, cx / 24) != TILE_EMPTY) REG_COLLISION_WALL = 1U << 0;
        game_update_bullets();
    }
    TEST_ASSERT(MAZE_TILE(6, 9) == TILE_EMPTY, "Brick breaks when approached from the left");

    // Brick approached from the right (corner leads, hardware flag clear)
    MAZE_TILE(6, 9) = TILE_BRICK_DESTRUCTIBLE;
    g_bullets[0].active = 1;
    g_bullets[0].bounces = 0;
    g_bullets[0].x_fp  = TO_FP(270);
    g_bullets[0].y_fp  = TO_FP(150);
    g_bullets[0].vx_fp = -TO_FP(6);
    g_bullets[0].vy_fp = 0;
    REG_COLLISION_WALL = 0;
    for (int f = 0; f < 10; f++) game_update_bullets();
    TEST_ASSERT(MAZE_TILE(6, 9) == TILE_EMPTY, "Brick breaks when approached from the right");

    // Every brick in a long run breaks, not just the first few
    reset_mock_mmio();
    game_init();
    int broken = 0;
    for (int c = 8; c <= 11; c++) {
        MAZE_TILE(10, c) = TILE_BRICK_DESTRUCTIBLE;
        g_bullets[0].active  = 1;
        g_bullets[0].bounces = 0;
        g_bullets[0].is_big  = 0;
        g_bullets[0].x_fp  = TO_FP(c * 24 + 10);
        g_bullets[0].y_fp  = TO_FP(10 * 24 - 10);
        g_bullets[0].vx_fp = 0;
        g_bullets[0].vy_fp = TO_FP(4);
        REG_COLLISION_WALL = 1U << 0;               // flag set every time
        for (int f = 0; f < 6; f++) game_update_bullets();
        if (MAZE_TILE(10, c) == TILE_EMPTY) broken++;
    }
    TEST_ASSERT(broken == 4, "All four bricks break (never stops breaking after the first ones)");

    // --- Maze is restored on game_init (reset) ---
    reset_mock_mmio();
    game_init();
    TEST_ASSERT(MAZE_TILE(10, 8) == TILE_BRICK_DESTRUCTIBLE, "game_init places bricks at row 10, col 8");
    TEST_ASSERT(MAZE_TILE(10, 11) == TILE_BRICK_DESTRUCTIBLE, "game_init places bricks at row 10, col 11");
    TEST_ASSERT(MAZE_TILE(10, 7) == TILE_EMPTY && MAZE_TILE(10, 12) == TILE_EMPTY, "Floor around bricks is empty");
    TEST_ASSERT(MAZE_TILE(0, 0) == TILE_STEEL_SOLID && MAZE_TILE(19, 5) == TILE_STEEL_SOLID, "Border is steel");
    TEST_ASSERT(MAZE_TILE(4, 4) == TILE_STEEL_SOLID && MAZE_TILE(8, 12) == TILE_STEEL_SOLID, "Pillars are steel");
    TEST_ASSERT(MAZE_TILE(5, 5) == TILE_EMPTY, "Open floor is empty");
    MAZE_TILE(10, 8) = TILE_EMPTY;
    MAZE_TILE(10, 9) = TILE_EMPTY;
    MAZE_TILE(10, 10) = TILE_EMPTY;
    MAZE_TILE(10, 11) = TILE_EMPTY;
    MAZE_TILE(5, 5) = TILE_STEEL_SOLID;
    game_init();                                     // "reset game"
    TEST_ASSERT(MAZE_TILE(10, 8) == TILE_BRICK_DESTRUCTIBLE && MAZE_TILE(10, 9) == TILE_BRICK_DESTRUCTIBLE &&
                MAZE_TILE(10, 10) == TILE_BRICK_DESTRUCTIBLE && MAZE_TILE(10, 11) == TILE_BRICK_DESTRUCTIBLE,
                "Broken bricks are back after reset");
    TEST_ASSERT(MAZE_TILE(5, 5) == TILE_EMPTY, "Stray tile removed after reset");

    // --- Tank vs tank blocking ---
    reset_mock_mmio();
    game_init();
    g_p1.x_fp = TO_FP(100); g_p1.y_fp = TO_FP(150); g_p1.angle = 0;      // facing East
    g_p2.x_fp = TO_FP(124); g_p2.y_fp = TO_FP(150);                      // 24 px ahead
    REG_P1_KEYS = BTN_FWD;
    for (int f = 0; f < 30; f++) game_update_tanks();
    TEST_ASSERT(FROM_FP(g_p1.x_fp) + TANK_SIZE <= FROM_FP(g_p2.x_fp), "P1 is blocked by P2 straight ahead");
    TEST_ASSERT(!physics_tanks_overlap(FROM_FP(g_p1.x_fp), FROM_FP(g_p1.y_fp),
                                       FROM_FP(g_p2.x_fp), FROM_FP(g_p2.y_fp)), "Tanks never overlap (P1 driving)");
    TEST_ASSERT(FROM_FP(g_p1.x_fp) >= 100 + 2, "P1 still moved up to the other tank");
    REG_P1_KEYS = 0;

    // P2 driving into P1
    g_p1.x_fp = TO_FP(200); g_p1.y_fp = TO_FP(150);
    g_p2.x_fp = TO_FP(230); g_p2.y_fp = TO_FP(150); g_p2.angle = 8;      // facing West
    REG_P2_KEYS = BTN_FWD;
    for (int f = 0; f < 30; f++) game_update_tanks();
    TEST_ASSERT(FROM_FP(g_p2.x_fp) >= FROM_FP(g_p1.x_fp) + TANK_SIZE, "P2 is blocked by P1 straight ahead");
    TEST_ASSERT(!physics_tanks_overlap(FROM_FP(g_p1.x_fp), FROM_FP(g_p1.y_fp),
                                       FROM_FP(g_p2.x_fp), FROM_FP(g_p2.y_fp)), "Tanks never overlap (P2 driving)");

    // Reversing into the other tank is blocked too
    REG_P2_KEYS = 0;
    g_p1.x_fp = TO_FP(300); g_p1.y_fp = TO_FP(150); g_p1.angle = 0;
    g_p2.x_fp = TO_FP(270); g_p2.y_fp = TO_FP(150);
    REG_P1_KEYS = BTN_BWD;                                               // backing West into P2
    for (int f = 0; f < 30; f++) game_update_tanks();
    TEST_ASSERT(FROM_FP(g_p1.x_fp) >= FROM_FP(g_p2.x_fp) + TANK_SIZE, "Reversing into the other tank is blocked");

    // Diagonal approach slides, but never overlaps
    REG_P1_KEYS = 0;
    g_p1.x_fp = TO_FP(150); g_p1.y_fp = TO_FP(150); g_p1.angle = 2;      // South-East
    g_p2.x_fp = TO_FP(172); g_p2.y_fp = TO_FP(172);
    REG_P1_KEYS = BTN_FWD;
    int ok = 1;
    for (int f = 0; f < 60; f++) {
        game_update_tanks();
        if (physics_tanks_overlap(FROM_FP(g_p1.x_fp), FROM_FP(g_p1.y_fp),
                                  FROM_FP(g_p2.x_fp), FROM_FP(g_p2.y_fp))) ok = 0;
    }
    TEST_ASSERT(ok, "No overlap at any frame during a diagonal approach");

    // Tanks that already overlap can always drive apart
    g_p1.x_fp = TO_FP(100); g_p1.y_fp = TO_FP(150); g_p1.angle = 8;      // facing West
    g_p2.x_fp = TO_FP(105); g_p2.y_fp = TO_FP(150);
    REG_P1_KEYS = BTN_FWD;
    game_update_tanks();
    TEST_ASSERT(FROM_FP(g_p1.x_fp) < 100, "Overlapping tanks are not stuck: P1 can move away");
    REG_P1_KEYS = 0;
    REG_P2_KEYS = 0;

    TEST_ASSERT(physics_tanks_overlap(0, 0, 19, 19) == 1, "physics_tanks_overlap: corner overlap");
    TEST_ASSERT(physics_tanks_overlap(0, 0, 20, 0)  == 0, "physics_tanks_overlap: touching edges do not overlap");
}

//=============================================================================
// Main Test Runner Entrypoint
//=============================================================================
int main(void) {
    printf("===================================================================\n");
    printf("     BATTLE TANKS: C GAME SOFTWARE UNIT TEST SUITE (HOST GCC)      \n");
    printf("===================================================================\n");

    RUN_SUITE(test_suite_trig_and_fixed_point, "1. Trigonometry & Fixed-Point Math");
    RUN_SUITE(test_suite_game_init,            "2. Game Initialization & Hardware Reset");
    RUN_SUITE(test_suite_tank_steering,        "3. Tank Steering, Rotation & 360-Wrap");
    RUN_SUITE(test_suite_tank_movement_and_bounds, "4. Tank Movement & Arena Bounds Clamping");
    RUN_SUITE(test_suite_bullet_spawning,      "5. Bullet Spawning & Cooldown Invalidation");
    RUN_SUITE(test_suite_reflection_physics,   "6. 2D Angular Reflection & Bounce Limits");
    RUN_SUITE(test_suite_maze_destruction,     "7. Dynamic Maze Destruction in Mirrored BRAM");
    RUN_SUITE(test_suite_collision_and_damage, "8. Collision Engine Handshake & Combat Damage");
    RUN_SUITE(test_suite_display_sync,         "9. MMIO Display & HUD Synchronization");
    RUN_SUITE(test_suite_bricks_reset_and_tank_blocking, "10. Bricks, Reset & Tank-vs-Tank Blocking");

    printf("\n===================================================================\n");
    printf("  TEST EXECUTION SUMMARY: %d RUN | %d PASSED | %d FAILED\n",
           g_tests_run, g_tests_passed, g_tests_failed);
    printf("===================================================================\n");

    if (g_tests_failed == 0) {
        printf(">> ALL C SOFTWARE TESTS PASSED SUCCESSFULLY! <<\n\n");
        return 0;
    } else {
        printf(">> WARNING: %d TESTS FAILED! <<\n\n", g_tests_failed);
        return 1;
    }
}
