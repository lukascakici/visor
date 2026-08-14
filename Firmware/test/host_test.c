/* Runs the parts of the firmware that have no hardware in them.
 *
 * Decoding, the frame, the crossing between packets and the whole rasteriser
 * are plain C over plain memory, so they run here rather than only on a bench
 * with a phone in one hand. The byte sequences below are the ones the Swift
 * tests in Visor/Tests/TransportTests produce; if the two sides ever drift
 * apart, this is where it shows.
 *
 *     cd Firmware/test && ./run.sh
 */
#include <math.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "visor_draw.h"
#include "visor_hud.h"
#include "visor_packet.h"
#include "visor_view.h"

static int failures = 0;
static int checks = 0;

static void check(int passed, const char *what)
{
    checks++;
    if (!passed) {
        failures++;
        printf("  FAIL  %s\n", what);
    }
}

static void check_near(float actual, float expected, float tolerance, const char *what)
{
    checks++;
    float difference = actual - expected;
    if (difference < 0) {
        difference = -difference;
    }
    if (difference > tolerance) {
        failures++;
        printf("  FAIL  %s (got %.3f, wanted %.3f)\n", what, actual, expected);
    }
}

/* --- the wire ------------------------------------------------------------- */

/* Right in 100 m, 600 m and 80 s to go, 43 km/h, on "Bagdat". */
static const uint8_t GUIDANCE[] = {
    0x01, 0x04, 0x64, 0x00, 0x3C, 0x00, 0x50, 0x00, 0x2B, 0x00,
    'B', 'a', 'g', 'd', 'a', 't',
};

/* Coming from 100 m behind, straight to a junction 50 m ahead, then 120 m to
 * the right. The same three points the Swift packet tests use. */
static const uint8_t PATH[] = {
    /* Byte 3: the rider is 100 m along a 270 m line, which is 94 of 255. */
    0x01, 0x03, 0x01, 0x5E,
    0x00, 0x00, 0x18, 0xFC,
    0x00, 0x00, 0xF4, 0x01,
    0xB0, 0x04, 0xF4, 0x01,
};

static void test_guidance(void)
{
    printf("guidance packet\n");

    visor_guidance_t out;
    check(visor_guidance_decode(GUIDANCE, sizeof(GUIDANCE), &out), "decodes");
    check(out.version == 1, "version");
    check(out.maneuver == VISOR_MANEUVER_RIGHT, "maneuver is right");
    check(out.distance_to_maneuver_m == 100, "100 m to the turn");
    check(out.distance_remaining_m == 600, "tens of meters scaled back up");
    check(out.time_remaining_s == 80, "80 seconds out");
    check(out.speed_kmh == 43, "43 km/h");
    check(strcmp(out.street, "Bagdat") == 0, "street name");

    check(!visor_guidance_decode(GUIDANCE, 9, &out), "nine bytes is not a packet");

    /* A header with nothing after it is a packet with no name, not a broken
     * one: plenty of roads have no name worth sending. */
    check(visor_guidance_decode(GUIDANCE, 10, &out), "header alone decodes");
    check(out.street[0] == '\0', "and carries an empty name");

    /* Leniency, deliberately: a version this build has never seen still
     * arrives, because a display showing nothing is worse than one showing a
     * field it read generously. */
    uint8_t future[sizeof(GUIDANCE)];
    memcpy(future, GUIDANCE, sizeof(GUIDANCE));
    future[0] = 9;
    future[1] = 200;
    check(visor_guidance_decode(future, sizeof(future), &out), "an unknown version decodes");
    check(out.version == 9 && out.maneuver == 200, "and is reported as it came");
}

static void test_street_truncation(void)
{
    printf("street truncation\n");

    /* A name of two-byte characters, longer than there is room for. Cutting it
     * mid-character would leave a broken string on screen. */
    uint8_t packet[VISOR_GUIDANCE_HEADER + 200];
    memset(packet, 0, sizeof(packet));
    packet[0] = 1;
    for (size_t index = 0; index < 200; index += 2) {
        packet[VISOR_GUIDANCE_HEADER + index] = 0xC5;     /* leading byte */
        packet[VISOR_GUIDANCE_HEADER + index + 1] = 0x9E; /* continuation */
    }

    visor_guidance_t out;
    check(visor_guidance_decode(packet, sizeof(packet), &out), "decodes");

    size_t length = strlen(out.street);
    check(length < VISOR_STREET_MAX, "fits");
    check(length % 2 == 0, "cut on a character boundary");
    for (size_t index = 0; index < length; index += 2) {
        check((unsigned char)out.street[index] == 0xC5, "leading byte intact");
    }
}

