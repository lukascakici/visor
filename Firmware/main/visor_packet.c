#include "visor_packet.h"

#include <string.h>

static uint16_t read_u16(const uint8_t *data)
{
    return (uint16_t)((uint16_t)data[0] | ((uint16_t)data[1] << 8));
}

static int16_t read_i16(const uint8_t *data)
{
    return (int16_t)read_u16(data);
}

/* Where to cut a UTF-8 string so the cut lands between characters.
 *
 * The phone already sizes the name to the link, so this normally does nothing.
 * It earns its keep when a display with a small MTU meets a street like
 * Semsettin Gunaltay: half of a S with a cedilla is not a shorter name, it is a
 * broken one, and half the streets in Istanbul have such a letter in them.
 */
static size_t utf8_boundary(const uint8_t *text, size_t length)
{
    while (length > 0 && (text[length] & 0xC0) == 0x80) {
        length--;
    }
    return length;
}

bool visor_guidance_decode(const uint8_t *data, size_t length, visor_guidance_t *out)
{
    if (data == NULL || out == NULL || length < VISOR_GUIDANCE_HEADER) {
        return false;
    }

    out->version = data[0];
    out->maneuver = data[1];
    out->distance_to_maneuver_m = read_u16(data + 2);
    out->distance_remaining_m = (uint32_t)read_u16(data + 4) * 10u;
    out->time_remaining_s = read_u16(data + 6);
    out->speed_kmh = data[8];
    out->flags = data[9];

    size_t name = length - VISOR_GUIDANCE_HEADER;
    if (name > VISOR_STREET_MAX - 1) {
        name = utf8_boundary(data + VISOR_GUIDANCE_HEADER, VISOR_STREET_MAX - 1);
    }
    memcpy(out->street, data + VISOR_GUIDANCE_HEADER, name);
    out->street[name] = '\0';

    return true;
}

bool visor_path_decode(const uint8_t *data, size_t length, visor_path_t *out)
{
    if (data == NULL || out == NULL || length < VISOR_PATH_HEADER) {
        return false;
    }

    out->version = data[0];

    /* Three numbers have a say in how many points there are: what the packet
     * promised, what actually arrived, and what there is room for here. The
     * smallest of them wins, and none of the three is trusted over the others.
     */
    size_t promised = data[1];
    size_t arrived = (length - VISOR_PATH_HEADER) / VISOR_PATH_POINT_SIZE;
    size_t count = promised < arrived ? promised : arrived;
    if (count > VISOR_PATH_MAX_POINTS) {
        count = VISOR_PATH_MAX_POINTS;
    }
    out->count = (uint8_t)count;

    for (size_t index = 0; index < count; index++) {
        const uint8_t *point = data + VISOR_PATH_HEADER + index * VISOR_PATH_POINT_SIZE;
        out->points[index].right_dm = read_i16(point);
        out->points[index].ahead_dm = read_i16(point + 2);
    }

    /* A junction at a point that did not arrive is no junction. Drawing the
     * turn at whichever bend happens to sit at that index would put it
     * somewhere the road does not turn.
     */
    out->maneuver_index = data[2] < count ? (int16_t)data[2] : -1;

    return true;
}
