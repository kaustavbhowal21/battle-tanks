#ifndef PHYSICS_H
#define PHYSICS_H

#include <stdint.h>
#include "game.h"

// 16-angle lookup tables: cos(theta)*256 and sin(theta)*256
extern const int16_t g_cos_fp[16];
extern const int16_t g_sin_fp[16];

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
