/* The radio, as the display sees it.
 *
 * Advertises the Visor service and hands whatever the phone writes to a
 * callback. Nothing above this file knows a thing about NimBLE, and nothing in
 * it knows a thing about roads.
 */
#ifndef VISOR_BLE_H
#define VISOR_BLE_H

#include <stddef.h>
#include <stdint.h>

/* Called from the Bluetooth host's own task, not from whatever called
 * `visor_ble_start`. Whatever it touches has to be safe to touch from there. */
typedef void (*visor_ble_write_fn)(const uint8_t *data, size_t length, void *context);

void visor_ble_start(visor_ble_write_fn on_guidance, visor_ble_write_fn on_path, void *context);

#endif /* VISOR_BLE_H */