static void test_path(void)
{
    printf("path packet\n");

    visor_path_t out;
    check(visor_path_decode(PATH, sizeof(PATH), &out), "decodes");
    check(out.count == 3, "three points");
    check(out.maneuver_index == 1, "the junction is the second of them");
    check(out.points[0].right_dm == 0 && out.points[0].ahead_dm == -1000, "100 m behind");
    check(out.points[1].right_dm == 0 && out.points[1].ahead_dm == 500, "50 m ahead");
    check(out.points[2].right_dm == 1200 && out.points[2].ahead_dm == 500, "120 m to the right");

    check(!visor_path_decode(PATH, 3, &out), "three bytes is not a packet");

    /* Says three points, carries one and a half. The one that made it is still
     * road worth drawing; the junction it named is not there to draw. */
    check(visor_path_decode(PATH, VISOR_PATH_HEADER + 6, &out), "a short write still decodes");
    check(out.count == 1, "yields what arrived");
    check(out.maneuver_index == -1, "and drops a junction that did not");
}

/* --- the frame ------------------------------------------------------------ */

static void test_view(void)
{
    printf("frame and crossing\n");

    visor_path_t path;
    visor_path_decode(PATH, sizeof(PATH), &path);

    visor_view_t view;
    visor_view_between(NULL, &path, 1.0f, &view);

    check(view.has_junction, "the junction is drawn");
    check_near(view.junction.ahead_m, 50.0f, 0.01f, "50 m ahead");
    check_near(view.junction.right_m, 0.0f, 0.01f, "dead ahead");

    /* Resampling walks the road end to end, so the ends have to be the ends. */
    check_near(view.road[0].ahead_m, -100.0f, 0.5f, "starts behind the rider");
    check_near(view.road[VISOR_VIEW_SAMPLES - 1].right_m, 120.0f, 0.5f, "ends off to the right");

    /* Spread evenly by length, which is what makes two packets comparable
     * point for point. The road is 150 m up and 120 m across, so every step
     * should be 270/63 m long wherever it falls, corner included. */
    float step = 270.0f / (float)(VISOR_VIEW_SAMPLES - 1);
    for (int index = 1; index < VISOR_VIEW_SAMPLES; index++) {
        float right = view.road[index].right_m - view.road[index - 1].right_m;
        float ahead = view.road[index].ahead_m - view.road[index - 1].ahead_m;
        float length = sqrtf(right * right + ahead * ahead);
        /* The one step that straddles the corner is shorter across the chord
         * than along the road, which is the only slack allowed here. */
        check(length <= step + 0.01f && length > step * 0.7f, "an even step along the road");
    }

    float crossing = visor_view_crossing(1500000, 1000000, 1000000);
    check_near(crossing, 0.5f, 0.001f, "halfway between packets");
    check_near(visor_view_crossing(5000000, 1000000, 1000000), 1.0f, 0.001f, "and never past the newest");
    check_near(visor_view_crossing(900000, 1000000, 1000000), 0.0f, 0.001f, "nor before it");

    visor_frame_t frame = visor_frame_make(240, 240);
    check_near(visor_frame_x(&frame, 0.0f), 120.0f, 0.01f, "the rider is centred");
    check_near(visor_frame_y(&frame, 0.0f), 240.0f * VISOR_VIEW_RIDER, 0.01f,
               "and sits low, with the road ahead of them");
    check_near(visor_frame_y(&frame, VISOR_VIEW_AHEAD_M), 0.0f, 0.01f,
               "and the road ahead reaches the top of the panel");
    check(visor_frame_y(&frame, 100.0f) < visor_frame_y(&frame, 0.0f), "ahead is up the panel");
    check(visor_frame_x(&frame, 10.0f) > visor_frame_x(&frame, 0.0f), "right is to the right");
}

