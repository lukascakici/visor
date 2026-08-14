#include "visor_draw.h"

#include <math.h>
#include <stddef.h>

#include "visor_packet.h"

/* --- pixels --------------------------------------------------------------- */

static void blend(const visor_canvas_t *canvas, int x, int y, uint16_t colour, float coverage)
{
    if (x < 0 || y < 0 || x >= canvas->width || y >= canvas->height || coverage <= 0.0f) {
        return;
    }

    uint16_t *pixel = &canvas->pixels[(size_t)y * (size_t)canvas->width + (size_t)x];
    if (coverage >= 1.0f) {
        *pixel = colour;
        return;
    }

    int dst_r = (*pixel >> 11) & 0x1F;
    int dst_g = (*pixel >> 5) & 0x3F;
    int dst_b = *pixel & 0x1F;
    int src_r = (colour >> 11) & 0x1F;
    int src_g = (colour >> 5) & 0x3F;
    int src_b = colour & 0x1F;

    int r = dst_r + (int)lrintf((float)(src_r - dst_r) * coverage);
    int g = dst_g + (int)lrintf((float)(src_g - dst_g) * coverage);
    int b = dst_b + (int)lrintf((float)(src_b - dst_b) * coverage);

    *pixel = (uint16_t)((r << 11) | (g << 5) | b);
}

void visor_draw_fill(const visor_canvas_t *canvas, uint16_t colour)
{
    size_t count = (size_t)canvas->width * (size_t)canvas->height;
    for (size_t index = 0; index < count; index++) {
        canvas->pixels[index] = colour;
    }
}

/* --- shapes --------------------------------------------------------------- */

static float clampf(float value, float low, float high)
{
    if (value < low) {
        return low;
    }
    return value > high ? high : value;
}

/* Distance from a point to a segment, which is what gives round caps: past
 * either end the nearest thing on the line is the end itself. */
static float distance_to_segment(float px, float py, visor_pt_t from, visor_pt_t to)
{
    float run_x = to.x - from.x;
    float run_y = to.y - from.y;
    float length = run_x * run_x + run_y * run_y;

    float fraction = 0.0f;
    if (length > 0.0f) {
        fraction = clampf(((px - from.x) * run_x + (py - from.y) * run_y) / length, 0.0f, 1.0f);
    }

    float dx = px - (from.x + fraction * run_x);
    float dy = py - (from.y + fraction * run_y);
    return sqrtf(dx * dx + dy * dy);
}

void visor_draw_line(const visor_canvas_t *canvas,
                     visor_pt_t from,
                     visor_pt_t to,
                     float width,
                     uint16_t colour)
{
    float half = width * 0.5f;
    float reach = half + 1.0f;

    int left = (int)floorf(fminf(from.x, to.x) - reach);
    int right = (int)ceilf(fmaxf(from.x, to.x) + reach);
    int top = (int)floorf(fminf(from.y, to.y) - reach);
    int bottom = (int)ceilf(fmaxf(from.y, to.y) + reach);

    if (left < 0) { left = 0; }
    if (top < 0) { top = 0; }
    if (right > canvas->width - 1) { right = canvas->width - 1; }
    if (bottom > canvas->height - 1) { bottom = canvas->height - 1; }

    for (int y = top; y <= bottom; y++) {
        for (int x = left; x <= right; x++) {
            float away = distance_to_segment((float)x + 0.5f, (float)y + 0.5f, from, to);
            blend(canvas, x, y, colour, clampf(half + 0.5f - away, 0.0f, 1.0f));
        }
    }
}

void visor_draw_polyline(const visor_canvas_t *canvas,
                         const visor_pt_t *points,
                         int count,
                         float width,
                         uint16_t colour)
{
    for (int index = 1; index < count; index++) {
        visor_draw_line(canvas, points[index - 1], points[index], width, colour);
    }
}

void visor_draw_disc(const visor_canvas_t *canvas, visor_pt_t centre, float radius, uint16_t colour)
{
    visor_draw_line(canvas, centre, centre, radius * 2.0f, colour);
}

