// Tesstats push microservice
// ----------------------------------------------------------------------------
// OPTIONAL. Bridges TeslaMate MQTT events to Apple Push Notifications (APNs) so
// the Tesstats app receives IMMEDIATE alerts (e.g. a possible Sentry event) even
// when it is closed. The app works fine without this — it just relies on local
// notifications while running. See README.md for setup.
//
// Zero third-party deps except `mqtt`. APNs auth (ES256 JWT) and the HTTP/2 push
// use Node's built-in `crypto`, `http2`, `http` and `fs`.

import mqtt from 'mqtt'
import http from 'node:http'
import http2 from 'node:http2'
import crypto from 'node:crypto'
import fs from 'node:fs'

// ---- Config (env) ----------------------------------------------------------
const cfg = {
  mqttUrl: process.env.MQTT_URL || 'mqtt://mosquitto:1883',   // mqtt(s)/ws(s)
  mqttUser: process.env.MQTT_USERNAME || '',
  mqttPass: process.env.MQTT_PASSWORD || '',
  basicAuth: process.env.MQTT_BASIC_AUTH || '',               // "user:pass" for wss reverse proxy
  topicRoot: process.env.TOPIC_ROOT || 'teslamate/cars',
  httpPort: parseInt(process.env.PORT || '8090', 10),
  registerToken: process.env.REGISTER_TOKEN || '',            // shared secret the app must send
  tokensFile: process.env.TOKENS_FILE || './tokens.json',
  // APNs
  apnsKeyPath: process.env.APNS_KEY_PATH || '',               // AuthKey_XXXX.p8
  apnsKeyId: process.env.APNS_KEY_ID || '',
  apnsTeamId: process.env.APNS_TEAM_ID || '',
  bundleId: process.env.APNS_BUNDLE_ID || 'com.tesstats.app',
  production: (process.env.APNS_PRODUCTION || 'false') === 'true',
  // Which events to push
  notifySentry: (process.env.NOTIFY_SENTRY || 'true') === 'true',
  notifyUnlocked: (process.env.NOTIFY_UNLOCKED || 'true') === 'true',
  notifyOpenings: (process.env.NOTIFY_OPENINGS || 'true') === 'true',
}

// ---- Device token store ----------------------------------------------------
let tokens = new Set()
try { tokens = new Set(JSON.parse(fs.readFileSync(cfg.tokensFile, 'utf8'))) } catch {}
const saveTokens = () => { try { fs.writeFileSync(cfg.tokensFile, JSON.stringify([...tokens])) } catch (e) { console.error('save tokens', e) } }

// ---- APNs (HTTP/2 + ES256 JWT) --------------------------------------------
let apnsJwt = { token: null, iat: 0 }
function apnsAuthToken() {
  const now = Math.floor(Date.now() / 1000)
  if (apnsJwt.token && now - apnsJwt.iat < 2400) return apnsJwt.token // reuse < 40 min
  const key = fs.readFileSync(cfg.apnsKeyPath, 'utf8')
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: cfg.apnsKeyId }))
  const claims = b64url(JSON.stringify({ iss: cfg.apnsTeamId, iat: now }))
  const signer = crypto.createSign('SHA256')
  signer.update(`${header}.${claims}`)
  const sig = signer.sign({ key, dsaEncoding: 'ieee-p1363' })
  apnsJwt = { token: `${header}.${claims}.${b64urlBuf(sig)}`, iat: now }
  return apnsJwt.token
}
const b64url = (s) => Buffer.from(s).toString('base64url')
const b64urlBuf = (b) => b.toString('base64url')

function pushAll(title, body, extra = {}) {
  if (!cfg.apnsKeyPath) { console.log('[push skipped — no APNs key]', title, body); return }
  const host = cfg.production ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com'
  const payload = JSON.stringify({
    aps: { alert: { title, body }, sound: 'default', 'interruption-level': 'time-sensitive' },
    ...extra,
  })
  let jwt
  try { jwt = apnsAuthToken() } catch (e) { console.error('APNs JWT error', e); return }
  const client = http2.connect(host)
  client.on('error', (e) => console.error('APNs conn', e.message))
  for (const token of tokens) {
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      'authorization': `bearer ${jwt}`,
      'apns-topic': cfg.bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
    })
    let status = 0
    req.on('response', (h) => { status = h[':status'] })
    let data = ''
    req.on('data', (d) => data += d)
    req.on('end', () => {
      if (status !== 200) {
        console.warn('APNs', status, data)
        if (status === 410 || /BadDeviceToken/.test(data)) { tokens.delete(token); saveTokens() } // prune dead tokens
      }
    })
    req.end(payload)
  }
  setTimeout(() => client.close(), 4000)
}