static void test_crossing_moves_the_road(void)
{
    printf("the road moves rather than jumps\n");

    /* The same junction, 20 m closer. Crossing the two has to land between
     * them, not on either. */
    uint8_t nearer[sizeof(PATH)];
    memcpy(nearer, PATH, sizeof(PATH));
    nearer[10] = 0x2C; /* 300 dm ahead */
    nearer[11] = 0x01;
    nearer[14] = 0x2C;
    nearer[15] = 0x01;

    visor_path_t before, after;
    visor_path_decode(PATH, sizeof(PATH), &before);
    visor_path_decode(nearer, sizeof(nearer), &after);

    visor_view_t view;
    visor_view_between(&before, &after, 0.5f, &view);
    check_near(view.junction.ahead_m, 40.0f, 0.5f, "the marker is halfway between the two");

    visor_view_between(&before, &after, 0.0f, &view);
    check_near(view.junction.ahead_m, 50.0f, 0.5f, "at the start it is where it was");

    visor_view_between(&before, &after, 1.0f, &view);
    check_near(view.junction.ahead_m, 30.0f, 0.5f, "at the end it is where it is");
}

static void test_a_new_junction_does_not_slide(void)
{
    printf("a junction that is a different junction\n");

    /* The turn has been ridden through and the next one is 400 m on. Easing the
     * marker up the road would draw a turn where there is none. */
    uint8_t far[sizeof(PATH)];
    memcpy(far, PATH, sizeof(PATH));
    far[10] = 0xA0; /* 4000 dm ahead */
    far[11] = 0x0F;

    visor_path_t before, after;
    visor_path_decode(PATH, sizeof(PATH), &before);
    visor_path_decode(far, sizeof(far), &after);

    visor_view_t view;
    visor_view_between(&before, &after, 0.5f, &view);
    check_near(view.junction.ahead_m, 400.0f, 0.5f, "it snaps to the new one");
}

/* --- the screen ----------------------------------------------------------- */

#define WIDTH 240
#define HEIGHT 240

static uint16_t pixels[WIDTH * HEIGHT];

/* Writes what the panel would show. On round glass the corners are not dark,
 * they are absent, so masking them out here is the only way to see what a rider
 * would actually see. */
static void write_image(const char *name, bool round)
{
    FILE *file = fopen(name, "wb");
    if (file == NULL) {
        return;
    }

    fprintf(file, "P6\n%d %d\n255\n", WIDTH, HEIGHT);
    for (int index = 0; index < WIDTH * HEIGHT; index++) {
        uint16_t pixel = pixels[index];
        if (round) {
            float dx = (float)(index % WIDTH) - WIDTH / 2.0f;
            float dy = (float)(index / WIDTH) - HEIGHT / 2.0f;
            if (dx * dx + dy * dy > (WIDTH / 2.0f) * (WIDTH / 2.0f)) {
                pixel = visor_rgb(26, 26, 30);
            }
        }
        unsigned char rgb[3] = {
            (unsigned char)(((pixel >> 11) & 0x1F) * 255 / 31),
            (unsigned char)(((pixel >> 5) & 0x3F) * 255 / 63),
            (unsigned char)((pixel & 0x1F) * 255 / 31),
        };
        fwrite(rgb, 1, 3, file);
    }
    fclose(file);
}

static int lit_pixels(void)
{
    int lit = 0;
    for (int index = 0; index < WIDTH * HEIGHT; index++) {
        if (pixels[index] != 0) {
            lit++;
        }
    }
    return lit;
}

/* Whether a pixel is something a rider is meant to read, rather than the ground
 * it is drawn on. The band runs to the edge of the glass on purpose, the way a
 * chord does; what must never run off it is a number, an arrow or a road. */
static bool is_content(uint16_t pixel)
{
    int r = ((pixel >> 11) & 0x1F) * 255 / 31;
    int g = ((pixel >> 5) & 0x3F) * 255 / 63;
    int b = (pixel & 0x1F) * 255 / 31;
    int brightest = r > g ? (r > b ? r : b) : (g > b ? g : b);
    return brightest > 150;
}

static int content_pixels(void)
{
    int lit = 0;
    for (int index = 0; index < WIDTH * HEIGHT; index++) {
        if (is_content(pixels[index])) {
            lit++;
        }
    }
    return lit;
}

