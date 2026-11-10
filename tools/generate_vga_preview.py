import zlib
import struct
import os

def rgb12_to_rgb24(val12):
    r = (val12 >> 8) & 0xF
    g = (val12 >> 4) & 0xF
    b = val12 & 0xF
    return ((r << 4) | r, (g << 4) | g, (b << 4) | b)

def save_png(filename, width, height, rgb_pixels):
    # rgb_pixels: list of (r, g, b) tuples of length width * height
    raw_rows = bytearray()
    idx = 0
    for y in range(height):
        raw_rows.append(0) # Filter type 0 (None)
        for x in range(width):
            r, g, b = rgb_pixels[idx]
            raw_rows.append(r)
            raw_rows.append(g)
            raw_rows.append(b)
            idx += 1
            
    compressed = zlib.compress(bytes(raw_rows), 9)
    
    def make_chunk(chunk_type, data):
        length = len(data)
        crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
        return struct.pack(">I", length) + chunk_type + data + struct.pack(">I", crc)
        
    png_data = bytearray(b"\x89PNG\r\n\x1a\n")
    # IHDR: width (4), height (4), bit_depth (1=8), color_type (1=2: Truecolor), comp (1=0), filter (1=0), interlace (1=0)
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png_data.extend(make_chunk(b"IHDR", ihdr_data))
    png_data.extend(make_chunk(b"IDAT", compressed))
    png_data.extend(make_chunk(b"IEND", b""))
    
    with open(filename, "wb") as f:
        f.write(png_data)

# 8x8 font glyphs matching health_hud.v
FONT_GLYPHS = {
    '0': 0x3C666E7666663C00,
    '1': 0x1838181818187E00,
    '2': 0x3C66061C30607E00,
    '3': 0x3C66061C06663C00,
    '4': 0x0C1C2C4C7E0C0C00,
    '5': 0x7E607C0606663C00,
    '6': 0x3C607C6666663C00,
    '7': 0x7E060C1818181800,
    '8': 0x3C66663C66663C00,
    '9': 0x3C66663E06663C00,
    'A': 0x3C66667E66666600,
    'B': 0x7C66667C66667C00,
    'C': 0x3C66606060663C00,
    'D': 0x786C6666666C7800,
    'E': 0x7E60607C60607E00,
    'F': 0x7E60607C60606000,
    'G': 0x3C66606E66663C00,
    'H': 0x6666667E66666600,
    'I': 0x7E18181818187E00,
    'K': 0x666C7870786C6600,
    'L': 0x6060606060607E00,
    'M': 0x63777F6B63636300,
    'N': 0x66767E7E6E666600,
    'O': 0x3C66666666663C00,
    'P': 0x7C66667C60606000,
    'R': 0x7C66667C786C6600,
    'S': 0x3C66603C06663C00,
    'T': 0x7E18181818181800,
    'U': 0x6666666666663C00,
    'V': 0x66666666663C1800,
    'W': 0x6363636B7F776300,
    'Y': 0x6666663C18181800,
    '/': 0x060C183060400000,
    ':': 0x0018180018180000,
    '-': 0x0000007E00000000,
    ' ': 0x0000000000000000,
    '\x01': 0x183C7E1818181800, # Up Arrow
    '\x02': 0x181818187E3C1800, # Down Arrow
    '\x03': 0x10307EFF7E301000, # Left Arrow
    '\x04': 0x080C7EFF7E0C0800, # Right Arrow
}

def get_glyph_pixel(ch, px, py):
    if px < 0 or px >= 8 or py < 0 or py >= 8:
        return 0
    val = FONT_GLYPHS.get(ch, 0)
    bit_idx = (7 - py) * 8 + (7 - px)
    return (val >> bit_idx) & 1

HEART_ROM = [
    0x3C3C,
    0xFFFF,
    0xFFFF,
    0xFFFF,
    0x3FFC,
    0x0FF0,
    0x03C0,
    0x0000
]

