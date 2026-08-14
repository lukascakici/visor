/* The glass.
 *
 * The one file that knows which panel this is. Everything above it renders into
 * a framebuffer and asks for it to be shown; swapping a GC9A01 for an AMOLED
 * changes this file and nothing else, because the drawing is written in
 * fractions of the canvas rather than in pixels.
 */
#ifndef VISOR_PANEL_H
#define VISOR_PANEL_H

#include <stdint.h>

#include "esp_err.h"

#include "visor_draw.h"

esp_err_t visor_panel_start(void);

/* The canvas to draw into. Valid once `visor_panel_start` has returned. */
const visor_canvas_t *visor_panel_canvas(void);

/* Puts the framebuffer on the glass and waits until it is there.
 *
 * Waiting matters: the transfer reads the buffer directly, so drawing the next
 * frame into it before the last one has gone out would tear the picture.
 */
void visor_panel_present(void);

#endif /* VISOR_PANEL_H */
