/* Turning two path packets into one moving road.
 *
 * The phone sends the truth once a second. Making that look like motion is this
 * side's job, because only this side knows its own frame rate. The Swift
 * simulator does exactly the same thing in VisorSim/Sources/PathView.swift, and
 * the two are meant to stay recognisably the same piece of reasoning.
 *
 * No ESP-IDF headers here either: this is arithmetic and it is tested on a
 * desktop.
 */
#ifndef VISOR_VIEW_H
#define VISOR_VIEW_H

#include <stdbool.h>
#include <stdint.h>

#include "visor_packet.h"

/* How much road the panel holds. Fixed, so the scale never moves.
 *
 * Sizing the drawing to whatever happened to arrive means every packet that
 * reaches a little further redraws the world at a new scale, which reads as
 * violent motion where there was none.
 */
#define VISOR_VIEW_AHEAD_M 300.0f
#define VISOR_VIEW_BEHIND_M 60.0f

/* Points the road is redrawn with. Both packets are resampled to this many so
 * they can be crossed between; the wire's own points are unevenly spaced and
 * there is no sensible pairing otherwise.
 */
#define VISOR_VIEW_SAMPLES 64

/* Past this, a junction that has moved is not the same junction: the last one
 * has been ridden through and this is the next, several hundred meters on.
 * Sliding the marker up the road would be a lie about a turn.
 */
#define VISOR_VIEW_SAME_JUNCTION_M 100.0f

typedef struct {
    float right_m;
    float ahead_m;
} visor_xy_t;

typedef struct {
    visor_xy_t road[VISOR_VIEW_SAMPLES];
    bool has_junction;
    visor_xy_t junction;
} visor_view_t;

/* Where the road is between the previous packet and the newest one.
 *
 * `crossing` runs 0 at the moment the newest packet landed to 1 a whole packet
 * interval later. Pass NULL for `previous` before a second packet has arrived.
 */
void visor_view_between(const visor_path_t *previous,
                        const visor_path_t *latest,
                        float crossing,
                        visor_view_t *out);

/* How far through the crossing the clock says we are, clamped to 0...1.
 *
 * Microseconds, because that is what esp_timer_get_time returns and converting
 * it somewhere else would only invite a unit mistake.
 */
float visor_view_crossing(int64_t now_us, int64_t arrived_us, int64_t interval_us);

/* Meters to pixels: one scale for both axes, and a rider who never moves.
 *
 * Stretching the picture to fill the panel would turn a gentle bend into a hard
 * one, which is the one thing a map on a HUD must never do.
 */
typedef struct {
    float scale;    /* pixels per meter */
    float centre_x; /* pixels */
    float rider_y;  /* pixels */
} visor_frame_t;

visor_frame_t visor_frame_make(int width, int height);
float visor_frame_x(const visor_frame_t *frame, float right_m);
float visor_frame_y(const visor_frame_t *frame, float ahead_m);

#endif /* VISOR_VIEW_H */
