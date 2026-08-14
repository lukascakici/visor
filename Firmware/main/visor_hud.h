/* The screen itself: what goes where.
 *
 * Kept apart from both the rasteriser and the radio so that the whole display
 * can be rendered without either. The host test draws real frames through this
 * and writes them out as images.
 */
#ifndef VISOR_HUD_H
#define VISOR_HUD_H

#include <stdbool.h>
#include <stdint.h>

#include "visor_draw.h"
#include "visor_packet.h"
#include "visor_view.h"

/* Everything the screen is drawn from, and nothing else.
 *
 * `has_guidance` is false before the first packet: a display that has heard
 * nothing must not show the numbers it would have shown, because a rider cannot
 * tell a stale instruction from a current one.
 */
typedef struct {
    bool has_guidance;
    visor_guidance_t guidance;

    bool has_path;
    visor_path_t path;
    visor_path_t previous_path;
    bool has_previous_path;
    int64_t path_arrived_us;
    int64_t path_interval_us;
} visor_hud_state_t;

void visor_hud_reset(visor_hud_state_t *state);

/* Takes a write from the phone. Unrecognised or truncated writes are ignored
 * rather than allowed to blank the screen. */
void visor_hud_receive_guidance(visor_hud_state_t *state, const uint8_t *data, size_t length);
void visor_hud_receive_path(visor_hud_state_t *state,
                            const uint8_t *data,
                            size_t length,
                            int64_t now_us);

/* Draws the whole screen. Call as often as the panel can take it: the road is
 * crossed between packets, so the more often this runs the smoother it moves.
 */
void visor_hud_render(const visor_canvas_t *canvas, const visor_hud_state_t *state, int64_t now_us);

#endif /* VISOR_HUD_H */
