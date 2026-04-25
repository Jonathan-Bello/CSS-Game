# CSS-Game

Integración Godot + overlay web + backend Emis para chat contextual de CSS.

## 1) Submódulo backend (`backend/emis-backend`)

> Ruta del submódulo en este repo: `backend/emis-backend`.

### Inicializar/actualizar

```bash
git submodule sync -- backend/emis-backend
git submodule update --init --recursive backend/emis-backend
```

Si tu entorno bloquea SSH con GitHub, este repo ya deja el submódulo en HTTPS dentro de `.gitmodules`.

## 2) Endpoint real de chat (cómo identificarlo sin asumir ruta)

El cliente Godot **ya no asume una ruta fija**. Resuelve endpoint en este orden:

1. `EMIS_CHAT_ENDPOINT` (explícito)
2. propiedad exportada `chat_endpoint` (si se configuró)
3. auto-discovery vía OpenAPI (`/openapi.json`, `/docs/openapi.json`)
4. fallback por candidatos (`EMIS_CHAT_ENDPOINTS` o lista local)

Contrato actual del cliente:

- Método HTTP: `POST`
- `Content-Type: application/json`
- Body (request):

```json
{
  "contract_version": "emis_chat_v1",
  "message": "¿Cómo mejoro el contraste del botón?",
  "context": {
    "contract_version": "emis_chat_v1",
    "css_text": ".btn{color:#fff;background:#333}",
    "svg_text": "<svg>...</svg>",
    "bullet_equipped": true,
    "updated_at": "2026-04-25T00:00:00Z",
    "detected_properties": ["color", "background"],
    "css_rules": ["color", "background"],
    "locked_properties": ["position"],
    "unlock_state": {},
    "all_properties": ["color", "background", "border"]
  }
}
```

Response aceptada por el cliente (200-299):

```json
{ "reply": "Sube el contraste cambiando el fondo a #1f2937." }
```

o también:

```json
{ "message": "Sube el contraste cambiando el fondo a #1f2937." }
```

## 3) Levantar backend en `127.0.0.1:8080`

Desde el raíz del proyecto principal:

```bash
cd backend/emis-backend
```

Luego ejecuta el comando de arranque definido por el backend (por ejemplo `docker compose up`, `npm run dev`, `uvicorn ...`, etc.).

El requisito para el cliente Godot es que el backend quede accesible en:

- Base URL: `http://127.0.0.1:8080`
- Endpoint: el detectado por auto-discovery o el indicado en variables de entorno.

## 4) Variables de entorno necesarias

Variables consumidas por `EmisClient`:

- `EMIS_BASE_URL` (opcional): sobreescribe `base_url`.
  - Ejemplo: `EMIS_BASE_URL=http://127.0.0.1:8080`
- `EMIS_CHAT_ENDPOINT` (opcional): endpoint explícito de chat.
  - Ejemplo: `EMIS_CHAT_ENDPOINT=/api/chat`
- `EMIS_CHAT_ENDPOINTS` (opcional): candidatos separados por coma para auto-probing.
  - Ejemplo: `EMIS_CHAT_ENDPOINTS=/api/chat,/chat,/v1/chat`

Si defines `EMIS_CHAT_ENDPOINT`, esa ruta tiene prioridad.

## 5) Guía de prueba manual (overlay chat)

1. Levanta el backend Emis en `127.0.0.1:8080`.
2. Ejecuta el proyecto Godot.
3. Abre el overlay web donde aparece el panel **💬 Emis (chatbot)**.
4. Envía un mensaje de prueba (ej. “¿qué propiedad CSS desbloqueo primero?”).
5. Verifica en consola Godot:
   - log de envío: `"[Emis] solicitud -> ..."`
   - endpoint resuelto: `"[Emis] endpoint ..."`
   - log de respuesta: `"[Emis] respuesta <- ..."`
6. Valida en UI:
   - aparece burbuja del usuario,
   - aparece estado “Emis escribiendo…”,
   - aparece burbuja de respuesta Emis,
   - el input se vuelve a habilitar.
7. Prueba manejo de error:
   - apaga backend,
   - envía otro mensaje,
   - debe mostrarse mensaje de falla controlada en overlay.

## 6) Comprobación rápida por cURL

Con endpoint explícito:

```bash
curl -sS -X POST "http://127.0.0.1:8080/api/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "contract_version":"emis_chat_v1",
    "message":"hola emis",
    "context":{"css_text":".btn{color:#fff}","svg_text":"<svg></svg>"}
  }'
```

Si no conoces la ruta, revisa OpenAPI:

```bash
curl -sS http://127.0.0.1:8080/openapi.json
curl -sS http://127.0.0.1:8080/docs/openapi.json
```