/* Anything readable outside the glass is something a rider will never see. */
static int lit_off_the_glass(void)
{
    int lost = 0;
    float radius = WIDTH / 2.0f;

    for (int index = 0; index < WIDTH * HEIGHT; index++) {
        if (!is_content(pixels[index])) {
            continue;
        }
        float dx = (float)(index % WIDTH) - radius;
        float dy = (float)(index / WIDTH) - radius;
        if (dx * dx + dy * dy > radius * radius) {
            lost++;
        }
    }
    return lost;
}

static void test_screen(void)
{
    printf("the screen\n");

    visor_canvas_t canvas = { pixels, WIDTH, HEIGHT };
    visor_hud_state_t state;
    visor_hud_reset(&state);

    visor_hud_render(&canvas, &state, 0, VISOR_PANEL_ROUND);
    check(lit_pixels() > 0, "with no packets the panel is still laid out");
    // Nothing to read, and nothing pretending there is. The rider chevron is
    // the only bright thing a silent display shows.
    int quiet = content_pixels();

    visor_hud_receive_guidance(&state, GUIDANCE, sizeof(GUIDANCE));
    visor_hud_receive_path(&state, PATH, sizeof(PATH), 1000000);
    visor_hud_render(&canvas, &state, 1000000, VISOR_PANEL_ROUND);

    check(content_pixels() > quiet * 3, "a packet gives it a great deal to say");
    write_image("hud.ppm", true);

    /* The road is drawn in the road colour and the alarm colour never appears
     * unless the phone says the route has been left. */
    int alarm = 0;
    for (int index = 0; index < WIDTH * HEIGHT; index++) {
        if (pixels[index] == visor_rgb(255, 60, 50)) {
            alarm++;
        }
    }
    check(alarm == 0, "nothing is red on a clean ride");

    uint8_t off_route[sizeof(GUIDANCE)];
    memcpy(off_route, GUIDANCE, sizeof(GUIDANCE));
    off_route[9] = VISOR_FLAG_OFF_ROUTE;
    visor_hud_receive_guidance(&state, off_route, sizeof(off_route));
    visor_hud_render(&canvas, &state, 1000000, VISOR_PANEL_ROUND);

    alarm = 0;
    for (int index = 0; index < WIDTH * HEIGHT; index++) {
        if (pixels[index] == visor_rgb(255, 60, 50)) {
            alarm++;
        }
    }
    check(alarm > 100, "and a good deal is once the route has been left");
    write_image("hud-off-route.ppm", true);
}

/* Nothing in the layout is written in pixels, so a denser panel should cost a
 * number and nothing else. This renders the same packets onto the 466 pixel
 * AMOLED those round boards also come with, and writes it out to be looked at.
 */
#define DENSE 466
static uint16_t dense_pixels[DENSE * DENSE];

static void test_denser_glass(void)
{
    printf("a denser panel\n");

    visor_canvas_t canvas = { dense_pixels, DENSE, DENSE };
    visor_hud_state_t state;
    visor_hud_reset(&state);

    visor_hud_receive_guidance(&state, GUIDANCE, sizeof(GUIDANCE));
    visor_hud_receive_path(&state, PATH, sizeof(PATH), 1000000);
    visor_hud_render(&canvas, &state, 1000000, VISOR_PANEL_ROUND);

    int lost = 0;
    float radius = DENSE / 2.0f;
    for (int index = 0; index < DENSE * DENSE; index++) {
        if (!is_content(dense_pixels[index])) {
            continue;
        }
        float dx = (float)(index % DENSE) - radius;
        float dy = (float)(index / DENSE) - radius;
        if (dx * dx + dy * dy > radius * radius) {
            lost++;
        }
    }
    check(lost == 0, "the layout holds at a different size without being told");

    FILE *file = fopen("hud-466.ppm", "wb");
    if (file != NULL) {
        fprintf(file, "P6\n%d %d\n255\n", DENSE, DENSE);
        for (int index = 0; index < DENSE * DENSE; index++) {
            uint16_t pixel = dense_pixels[index];
            float dx = (float)(index % DENSE) - radius;
            float dy = (float)(index / DENSE) - radius;
            if (dx * dx + dy * dy > radius * radius) {
                pixel = visor_rgb(26, 26, 30);
            }
            unsigned char rgb[3] = {
                (unsigned char)(((pixel >> 11) & 0x1F) * 255 / 31),
                (unsigned char)(((pixel >> 5) & 0x3F) * 255 / 63),
                (unsigned char)((pixel & 0x1F) * 255 / 31),
            };
            fwrite(rgb, 1, 3, file);
        }
        fclose(file);
    }
}