// ---- Event detection from MQTT --------------------------------------------
const cars = {} // carId -> { name, lastCenterDisplay, locked, anyOpen, parked }

function handle(carId, metric, value) {
  const c = (cars[carId] ||= { name: `Car ${carId}` })
  switch (metric) {
    case 'display_name': c.name = value; break
    case 'shift_state': c.parked = (value !== 'D' && value !== 'R'); break
    case 'center_display_state': {
      const v = parseInt(value, 10)
      if (cfg.notifySentry && c.lastCenterDisplay !== 7 && v === 7) {
        pushAll('Possible Sentry event',
          `${c.name} showed the Sentry banner. Inferred from the screen — any clip is on the car's USB.`,
          { carId, event: 'sentry' })
      }
      c.lastCenterDisplay = v
      break
    }
    case 'locked': {
      const locked = value === 'true'
      if (cfg.notifyUnlocked && c.locked === true && !locked && c.parked) {
        pushAll('Vehicle unlocked', `${c.name} was unlocked while parked.`, { carId, event: 'unlocked' })
      }
      c.locked = locked
      break
    }
    case 'doors_open': case 'frunk_open': case 'trunk_open': case 'windows_open': {
      const open = value === 'true'
      if (cfg.notifyOpenings && open && c.parked) {
        pushAll('Something is open', `${metric.replace('_', ' ')} on ${c.name} is open.`, { carId, event: 'open' })
      }
      break
    }
  }
}

// ---- MQTT ------------------------------------------------------------------
const mqttOptions = { reconnectPeriod: 5000 }
if (cfg.mqttUser) { mqttOptions.username = cfg.mqttUser; mqttOptions.password = cfg.mqttPass }
if (cfg.basicAuth) {
  mqttOptions.wsOptions = { headers: { Authorization: 'Basic ' + Buffer.from(cfg.basicAuth).toString('base64') } }
}
const client = mqtt.connect(cfg.mqttUrl, mqttOptions)
client.on('connect', () => {
  console.log('MQTT connected:', cfg.mqttUrl)
  client.subscribe(`${cfg.topicRoot}/+/#`)
})
client.on('error', (e) => console.error('MQTT error', e.message))
client.on('message', (topic, payload) => {
  const rest = topic.startsWith(cfg.topicRoot + '/') ? topic.slice(cfg.topicRoot.length + 1) : null
  if (!rest) return
  const i = rest.indexOf('/')
  if (i < 0) return
  const carId = rest.slice(0, i)
  const metric = rest.slice(i + 1)
  handle(carId, metric, payload.toString())
})

// ---- HTTP: token registration ---------------------------------------------
const httpServer = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/register') {
    let body = ''
    req.on('data', (d) => { body += d; if (body.length > 1e4) req.destroy() })
    req.on('end', () => {
      try {
        const { token, secret } = JSON.parse(body || '{}')
        if (cfg.registerToken && secret !== cfg.registerToken) { res.writeHead(401).end('unauthorized'); return }
        if (typeof token === 'string' && /^[0-9a-fA-F]{64,}$/.test(token)) {
          tokens.add(token); saveTokens()
          res.writeHead(200).end('ok')
        } else {
          res.writeHead(400).end('bad token')
        }
      } catch { res.writeHead(400).end('bad json') }
    })
  } else if (req.method === 'GET' && req.url === '/healthz') {
    res.writeHead(200).end(JSON.stringify({ ok: true, tokens: tokens.size }))
  } else {
    res.writeHead(404).end()
  }
})
httpServer.listen(cfg.httpPort, () => console.log('HTTP listening on', cfg.httpPort))
