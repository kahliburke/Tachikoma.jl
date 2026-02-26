# Graphics & Pixel Rendering

Tachikoma offers three levels of graphical fidelity, from universal braille characters to pixel-perfect pixel rendering via the Kitty or sixel protocol.

## Canvas (Braille)

`Canvas` uses Unicode braille characters to draw at 2×4 resolution per terminal cell (each cell has 8 individually addressable dots):

<!-- tachi:widget canvas_braille w=40 h=20 -->
```julia
canvas = Canvas(40, 20; style=tstyle(:primary))

# Draw a circle and some lines
circle!(canvas, 39, 39, 30)
line!(canvas, 0, 0, 79, 79)
line!(canvas, 79, 0, 0, 79)
rect!(canvas, 10, 10, 68, 68)

render(canvas, area, buf)
```

<!-- tachi:noeval -->
```julia
# Drawing coordinates: 0..width*2-1 × 0..height*4-1
set_point!(canvas, dx, dy)        # set a dot
unset_point!(canvas, dx, dy)      # clear a dot
clear!(canvas)                     # clear all dots
line!(canvas, x0, y0, x1, y1)     # Bresenham line
rect!(canvas, x0, y0, x1, y1)     # rectangle outline
circle!(canvas, cx, cy, r)        # circle outline
arc!(canvas, cx, cy, r, start_deg, end_deg; steps=0)  # arc
```

The braille canvas works in every terminal and is the default rendering backend.

## BlockCanvas (Quadrant Blocks)

`BlockCanvas` uses Unicode quadrant block characters at 2×2 resolution per cell. Each cell has 4 independently addressable quadrants, producing gap-free solid shapes:

<!-- tachi:widget canvas_block w=40 h=20 -->
```julia
canvas = BlockCanvas(40, 20; style=tstyle(:primary))

circle!(canvas, 39, 19, 15)
line!(canvas, 0, 0, 79, 39)
rect!(canvas, 5, 5, 74, 34)

render(canvas, area, buf)
```

Same drawing API as `Canvas` but at 2×2 resolution per cell.

BlockCanvas produces visually denser output than braille — better for filled shapes and thick lines.

## PixelImage (Pixel Raster)

`PixelImage` is a widget that renders pixel-perfect raster graphics using the Kitty or sixel graphics protocol (auto-detected), with braille fallback. Each terminal cell maps to approximately 8×16 pixels (varies by terminal):

<!-- tachi:noeval -->
```julia
img = PixelImage(40, 20)    # 40 cells × 20 cells

# Pixel API (1-based coordinates, up to pixel_w × pixel_h)
set_pixel!(img, px, py)                      # use current color
set_pixel!(img, px, py, ColorRGB(255, 0, 0)) # explicit color
fill_rect!(img, x0, y0, x1, y1, color)       # filled rectangle
load_pixels!(img, pixel_matrix)               # bulk load from Matrix{ColorRGB}

# With a border
img = PixelImage(40, 20; block=Block(title="Image"))

# Render to frame (raster output needs Frame, not just Buffer)
render(img, area, frame)
```

### Pixel Line Drawing

<!-- tachi:noeval -->
```julia
pixel_line!(img, x0, y0, x1, y1)    # line using current color
```

### Decay Effects

<!-- tachi:noeval -->
```julia
img = PixelImage(40, 20; decay=DecayParams(decay=0.3, jitter=0.1))
```

## PixelCanvas (Pixel Drawing Surface)

`PixelCanvas` renders at full pixel resolution via the Kitty or sixel graphics protocol (auto-detected), with braille fallback. It combines pixel resolution with the Canvas drawing API, providing shape primitives at full pixel resolution:

<!-- tachi:noeval -->
```julia
canvas = PixelCanvas(40, 20; style=tstyle(:primary))

# Drawing at pixel resolution
set_pixel!(canvas, px, py)
set_pixel!(canvas, px, py, color)
pixel_line!(canvas, x0, y0, x1, y1)
fill_pixel_rect!(canvas, x0, y0, x1, y1, color)

# Set drawing color
canvas.color = ColorRGB(0, 200, 255)

# Render
render(canvas, area, buf)
```

### Resolution Properties

<!-- tachi:noeval -->
```julia
canvas.pixel_w    # total pixel width
canvas.pixel_h    # total pixel height
canvas.dot_w      # braille-compatible width (width * 2)
canvas.dot_h      # braille-compatible height (height * 4)
```

## Render Backend Switching

Switch between rendering backends globally:

```julia
set_render_backend!(braille_backend)    # universal, 2×4 per cell
set_render_backend!(block_backend)      # gap-free, 2×2 per cell
set_render_backend!(sixel_backend)      # pixel-perfect, ~16×32 per cell
```

Or cycle at runtime with **Ctrl+S** → Render Backend.

The `create_canvas` helper creates the appropriate canvas type for the current backend:

<!-- tachi:noeval -->
```julia
canvas = create_canvas(width, height; style=tstyle(:primary))
# Returns Canvas, BlockCanvas, or PixelCanvas based on render_backend()
```

## Terminal Pixel Detection

Tachikoma auto-detects the pixel dimensions of terminal cells for accurate pixel sizing:

<!-- tachi:noeval -->
```julia
# Read detected values
CELL_PX[]         # (w=8, h=16) — pixels per cell
TEXT_AREA_PX[]    # total text area in pixels
TEXT_AREA_CELLS[] # total text area in cells
SIXEL_AREA_PX[]  # sixel graphics area (from XTSMGRAPHICS)
SIXEL_SCALE[]    # (w=1.0, h=1.0) — manual scale adjustment
```

### Query Helpers

<!-- tachi:noeval -->
```julia
cell_pixels(n; axis=:w)      # cells to pixels
sixel_area_pixels()           # (w=, h=) of sixel area
pixel_size(canvas, rect)      # compute pixel dimensions for a canvas in a rect
```

### Manual Override

If auto-detection gets the wrong size, override in `LocalPreferences.toml`:

```toml
[Tachikoma]
cell_pixel_w = 10
cell_pixel_h = 20
sixel_scale_w = 1.0
sixel_scale_h = 1.0
```

## Choosing a Backend

| Need | Backend | Why |
|:-----|:--------|:----|
| Maximum compatibility | `braille_backend` | Works in every terminal |
| Solid filled shapes | `block_backend` | Gap-free quadrant blocks |
| High-resolution graphics | `sixel_backend` | True pixel rendering (Kitty or sixel) |
| Data visualization (charts) | `braille_backend` | Clean lines, universal |
| Image display | `sixel_backend` | Pixel-perfect raster (Kitty or sixel) |
