#include "visor_hud.h"

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

static void render_instruction(const visor_canvas_t *canvas, const visor_hud_state_t *state, int height)
{
    visor_canvas_t band = {
        .pixels = canvas->pixels,
        .width = canvas->width,
        .height = height,
    };

    if (!state->has_guidance) {
        visor_pt_t middle = { (float)band.width * 0.5f, (float)band.height * 0.5f };
        visor_draw_disc(&band, middle, 6.0f, COLOUR_DIM);
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
    float left = ((float)band.width - (size * 2.0f + gap + number)) * 0.5f;

    visor_pt_t arrow = { left + size, (float)height * 0.5f };
    visor_draw_maneuver(&band, state->guidance.maneuver, arrow, size, COLOUR_TEXT, COLOUR_BACKGROUND);

    visor_pt_t at = { left + size * 2.0f + gap, ((float)height - digits) * 0.5f };
    visor_draw_number(&band, metres, at, digits, COLOUR_TEXT);
}

static void render_flags(const visor_canvas_t *canvas, const visor_hud_state_t *state, int top)
{
    if (!state->has_guidance) {
        return;
    }

    /* Three lamps rather than three words: at a glance a rider reads colour and
     * position, and words would need the font this display does not carry. */
    struct {
        uint8_t bit;
        uint16_t colour;
    } lamps[3] = {
        { VISOR_FLAG_OFF_ROUTE, COLOUR_ALARM },
        { VISOR_FLAG_REROUTING, visor_rgb(255, 170, 0) },
        { VISOR_FLAG_WEAK_GPS, visor_rgb(240, 220, 0) },
    };

    for (int index = 0; index < 3; index++) {
        visor_pt_t at = { 16.0f + (float)index * 26.0f, (float)top };
        bool on = (state->guidance.flags & lamps[index].bit) != 0;
        visor_draw_disc(canvas, at, 7.0f, on ? lamps[index].colour : visor_rgb(28, 32, 36));
    }
}

void visor_hud_render(const visor_canvas_t *canvas, const visor_hud_state_t *state, int64_t now_us)
{
    visor_draw_fill(canvas, COLOUR_BACKGROUND);

    int band = canvas->height * 30 / 100;
    int lamps = canvas->height - 18;
    int road_height = lamps - band - 12;

    render_instruction(canvas, state, band);
    render_road(canvas, state, now_us, band, road_height);
    render_flags(canvas, state, lamps);
}
