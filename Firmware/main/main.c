/* Visor HUD.
 *
 * Two packets come in over Bluetooth and a picture goes out to the glass. All
 * the thinking happened on the phone; what is left here is drawing it, and
 * doing it often enough that the road appears to move rather than to jump.
 */
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "visor_ble.h"
#include "visor_hud.h"
#include "visor_panel.h"

static const char *TAG = "visor";

/* Packets arrive on the Bluetooth host's task and the picture is drawn on this
 * one, so the state between them is guarded. The lock is held only long enough
 * to take a copy: rendering under it would leave the radio waiting on the
 * screen, and there is no reason the two should ever wait for each other. */
static visor_hud_state_t shared;
static SemaphoreHandle_t lock;

static void took_guidance(const uint8_t *data, size_t length, void *context)
{
    (void)context;
    xSemaphoreTake(lock, portMAX_DELAY);
    visor_hud_receive_guidance(&shared, data, length, esp_timer_get_time());
    xSemaphoreGive(lock);
}

static void took_path(const uint8_t *data, size_t length, void *context)
{
    (void)context;
    xSemaphoreTake(lock, portMAX_DELAY);
    visor_hud_receive_path(&shared, data, length, esp_timer_get_time());
    xSemaphoreGive(lock);
}

void app_main(void)
{
    esp_err_t nvs = nvs_flash_init();
    if (nvs == ESP_ERR_NVS_NO_FREE_PAGES || nvs == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        nvs = nvs_flash_init();
    }
    ESP_ERROR_CHECK(nvs);

    lock = xSemaphoreCreateMutex();
    visor_hud_reset(&shared);

    ESP_ERROR_CHECK(visor_panel_start());
    const visor_canvas_t *canvas = visor_panel_canvas();

    /* The screen comes up before the radio, so a display that never finds a
     * phone still shows that it is alive and waiting rather than staying dark
     * and looking broken. */
    visor_hud_render(canvas, &shared, esp_timer_get_time(), VISOR_PANEL_ROUND);
    visor_panel_present();

    visor_ble_start(took_guidance, took_path, NULL);
    ESP_LOGI(TAG, "waiting for a phone");

    static visor_hud_state_t frame;

    while (true) {
        xSemaphoreTake(lock, portMAX_DELAY);
        frame = shared;
        xSemaphoreGive(lock);

        /* Redrawn far more often than packets arrive, which is the whole point:
         * the phone sends the truth once a second and this is what turns it
         * into motion. */
        visor_hud_render(canvas, &frame, esp_timer_get_time(), VISOR_PANEL_ROUND);
        visor_panel_present();

        vTaskDelay(pdMS_TO_TICKS(20));
    }
}