void visor_draw_triangle(const visor_canvas_t *canvas,
                         visor_pt_t a,
                         visor_pt_t b,
                         visor_pt_t c,
                         uint16_t colour)
{
    int left = (int)floorf(fminf(a.x, fminf(b.x, c.x)));
    int right = (int)ceilf(fmaxf(a.x, fmaxf(b.x, c.x)));
    int top = (int)floorf(fminf(a.y, fminf(b.y, c.y)));
    int bottom = (int)ceilf(fmaxf(a.y, fmaxf(b.y, c.y)));

    if (left < 0) { left = 0; }
    if (top < 0) { top = 0; }
    if (right > canvas->width - 1) { right = canvas->width - 1; }
    if (bottom > canvas->height - 1) { bottom = canvas->height - 1; }

    /* Twice the signed area, which also says which way round the corners were
     * given; dividing the edge tests by it makes the winding order irrelevant. */
    float area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
    if (fabsf(area) < 1e-6f) {
        return;
    }

    /* Sampled nine times a pixel rather than once.
     *
     * Lines already soften their own edges from the distance to the segment,
     * and a triangle has no such measure to hand. Testing it once at the centre
     * leaves every diagonal a staircase, which on a panel this coarse is the
     * difference between an arrowhead and a flight of steps. */
    for (int y = top; y <= bottom; y++) {
        for (int x = left; x <= right; x++) {
            int hits = 0;

            for (int sy = 0; sy < 3; sy++) {
                for (int sx = 0; sx < 3; sx++) {
                    float px = (float)x + (float)sx / 3.0f + 1.0f / 6.0f;
                    float py = (float)y + (float)sy / 3.0f + 1.0f / 6.0f;

                    float w0 = ((b.x - a.x) * (py - a.y) - (px - a.x) * (b.y - a.y)) / area;
                    float w1 = ((c.x - b.x) * (py - b.y) - (px - b.x) * (c.y - b.y)) / area;
                    float w2 = ((a.x - c.x) * (py - c.y) - (px - c.x) * (a.y - c.y)) / area;

                    if (w0 >= 0.0f && w1 >= 0.0f && w2 >= 0.0f) {
                        hits++;
                    }
                }
            }

            blend(canvas, x, y, colour, (float)hits / 9.0f);
        }
    }
}

/* --- numbers -------------------------------------------------------------- */

/* Seven segments, in the order a b c d e f g. */
static const uint8_t DIGIT_SEGMENTS[10] = {
    0x3F, /* 0: a b c d e f */
    0x06, /* 1: b c */
    0x5B, /* 2: a b g e d */
    0x4F, /* 3: a b g c d */
    0x66, /* 4: f g b c */
    0x6D, /* 5: a f g c d */
    0x7D, /* 6: a f g e c d */
    0x07, /* 7: a b c */
    0x7F, /* 8: everything */
    0x6F, /* 9: a b c d f g */
};

static void bar(const visor_canvas_t *canvas, float x, float y, float w, float h, uint16_t colour)
{
    /* Drawn as a fat line down the middle of the bar, so the ends come out
     * rounded and the whole number looks less like a calculator. */
    if (w >= h) {
        visor_pt_t from = { x + h * 0.5f, y + h * 0.5f };
        visor_pt_t to = { x + w - h * 0.5f, y + h * 0.5f };
        visor_draw_line(canvas, from, to, h, colour);
    } else {
        visor_pt_t from = { x + w * 0.5f, y + w * 0.5f };
        visor_pt_t to = { x + w * 0.5f, y + h - w * 0.5f };
        visor_draw_line(canvas, from, to, w, colour);
    }
}

