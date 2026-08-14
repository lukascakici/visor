#include "visor_hud.h"

#include <math.h>
#include <string.h>

/* Dark, because this is read at night as often as by day, and because every
 * unlit pixel is one that does not reflect back off the inside of a visor.
 *
 * The road is white rather than a colour. White is the brightest thing an
 * emissive panel can put on black, which is the whole argument on glass a rider
 * glances at, and it leaves colour free to mean something: nothing on this
 * display is red unless something is wrong.
 */
#define COLOUR_BACKGROUND visor_rgb(6, 8, 14)
#define COLOUR_BAND visor_rgb(22, 26, 34)
#define COLOUR_ROAD visor_rgb(255, 255, 255)
#define COLOUR_BEHIND visor_rgb(88, 95, 105)
#define COLOUR_ALARM visor_rgb(255, 60, 50)
#define COLOUR_TEXT visor_rgb(255, 255, 255)
#define COLOUR_DIM visor_rgb(120, 130, 140)

void visor_hud_reset(visor_hud_state_t *state)
{
    memset(state, 0, sizeof(*state));
    state->path_interval_us = 1000000;
}

void visor_hud_receive_guidance(visor_hud_state_t *state, const uint8_t *data, size_t length)
{
    visor_guidance_t decoded;
    if (!visor_guidance_decode(data, length, &decoded)) {
        return;
    }

    state->guidance = decoded;
    state->has_guidance = true;
}

void visor_hud_receive_path(visor_hud_state_t *state,
                            const uint8_t *data,
                            size_t length,
                            int64_t now_us)
{
    visor_path_t decoded;
    if (!visor_path_decode(data, length, &decoded)) {
        return;
    }

    /* The rate is measured rather than assumed, so the crossing keeps step with
     * whatever the phone actually manages. A gap that is neither a duplicate
     * nor a reconnection is the only kind worth pacing to. */
    if (state->has_path) {
        int64_t gap = now_us - state->path_arrived_us;
        if (gap > 50000 && gap < 3000000) {
            state->path_interval_us = gap;
        }
        state->previous_path = state->path;
        state->has_previous_path = true;
    }

    state->path = decoded;
    state->has_path = true;
    state->path_arrived_us = now_us;
}

static uint16_t road_colour(const visor_hud_state_t *state)
{
    if (state->has_guidance && (state->guidance.flags & VISOR_FLAG_OFF_ROUTE)) {
        return COLOUR_ALARM;
    }
    return COLOUR_ROAD;
}

/* How much room a band has, measured at its worst row.
 *
 * On a round panel the glass narrows towards the top and bottom, so a band's
 * width is decided by whichever of its edges is furthest from the middle. Put
 * something wider than this and it does not get clipped, it simply is not
 * there.
 */
static float band_half_width(const visor_canvas_t *canvas, visor_panel_shape_t shape, int top, int bottom)
{
    if (shape == VISOR_PANEL_SQUARE) {
        return (float)canvas->width * 0.5f;
    }

    float radius = (float)(canvas->width < canvas->height ? canvas->width : canvas->height) * 0.5f;
    float middle = (float)canvas->height * 0.5f;
    float from_top = fabsf((float)top - middle);
    float from_bottom = fabsf((float)bottom - middle);
    float furthest = from_top > from_bottom ? from_top : from_bottom;

    return furthest >= radius ? 0.0f : sqrtf(radius * radius - furthest * furthest);
}

/* The rider, outlined.
 *
 * The road is white and so is the rider, and without a dark edge between them
 * the marker disappears into the road exactly when it is on it, which is all
 * the time. The outline is offset from the centroid rather than scaled about a
 * point, so it comes out the same thickness on all three sides.
 */
static void render_rider(const visor_canvas_t *canvas, uint16_t colour, float x, float y)
{
    float size = (float)canvas->width * 0.042f;
    float edge = (float)canvas->width * 0.011f;

    visor_pt_t point[3] = {
        { x, y - size * 1.15f },
        { x - size * 0.92f, y + size * 0.85f },
        { x + size * 0.92f, y + size * 0.85f },
    };

    visor_pt_t centre = {
        (point[0].x + point[1].x + point[2].x) / 3.0f,
        (point[0].y + point[1].y + point[2].y) / 3.0f,
    };

    visor_pt_t outer[3];
    for (int index = 0; index < 3; index++) {
        float dx = point[index].x - centre.x;
        float dy = point[index].y - centre.y;
        float away = sqrtf(dx * dx + dy * dy);
        if (away < 1e-3f) {
            outer[index] = point[index];
            continue;
        }
        outer[index].x = point[index].x + dx / away * edge;
        outer[index].y = point[index].y + dy / away * edge;
    }

    visor_draw_triangle(canvas, outer[0], outer[1], outer[2], COLOUR_BACKGROUND);
    visor_draw_triangle(canvas, point[0], point[1], point[2], colour);
}

