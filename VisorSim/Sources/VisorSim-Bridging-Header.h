/* The firmware, compiled into the simulator.
 *
 * The point is that the preview cannot drift. Redrawing the device's screen in
 * Swift would give two implementations of one layout, and the one on the Mac
 * would quietly stop being the one on the glass. This way the pixels on screen
 * are the pixels the ESP32 would push, produced by the same C.
 *
 * Only the files with no hardware in them are compiled here; the NimBLE and
 * panel drivers stay on the device where they belong.
 */
#include "visor_draw.h"
#include "visor_hud.h"
#include "visor_packet.h"
#include "visor_view.h"
