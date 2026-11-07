#ifndef PHYSICS_H
#define PHYSICS_H

#include <stdint.h>
#include "game.h"

// 64-angle lookup table (5.625 deg per step): sin(theta)*256, extended by a quarter
// turn so that cos(theta)*256 is the same array read 16 entries further on.
// Valid indices for both: 0 .. NUM_ANGLES-1.
extern const int16_t g_sin_fp[NUM_ANGLES + NUM_ANGLES / 4];
#define g_cos_fp   (&g_sin_fp[NUM_ANGLES / 4])

// Check maze tile collision and destroy brick if destructible (using RV32M DIV)
int physics_check_and_destroy_tile(int px, int py, int is_big);

// Restore the maze to its power-up layout (steel border/pillars + bricks)
void physics_reset_maze(void);

// 1 if two TANK_SIZE x TANK_SIZE tanks with top-left corners (x1,y1) / (x2,y2) overlap
int physics_tanks_overlap(int x1, int y1, int x2, int y2);

// Tank vs maze: 1 if a tank at top-left (x, y) would overlap a wall tile
int physics_tank_hits_wall(int x, int y);

// Spawn projectile with angle-derived velocity vector (using RV32M MUL)
void physics_spawn_bullet(int owner, int is_big);

// Angular wall reflection calculation
int physics_reflect_bullet(Bullet *b, int prev_x, int prev_y, int new_x, int new_y);

#endif // PHYSICS_H
