#include "visor_hud.h"

#include <math.h>
#include <string.h>

/* Dark, because this is read at night as often as by day, and because every
 * unlit pixel is one that does not reflect back off the inside of a visor. */
#define COLOUR_BACKGROUND visor_rgb(0, 0, 0)
#define COLOUR_ROAD visor_rgb(0, 210, 235)
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

static void render_road(const visor_canvas_t *canvas,
                        const visor_hud_state_t *state,
                        int64_t now_us,
                        int top,
                        int height)
{
    visor_canvas_t panel = {
        .pixels = canvas->pixels + (size_t)top * (size_t)canvas->width,
        .width = canvas->width,
        .height = height,
    };

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

    visor_pt_t road[VISOR_VIEW_SAMPLES];
    for (int index = 0; index < VISOR_VIEW_SAMPLES; index++) {
        road[index].x = visor_frame_x(&frame, view.road[index].right_m);
        road[index].y = visor_frame_y(&frame, view.road[index].ahead_m);
    }
    visor_draw_polyline(&panel, road, VISOR_VIEW_SAMPLES, 7.0f, colour);

    if (view.has_junction) {
        visor_pt_t at = {
            visor_frame_x(&frame, view.junction.right_m),
            visor_frame_y(&frame, view.junction.ahead_m),
        };
        visor_draw_disc(&panel, at, 9.0f, COLOUR_TEXT);
        visor_draw_disc(&panel, at, 5.0f, colour);
    }

    visor_pt_t rider = { frame.centre_x, frame.rider_y };
    visor_pt_t nose = { rider.x, rider.y - 10.0f };
    visor_pt_t left = { rider.x - 8.0f, rider.y + 8.0f };
    visor_pt_t right = { rider.x + 8.0f, rider.y + 8.0f };
    visor_draw_triangle(&panel, nose, left, right, COLOUR_TEXT);
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
        visor_draw_disc(canvas, middle, 6.0f, COLOUR_DIM);
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
    visor_draw_maneuver(canvas, state->guidance.maneuver, arrow, size, COLOUR_TEXT, COLOUR_BACKGROUND);

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

    float spacing = (float)canvas->width * 0.11f;
    float centre = (float)canvas->width * 0.5f;

    for (int index = 0; index < 3; index++) {
        visor_pt_t at = { centre + (float)(index - 1) * spacing, (float)row };
        bool on = (state->guidance.flags & lamps[index].bit) != 0;
        visor_draw_disc(canvas, at, 7.0f, on ? lamps[index].colour : visor_rgb(28, 32, 36));
    }
}

void visor_hud_render(const visor_canvas_t *canvas,
                      const visor_hud_state_t *state,
                      int64_t now_us,
                      visor_panel_shape_t shape)
{
    visor_draw_fill(canvas, COLOUR_BACKGROUND);

    /* Laid out down the middle of the glass rather than out to its edges. On a
     * round panel the corners simply are not there, and a layout that pretends
     * otherwise loses whatever it puts in them. On a square one this reads as
     * generous margins, which is a cheap price for one layout instead of two.
     */
    int instruction_top = canvas->height * 14 / 100;
    int instruction_height = canvas->height * 26 / 100;
    int road_top = canvas->height * 42 / 100;
    int road_height = canvas->height * 44 / 100;
    int lamp_row = canvas->height * 91 / 100;

    float room = band_half_width(canvas, shape, instruction_top, instruction_top + instruction_height);

    render_instruction(canvas, state, instruction_top, instruction_height, room);
    render_road(canvas, state, now_us, road_top, road_height);
    render_flags(canvas, state, lamp_row);
}
