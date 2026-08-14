/* Putting the HUD on a framebuffer.
 *
 * Everything is drawn from primitives and there is no font anywhere. That is a
 * choice, not a shortcut: a font is the one asset that would have to be
 * generated, embedded and kept in step with a character set, and the things a
 * rider actually reads at speed are a shape, an arrow and a number. Numbers are
 * seven segments; arrows are polygons.
 *
 * Pixels are RGB565 in host order. Whatever a particular panel wants on the
 * wire is the display layer's problem, not this one's.
 *
 * No ESP-IDF headers: this renders into memory, so it renders on a desktop too,
 * which is where it is tested.
 */
#ifndef VISOR_DRAW_H
#define VISOR_DRAW_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint16_t *pixels;
    int width;
    int height;
} visor_canvas_t;

typedef struct {
    float x;
    float y;
} visor_pt_t;

static inline uint16_t visor_rgb(uint8_t r, uint8_t g, uint8_t b)
{
    return (uint16_t)(((uint16_t)(r & 0xF8) << 8) | ((uint16_t)(g & 0xFC) << 3) | (uint16_t)(b >> 3));
}

void visor_draw_fill(const visor_canvas_t *canvas, uint16_t colour);

/* Thick lines with soft edges.
 *
 * Coverage is worked out from the distance to the segment rather than by
 * stepping along it, which costs a little arithmetic and buys round caps and
 * joins for nothing. On a HUD the alternative shows: a stepped diagonal reads
 * as a rough road.
 */
void visor_draw_line(const visor_canvas_t *canvas,
                     visor_pt_t from,
                     visor_pt_t to,
                     float width,
                     uint16_t colour);

void visor_draw_polyline(const visor_canvas_t *canvas,
                         const visor_pt_t *points,
                         int count,
                         float width,
                         uint16_t colour);

void visor_draw_disc(const visor_canvas_t *canvas, visor_pt_t centre, float radius, uint16_t colour);

void visor_draw_triangle(const visor_canvas_t *canvas,
                         visor_pt_t a,
                         visor_pt_t b,
                         visor_pt_t c,
                         uint16_t colour);

/* A whole number in seven-segment digits, drawn left to right from `at`.
 *
 * Returns how wide it came out, so a caller can right-align it or put a unit
 * after it without guessing.
 */
float visor_draw_number(const visor_canvas_t *canvas,
                        uint32_t value,
                        visor_pt_t at,
                        float height,
                        uint16_t colour);

/* How wide `value` will be at `height`, without drawing it. */
float visor_draw_number_width(uint32_t value, float height);

/* A lowercase m, for the unit under a distance.
 *
 * The one letter this display can spell, and the only one it needs: a bare
 * number on a HUD is ambiguous in a way that matters, and drawing three strokes
 * is cheaper than carrying a font for them.
 */
void visor_draw_metres(const visor_canvas_t *canvas, visor_pt_t at, float height, uint16_t colour);
float visor_draw_metres_width(float height);

/* An arc of a circle, stroked.
 *
 * Angles in degrees, measured from three o'clock and running clockwise down the
 * screen, so 90 is the bottom of the circle.
 */
void visor_draw_arc(const visor_canvas_t *canvas,
                    visor_pt_t centre,
                    float radius,
                    float from_degrees,
                    float to_degrees,
                    float width,
                    uint16_t colour);

/* A ring: the outline of a circle rather than the whole of it. */
void visor_draw_ring(const visor_canvas_t *canvas,
                     visor_pt_t centre,
                     float radius,
                     float width,
                     uint16_t colour);

/* The maneuver as an arrow, centred on `at` and fitting a box of `size`.
 *
 * `hole` is what shows through the middle of the arrival marker; everywhere
 * else it goes unused.
 */
void visor_draw_maneuver(const visor_canvas_t *canvas,
                         uint8_t maneuver,
                         visor_pt_t at,
                         float size,
                         uint16_t colour,
                         uint16_t hole);

#endif /* VISOR_DRAW_H */
