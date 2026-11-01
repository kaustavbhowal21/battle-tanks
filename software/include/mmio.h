#ifndef MMIO_H
#define MMIO_H

#include <stdint.h>

//=============================================================================
// Memory-Mapped I/O Base Addresses & Register Map (Fig 2a & Fig 2b)
// Memory space: addr[31] = 0 -> DMEM (4 KB)
//               addr[31] = 1 -> Hardware MMIO Peripherals
//=============================================================================

#ifndef HOST_TEST
#define MMIO_BASE               0x80000000U
// Direct volatile pointer access
#define MMIO_REG(addr)          (*(volatile uint32_t *)(MMIO_BASE + (addr)))
#define MAZE_RAM_BASE           (MMIO_BASE + 0x0100U)
#else
extern uint32_t g_mock_mmio_space[1024];
#define MMIO_BASE               ((uintptr_t)g_mock_mmio_space)
#define MMIO_REG(addr)          (*(volatile uint32_t *)((uintptr_t)g_mock_mmio_space + (addr)))
#define MAZE_RAM_BASE           ((uintptr_t)g_mock_mmio_space + 0x0100U)
#endif

// 1. Input Controller (Fig 3)
// Buttons: [0]=FWD, [1]=BWD, [2]=LEFT, [3]=RIGHT, [4]=SHOOT, [5]=SPECIAL
#define REG_P1_KEYS             MMIO_REG(0x0000)
#define REG_P2_KEYS             MMIO_REG(0x0004)

#define BTN_FWD                 (1U << 0)
#define BTN_BWD                 (1U << 1)
#define BTN_LEFT                (1U << 2)
#define BTN_RIGHT               (1U << 3)
#define BTN_SHOOT               (1U << 4)
#define BTN_SPECIAL             (1U << 5)

// 2. Hardware Cooldown Timers (Fig 4)
// Status: 1 = Weapon Ready, 0 = Cooling Down
#define REG_TIMER_STATUS        MMIO_REG(0x0010)
#define REG_TIMER_TRIGGER       MMIO_REG(0x0014)

// Bit order matches hardware (cooldown_timers.v): {P2 spec, P2 shoot, P1 spec, P1 shoot}
#define TMR_P1_SHOOT            (1U << 0) // 0.5s primary fire
#define TMR_P1_SPECIAL          (1U << 1) // 20.0s special attack
#define TMR_P2_SHOOT            (1U << 2) // 0.5s primary fire
#define TMR_P2_SPECIAL          (1U << 3) // 20.0s special attack

// 3. Hardware Collision Engine (Write-1-to-Clear sticky registers) (Fig 6a..6d)
#define REG_COLLISION_FLAG      MMIO_REG(0x0020) // [0] wall, [1] bullet-bullet, [2] tank hit (any)
#define REG_COLLISION_WALL      MMIO_REG(0x0024) // [7:0] bullet i hit a wall          (W1C)
#define REG_COLLISION_BULLET    MMIO_REG(0x0028) // [7:0] bullet i hit another bullet  (W1C)
#define REG_COLLISION_TANK      MMIO_REG(0x002C) // [7:0]=bullet i hit a tank, [8]=P1 tank hit, [9]=P2 tank hit (W1C)
#define COLL_TANK_P1_HIT        (1U << 8)
#define COLL_TANK_P2_HIT        (1U << 9)

// 4. Sprite & HUD Register File (Fig 5) -- matches sprite_hud_regfile.v
// Tank position: {6'b0, y[9:0], 6'b0, x[9:0]}
#define REG_SPRITE_P1_TANK      MMIO_REG(0x0040)
#define REG_SPRITE_P2_TANK      MMIO_REG(0x0044)

// 8 bullet registers, one word each: {10'b0, big, active, y[9:0], x[9:0]}
#define REG_SPRITE_BULLET(i)    MMIO_REG(0x0048 + ((i) * 4))

#define REG_HUD_HEALTH          MMIO_REG(0x0080) // {16'b0, hp2[7:0], hp1[7:0]} (0..20 hearts)
#define REG_TANK_ANGLES         MMIO_REG(0x0084) // {24'b0, ang2[3:0], ang1[3:0]}