static void digit(const visor_canvas_t *canvas, int value, float x, float y, float h, uint16_t colour)
{
    if (value < 0 || value > 9) {
        return;
    }

    float w = h * 0.58f;
    float t = h * 0.15f;
    uint8_t on = DIGIT_SEGMENTS[value];

    if (on & 0x01) { bar(canvas, x + t * 0.5f, y, w - t, t, colour); }
    if (on & 0x02) { bar(canvas, x + w - t, y + t * 0.5f, t, h * 0.5f - t * 0.5f, colour); }
    if (on & 0x04) { bar(canvas, x + w - t, y + h * 0.5f, t, h * 0.5f - t * 0.5f, colour); }
    if (on & 0x08) { bar(canvas, x + t * 0.5f, y + h - t, w - t, t, colour); }
    if (on & 0x10) { bar(canvas, x, y + h * 0.5f, t, h * 0.5f - t * 0.5f, colour); }
    if (on & 0x20) { bar(canvas, x, y + t * 0.5f, t, h * 0.5f - t * 0.5f, colour); }
    if (on & 0x40) { bar(canvas, x + t * 0.5f, y + h * 0.5f - t * 0.5f, w - t, t, colour); }
}

static int digit_count(uint32_t value)
{
    int count = 1;
    while (value >= 10) {
        value /= 10;
        count++;
    }
    return count;
}

float visor_draw_number_width(uint32_t value, float height)
{
    int count = digit_count(value);
    float w = height * 0.58f;
    return (float)count * w + (float)(count - 1) * height * 0.16f;
}

float visor_draw_number(const visor_canvas_t *canvas,
                        uint32_t value,
                        visor_pt_t at,
                        float height,
                        uint16_t colour)
{
    int count = digit_count(value);
    float w = height * 0.58f;
    float gap = height * 0.16f;

    /* Right to left, because that is the order the digits fall out in. */
    for (int index = count - 1; index >= 0; index--) {
        digit(canvas, (int)(value % 10), at.x + (float)index * (w + gap), at.y, height, colour);
        value /= 10;
    }

    return (float)count * w + (float)(count - 1) * gap;
}

float visor_draw_metres_width(float height)
{
    return height * 0.95f;
}

void visor_draw_metres(const visor_canvas_t *canvas, visor_pt_t at, float height, uint16_t colour)
{
    float width = visor_draw_metres_width(height);
    float thickness = height * 0.26f;

    /* One bar across the top and three coming down from it. Blocky, but at the
     * size a unit is drawn nobody reads the letterform, they read that there is
     * a letter and which one it starts like. */
    bar(canvas, at.x, at.y, width, thickness, colour);
    bar(canvas, at.x, at.y, thickness, height, colour);
    bar(canvas, at.x + (width - thickness) * 0.5f, at.y, thickness, height, colour);
    bar(canvas, at.x + width - thickness, at.y, thickness, height, colour);
}

/* --- arcs ------------------------------------------------------------------ */

void visor_draw_arc(const visor_canvas_t *canvas,
                    visor_pt_t centre,
                    float radius,
                    float from_degrees,
                    float to_degrees,
                    float width,
                    uint16_t colour)
{
    /* Enough steps that the corners between them fall inside the stroke, which
     * is what makes a polyline pass for a curve. */
    int steps = (int)(fabsf(to_degrees - from_degrees) / 3.0f) + 2;
    visor_pt_t previous = { 0.0f, 0.0f };

    for (int step = 0; step <= steps; step++) {
        float angle = (from_degrees + (to_degrees - from_degrees) * (float)step / (float)steps);
        float radians = angle * 3.14159265f / 180.0f;
        visor_pt_t at = {
            centre.x + cosf(radians) * radius,
            centre.y + sinf(radians) * radius,
        };

        if (step > 0) {
            visor_draw_line(canvas, previous, at, width, colour);
        }
        previous = at;
    }
}

void visor_draw_ring(const visor_canvas_t *canvas,
                     visor_pt_t centre,
                     float radius,
                     float width,
                     uint16_t colour)
{
    visor_draw_arc(canvas, centre, radius, 0.0f, 360.0f, width, colour);
}

/* --- maneuvers ------------------------------------------------------------- */

/* Each arrow is a short path in a unit box, y up, with the head put on the end
 * pointing the way the last leg was going. One table, nine arrows, no artwork.
 */
typedef struct {
    int count;
    visor_pt_t points[4];
} arrow_t;

