/* Reading what the phone writes.
 *
 * The mirror image of the Swift encoders in Visor/Sources/Transport. Every
 * layout decision on this side was made on the other one, which is why there is
 * no parser here worth the name: fixed offsets, little-endian, no floats.
 *
 * Nothing in this file includes an ESP-IDF header. It compiles and runs on a
 * desktop, which is where its tests run.
 */
#ifndef VISOR_PACKET_H
#define VISOR_PACKET_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Guidance packet, version 1:
 *
 *   byte  0      protocol version
 *   byte  1      maneuver type
 *   bytes 2...3  distance to the maneuver, uint16, meters
 *   bytes 4...5  distance to the destination, uint16, tens of meters
 *   bytes 6...7  time to the destination, uint16, seconds
 *   byte  8      speed, uint8, km/h
 *   byte  9      flags
 *   byte 10...   street name, UTF-8, to the end of the packet
 */
#define VISOR_GUIDANCE_HEADER 10

/* Path packet, version 1:
 *
 *   byte  0      protocol version
 *   byte  1      number of points
 *   byte  2      index of the maneuver point, 255 for none
 *   byte  3      padding, zero
 *   bytes 4...   points, each int16 right then int16 ahead, decimeters
 */
#define VISOR_PATH_HEADER 4
#define VISOR_PATH_POINT_SIZE 4
#define VISOR_PATH_NO_MANEUVER 0xFF

/* A write can carry no more than this even at the largest MTU iOS negotiates,
 * and the phone never builds a longer one. Points past it are dropped rather
 * than overrunning: the road gets shorter, which is survivable, instead of the
 * stack getting shorter, which is not.
 */
#define VISOR_PATH_MAX_POINTS 128

/* Street names are cut to fit here. Long enough for anything the phone sends at
 * a normal MTU; the cut, if it ever happens, lands on a character boundary.
 */
#define VISOR_STREET_MAX 64

typedef enum {
    VISOR_MANEUVER_UNKNOWN = 0,
    VISOR_MANEUVER_DEPART = 1,
    VISOR_MANEUVER_STRAIGHT = 2,
    VISOR_MANEUVER_SLIGHT_RIGHT = 3,
    VISOR_MANEUVER_RIGHT = 4,
    VISOR_MANEUVER_SHARP_RIGHT = 5,
    VISOR_MANEUVER_SLIGHT_LEFT = 6,
    VISOR_MANEUVER_LEFT = 7,
    VISOR_MANEUVER_SHARP_LEFT = 8,
    VISOR_MANEUVER_UTURN = 9,
    VISOR_MANEUVER_ARRIVE = 10,
    VISOR_MANEUVER_COUNT
} visor_maneuver_t;

#define VISOR_FLAG_OFF_ROUTE (1u << 0)
#define VISOR_FLAG_REROUTING (1u << 1)
#define VISOR_FLAG_WEAK_GPS  (1u << 2)

typedef struct {
    uint8_t version;
    /* Kept raw rather than as the enum. A maneuver this build has never heard
     * of still arrived, and saying so beats quietly calling it unknown. */
    uint8_t maneuver;
    uint16_t distance_to_maneuver_m;
    /* Already scaled up out of the tens of meters the wire carries. */
    uint32_t distance_remaining_m;
    uint16_t time_remaining_s;
    uint8_t speed_kmh;
    uint8_t flags;
    char street[VISOR_STREET_MAX];
} visor_guidance_t;

typedef struct {
    int16_t right_dm;
    int16_t ahead_dm;
} visor_point_t;

typedef struct {
    uint8_t version;
    uint8_t count;
    /* -1 when the packet named no junction, or named one that did not arrive. */
    int16_t maneuver_index;
    visor_point_t points[VISOR_PATH_MAX_POINTS];
} visor_path_t;

/* Both decoders are lenient in the same way the phone's are: a version this
 * build does not know is reported rather than refused, and a write that arrived
 * short of what it promised yields what did arrive. A display drawing a shorter
 * road is still guiding; one that draws nothing has given up.
 *
 * They return false only when there is not a whole header to read.
 */
bool visor_guidance_decode(const uint8_t *data, size_t length, visor_guidance_t *out);
bool visor_path_decode(const uint8_t *data, size_t length, visor_path_t *out);

#endif /* VISOR_PACKET_H */
