# The ESP-IDF side. Build with `idf.py set-target esp32s3 && idf.py build`.
#
# The files with no hardware in them are also compiled by the macOS simulator
# and by Firmware/test, so they are kept free of ESP-IDF headers on purpose.
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(visor-hud)
