# Tesstats Push Microservice (optional)

Bridges TeslaMate **MQTT → Apple Push Notifications (APNs)** so Tesstats gets
**immediate alerts even when the app is closed** — most importantly a *possible
Sentry event* (inferred from `center_display_state == 7`), plus optional
"unlocked while parked" and "something open" alerts.

> **Why this is optional.** iOS cannot reliably poll in the background, so the app
> alone can only raise local notifications while it is running. For guaranteed,
> instant alerts with the app closed you need a tiny always-on server that listens
> to MQTT and pushes to APNs. That's this service. If you don't run it, the app
> still works — it just uses local notifications with that limitation.

## What you need

1. An **Apple Developer account** (for the APNs Auth Key) and the app installed via
   Xcode/TestFlight with the **Push Notifications** capability enabled.
2. An **APNs Auth Key** (`.p8`): Apple Developer → *Certificates, Identifiers & Profiles*
   → *Keys* → **+** → enable **Apple Push Notifications service (APNs)** → download the
   `AuthKey_XXXXXXXXXX.p8`. Note the **Key ID** and your **Team ID**.

## Run with Docker (alongside TeslaMate)

Add to your existing `docker-compose.yml` (same network as `mosquitto`):

```yaml
  tesstats-push:
    build: ./tesstats-push        # or image: yourrepo/tesstats-push
    restart: always
    environment:
      - MQTT_URL=mqtt://mosquitto:1883
      - MQTT_USERNAME=tesstats
      - MQTT_PASSWORD=<your-mqtt-pass>
      - TOPIC_ROOT=teslamate/cars
      - PORT=8090
      - REGISTER_TOKEN=<long-random-secret>
      - APNS_KEY_PATH=/keys/AuthKey_ABCDE12345.p8
      - APNS_KEY_ID=ABCDE12345
      - APNS_TEAM_ID=YOURTEAMID
      - APNS_BUNDLE_ID=com.tesstats.app
      - APNS_PRODUCTION=false
    volumes:
      - ./tesstats-push/keys:/keys:ro
      - ./tesstats-push/data:/app/data
    depends_on:
      - mosquitto
```

Expose `tesstats-push:8090` through your reverse proxy (e.g. `push.example.com`)
**with Basic Auth / TLS** so the app can register its device token.

## How the app uses it

1. In **Tesstats → Settings → Alerts**, enable **Immediate push** and set the
   **Push service URL** (e.g. `https://push.example.com`) and the **shared secret**
   (`REGISTER_TOKEN`).
2. The app asks iOS for a device token and `POST`s it to `…/register`:
   ```json
   { "token": "<apns-device-token>", "secret": "<REGISTER_TOKEN>" }
   ```
3. This service watches MQTT and pushes to every registered token when an event fires.
   Dead tokens (HTTP 410 / BadDeviceToken) are pruned automatically.

## Endpoints

- `POST /register` — `{ token, secret }` → stores the device token.
- `GET  /healthz`  — `{ ok, tokens }`.

## Events

| Event | Trigger | Env toggle |
|---|---|---|
| Possible Sentry | `center_display_state` becomes `7` | `NOTIFY_SENTRY` |
| Unlocked while parked | `locked` true→false while not driving | `NOTIFY_UNLOCKED` |
| Something open | door/frunk/trunk/window opens while parked | `NOTIFY_OPENINGS` |

## Honesty

- The Sentry alert is an **inference** from the car's screen state. TeslaMate does
  not expose a dedicated Sentry event, and the **video clip lives on the car's USB**
  — it is not available through TeslaMate or this service.
- Tesla does not expose battery **pack temperature** to third parties, so it isn't
  available in TeslaMate or here.
