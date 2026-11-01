#include "game.h"

int main(void) {
    game_init();

    while (1) {
        // 1. Read input controllers, steer tanks, rotate, fire weapons
        game_update_tanks();

        // 2. Propagate projectiles with 2D angular wall reflection
        game_update_bullets();

        // 3. Process collision engine status registers and damage tanks
        game_process_collisions();

        // 4. Update memory-mapped hardware sprite and HUD registers
        game_sync_display();

        // 5. Pace game frame loop (~60 FPS at 50 MHz core clock)
        game_delay(FRAME_DELAY_ITERATIONS);
    }

    return 0;
}