static void render_road(const visor_canvas_t *canvas,
                        const visor_hud_state_t *state,
                        int64_t now_us)
{
    if (!state->has_path) {
        return;
    }

    float crossing = visor_view_crossing(now_us, state->path_arrived_us, state->path_interval_us);

    visor_view_t view;
    visor_view_between(state->has_previous_path ? &state->previous_path : NULL,
                       &state->path,
                       crossing,
                       &view);

    visor_frame_t frame = visor_frame_make(canvas->width, canvas->height);
    uint16_t colour = road_colour(state);
    float thickness = (float)canvas->width * 0.036f;

    visor_pt_t road[VISOR_VIEW_SAMPLES];
    int here = 0;
    for (int index = 0; index < VISOR_VIEW_SAMPLES; index++) {
        road[index].x = visor_frame_x(&frame, view.road[index].right_m);
        road[index].y = visor_frame_y(&frame, view.road[index].ahead_m);

        if (fabsf(view.road[index].ahead_m) < fabsf(view.road[here].ahead_m)) {
            here = index;
        }
    }

    /* Road already ridden in grey, road still to ride in white. The rider is
     * the join between them, so which way they are pointing needs no arrow to
     * explain it.
     *
     * Nothing is drawn at the junction. The bend is the turn, and a mark on top
     * of it was one more thing on the glass saying what the shape already said.
     */
    visor_draw_polyline(canvas, road, here + 1, thickness * 0.75f, COLOUR_BEHIND);
    visor_draw_polyline(canvas, road + here, VISOR_VIEW_SAMPLES - here, thickness, colour);

    /* Last, so nothing is ever drawn over the rider. Where they are is the one
     * thing on this display that must never be ambiguous. */
    render_rider(canvas, colour, frame.centre_x, frame.rider_y);
}

/* A frosted strip along the bottom for the readings to sit on.
 *
 * Blurred rather than merely darkened, and the road is why: a hard white line
 * passing behind white digits is unreadable, while a soft one is a glow. One
 * pass across is enough for that. Blurring downwards as well would want a copy
 * of the whole strip, and there is nothing in it but the road to justify the
 * memory.
 *
 * It is a layer over the map rather than a band beside it, which is what lets
 * the map have the whole of the glass. On a round panel that matters twice
 * over: the area is small to begin with, and cutting a rectangle out of a
 * circle wastes the parts that were never square.
 */
static void render_frost(const visor_canvas_t *canvas, int top)
{
    enum { WIDEST = 512 };
    static uint16_t source[WIDEST];

    int width = canvas->width;
    if (width > WIDEST || width < 3) {
        return;
    }

    int reach = width / 36;
    if (reach < 1) {
        reach = 1;
    }

    int tint_r = (COLOUR_BAND >> 11) & 0x1F;
    int tint_g = (COLOUR_BAND >> 5) & 0x3F;
    int tint_b = COLOUR_BAND & 0x1F;

    for (int y = top; y < canvas->height; y++) {
        uint16_t *row = canvas->pixels + (size_t)y * (size_t)width;
        for (int x = 0; x < width; x++) {
            source[x] = row[x];
        }

        int sum_r = 0, sum_g = 0, sum_b = 0, count = 0;
        for (int x = 0; x <= reach && x < width; x++) {
            sum_r += (source[x] >> 11) & 0x1F;
            sum_g += (source[x] >> 5) & 0x3F;
            sum_b += source[x] & 0x1F;
            count++;
        }

        for (int x = 0; x < width; x++) {
            if (x > 0) {
                int leaving = x - reach - 1;
                int entering = x + reach;
                if (leaving >= 0) {
                    sum_r -= (source[leaving] >> 11) & 0x1F;
                    sum_g -= (source[leaving] >> 5) & 0x3F;
                    sum_b -= source[leaving] & 0x1F;
                    count--;
                }
                if (entering < width) {
                    sum_r += (source[entering] >> 11) & 0x1F;
                    sum_g += (source[entering] >> 5) & 0x3F;
                    sum_b += source[entering] & 0x1F;
                    count++;
                }
            }

            /* A third of what was there, on top of a tint. Multiplying alone
             * would leave the strip as black as the map and there would be no
             * layer to see. */
            int r = ((sum_r / count) * 34 + tint_r * 66) / 100;
            int g = ((sum_g / count) * 34 + tint_g * 66) / 100;
            int b = ((sum_b / count) * 34 + tint_b * 66) / 100;
            row[x] = (uint16_t)((r << 11) | (g << 5) | b);
        }
    }
}

