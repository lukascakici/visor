#include "visor_panel.h"

#include "driver/spi_master.h"
#include "esp_heap_caps.h"
#include "esp_lcd_gc9a01.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static const char *TAG = "visor-panel";

/* Wired for a 1.28 inch round GC9A01 on an ESP32-S3.
 *
 * These are the numbers to change for a different board, and they are the only
 * ones: nothing else in the firmware is written in pixels or pins.
 */
#define PANEL_WIDTH 240
#define PANEL_HEIGHT 240
#define PIN_SCLK 10
#define PIN_MOSI 11
#define PIN_CS 9
#define PIN_DC 8
#define PIN_RESET 14
#define PIN_BACKLIGHT 2
#define PIXEL_CLOCK_HZ (40 * 1000 * 1000)

static esp_lcd_panel_handle_t panel;
static SemaphoreHandle_t sent;
static uint16_t *pixels;
static visor_canvas_t canvas;

static bool on_transfer_done(esp_lcd_panel_io_handle_t io,
                             esp_lcd_panel_io_event_data_t *event,
                             void *context)
{
    (void)io;
    (void)event;
    (void)context;

    BaseType_t woken = pdFALSE;
    xSemaphoreGiveFromISR(sent, &woken);
    return woken == pdTRUE;
}

esp_err_t visor_panel_start(void)
{
    sent = xSemaphoreCreateBinary();
    if (sent == NULL) {
        return ESP_ERR_NO_MEM;
    }

    /* Drawn into by the CPU and read out of by DMA, so it has to be memory both
     * can reach. On a board with PSRAM a larger panel's buffer goes there
     * instead; internal RAM is faster and this one fits. */
    pixels = heap_caps_malloc(PANEL_WIDTH * PANEL_HEIGHT * sizeof(uint16_t),
                              MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    if (pixels == NULL) {
        ESP_LOGE(TAG, "no room for a %dx%d framebuffer", PANEL_WIDTH, PANEL_HEIGHT);
        return ESP_ERR_NO_MEM;
    }

    canvas.pixels = pixels;
    canvas.width = PANEL_WIDTH;
    canvas.height = PANEL_HEIGHT;

    spi_bus_config_t bus = {
        .sclk_io_num = PIN_SCLK,
        .mosi_io_num = PIN_MOSI,
        .miso_io_num = -1,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = PANEL_WIDTH * PANEL_HEIGHT * sizeof(uint16_t),
    };
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));

    esp_lcd_panel_io_handle_t io = NULL;
    esp_lcd_panel_io_spi_config_t io_config = {
        .dc_gpio_num = PIN_DC,
        .cs_gpio_num = PIN_CS,
        .pclk_hz = PIXEL_CLOCK_HZ,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
        .spi_mode = 0,
        .trans_queue_depth = 4,
        .on_color_trans_done = on_transfer_done,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)SPI2_HOST, &io_config, &io));

    /* Only the two fields every ESP-IDF 5 release spells the same way. The
     * colour order enum was renamed along the way and its default is RGB in
     * both spellings, so leaving it out is what keeps this compiling across
     * versions. */
    esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = PIN_RESET,
        .bits_per_pixel = 16,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_gc9a01(io, &panel_config, &panel));

    ESP_ERROR_CHECK(esp_lcd_panel_reset(panel));
    ESP_ERROR_CHECK(esp_lcd_panel_init(panel));
    /* These two are the panel's own quirks rather than ours: a GC9A01 wired
     * this way comes up with its colours inverted and its rows the wrong way
     * up. If a board shows a photographic negative, this is the line. */
    ESP_ERROR_CHECK(esp_lcd_panel_invert_color(panel, true));
    ESP_ERROR_CHECK(esp_lcd_panel_mirror(panel, true, false));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panel, true));

#if PIN_BACKLIGHT >= 0
    gpio_set_direction(PIN_BACKLIGHT, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_BACKLIGHT, 1);
#endif

    ESP_LOGI(TAG, "panel up, %dx%d", PANEL_WIDTH, PANEL_HEIGHT);
    return ESP_OK;
}

const visor_canvas_t *visor_panel_canvas(void)
{
    return &canvas;
}

void visor_panel_present(void)
{
    /* The rasteriser works in the CPU's byte order and the panel wants the
     * other one. Swapped in place rather than into a second buffer, which
     * would double the memory for one frame's benefit: the next frame begins
     * by filling the whole canvas, so nothing ever reads these bytes back. */
    size_t count = (size_t)PANEL_WIDTH * PANEL_HEIGHT;
    for (size_t index = 0; index < count; index++) {
        uint16_t pixel = pixels[index];
        pixels[index] = (uint16_t)((pixel >> 8) | (pixel << 8));
    }

    ESP_ERROR_CHECK(esp_lcd_panel_draw_bitmap(panel, 0, 0, PANEL_WIDTH, PANEL_HEIGHT, pixels));
    xSemaphoreTake(sent, portMAX_DELAY);
}
