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

    /* The high-water mark is the route length. It rises when a reroute makes
     * the way home longer, which is exactly when the arc should give ground
     * back. */
    if (decoded.distance_remaining_m > state->route_length_m) {
        state->route_length_m = decoded.distance_remaining_m;
    }
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

static void render_road(const visor_canvas_t *canvas,
                        const visor_hud_state_t *state,
                        int64_t now_us,
                        int height)
{
    visor_canvas_t panel = { canvas->pixels, canvas->width, height };

    if (!state->has_path) {
        return;
    }

    float crossing = visor_view_crossing(now_us, state->path_arrived_us, state->path_interval_us);

    visor_view_t view;
    visor_view_between(state->has_previous_path ? &state->previous_path : NULL,
                       &state->path,
                       crossing,
                       &view);

    visor_frame_t frame = visor_frame_make(panel.width, panel.height);
    uint16_t colour = road_colour(state);
    float thickness = (float)canvas->width * 0.055f;

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
     * explain it. */
    visor_draw_polyline(&panel, road, here + 1, thickness * 0.75f, COLOUR_BEHIND);
    visor_draw_polyline(&panel, road + here, VISOR_VIEW_SAMPLES - here, thickness, colour);

    if (view.has_junction) {
        visor_pt_t at = {
            visor_frame_x(&frame, view.junction.right_m),
            visor_frame_y(&frame, view.junction.ahead_m),
        };
        /* A hole punched in the road rather than a blob laid on top of it. The
         * bend already shows where the turn is; this only says which bend. */
        visor_draw_disc(&panel, at, thickness * 0.34f, COLOUR_BACKGROUND);
    }
}

/* The rider: a chevron, drawn as two triangles so it can have a notch.
 *
 * A plain triangle at this size reads as a blob. The notch is what makes it
 * point. */
static void render_rider(const visor_canvas_t *canvas, uint16_t colour, float centre_x, float y)
{
    float size = (float)canvas->width * 0.062f;

    visor_pt_t tip = { centre_x, y - size };
    visor_pt_t notch = { centre_x, y + size * 0.28f };
    visor_pt_t left = { centre_x - size * 0.86f, y + size * 0.60f };
    visor_pt_t right = { centre_x + size * 0.86f, y + size * 0.60f };

    visor_draw_triangle(canvas, tip, right, notch, colour);
    visor_draw_triangle(canvas, tip, notch, left, colour);
}

/* The band along the bottom: what to do, how far, how fast, how much is left.
 *
 * Everything a rider acts on lives here, below the road and out of its way. The
 * distance is the number they act on, so it gets the room, and it is never
 * smoothed and never guessed at: it is whatever the last packet said.
 */
static void render_band(const visor_canvas_t *canvas,
                        const visor_hud_state_t *state,
                        int top,
                        visor_panel_shape_t shape)
{
    float width = (float)canvas->width;
    float height = (float)canvas->height;

    /* A lighter ground under the readings, so they sit on something rather than
     * floating over the road. */
    visor_pt_t from = { 0.0f, (float)top + (height - (float)top) * 0.5f };
    visor_pt_t to = { width, from.y };
    visor_draw_line(canvas, from, to, height - (float)top, COLOUR_BAND);

    /* The trail: where the rider has come from, carried on down through the
     * band so the eye follows it out of the map. Drawn first, so the readings
     * sit over it rather than beside it. */
    visor_pt_t trail_top = { width * 0.5f, (float)top };
    visor_pt_t trail_end = { width * 0.5f, height * 0.815f };
    visor_draw_line(canvas, trail_top, trail_end, width * 0.038f, COLOUR_BEHIND);

    if (!state->has_guidance) {
        return;
    }

    uint16_t alarm = (state->guidance.flags & VISOR_FLAG_OFF_ROUTE) ? COLOUR_ALARM : COLOUR_TEXT;

    visor_pt_t arrow = { width * 0.305f, height * 0.795f };
    visor_draw_maneuver(canvas, state->guidance.maneuver, arrow, height * 0.100f, alarm, COLOUR_BAND);

    /* Speed sits in a plain ring, not a roundel with a red border. That border
     * means a limit everywhere in the world, and a limit is the one thing this
     * display has no way of knowing. */
    float radius = height * 0.074f;
    visor_pt_t dial = { width * 0.838f, height * 0.752f };
    visor_draw_ring(canvas, dial, radius, radius * 0.22f, COLOUR_DIM);

    float speed_height = radius * 0.60f;
    float speed_width = visor_draw_number_width(state->guidance.speed_kmh, speed_height);
    visor_pt_t speed = { dial.x - speed_width * 0.5f, dial.y - speed_height * 0.5f };
    visor_draw_number(canvas, state->guidance.speed_kmh, speed, speed_height, COLOUR_TEXT);

    /* The distance starts where the trail runs, so the trail passes behind its
     * first digit rather than through the middle of the number. */
    float digits = height * 0.126f;
    uint32_t metres = state->guidance.distance_to_maneuver_m;
    visor_pt_t number = { width * 0.505f, height * 0.722f };

    /* Four digits are wider than three, and there is only so much band. What
     * limits it is whichever comes first: the speed ring, or the edge of the
     * glass. Shrinking keeps the number whole; letting it run on would cost
     * either the leading digit or the speed, and both are worth more than the
     * size of the type. */
    float edge = band_half_width(canvas, shape, (int)number.y, (int)(number.y + digits));
    float until_ring = dial.x - radius - width * 0.025f;
    float until_edge = width * 0.5f + edge - width * 0.03f;
    float room = (until_ring < until_edge ? until_ring : until_edge) - number.x;

    float drawn_width = visor_draw_number_width(metres, digits);
    if (drawn_width > room && room > 0.0f) {
        digits *= room / drawn_width;
    }

    visor_draw_number(canvas, metres, number, digits, COLOUR_TEXT);

    /* The unit, tucked under the number's first digit. A bare number on a HUD
     * is ambiguous in a way that matters at speed. */
    visor_pt_t unit = { number.x, number.y + digits + height * 0.014f };
    visor_draw_metres(canvas, unit, height * 0.056f, COLOUR_DIM);
}

