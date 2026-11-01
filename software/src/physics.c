#include "physics.h"
#include "mmio.h"

//=============================================================================
// 16-Angle Fixed-Point Trigonometry Tables (8-bit fractional scale = 256)
// Angles: 0 = 0 deg (East), 4 = 90 deg (South), 8 = 180 deg (West), 12 = 270 deg (North)
//=============================================================================
const int16_t g_cos_fp[16] = {
     256,  237,  181,   98,    0,  -98, -181, -237,
    -256, -237, -181,  -98,    0,   98,  181,  237
};

const int16_t g_sin_fp[16] = {
       0,   98,  181,  237,  256,  237,  181,   98,
       0,  -98, -181, -237, -256, -237, -181,  -98
};

//=============================================================================
// Maze Tile Query & Destructible Brick Shattering
// Uses RV32M Hardware DIV instructions
//=============================================================================
int physics_check_and_destroy_tile(int px, int py, int is_big) {
    if (px < 0 || px >= 480 || py < 0 || py >= 480)
        return 1; // Outside boundary is solid

    // Hardware DIV instruction emitted here:
    int col = px / 24;
    int row = py / 24;

    if (col < 0 || col >= 20 || row < 0 || row >= 20)
        return 1;

    uint32_t tile = MAZE_TILE(row, col);

    if (tile == TILE_EMPTY) {
        return 0; // Empty floor
    } else if (tile == TILE_BRICK_DESTRUCTIBLE) {
        // Shatter destructible brick in hardware mirrored BRAM!
        MAZE_TILE(row, col) = TILE_EMPTY;
        return 1;
    } else {
        // Solid indestructible steel wall
        return 1;
    }
}

//=============================================================================
// Tank vs Maze Collision
// Returns 1 if a TANK_SIZE x TANK_SIZE tank whose top-left corner is (x, y)
// would overlap any non-floor maze tile. TANK_SIZE (20) < tile size (24), so
// checking the four corners is sufficient.
//=============================================================================
static int tile_is_solid(int px, int py) {
    if (px < 0 || px >= 480 || py < 0 || py >= 480)
        return 1;
    return MAZE_TILE(py / 24, px / 24) != TILE_EMPTY;
}

int physics_tank_hits_wall(int x, int y) {
    const int s = TANK_SIZE - 1;
    return tile_is_solid(x,     y)     ||
           tile_is_solid(x + s, y)     ||
           tile_is_solid(x,     y + s) ||
           tile_is_solid(x + s, y + s);
}

//=============================================================================
// Tank vs Tank Collision (axis-aligned boxes, touching edges do not overlap)
//=============================================================================
int physics_tanks_overlap(int x1, int y1, int x2, int y2) {
    return (x1 < x2 + TANK_SIZE) && (x2 < x1 + TANK_SIZE) &&
           (y1 < y2 + TANK_SIZE) && (y2 < y1 + TANK_SIZE);
}

//=============================================================================
// Maze Reset
// Rewrites every tile with the power-up layout, i.e. the same pattern that
// modules/game_engine/maze_tile_ram.v is initialised with. The tile RAM keeps its
// contents across a reset, so without this broken bricks never came back.
//=============================================================================
void physics_reset_maze(void) {
    for (int r = 0; r < 20; r++) {
        for (int c = 0; c < 20; c++) {
            uint32_t tile = TILE_EMPTY;
            if (r == 0 || r == 19 || c == 0 || c == 19)
                tile = TILE_STEEL_SOLID;                 // outer border
            else if ((r % 4 == 0) && (c % 4 == 0))
                tile = TILE_STEEL_SOLID;                 // interior pillars
            else if (r == 10 && c >= 8 && c <= 11)
                tile = TILE_BRICK_DESTRUCTIBLE;          // breakable bricks
            MAZE_TILE(r, c) = tile;
        }
    }
}

//=============================================================================
// Spawn Projectile from Tank Turret Tip
// Uses RV32M Hardware MUL instructions
//=============================================================================
void physics_spawn_bullet(int owner, int is_big) {
    int start_idx = (owner == 1) ? P1_BULLET_START : P2_BULLET_START;
    int end_idx   = (owner == 1) ? P1_BULLET_END   : P2_BULLET_END;
    Tank *t       = (owner == 1) ? &g_p1 : &g_p2;

    for (int i = start_idx; i <= end_idx; i++) {
        if (!g_bullets[i].active) {
            g_bullets[i].active  = 1;
            g_bullets[i].is_big  = is_big ? 1 : 0;
            g_bullets[i].bounces = 0;
            g_bullets[i].owner   = owner;

            int32_t speed   = is_big ? BULLET_BIG_SPEED : BULLET_NORM_SPEED;
            int32_t cos_val = g_cos_fp[t->angle];
            int32_t sin_val = g_sin_fp[t->angle];

            // Barrel tip spawn position (center 10,10 + barrel length 14)
            g_bullets[i].x_fp = t->x_fp + TO_FP(10) + ((cos_val * 14) << (FP_SHIFT - 8));
            g_bullets[i].y_fp = t->y_fp + TO_FP(10) + ((sin_val * 14) << (FP_SHIFT - 8));

            // Velocity vector
            g_bullets[i].vx_fp = (cos_val * speed) << (FP_SHIFT - 8);
            g_bullets[i].vy_fp = (sin_val * speed) << (FP_SHIFT - 8);

            break;
        }
    }
}

//=============================================================================
// 2D Angular Reflection Physics
// Inverts velocity along normal axis: vx' = -vx (vertical) or vy' = -vy (horizontal)
//=============================================================================
int physics_reflect_bullet(Bullet *b, int prev_x, int prev_y, int new_x, int new_y) {
    int reflected = 0;

    // Check perimeter boundary reflection
    if (new_x <= ARENA_MIN_X || new_x >= ARENA_MAX_X) {
        b->vx_fp = -b->vx_fp;
        reflected = 1;
    }
    if (new_y <= ARENA_MIN_Y || new_y >= ARENA_MAX_Y) {
        b->vy_fp = -b->vy_fp;
        reflected = 1;
    }

    // Check maze tile reflection
    if (!reflected) {
        int prev_col = prev_x / 24;
        int new_col  = new_x / 24;
        int prev_row = prev_y / 24;
        int new_row  = new_y / 24;

        if (prev_col != new_col) {
            b->vx_fp = -b->vx_fp; // Vertical face reflection
            reflected = 1;
        }
        if (prev_row != new_row) {
            b->vy_fp = -b->vy_fp; // Horizontal face reflection
            reflected = 1;
        }
    }

    if (reflected) {
        b->bounces++;
        if (b->bounces > MAX_BOUNCES) {
            b->active = 0; // Despawn after maximum bounces
            return 0;
        }
    }

    return reflected;
}
