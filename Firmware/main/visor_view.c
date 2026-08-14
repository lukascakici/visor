#include "visor_view.h"

#include <math.h>
#include <stddef.h>

static visor_xy_t meters(visor_point_t point)
{
    visor_xy_t out;
    out.right_m = (float)point.right_dm / 10.0f;
    out.ahead_m = (float)point.ahead_dm / 10.0f;
    return out;
}

static visor_xy_t between(visor_xy_t a, visor_xy_t b, float fraction)
{
    visor_xy_t out;
    out.right_m = a.right_m + (b.right_m - a.right_m) * fraction;
    out.ahead_m = a.ahead_m + (b.ahead_m - a.ahead_m) * fraction;
    return out;
}

static float span(visor_xy_t a, visor_xy_t b)
{
    float right = b.right_m - a.right_m;
    float ahead = b.ahead_m - a.ahead_m;
    return sqrtf(right * right + ahead * ahead);
}

/* The same road as VISOR_VIEW_SAMPLES points spread evenly along its length. */
static void resample(const visor_path_t *path, visor_xy_t *out)
{
    if (path == NULL || path->count == 0) {
        for (int index = 0; index < VISOR_VIEW_SAMPLES; index++) {
            out[index].right_m = 0.0f;
            out[index].ahead_m = 0.0f;
        }
        return;
    }

    if (path->count == 1) {
        visor_xy_t only = meters(path->points[0]);
        for (int index = 0; index < VISOR_VIEW_SAMPLES; index++) {
            out[index] = only;
        }
        return;
    }

    /* Distance along the road at each of its own points, which is what turns
     * "a fraction of the way along" into a position. */
    float travelled[VISOR_PATH_MAX_POINTS];
    travelled[0] = 0.0f;
    for (int index = 1; index < path->count; index++) {
        travelled[index] = travelled[index - 1]
            + span(meters(path->points[index - 1]), meters(path->points[index]));
    }

    float total = travelled[path->count - 1];
    if (total <= 0.0f) {
        visor_xy_t only = meters(path->points[0]);
        for (int index = 0; index < VISOR_VIEW_SAMPLES; index++) {
            out[index] = only;
        }
        return;
    }

    int segment = 1;
    for (int step = 0; step < VISOR_VIEW_SAMPLES; step++) {
        float target = total * (float)step / (float)(VISOR_VIEW_SAMPLES - 1);
        while (segment < path->count - 1 && travelled[segment] < target) {
            segment++;
        }

        float length = travelled[segment] - travelled[segment - 1];
        float fraction = length > 0.0f ? (target - travelled[segment - 1]) / length : 0.0f;
        out[step] = between(meters(path->points[segment - 1]),
                            meters(path->points[segment]),
                            fraction);
    }
}

static bool marker(const visor_path_t *path, visor_xy_t *out)
{
    if (path == NULL || path->maneuver_index < 0 || path->maneuver_index >= path->count) {
        return false;
    }
    *out = meters(path->points[path->maneuver_index]);
    return true;
}

void visor_view_between(const visor_path_t *previous,
                        const visor_path_t *latest,
                        float crossing,
                        visor_view_t *out)
{
    if (out == NULL) {
        return;
    }

    out->has_junction = false;
    out->rider = 0;

    if (latest == NULL || latest->count == 0) {
        for (int index = 0; index < VISOR_VIEW_SAMPLES; index++) {
            out->road[index].right_m = 0.0f;
            out->road[index].ahead_m = 0.0f;
        }
        return;
    }

    if (crossing < 0.0f) {
        crossing = 0.0f;
    }
    if (crossing > 1.0f) {
        crossing = 1.0f;
    }

    /* The packet says where the rider is as a fraction of the whole line, which
     * survives resampling exactly: a fraction of a line is the same fraction
     * however many points it is drawn with. */
    out->rider = (int)(((float)latest->rider / 255.0f) * (float)(VISOR_VIEW_SAMPLES - 1) + 0.5f);
    if (out->rider < 0) {
        out->rider = 0;
    }
    if (out->rider > VISOR_VIEW_SAMPLES - 1) {
        out->rider = VISOR_VIEW_SAMPLES - 1;
    }

    visor_xy_t current[VISOR_VIEW_SAMPLES];
    resample(latest, current);

    /* With nothing to cross from, the newest road is the road. This is the
     * first packet of a ride, and there is nowhere to have come from. */
    if (previous == NULL || previous->count < 2) {
        for (int index = 0; index < VISOR_VIEW_SAMPLES; index++) {
            out->road[index] = current[index];
        }
    } else {
        visor_xy_t earlier[VISOR_VIEW_SAMPLES];
        resample(previous, earlier);
        for (int index = 0; index < VISOR_VIEW_SAMPLES; index++) {
            out->road[index] = between(earlier[index], current[index], crossing);
        }
    }

    visor_xy_t now;
    if (!marker(latest, &now)) {
        return;
    }

    visor_xy_t before;
    out->has_junction = true;
    out->junction = now;

    if (marker(previous, &before) && span(before, now) < VISOR_VIEW_SAME_JUNCTION_M) {
        out->junction = between(before, now, crossing);
    }
}

float visor_view_crossing(int64_t now_us, int64_t arrived_us, int64_t interval_us)
{
    if (interval_us < 100000) {
        interval_us = 100000;
    }

    float elapsed = (float)(now_us - arrived_us) / (float)interval_us;
    if (elapsed < 0.0f) {
        return 0.0f;
    }
    return elapsed > 1.0f ? 1.0f : elapsed;
}

visor_frame_t visor_frame_make(int width, int height)
{
    visor_frame_t frame;

    /* The rider never moves. That is the whole point of a fixed frame: the road
     * flows past a still rider, the way it does through a visor.
     *
     * The scale follows from where they sit: the road ahead has to reach the
     * top of the panel from there, and everything below is however much road
     * behind that leaves room for. */
    frame.rider_y = (float)height * VISOR_VIEW_RIDER;
    frame.scale = frame.rider_y / VISOR_VIEW_AHEAD_M;
    frame.centre_x = (float)width / 2.0f;

    return frame;
}

float visor_frame_x(const visor_frame_t *frame, float right_m)
{
    return frame->centre_x + right_m * frame->scale;
}

float visor_frame_y(const visor_frame_t *frame, float ahead_m)
{
    return frame->rider_y - ahead_m * frame->scale;
}