static void render_instruction(const visor_canvas_t *canvas,
                               const visor_hud_state_t *state,
                               int top,
                               int height,
                               float half_width)
{
    float middle_y = (float)top + (float)height * 0.5f;

    if (!state->has_guidance) {
        visor_pt_t middle = { (float)canvas->width * 0.5f, middle_y };
        visor_draw_disc(canvas, middle, (float)canvas->width * 0.025f, COLOUR_DIM);
        return;
    }

    /* The distance is the number a rider acts on, so it gets the room. It is
     * never smoothed and never guessed at: it is whatever the last packet said,
     * and if no packet has come the whole band stays empty.
     *
     * Arrow and number are measured together and centred as one, so the band
     * does not lurch left and right as the distance loses a digit. */
    uint32_t metres = state->guidance.distance_to_maneuver_m;
    float size = (float)height * 0.44f;
    float digits = (float)height * 0.58f;
    float gap = (float)height * 0.18f;
    float number = visor_draw_number_width(metres, digits);
    float total = size * 2.0f + gap + number;

    /* Four digits are wider than three, and on round glass there may not be
     * room for them. Shrinking the whole group keeps it readable and keeps it
     * on the panel; letting it run off the edge would lose the leading digit,
     * which is the one that matters. */
    float room = half_width * 2.0f - 10.0f;
    if (total > room && room > 0.0f) {
        float shrink = room / total;
        size *= shrink;
        digits *= shrink;
        gap *= shrink;
        number = visor_draw_number_width(metres, digits);
        total = size * 2.0f + gap + number;
    }

    float left = (float)canvas->width * 0.5f - total * 0.5f;

    visor_pt_t arrow = { left + size, middle_y };
    visor_draw_maneuver(canvas, state->guidance.maneuver, arrow, size, COLOUR_TEXT, COLOUR_BAND);

    visor_pt_t at = { left + size * 2.0f + gap, middle_y - digits * 0.5f };
    visor_draw_number(canvas, metres, at, digits, COLOUR_TEXT);
}

static void render_flags(const visor_canvas_t *canvas, const visor_hud_state_t *state, int row)
{
    if (!state->has_guidance) {
        return;
    }

    /* Three lamps rather than three words: at a glance a rider reads colour and
     * position, and words would need the font this display does not carry.
     * Centred, because on round glass the corners a status bar would live in
     * are not there. */
    struct {
        uint8_t bit;
        uint16_t colour;
    } lamps[3] = {
        { VISOR_FLAG_OFF_ROUTE, COLOUR_ALARM },
        { VISOR_FLAG_REROUTING, visor_rgb(255, 170, 0) },
        { VISOR_FLAG_WEAK_GPS, visor_rgb(240, 220, 0) },
    };

    float spacing = (float)canvas->width * 0.085f;
    float centre = (float)canvas->width * 0.5f;
    float radius = (float)canvas->width * 0.022f;

    for (int index = 0; index < 3; index++) {
        visor_pt_t at = { centre + (float)(index - 1) * spacing, (float)row };
        bool on = (state->guidance.flags & lamps[index].bit) != 0;
        visor_draw_disc(canvas, at, radius, on ? lamps[index].colour : visor_rgb(28, 32, 36));
    }
}

void visor_hud_render(const visor_canvas_t *canvas,
                      const visor_hud_state_t *state,
                      int64_t now_us,
                      visor_panel_shape_t shape)
{
    visor_draw_fill(canvas, COLOUR_BACKGROUND);

    /* The map has the whole panel. What a rider needs to read sits on a frosted
     * layer over the bottom of it, and the rider marker is placed high enough
     * that it never reaches that layer. */
    int frost_top = canvas->height * 68 / 100;
    int instruction_top = canvas->height * 695 / 1000;
    int instruction_height = canvas->height * 19 / 100;
    int lamp_row = canvas->height * 935 / 1000;

    render_road(canvas, state, now_us);
    render_frost(canvas, frost_top);

    float room = band_half_width(canvas, shape, instruction_top, instruction_top + instruction_height);
    render_instruction(canvas, state, instruction_top, instruction_height, room);
    render_flags(canvas, state, lamp_row);
}