/* How much of the ride is behind, drawn around the bottom of the glass.
 *
 * The one reading here that is inferred rather than received; see the note on
 * `route_length_m`.
 */
static void render_progress(const visor_canvas_t *canvas, const visor_hud_state_t *state)
{
    if (!state->has_guidance || state->route_length_m == 0) {
        return;
    }

    visor_pt_t centre = { (float)canvas->width * 0.5f, (float)canvas->height * 0.5f };
    float radius = (float)canvas->width * 0.5f * 0.90f;
    float thickness = (float)canvas->width * 0.018f;
    float start = 148.0f;
    float end = 32.0f;

    visor_draw_arc(canvas, centre, radius, start, end, thickness, visor_rgb(52, 58, 66));

    uint32_t left = state->guidance.distance_remaining_m;
    if (left > state->route_length_m) {
        left = state->route_length_m;
    }
    float done = 1.0f - (float)left / (float)state->route_length_m;
    if (done <= 0.0f) {
        return;
    }

    visor_draw_arc(canvas, centre, radius, start, start + (end - start) * done, thickness, COLOUR_TEXT);
}

/* Only the flags that are raised, and only when they are.
 *
 * A row of unlit lamps is furniture a rider learns to stop seeing, which is
 * exactly the wrong thing to happen to a warning.
 */
static void render_flags(const visor_canvas_t *canvas, const visor_hud_state_t *state)
{
    if (!state->has_guidance) {
        return;
    }

    struct {
        uint8_t bit;
        uint16_t colour;
    } lamps[3] = {
        { VISOR_FLAG_OFF_ROUTE, COLOUR_ALARM },
        { VISOR_FLAG_REROUTING, visor_rgb(255, 170, 0) },
        { VISOR_FLAG_WEAK_GPS, visor_rgb(240, 220, 0) },
    };

    float spacing = (float)canvas->width * 0.055f;
    float centre = (float)canvas->width * 0.5f;
    float radius = (float)canvas->width * 0.017f;

    int raised = 0;
    for (int index = 0; index < 3; index++) {
        if (state->guidance.flags & lamps[index].bit) {
            raised++;
        }
    }
    if (raised == 0) {
        return;
    }

    float x = centre - spacing * (float)(raised - 1) * 0.5f;
    for (int index = 0; index < 3; index++) {
        if ((state->guidance.flags & lamps[index].bit) == 0) {
            continue;
        }
        visor_pt_t at = { x, (float)canvas->height * 0.075f };
        visor_draw_disc(canvas, at, radius, lamps[index].colour);
        x += spacing;
    }
}

void visor_hud_render(const visor_canvas_t *canvas,
                      const visor_hud_state_t *state,
                      int64_t now_us,
                      visor_panel_shape_t shape)
{
    visor_draw_fill(canvas, COLOUR_BACKGROUND);

    /* The map runs the full width and most of the height; the readings sit in a
     * band under it. On round glass that band is where the circle is narrowing,
     * so everything in it is measured off the middle rather than off an edge
     * that is not there. */
    int map_height = canvas->height * 72 / 100;
    int band_top = canvas->height * 70 / 100;
    float rider_y = (float)canvas->height * 0.60f;

    render_road(canvas, state, now_us, map_height);
    render_band(canvas, state, band_top, shape);
    render_progress(canvas, state);
    render_flags(canvas, state);

    /* Last, so nothing is ever drawn over the rider. Where they are is the one
     * thing on this display that must never be ambiguous. */
    render_rider(canvas, road_colour(state), (float)canvas->width * 0.5f, rider_y);
}
