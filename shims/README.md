# Self-hosted AI shims

Small FastAPI containers that give the iPad app the same JSON contracts it
already uses for BYOK providers, backed by self-hosted models. Deployed with
`docker compose` on the NAS (no OpenAI account needed for these features).

## Stack (`docker compose up -d --build`)

| Service       | Port   | Endpoint                  | Backend                       |
|---------------|--------|---------------------------|-------------------------------|
| rembg-openai  | 19538  | `POST /v1/images/edits`   | rembg (u2net)                 |
| pix2tex-openai| 19539  | `POST /v1/math/ocr`       | pix2tex LaTeX-OCR             |

Both require `Authorization: Bearer <key>`. Set the shared key in a `.env`
file next to `docker-compose.yml`:

```ini
SHIM_API_KEY=change-me
```

Without a key the shims accept anonymous requests (fine for a private LAN).

## Contracts

### Background removal — `POST /v1/images/edits`

Multipart form. Returns transparent PNG in OpenAI Images edits shape, which the
app's existing OpenAI-compatible client already parses.

```
curl -X POST http://nas:19538/v1/images/edits \
  -H "Authorization: Bearer change-me" \
  -F image=@photo.jpg
# => { "created": 0, "data": [ { "b64_json": "iVBORw0..." } ] }
```

### Math OCR — `POST /v1/math/ocr`

Multipart `image` (crop of an equation). Returns LaTeX.

```
curl -X POST http://nas:19539/v1/math/ocr \
  -H "Authorization: Bearer change-me" \
  -F image=@equation.png
# => { "latex": "\\int_0^1 x^2\\,dx" }
```

## Exposing publicly

The stack binds to `0.0.0.0` on the NAS LAN. For the app to reach it from
cellular, add Cloudflare Tunnels (DNS records e.g. `rembg.<domain>` and
`mathocr.<domain>`) pointing each to `http://localhost:19538` / `19539`. The app
onboarding accepts any base URL + key, so the tunnels need no app-side changes.