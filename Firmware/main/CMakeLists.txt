idf_component_register(
    SRCS
        "main.c"
        "visor_ble.c"
        "visor_panel.c"
        "visor_packet.c"
        "visor_view.c"
        "visor_draw.c"
        "visor_hud.c"
    INCLUDE_DIRS "."
    REQUIRES bt driver esp_lcd esp_timer nvs_flash
)