/* Straight ahead, no junction: 100 m of road behind and 300 m in front. */
static const uint8_t STRAIGHT[] = {
    /* 100 m of a 400 m line is behind the rider: 64 of 255. */
    0x01, 0x03, 0xFF, 0x40,
    0x00, 0x00, 0x18, 0xFC,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xB8, 0x0B,
};

/* The rider and the road are both white, and a white marker on a white road is
 * no marker at all. What keeps them apart is a dark edge around the rider, and
 * it is the sort of thing that goes missing in a layout change without anyone
 * noticing until they are riding.
 */
static void test_the_rider_stays_visible_on_the_road(void)
{
    printf("the rider against the road\n");

    visor_canvas_t canvas = { pixels, WIDTH, HEIGHT };
    visor_hud_state_t state;
    visor_hud_reset(&state);

    visor_hud_receive_guidance(&state, GUIDANCE, sizeof(GUIDANCE));
    visor_hud_receive_path(&state, STRAIGHT, sizeof(STRAIGHT), 1000000);
    visor_hud_render(&canvas, &state, 1000000, VISOR_PANEL_ROUND);

    /* Walked up the middle rather than across it. The road is narrower than the
     * rider is wide, so sideways the marker simply covers it; the join that has
     * to stay visible is the one straight ahead, where the road runs out from
     * under the rider's nose. */
    int centre = WIDTH / 2;
    int y = (int)((float)HEIGHT * VISOR_VIEW_RIDER);

    check(is_content(pixels[y * WIDTH + centre]), "the rider is drawn");

    while (y > 0 && is_content(pixels[y * WIDTH + centre])) {
        y--;
    }

    int gap = 0;
    while (y > 0 && !is_content(pixels[y * WIDTH + centre])) {
        gap++;
        y--;
    }

    check(gap > 0, "a dark edge follows it");
    check(y > 0 && is_content(pixels[y * WIDTH + centre]), "and then the road resumes");
}

/* Where the road behind ends and the road ahead begins is told, not deduced.
 *
 * The obvious deduction is to look for the point nearest the origin, and it
 * fails exactly where it matters: past a sharp corner the road ahead swings
 * back across the rider and wins the comparison, so most of the way forward
 * gets drawn as the way already ridden, and flickers between the two as the
 * geometry shifts.
 */
static void test_the_rider_is_where_the_packet_says(void)
{
    printf("where the rider sits on the line\n");

    uint8_t packet[sizeof(PATH)];
    memcpy(packet, PATH, sizeof(PATH));

    visor_path_t path;
    visor_view_t view;

    check(visor_path_decode(packet, sizeof(packet), &path), "decodes");
    check(path.rider == 0x5E, "the byte comes through untouched");

    visor_view_between(NULL, &path, 1.0f, &view);
    check(view.rider == (int)((94.0f / 255.0f) * (VISOR_VIEW_SAMPLES - 1) + 0.5f),
          "and lands on the sample the fraction names");

    /* A fraction of a line is the same fraction however many points it is
     * drawn with, so the ends have to be the ends. */
    packet[3] = 0;
    visor_path_decode(packet, sizeof(packet), &path);
    visor_view_between(NULL, &path, 1.0f, &view);
    check(view.rider == 0, "nothing behind means nothing drawn as behind");

    packet[3] = 255;
    visor_path_decode(packet, sizeof(packet), &path);
    visor_view_between(NULL, &path, 1.0f, &view);
    check(view.rider == VISOR_VIEW_SAMPLES - 1, "and all of it behind means all of it");
}

/* The layout has to hold on round glass, and the awkward case is a four figure
 * distance in the narrowest part of the panel. */
