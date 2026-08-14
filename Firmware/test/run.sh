#!/bin/sh
# Builds and runs the parts of the firmware that have no hardware in them.
#
# No ESP-IDF, no toolchain, no board: these files were written so that decoding,
# the frame, the crossing between packets and the rasteriser could be checked
# here rather than only on a bench.
#
# Writes hud.ppm and hud-off-route.ppm next to itself, which is the fastest way
# to see what the display would actually look like.
set -e

cd "$(dirname "$0")"

cc -std=c99 -Wall -Wextra -Werror -O1 \
    -I../main \
    host_test.c ../main/visor_packet.c ../main/visor_view.c ../main/visor_draw.c ../main/visor_hud.c \
    -lm -o host_test

./host_test
