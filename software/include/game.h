#ifndef GAME_H
#define GAME_H

#include <stdint.h>
#include "mmio.h"

//=============================================================================
// Arena & Game Constants
//=============================================================================
#define ARENA_MIN_X         24
#define ARENA_MAX_X         456
#define ARENA_MIN_Y         24
#define ARENA_MAX_Y         456

#define TANK_SIZE           20
#define BULLET_NORM_SPEED   6
#define BULLET_BIG_SPEED    4
#define MAX_BOUNCES         5
#define MAX_BULLETS         8

// Busy-wait iterations per game frame. Tuned so one full game-loop pass takes
// ~1/60 s at the 50 MHz system clock (it was 4000, i.e. ~2400 frames/s, which made
// tanks cross the whole arena in a fraction of a second).
#ifndef FRAME_DELAY_ITERATIONS
#define FRAME_DELAY_ITERATIONS  166500
#endif

#define P1_BULLET_START     0
#define P1_BULLET_END       3
#define P2_BULLET_START     4
#define P2_BULLET_END       7

// Fixed-point 16.8 scaling
#define FP_SHIFT            8
#define TO_FP(val)          ((int32_t)(val) << FP_SHIFT)
#define FROM_FP(val)        ((int32_t)(val) >> FP_SHIFT)

//=============================================================================
// Game Entities
//=============================================================================
typedef struct {
    int32_t  x_fp;
    int32_t  y_fp;
    uint8_t  angle;     // 0..15 (step 22.5 deg)
    uint8_t  hp;        // 0..20 hearts
    uint16_t score;
} Tank;

typedef struct {
    int32_t  x_fp;
    int32_t  y_fp;
    int32_t  vx_fp;
    int32_t  vy_fp;
    uint8_t  active;
    uint8_t  is_big;
    uint8_t  bounces;
    uint8_t  owner;     // 1 or 2
} Bullet;

extern Tank g_p1, g_p2;
extern Bullet g_bullets[MAX_BULLETS];

//=============================================================================
// Core Function Prototypes
//=============================================================================
void game_init(void);
void game_update_tanks(void);
void game_update_bullets(void);
void game_process_collisions(void);
void game_sync_display(void);
void game_delay(uint32_t count);

#endif // GAME_H