static arrow_t arrow_for(uint8_t maneuver)
{
    switch (maneuver) {
    case VISOR_MANEUVER_DEPART:
    case VISOR_MANEUVER_STRAIGHT:
        return (arrow_t){ 2, { { 0.0f, -0.85f }, { 0.0f, 0.40f } } };
    case VISOR_MANEUVER_SLIGHT_RIGHT:
        return (arrow_t){ 3, { { 0.0f, -0.85f }, { 0.0f, -0.15f }, { 0.42f, 0.40f } } };
    case VISOR_MANEUVER_RIGHT:
        return (arrow_t){ 3, { { 0.0f, -0.85f }, { 0.0f, 0.05f }, { 0.50f, 0.05f } } };
    case VISOR_MANEUVER_SHARP_RIGHT:
        return (arrow_t){ 3, { { 0.0f, -0.85f }, { 0.0f, 0.30f }, { 0.48f, -0.20f } } };
    case VISOR_MANEUVER_SLIGHT_LEFT:
        return (arrow_t){ 3, { { 0.0f, -0.85f }, { 0.0f, -0.15f }, { -0.42f, 0.40f } } };
    case VISOR_MANEUVER_LEFT:
        return (arrow_t){ 3, { { 0.0f, -0.85f }, { 0.0f, 0.05f }, { -0.50f, 0.05f } } };
    case VISOR_MANEUVER_SHARP_LEFT:
        return (arrow_t){ 3, { { 0.0f, -0.85f }, { 0.0f, 0.30f }, { -0.48f, -0.20f } } };
    case VISOR_MANEUVER_UTURN:
        return (arrow_t){ 4, { { 0.30f, -0.85f }, { 0.30f, 0.30f }, { -0.30f, 0.30f }, { -0.30f, -0.30f } } };
    default:
        return (arrow_t){ 0, { { 0.0f, 0.0f } } };
    }
}

void visor_draw_maneuver(const visor_canvas_t *canvas,
                         uint8_t maneuver,
                         visor_pt_t at,
                         float size,
                         uint16_t colour,
                         uint16_t hole)
{
    if (maneuver == VISOR_MANEUVER_ARRIVE) {
        visor_draw_disc(canvas, at, size * 0.44f, colour);
        visor_draw_disc(canvas, at, size * 0.20f, hole);
        return;
    }

    arrow_t arrow = arrow_for(maneuver);
    if (arrow.count < 2) {
        /* Nothing known to point at, and inventing a direction would be worse
         * than showing none. A dot says the display is alive and has no
         * instruction. */
        visor_draw_disc(canvas, at, size * 0.12f, colour);
        return;
    }

    visor_pt_t on_screen[4];
    for (int index = 0; index < arrow.count; index++) {
        on_screen[index].x = at.x + arrow.points[index].x * size;
        on_screen[index].y = at.y - arrow.points[index].y * size;
    }

    /* The body stops short of the tip so the head does not sit on a blunt end. */
    visor_pt_t last = on_screen[arrow.count - 1];
    visor_pt_t before = on_screen[arrow.count - 2];
    float run_x = last.x - before.x;
    float run_y = last.y - before.y;
    float length = sqrtf(run_x * run_x + run_y * run_y);
    if (length < 1e-3f) {
        return;
    }
    run_x /= length;
    run_y /= length;

    float head = size * 0.34f;
    on_screen[arrow.count - 1].x = last.x - run_x * head * 0.8f;
    on_screen[arrow.count - 1].y = last.y - run_y * head * 0.8f;

    visor_draw_polyline(canvas, on_screen, arrow.count, size * 0.20f, colour);

    visor_pt_t tip = { last.x + run_x * head * 0.35f, last.y + run_y * head * 0.35f };
    visor_pt_t left = { last.x - run_x * head * 0.65f - run_y * head * 0.55f,
                        last.y - run_y * head * 0.65f + run_x * head * 0.55f };
    visor_pt_t right = { last.x - run_x * head * 0.65f + run_y * head * 0.55f,
                         last.y - run_y * head * 0.65f - run_x * head * 0.55f };
    visor_draw_triangle(canvas, tip, left, right, colour);
}