#define HUD_HEALTH_PACK(hp1, hp2)   ((((uint32_t)(hp2) & 0xFFU) << 8) | ((uint32_t)(hp1) & 0xFFU))
#define HUD_HEALTH_P1(reg)          ((reg) & 0xFFU)
#define HUD_HEALTH_P2(reg)          (((reg) >> 8) & 0xFFU)
#define TANK_ANGLES_PACK(a1, a2)    ((((uint32_t)(a2) & 0xFU) << 4) | ((uint32_t)(a1) & 0xFU))
#define SPRITE_POS_PACK(x, y)       ((((uint32_t)(y) & 0x3FFU) << 16) | ((uint32_t)(x) & 0x3FFU))
#define SPRITE_BULLET_PACK(x, y, act, big) \
    ((((uint32_t)(big) & 1U) << 21) | (((uint32_t)(act) & 1U) << 20) | \
     (((uint32_t)(y) & 0x3FFU) << 10) | ((uint32_t)(x) & 0x3FFU))

// 5. Mirrored Maze Tile RAM (Fig 7)
// 20x20 tiles = 400 words (0x0100 .. 0x073C, word addressed)
#define MAZE_TILE(row, col)     (*(volatile uint32_t *)(MAZE_RAM_BASE + (((row) * 20 + (col)) << 2)))

#define TILE_EMPTY              0x0U
#define TILE_BRICK_DESTRUCTIBLE 0x1U
#define TILE_STEEL_SOLID        0x2U
#define TILE_CORNER_SOLID       0x3U

//=============================================================================
// Helper Inline Functions
//=============================================================================

static inline uint32_t get_p1_input(void) {
    return REG_P1_KEYS;
}

static inline uint32_t get_p2_input(void) {
    return REG_P2_KEYS;
}

static inline int is_p1_shoot_ready(void) {
    return (REG_TIMER_STATUS & TMR_P1_SHOOT) != 0;
}

static inline int is_p2_shoot_ready(void) {
    return (REG_TIMER_STATUS & TMR_P2_SHOOT) != 0;
}

static inline int is_p1_spec_ready(void) {
    return (REG_TIMER_STATUS & TMR_P1_SPECIAL) != 0;
}

static inline int is_p2_spec_ready(void) {
    return (REG_TIMER_STATUS & TMR_P2_SPECIAL) != 0;
}

static inline void trigger_p1_shoot_cooldown(void) {
    REG_TIMER_TRIGGER = TMR_P1_SHOOT;
}

static inline void trigger_p2_shoot_cooldown(void) {
    REG_TIMER_TRIGGER = TMR_P2_SHOOT;
}

static inline void trigger_p1_spec_cooldown(void) {
    REG_TIMER_TRIGGER = TMR_P1_SPECIAL;
}

static inline void trigger_p2_spec_cooldown(void) {
    REG_TIMER_TRIGGER = TMR_P2_SPECIAL;
}

#ifndef HOST_TEST
static inline void clear_collision_wall(uint32_t mask) {
    REG_COLLISION_WALL = mask;
}

static inline void clear_collision_tank(uint32_t mask) {
    REG_COLLISION_TANK = mask;
}

static inline void clear_collision_bullet(uint32_t mask) {
    REG_COLLISION_BULLET = mask;
}
#else
static inline void clear_collision_wall(uint32_t mask) {
    REG_COLLISION_WALL &= ~mask;
}

static inline void clear_collision_tank(uint32_t mask) {
    REG_COLLISION_TANK &= ~mask;
}

static inline void clear_collision_bullet(uint32_t mask) {
    REG_COLLISION_BULLET &= ~mask;
}
#endif

static inline void update_tank_sprite(int player, uint32_t x, uint32_t y) {
    uint32_t val = SPRITE_POS_PACK(x, y);
    if (player == 1)
        REG_SPRITE_P1_TANK = val;
    else
        REG_SPRITE_P2_TANK = val;
}

#endif // MMIO_H
