#include "visor_ble.h"

#include <string.h>

#include "esp_log.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "visor_packet.h"

static const char *TAG = "visor-ble";

/* The same three identifiers the phone has, byte for byte.
 *
 * NimBLE takes 128-bit UUIDs least significant byte first, which is the reverse
 * of how they are written down. A1B2C3D4-0001-... ends in A1 here and begins
 * with it on the other side; getting that backwards produces a service nobody
 * can find and no error message anywhere.
 */
static const ble_uuid128_t SERVICE_UUID = BLE_UUID128_INIT(
    0x90, 0x8A, 0x7E, 0x2D, 0x3C, 0x5F, 0x1E, 0x9B,
    0x6F, 0x4A, 0x01, 0x00, 0xD4, 0xC3, 0xB2, 0xA1);

static const ble_uuid128_t GUIDANCE_UUID = BLE_UUID128_INIT(
    0x90, 0x8A, 0x7E, 0x2D, 0x3C, 0x5F, 0x1E, 0x9B,
    0x6F, 0x4A, 0x02, 0x00, 0xD4, 0xC3, 0xB2, 0xA1);

static const ble_uuid128_t PATH_UUID = BLE_UUID128_INIT(
    0x90, 0x8A, 0x7E, 0x2D, 0x3C, 0x5F, 0x1E, 0x9B,
    0x6F, 0x4A, 0x03, 0x00, 0xD4, 0xC3, 0xB2, 0xA1);

#define ADVERTISED_NAME "Visor HUD"

static visor_ble_write_fn guidance_handler;
static visor_ble_write_fn path_handler;
static void *handler_context;
static uint8_t own_address_type;

static void advertise(void);

/* Both characteristics arrive here. The largest thing either can carry is a
 * full path packet, and anything longer than that is not one of ours. */
static int on_write(uint16_t connection, uint16_t attribute, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)connection;
    (void)attribute;
    (void)arg;

    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    static uint8_t buffer[VISOR_PATH_HEADER + VISOR_PATH_MAX_POINTS * VISOR_PATH_POINT_SIZE];
    uint16_t length = 0;

    int status = ble_hs_mbuf_to_flat(ctxt->om, buffer, sizeof(buffer), &length);
    if (status != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    if (ble_uuid_cmp(ctxt->chr->uuid, &PATH_UUID.u) == 0) {
        if (path_handler != NULL) {
            path_handler(buffer, length, handler_context);
        }
    } else if (guidance_handler != NULL) {
        guidance_handler(buffer, length, handler_context);
    }

    return 0;
}

static const struct ble_gatt_svc_def SERVICES[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &SERVICE_UUID.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &GUIDANCE_UUID.u,
                .access_cb = on_write,
                /* Write without response, and nothing else. There is nothing
                 * useful to say back, and declaring it this way makes it
                 * impossible for the phone to wait on an acknowledgement that
                 * would never matter. */
                .flags = BLE_GATT_CHR_F_WRITE_NO_RSP,
            },
            {
                .uuid = &PATH_UUID.u,
                .access_cb = on_write,
                .flags = BLE_GATT_CHR_F_WRITE_NO_RSP,
            },
            { 0 },
        },
    },
    { 0 },
};

static int on_gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;

    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        ESP_LOGI(TAG, "connect: %s", event->connect.status == 0 ? "phone is here" : "failed");
        if (event->connect.status != 0) {
            advertise();
        }
        break;

    case BLE_GAP_EVENT_DISCONNECT:
        /* Straight back to advertising. A rider who rides out of range and back
         * again should not have to touch anything. */
        ESP_LOGI(TAG, "disconnect, advertising again");
        advertise();
        break;

    case BLE_GAP_EVENT_MTU:
        /* Worth logging: this one number decides how much road fits in a
         * packet. At the default 23 the display gets four points of it. */
        ESP_LOGI(TAG, "mtu is now %d", event->mtu.value);
        break;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise();
        break;

    default:
        break;
    }

    return 0;
}

static void advertise(void)
{
    /* The name goes in the scan response rather than the advertisement.
     *
     * An advertisement holds 31 bytes. Flags take 3 and a 128-bit service UUID
     * takes 18, and "Visor HUD" needs 11 more, which is one too many. The UUID
     * is the part that cannot move: it is what the phone scans for. */
    struct ble_hs_adv_fields advertisement;
    memset(&advertisement, 0, sizeof(advertisement));
    advertisement.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    advertisement.uuids128 = (ble_uuid128_t *)&SERVICE_UUID;
    advertisement.num_uuids128 = 1;
    advertisement.uuids128_is_complete = 1;

    int status = ble_gap_adv_set_fields(&advertisement);
    if (status != 0) {
        ESP_LOGE(TAG, "advertisement rejected: %d", status);
        return;
    }

    struct ble_hs_adv_fields response;
    memset(&response, 0, sizeof(response));
    response.name = (uint8_t *)ADVERTISED_NAME;
    response.name_len = strlen(ADVERTISED_NAME);
    response.name_is_complete = 1;
    ble_gap_adv_rsp_set_fields(&response);

    struct ble_gap_adv_params params;
    memset(&params, 0, sizeof(params));
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;

    status = ble_gap_adv_start(own_address_type, NULL, BLE_HS_FOREVER, &params, on_gap_event, NULL);
    if (status != 0) {
        ESP_LOGE(TAG, "could not advertise: %d", status);
    }
}

static void on_sync(void)
{
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &own_address_type);
    advertise();
}

static void on_reset(int reason)
{
    ESP_LOGE(TAG, "bluetooth reset, reason %d", reason);
}

static void host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void visor_ble_start(visor_ble_write_fn on_guidance, visor_ble_write_fn on_path, void *context)
{
    guidance_handler = on_guidance;
    path_handler = on_path;
    handler_context = context;

    ESP_ERROR_CHECK(nimble_port_init());

    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;

    ble_svc_gap_init();
    ble_svc_gatt_init();

    ESP_ERROR_CHECK(ble_gatts_count_cfg(SERVICES));
    ESP_ERROR_CHECK(ble_gatts_add_svcs(SERVICES));
    ESP_ERROR_CHECK(ble_svc_gap_device_name_set(ADVERTISED_NAME));

    /* Ask for everything the standard allows. iOS decides in the end, but a
     * display that never asks is stuck at 23 bytes a write, which is four
     * points of road and a street name cut to nine letters. */
    ble_att_set_preferred_mtu(517);

    nimble_port_freertos_init(host_task);
}