def render_vga():
    width = 640
    height = 480
    frame = [0x000] * (width * height)

    # 1. Maze Layout (20 x 20 tiles)
    maze = [[0]*20 for _ in range(20)]
    for r in range(20):
        for c in range(20):
            if r == 0 or r == 19 or c == 0 or c == 19:
                maze[r][c] = 2 # Perimeter steel
            elif (r in (3,6,13,16)) and (c in (3,6,13,16)):
                maze[r][c] = 2 # Steel pillar
            elif (r in (9,10)) and (c in (9,10)):
                maze[r][c] = 1 # Brick center block

    # Render Arena & Maze
    for y in range(480):
        for x in range(480):
            tile_x = x // 24
            tile_y = y // 24
            sub_x = x % 24
            sub_y = y % 24
            t_type = maze[tile_y][tile_x]
            if t_type == 0: # Floor
                if sub_x == 0 or sub_y == 0:
                    col = 0x010
                else:
                    col = 0x031
            elif t_type == 1: # Brick
                if sub_y == 0 or sub_y == 12 or (sub_y < 12 and sub_x == 0) or (sub_y >= 12 and sub_x == 12):
                    col = 0x444 # Mortar
                else:
                    col = 0xB52 # Brick terracotta
            elif t_type == 2: # Steel
                if sub_x == 0 or sub_y == 0:
                    col = 0x556 # Lighter edge
                elif sub_x == 23 or sub_y == 23:
                    col = 0x112 # Shadow edge
                elif (sub_x in (11,12) and sub_y < 12) or (sub_x in (11,12) and sub_y >= 12) or (sub_y in (11,12)):
                    col = 0x222 # Dark stone seam
                else:
                    col = 0x445 # Stone body
            else:
                col = 0x668
            frame[y * width + x] = col

    # Render Tanks
    # Tank 1: Blue at (60, 60), facing angle 0 (East)
    p1_x, p1_y = 60, 60
    for dy in range(20):
        for dx in range(20):
            fx = p1_x + dx
            fy = p1_y + dy
            if 0 <= fx < 480 and 0 <= fy < 480:
                # Treads
                if dx < 3 or dx >= 17:
                    t_col = 0x024 if (dy % 4 < 2) else 0x047
                    frame[fy * width + fx] = t_col
                elif 3 <= dy < 17:
                    if 7 <= dx <= 12 and 7 <= dy <= 12:
                        frame[fy * width + fx] = 0x4CF # Dome
                    else:
                        frame[fy * width + fx] = 0x06C # Hull
                # Barrel pointing East (along +x)
                if 10 <= dx <= 19 and 9 <= dy <= 10:
                    frame[fy * width + fx] = 0x4CF

    # Tank 2: Red at (390, 390), facing angle 8 (West)
    p2_x, p2_y = 390, 390
    for dy in range(20):
        for dx in range(20):
            fx = p2_x + dx
            fy = p2_y + dy
            if 0 <= fx < 480 and 0 <= fy < 480:
                if dx < 3 or dx >= 17:
                    t_col = 0x500 if (dy % 4 < 2) else 0x800
                    frame[fy * width + fx] = t_col
                elif 3 <= dy < 17:
                    if 7 <= dx <= 12 and 7 <= dy <= 12:
                        frame[fy * width + fx] = 0xF44 # Dome
                    else:
                        frame[fy * width + fx] = 0xB11 # Hull
                # Barrel pointing West (along -x)
                if 0 <= dx <= 9 and 9 <= dy <= 10:
                    frame[fy * width + fx] = 0xF44

    # Bullets
    # Normal yellow bullet at (160, 120)
    bx, by = 160, 120
    for dy in range(6):
        for dx in range(6):
            if (dx - 2)**2 + (dy - 2)**2 <= 6:
                frame[(by + dy) * width + (bx + dx)] = 0xFF2

    # Big special bullet at (300, 240)
    bbx, bby = 300, 240
    for dy in range(10):
        for dx in range(10):
            if (dx - 4)**2 + (dy - 4)**2 <= 18:
                frame[(bby + dy) * width + (bbx + dx)] = 0xF30

    # Vertical divider bar at x = 479..480
    for y in range(480):
        frame[y * width + 479] = 0x557
        frame[y * width + 480] = 0x334

    # Right HUD Strip (481 <= x < 640)
    # HUD Background
    for y in range(480):
        for x in range(481, 640):
            frame[y * width + x] = 0x111 # Dark background

    def draw_text(txt, start_dx, start_y, fg_col, bg_col=None):
        for ci, ch in enumerate(txt):
            cx = start_dx + ci * 8
            for py in range(8):
                for px in range(8):
                    bit = get_glyph_pixel(ch, px, py)
                    gx = 480 + cx + px
                    gy = start_y + py
                    if 480 <= gx < 640 and 0 <= gy < 480:
                        if bit:
                            frame[gy * width + gx] = fg_col
                        elif bg_col is not None:
                            frame[gy * width + gx] = bg_col

    def draw_keycap14(box_dx, box_y, glyph_char, is_pressed=False, p_theme=1):
        for v in range(14):
            for u in range(14):
                gx = 480 + box_dx + u
                gy = box_y + v
                if not (480 <= gx < 640 and 0 <= gy < 480):
                    continue
                # Corner check
                if (u == 0 or u == 13) and (v == 0 or v == 13):
                    continue
                is_border = (u == 0 or u == 13 or v == 0 or v == 13)
                in_glyph = (3 <= u <= 10 and 3 <= v <= 10)
                gbit = 0
                if in_glyph:
                    gbit = get_glyph_pixel(glyph_char, u - 3, v - 3)
                
                if gbit:
                    col = 0xFFF # White glyph
                elif is_border:
                    if is_pressed:
                        col = 0x5DF if p_theme == 1 else 0xFB4
                    else:
                        col = 0x88A # Sleek keycap border
                else: # Face
                    if is_pressed:
                        col = 0x037 if p_theme == 1 else 0x520
                    else:
                        col = 0x223 # Recessed key body
                frame[gy * width + gx] = col

    def draw_keycap_multi(box_dx, box_y, box_w, text, is_pressed=False, p_theme=1):
        for v in range(14):
            for u in range(box_w):
                gx = 480 + box_dx + u
                gy = box_y + v
                if not (480 <= gx < 640 and 0 <= gy < 480):
                    continue
                if (u == 0 or u == box_w - 1) and (v == 0 or v == 13):
                    continue
                is_border = (u == 0 or u == box_w - 1 or v == 0 or v == 13)
                
                # Check text glyphs
                gbit = 0
                # Centered text: start_x offset
                text_len = len(text)
                total_text_w = text_len * 8
                start_u = (box_w - total_text_w) // 2
                if 3 <= v <= 10 and start_u <= u < start_u + total_text_w:
                    ch_idx = (u - start_u) // 8
                    ch = text[ch_idx]
                    gbit = get_glyph_pixel(ch, (u - start_u) % 8, v - 3)

                if gbit:
                    col = 0xFFF
                elif is_border:
                    if is_pressed:
                        col = 0x5DF if p_theme == 1 else 0xFB4
                    else:
                        col = 0x88A
                else:
                    if is_pressed:
                        col = 0x037 if p_theme == 1 else 0x520
                    else:
                        col = 0x223
                frame[gy * width + gx] = col

    # --- P1 HEALTH & BANNER ---
    for y in range(12, 20):
        for dx in range(4, 80):
            frame[y * width + 480 + dx] = 0x029
    draw_text("P1 HP", 12, 12, 0xFFF)
    draw_text("20", 88, 12, 0x5DF)

    # 20 Hearts for P1 (2 rows of 10)
    for heart_idx in range(20):
        slot_x = 4 + (heart_idx % 10) * 16
        slot_y = 24 if (heart_idx < 10) else 32
        for py in range(8):
            for px in range(16):
                bit = (HEART_ROM[py] >> (15 - px)) & 1
                gx = 480 + slot_x + px
                gy = slot_y + py
                if bit:
                    if px == 4 and py == 2:
                        frame[gy * width + gx] = 0xFFA # Specular highlight
                    else:
                        frame[gy * width + gx] = 0xF00 # Red heart

    # --- P1 SPECIAL COOLDOWN BAR (100% full = READY) ---
    draw_text("SPECIAL", 24, 46, 0x0DE)
    draw_text("READY", 88, 46, 0x0FF)
    # Cooldown Bar (dx: 28..129, y: 58..69)
    bar1_fill = 100 # Full 100 pixels
    for by in range(58, 70):
        for bdx in range(28, 130):
            gx = 480 + bdx
            is_b_border = (bdx == 28 or bdx == 129 or by == 58 or by == 69)
            if is_b_border:
                frame[by * width + gx] = 0x357
            else:
                rel_px = bdx - 29
                if rel_px < bar1_fill:
                    if by == 59:
                        frame[by * width + gx] = 0x5FF # Gloss highlight
                    else:
                        frame[by * width + gx] = 0x0DE # Electric Cyan fill
                else:
                    frame[by * width + gx] = 0x012

    # --- P1 KEY CONTROLS (Stuck to top) ---
    for y in range(76, 84):
        for dx in range(8, 152):
            frame[y * width + 480 + dx] = 0x014
    draw_text("P1 CONTROLS", 36, 76, 0x5DF)

    # WASD
    draw_keycap14(28, 88, 'W', is_pressed=True, p_theme=1) # Illuminated to show active keypress!
    draw_keycap14(12, 104, 'A', is_pressed=False, p_theme=1)
    draw_keycap14(28, 104, 'S', is_pressed=False, p_theme=1)
    draw_keycap14(44, 104, 'D', is_pressed=False, p_theme=1)
    draw_text("MOVE/AIM", 66, 99, 0x8EF)

    # SPACE (SHOOT)
    draw_keycap_multi(12, 121, 46, "SPACE", is_pressed=False, p_theme=1)
    draw_text("SHOOT", 66, 124, 0xFFE)

    # E (SPECIAL)
    draw_keycap14(28, 138, 'E', is_pressed=False, p_theme=1)
    draw_text("SPECIAL", 66, 141, 0x0FF)

    # --- CENTER BANNER: BATTLE TANKS & ESC RESET ---
    for y in range(216, 226):
        for dx in range(8, 152):
            if y == 216 or y == 225:
                frame[y * width + 480 + dx] = 0x88A # Metallic frame
            else:
                frame[y * width + 480 + dx] = 0x113 # Navy steel plate
    draw_text("BATTLE TANKS", 32, 217, 0xFE2) # Golden arcade lettering

    draw_keycap_multi(16, 232, 32, "ESC", is_pressed=False, p_theme=1)
    draw_text("RESET", 66, 235, 0xF88)

    # --- P2 KEY CONTROLS (Stuck to bottom) ---
    for y in range(302, 310):
        for dx in range(8, 152):
            frame[y * width + 480 + dx] = 0xD00 # Bright Red Banner!
    draw_text("P2 CONTROLS", 36, 302, 0xFFF)

    # Arrow keys
    draw_keycap14(28, 314, '\x01', is_pressed=False, p_theme=2) # Up Arrow
    draw_keycap14(12, 330, '\x03', is_pressed=False, p_theme=2) # Left Arrow
    draw_keycap14(28, 330, '\x02', is_pressed=False, p_theme=2) # Down Arrow
    draw_keycap14(44, 330, '\x04', is_pressed=False, p_theme=2) # Right Arrow
    draw_text("MOVE/AIM", 66, 325, 0xFCA)

    # ENTER (SHOOT)
    draw_keycap_multi(12, 347, 46, "ENTER", is_pressed=False, p_theme=2)
    draw_text("SHOOT", 66, 350, 0xFFE)

    # P (SPECIAL ATTACK)
    draw_keycap14(28, 364, 'P', is_pressed=False, p_theme=2)
    draw_text("SPECIAL", 66, 367, 0xF33)

    # --- P2 SPECIAL COOLDOWN BAR (Bright Red theme, matching labels) ---
    for y in range(384, 392):
        for dx in range(4, 80):
            frame[y * width + 480 + dx] = 0xD00 # Bright Red Banner
    draw_text("SPECIAL", 12, 384, 0xFFF)
    draw_text("06s", 88, 384, 0xFFF)
    bar2_fill = 65 # 65 pixels filled
    for by in range(394, 408):
        for bdx in range(28, 132):
            gx = 480 + bdx
            is_b_border = (bdx <= 29 or bdx >= 130 or by <= 395 or by >= 406)
            if is_b_border:
                frame[by * width + gx] = 0xF22 # Bright Red Border
            else:
                rel_px = bdx - 30
                if rel_px < bar2_fill:
                    if by == 396:
                        frame[by * width + gx] = 0xF66 # Red highlight
                    else:
                        frame[by * width + gx] = 0xD00 # Bright solid Red fill!
                else:
                    frame[by * width + gx] = 0x300 # Deep dark red empty slot

    # --- P2 HEALTH & BANNER ---
    for y in range(420, 428):
        for dx in range(4, 80):
            frame[y * width + 480 + dx] = 0xD00 # Bright Red Banner
    draw_text("P2 HP", 12, 420, 0xFFF)
    draw_text("15", 88, 420, 0xFFA)

    # 15 Hearts for P2 (10 in row A, 5 in row B, 5 depleted)
    for heart_idx in range(20):
        slot_x = 4 + (heart_idx % 10) * 16
        slot_y = 432 if (heart_idx < 10) else 440
        is_full = (heart_idx < 15)
        for py in range(8):
            for px in range(16):
                bit = (HEART_ROM[py] >> (15 - px)) & 1
                gx = 480 + slot_x + px
                gy = slot_y + py
                if bit:
                    if is_full:
                        if px == 4 and py == 2:
                            frame[gy * width + gx] = 0xFFA
                        else:
                            frame[gy * width + gx] = 0xF00
                    else:
                        frame[gy * width + gx] = 0x300 # Depleted dark outline

    # Convert 12-bit to 24-bit RGB tuples
    rgb24 = [rgb12_to_rgb24(c) for c in frame]
    return width, height, rgb24

if __name__ == "__main__":
    w, h, pixels = render_vga()
    
    # Save standard 640x480
    out_dir = r"C:\Users\kaust\.gemini\antigravity\brain\e8d13bc5-03f3-441c-850e-78a7597c6db4"
    os.makedirs(out_dir, exist_ok=True)
    path_1x = os.path.join(out_dir, "vga_screen_640x480.png")
    save_png(path_1x, w, h, pixels)
    print("Saved 1x VGA:", path_1x)

    # Save 2x Upscaled (1280x960) with nearest-neighbor integer scaling for razor-sharp preview
    scale = 2
    w2 = w * scale
    h2 = h * scale
    pixels_2x = []
    for y in range(h):
        row = []
        for x in range(w):
            p = pixels[y * w + x]
            for _ in range(scale):
                row.append(p)
        for _ in range(scale):
            pixels_2x.extend(row)
            
    path_2x = os.path.join(out_dir, "vga_screen_preview.png")
    save_png(path_2x, w2, h2, pixels_2x)
    print("Saved 2x VGA Preview:", path_2x)