static void test_round_glass(void)
{
    printf("round glass\n");

    visor_canvas_t canvas = { pixels, WIDTH, HEIGHT };
    visor_hud_state_t state;
    visor_hud_reset(&state);

    uint8_t far[sizeof(GUIDANCE)];
    memcpy(far, GUIDANCE, sizeof(GUIDANCE));
    far[2] = 0x0F; /* 9999 m, the widest the field can be */
    far[3] = 0x27;

    visor_hud_receive_guidance(&state, far, sizeof(far));
    visor_hud_receive_path(&state, PATH, sizeof(PATH), 1000000);
    visor_hud_render(&canvas, &state, 1000000, VISOR_PANEL_ROUND);

    check(lit_off_the_glass() == 0, "nothing is drawn where there is no glass");
    write_image("hud-round-9999.ppm", true);

    /* And the road itself, which is the one thing allowed past the edge: a
     * turn 300 m out and 400 m to the side genuinely runs off the panel, and
     * cropping it is what the glass does. */
    visor_hud_render(&canvas, &state, 1000000, VISOR_PANEL_SQUARE);
    check(lit_pixels() > 0, "a square panel draws the same layout");
}

static void test_numbers(void)
{
    printf("numbers\n");

    visor_canvas_t canvas = { pixels, WIDTH, HEIGHT };
    visor_draw_fill(&canvas, 0);

    visor_pt_t at = { 10.0f, 10.0f };
    float width = visor_draw_number(&canvas, 1250, at, 60.0f, visor_rgb(255, 255, 255));

    check_near(width, visor_draw_number_width(1250, 60.0f), 0.01f, "the width it reports is the width it drew");
    check(lit_pixels() > 500, "four digits leave a mark");

    /* Every digit has to be distinguishable from every other, or a distance is
     * a guess. Comparing the pixels each one lights is a crude way of saying
     * so, and it is enough to catch a wrong segment table. */
    int lit[10];
    for (int digit = 0; digit < 10; digit++) {
        visor_draw_fill(&canvas, 0);
        visor_pt_t single = { 20.0f, 20.0f };
        visor_draw_number(&canvas, (uint32_t)digit, single, 80.0f, visor_rgb(255, 255, 255));
        lit[digit] = lit_pixels();
        check(lit[digit] > 0, "the digit is drawn");
    }
    check(lit[1] < lit[8], "one is thinner than eight");
    check(lit[7] < lit[8], "and so is seven");
}

/* How long a frame takes to draw, which is the question a bigger panel actually
 * raises. Memory is not the constraint on a module with PSRAM; filling four
 * times as many pixels thirty times a second is.
 *
 * Measured here on a desktop, so the absolute numbers mean nothing for the
 * device. The ratio between the two sizes is what transfers, and that is what
 * this prints.
 */
static void bench(void)
{
    struct {
        int size;
        uint16_t *pixels;
    } panels[2] = { { WIDTH, pixels }, { DENSE, dense_pixels } };

    visor_hud_state_t state;
    visor_hud_reset(&state);
    visor_hud_receive_guidance(&state, GUIDANCE, sizeof(GUIDANCE));
    visor_hud_receive_path(&state, PATH, sizeof(PATH), 1000000);

    printf("\nframe cost\n");
    for (int index = 0; index < 2; index++) {
        visor_canvas_t canvas = { panels[index].pixels, panels[index].size, panels[index].size };

        clock_t started = clock();
        int frames = 400;
        for (int frame = 0; frame < frames; frame++) {
            visor_hud_render(&canvas, &state, 1000000 + frame * 25000, VISOR_PANEL_ROUND);
        }
        double each = (double)(clock() - started) / CLOCKS_PER_SEC / frames;

        printf("  %3dx%-3d  %6.3f ms a frame  (%.0f fps)\n",
               panels[index].size, panels[index].size, each * 1000.0, 1.0 / each);
    }
}

int main(int argc, char **argv)
{
    test_guidance();
    test_street_truncation();
    test_path();
    test_view();
    test_crossing_moves_the_road();
    test_a_new_junction_does_not_slide();
    test_numbers();
    test_screen();
    test_the_rider_is_where_the_packet_says();
    test_the_rider_stays_visible_on_the_road();
    test_round_glass();
    test_denser_glass();

    printf("\n%d checks, %d failures\n", checks, failures);

    if (argc > 1 && strcmp(argv[1], "bench") == 0) {
        bench();
    }

    return failures == 0 ? 0 : 1;
}
