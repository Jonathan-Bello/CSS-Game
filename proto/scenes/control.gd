extends Control

@onready var panel: PanelContainer = $PanelContainer
@onready var web: Control = $PanelContainer/WebView

@export var window_size: Vector2 = Vector2(900, 600)
@export var content_padding: int = 8

var last_css: String = ""
var last_svg: String = ""
var last_bullet_profile_path: String = ""
var _web_hydration_payload: Dictionary = {}

signal overlay_opened
signal overlay_closed

func _ready() -> void:
	add_to_group("web_overlay")
	visible = false
	panel.visible = false
	web.visible = false

	# Estado seguro WebView2
	web.set("url", "about:blank")
	web.set("transparent", true)
	web.set("devtools", true)

	if not web.is_connected("ipc_message", Callable(self , "_on_web_ipc_message")):
		web.connect("ipc_message", Callable(self , "_on_web_ipc_message"))

	_layout_and_sync()
	print("[WebOverlay] READY")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_and_sync()

func _layout_and_sync() -> void:
	var vp := get_viewport_rect().size
	panel.custom_minimum_size = window_size
	panel.size = window_size
	panel.position = (vp - panel.size) * 0.5

	web.position = panel.position + Vector2(content_padding, content_padding)
	web.size = panel.size - Vector2(content_padding * 2, content_padding * 2)

func _emit_overlay_opened() -> void:
	emit_signal("overlay_opened")

func _emit_overlay_closed() -> void:
	emit_signal("overlay_closed")

func open() -> void:
	print("[WebOverlay] open()")
	visible = true
	panel.visible = true
	web.visible = true

	# Mientras esté abierto, el panel debe “parar” el input de la escena
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	await get_tree().process_frame
	_layout_and_sync()
	_load_editor_html()
	web.call_deferred("focus")
	_emit_overlay_opened()
	print("[WebOverlay] open -> HTML cargado, focus defer")

func close() -> void:
	print("[WebOverlay] close()")

	# Quita el foco del WebView
	if web.has_method("focus_parent"):
		web.call_deferred("focus_parent")
	if web.has_method("unfocus"):
		web.call_deferred("unfocus")
	get_viewport().gui_release_focus()

	# Oculta overlay y deja de interceptar input
	web.visible = false
	panel.visible = false
	visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Limpia contenido para próximas aperturas
	web.set("html", "")
	web.set("url", "about:blank")

	_emit_overlay_closed()

func _input(ev: InputEvent) -> void:
	if visible and ev.is_action_pressed("ui_cancel"):
		close()

# -----------------------------
# SECRET / ENV HELPERS
# -----------------------------
func _read_env_file(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq == -1:
			continue
		var k := line.substr(0, eq).strip_edges()
		var v := line.substr(eq + 1).strip_edges()
		# Quita comillas si vienen
		if (v.begins_with("\"") and v.ends_with("\"")) or (v.begins_with("'") and v.ends_with("'")):
			v = v.substr(1, v.length() - 2)
		out[k] = v
	return out

func _get_secret(key_name: String) -> String:
	# 1) variable de entorno real (ideal)
	var v := OS.get_environment(key_name)
	if v != "":
		return v

	# 2) modo dev: leer .env (NO recomendado para producción)
	# Puedes decidir moverlo a user://.env para no empacarlo en export.
	var env_res := _read_env_file("res://.env")
	if env_res.has(key_name) and String(env_res[key_name]) != "":
		return String(env_res[key_name])

	var env_user := _read_env_file("user://.env")
	if env_user.has(key_name) and String(env_user[key_name]) != "":
		return String(env_user[key_name])

	return ""

func _inject_window_var(var_name: String, value: String) -> void:
	if value == "":
		return
	if not web.has_method("eval"):
		return

	# Escapar para JS string literal simple
	var safe := value
	safe = safe.replace("\\", "\\\\")
	safe = safe.replace("'", "\\'")
	safe = safe.replace("\n", "\\n")
	safe = safe.replace("\r", "")

	var js := "window.%s='%s';" % [var_name, safe]
	web.call_deferred("eval", js)

# -----------------------------
# HTML LOADER
# -----------------------------
func _load_editor_html() -> void:
	_web_hydration_payload = _read_bullet_hydration_payload()
	var html := """
<!doctype html>
<html><head><meta charset="utf-8"/>
<style>
  html,body{margin:0;background:transparent;color:#fff;font-family:sans-serif}
  .wrap{display:grid;grid-template-rows:auto 1fr; height:100vh}
  .bar{display:flex;gap:8px;padding:8px;background:#0b1222cc;border-bottom:1px solid #335;align-items:center}
  button{background:#4a90e2;border:0;color:#fff;padding:6px 10px;border-radius:6px;cursor:pointer}
  button:disabled{opacity:.5;cursor:wait}
  select{background:#123;color:#fff;border:1px solid #345;border-radius:6px;padding:6px}
  .main{display:grid;grid-template-columns:2fr 1fr;gap:12px;padding:8px;box-sizing:border-box;height:100%;min-height:0}
  .editor{display:grid;grid-template-rows:auto 1fr;gap:8px;min-height:0}
  textarea{width:100%;height:160px;margin:0;background:#0b1222;color:#bfe;border:1px solid #345;border-radius:8px;box-sizing:border-box;padding:8px}
  .locked-panel{background:#131a2d;border:1px solid #3a2333;border-radius:8px;padding:8px;max-height:150px;overflow:auto}
  .locked-title{font-size:12px;color:#ff9ba6;margin:0 0 6px}
  .locked-list{display:flex;flex-wrap:wrap;gap:6px}
  .locked-chip{font-size:12px;padding:2px 6px;border-radius:999px;background:#3b1f2c;color:#ff5f73;border:1px solid #7d3142}
  .code-hint{font-size:12px;color:#ffb4bf}
  .css-preview{margin:0;background:#0a1120;border:1px solid #2a3450;border-radius:8px;padding:8px;color:#c4e1ff;max-height:170px;overflow:auto;white-space:pre-wrap}
  .css-preview .locked-prop{color:#ff5f73;font-weight:700}
  .preview{display:flex;align-items:center;justify-content:center;background:linear-gradient(145deg,#0f1b33,#0b1222);border:1px solid #243049;border-radius:12px;box-shadow:0 8px 26px rgba(0,0,0,.4)}
  svg{display:block;margin:12px auto;filter:drop-shadow(0 8px 16px rgba(0,0,0,.45))}
  .chat{display:grid;grid-template-rows:auto 1fr auto auto;gap:8px;background:#0b1222cc;border:1px solid #243049;border-radius:12px;padding:10px;box-shadow:0 10px 24px rgba(0,0,0,.35);min-height:0;max-height:100%}
  .chat header{display:flex;align-items:center;gap:8px;font-weight:bold;letter-spacing:.5px;color:#eac435}
  .chat header span{font-size:12px;color:#b2c7ff}
  .log{overflow-y:auto;overflow-x:hidden;display:flex;flex-direction:column;gap:8px;padding-right:4px;min-height:0;max-height:360px}
  .msg{display:grid;gap:4px;background:#111b33b8;border:1px solid #243049;border-radius:10px;padding:8px}
  .msg.user{border-color:#4a90e2}
  .msg.ai{border-color:#eac43544;background:linear-gradient(135deg,#181e32,#0f1629)}
  .msg .who{font-size:12px;color:#9fb2e7;display:flex;align-items:center;gap:6px}
  .msg.ai .who{color:#eac435}
  .bubble{line-height:1.4}
  .chat form{display:flex;gap:8px}
  .chat input{flex:1;background:#0f1b33;border:1px solid #243049;border-radius:10px;color:#e6f3ff;padding:10px 12px}
  .aside-note{font-size:12px;color:#b2c7ff;margin:0;line-height:1.5}
</style></head>
<body>
  <div class="wrap">
	<div class="bar">
	  <select id="tpl" onchange="setTpl(this.value)">
		<option value="box">Caja</option>
		<option value="circle">Círculo</option>
		<option value="star">Estrella</option>
      </select>
	  <button onclick="saveCSS()">Guardar CSS</button>
	  <button onclick="makeSprite()">Crear Sprite</button>
	  <button onclick="ipc.postMessage('close')">Cerrar</button>
	  <span style="margin-left:auto;font-size:13px;color:#eac435">Mentora IA: Emmys (tono aventurera)</span>
    </div>

	<div class="main">
	  <div class="editor">
		<textarea id="css">/* edita el estilo */
svg{width:180px;height:180px}
#shape{fill:#5cf;stroke:#036;stroke-width:8px;filter:drop-shadow(0 6px 10px rgba(0,0,0,.5))}
</textarea>
		<p class="code-hint">Las propiedades bloqueadas se muestran en rojo y no aplican bonus de ataque.</p>
		<div class="locked-panel">
		  <p class="locked-title">Propiedades CSS bloqueadas (progreso)</p>
		  <div class="locked-list" id="lockedList"></div>
		</div>
		<pre class="css-preview" id="cssPreview"></pre>

		<div class="preview">
		  <svg id="svg" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
			<defs><style id="styleEl"></style></defs>
			<rect id="shape" x="28" y="28" width="200" height="200" rx="24" ry="24"/>
          </svg>
        </div>
      </div>

	  <div class="chat">
        <header>💬 Emmys, guardiana CSS <span>(consejos breves + ejemplos)</span></header>
		<div class="log" id="log"></div>
		<form id="chatForm">
		  <input id="msg" type="text" placeholder="Pregúntame sobre sombras, gradientes, animaciones..." autocomplete="off" />
		  <button type="submit">Pedir consejo</button>
        </form>
		<p class="aside-note">Emmys responde como un personaje del juego y se apoya en tu CSS actual para dar tips accionables.</p>
      </div>
    </div>
  </div>

<script>
const css = document.getElementById('css');
const svg = document.getElementById('svg');
const log = document.getElementById('log');
const form = document.getElementById('chatForm');
const msg = document.getElementById('msg');
const lockedList = document.getElementById('lockedList');
const cssPreview = document.getElementById('cssPreview');
let unlockState = {};
let allProperties = [];

function getStyleEl(){
  return document.getElementById('styleEl');
}

function applyCssToPreview(){
  const liveStyle = getStyleEl();
  if(!liveStyle) return;
  liveStyle.textContent = css.value;
  renderLockedInfo();
}

applyCssToPreview();
css.addEventListener('input', applyCssToPreview);
ipc.postMessage('html_loaded');

function escapeHtml(raw){
  if(typeof raw !== 'string') return '';
  return raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function getLockedPropertiesFromCss(text){
  const found = [];
  const seen = new Set();
  const parts = String(text || '').split(';');
  for(const rawChunk of parts){
    const chunk = rawChunk.trim();
    if(!chunk) continue;
    const idx = chunk.indexOf(':');
    if(idx === -1) continue;
    let key = chunk.slice(0, idx).trim().toLowerCase();
    if(key === 'background') key = 'background-color';
    if(!key) continue;
    const enabled = Boolean(unlockState[key]);
    if(!enabled && !seen.has(key)){
      seen.add(key);
      found.push(key);
    }
  }
  return found;
}

function renderLockedInfo(){
  const locked = getLockedPropertiesFromCss(css.value);
  if(lockedList){
    if(!locked.length){
      lockedList.innerHTML = '<span style=\"color:#88ffb0;font-size:12px\">Todo lo escrito está desbloqueado ✨</span>';
    }else{
      lockedList.innerHTML = locked.map((p)=>`<span class=\"locked-chip\">${escapeHtml(p)}</span>`).join('');
    }
  }
  if(cssPreview){
    const previewText = escapeHtml(css.value).replace(/([a-zA-Z-]+)[ \t]*:/g, (match, prop)=>{
      const normalized = prop.toLowerCase() === 'background' ? 'background-color' : prop.toLowerCase();
      if(!unlockState[normalized]){
        return `<span class=\"locked-prop\">${escapeHtml(prop)}</span>:`;
      }
      return `${escapeHtml(prop)}:`;
    });
    cssPreview.innerHTML = previewText;
  }
}

function _sanitizeForPreviewSvg(raw){
  if(typeof raw !== 'string') return '';
  return raw.replace(/<script[\\s\\S]*?>[\\s\\S]*?<\\/script>/gi, '');
}

function _extractShapeNode(nextSvg){
  if(!nextSvg) return null;
  return nextSvg.querySelector('#shape') || nextSvg.querySelector('rect,circle,ellipse,path,polygon,polyline,g');
}

function hydrateFromGodot(payload){
  if(!payload || typeof payload !== 'object') return;
  const nextCss = typeof payload.css_text === 'string' ? payload.css_text : '';
  const nextSvgText = typeof payload.svg_text === 'string' ? payload.svg_text : '';
  unlockState = (payload.unlock_state && typeof payload.unlock_state === 'object') ? payload.unlock_state : unlockState;
  allProperties = Array.isArray(payload.all_properties) ? payload.all_properties : allProperties;

  if(nextCss){
    css.value = nextCss;
  }

  if(nextSvgText){
    const safeSvg = _sanitizeForPreviewSvg(nextSvgText);
    const parsed = new DOMParser().parseFromString(safeSvg, 'image/svg+xml');
    const nextSvg = parsed.documentElement;
    const nextShape = _extractShapeNode(nextSvg);
    if(nextShape){
      while(svg.firstChild) svg.removeChild(svg.firstChild);
      const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
      const styleNode = document.createElementNS('http://www.w3.org/2000/svg', 'style');
      styleNode.setAttribute('id', 'styleEl');
      defs.appendChild(styleNode);
      svg.appendChild(defs);
      svg.appendChild(document.importNode(nextShape, true));
    }
  }

  applyCssToPreview();
}

function exportState(){
  return {
    css_text: css.value,
    svg_text: new XMLSerializer().serializeToString(svg)
  };
}

const persona = {
  name: 'Emmys',
  role: 'guardiana CSS del bastión de sprites',
  color: '#EAC435'
};

function addMsg(kind, text){
  const box = document.createElement('div');
  box.className = `msg ${kind}`;
  box.innerHTML = `<div class="who">${kind==='ai' ? '🦊 ' + persona.name : '🧑 Tú'}</div><div class="bubble">${text}</div>`;
  log.appendChild(box);
  log.scrollTop = log.scrollHeight;
}

async function callEmmysLLM(question){
  const apiUrl = 'https://api.openai.com/v1/chat/completions';

  // ✅ SOLO toma la key que inyecta Godot
  const apiKey = (typeof window !== 'undefined' && window.OPENAI_API_KEY) ? window.OPENAI_API_KEY : '';

  if(!apiKey){
    throw new Error('Falta window.OPENAI_API_KEY (inyéctala desde Godot).');
  }

  const cssNow = css.value;

  const body = {
    model: (typeof window !== 'undefined' && window.OPENAI_MODEL) ? window.OPENAI_MODEL : 'o3-mini',
    reasoning_effort: 'medium',
    max_completion_tokens: 180,
    messages: [
      {role: 'system', content: `Eres Emmys, guardiana CSS de un videojuego. Responde en tono aventurero, breve y con ejemplos. Color de firma ${persona.color}. Siempre usa el CSS actual que recibe para dar tips.`},
      {role: 'user', content: `CSS actual:\\n${cssNow}\\n\\nPregunta: ${question}`}
    ]
  };

  const res = await fetch(apiUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify(body)
  });

  if(!res.ok){
    throw new Error('Error del modelo: ' + res.status);
  }

  const data = await res.json();
  const reply = data?.choices?.[0]?.message?.content?.trim();
  if(!reply) throw new Error('Respuesta vacía del modelo');
  return reply;
}

function localFallback(question){
  const cssNow = css.value;
  const hints = [];
  if(/box-shadow/i.test(cssNow)) hints.push('Refuerza la luz con capas: box-shadow: 0 4px 12px rgba(0,0,0,.35), 0 0 0 4px rgba(234,196,53,.18);');
  if(/linear-gradient/i.test(cssNow)) hints.push('Usa stops cercanos (0%, 12%, 100%) para lograr brillo dorado y mantener legibilidad.');
  if(/animation/i.test(cssNow)) hints.push('Añade animation-fill-mode: forwards para conservar la pose final.');
  if(/stroke-width/i.test(cssNow)) hints.push('stroke-linejoin: round suaviza las esquinas heroicas.');
  if(!hints.length) hints.push('Puedes sumar glow: filter: drop-shadow(0 0 14px rgba(234,196,53,.55));');
  const focus = question.toLowerCase();
  let hook = 'Emmys aquí, brillo ámbar en mano: ';
  if(focus.includes('gradiente')||focus.includes('gradient')) hook += 'veo rutas de color que necesitan transición suave. ';
  else if(focus.includes('sombra')||focus.includes('shadow')) hook += 'las sombras cuentan de dónde viene tu luz. ';
  else if(focus.includes('anim')) hook += 'una animación corta mantiene el ritmo de la aventura. ';
  else hook += 'pulamos tu pieza con un truco rápido. ';
  const sample = '`#shape { transition: 160ms ease; transform-origin: 50% 60%; }`';
  return `${hook}${hints.join(' ')} Prueba también ${sample} para darle carácter.`;
}

async function sendToAI(evt){
  evt.preventDefault();
  const q = msg.value.trim();
  if(!q) return;
  addMsg('user', q);
  msg.value = '';
  const submitBtn = form.querySelector('button');
  submitBtn.disabled = true;

  try{
    const reply = await callEmmysLLM(q);
    addMsg('ai', reply);
  }catch(err){
    console.error(err);
    addMsg('ai', localFallback(q));
  }finally{
    submitBtn.disabled = false;
    ipc.postMessage(JSON.stringify({type:'ai_chat', question:q, css: css.value}));
  }
}

form.addEventListener('submit', sendToAI);
addMsg('ai', '¡Salud, creador! Soy Emmys, brillo ámbar (#EAC435). Muéstrame tu duda CSS y te daré un tip aventurero usando tu código actual.');

function setTpl(kind){
  let inner = '';
  if(kind==='box'){
	inner = '<rect id="shape" x="28" y="28" width="200" height="200" rx="24" ry="24"/>';
  }else if(kind==='circle'){
	inner = '<circle id="shape" cx="128" cy="128" r="96"/>';
  }else{
	inner = '<polygon id="shape" points="128,24 156,100 236,100 172,148 196,228 128,180 60,228 84,148 20,100 100,100"/>';
  }
  svg.innerHTML = '<defs><style id="styleEl"></style></defs>' + inner;
  applyCssToPreview();
}

function saveCSS(){
  const tpl = new XMLSerializer().serializeToString(svg);
  ipc.postMessage(JSON.stringify({type:'save_css', css: css.value, svg: tpl}));
}

function makeSprite(){
  const clone = svg.cloneNode(true);
  const cloneStyle = clone.querySelector('#styleEl');
  if(cloneStyle){
    cloneStyle.textContent = css.value;
  }
  const txt = new XMLSerializer().serializeToString(clone);
  const blob = new Blob([txt], {type:'image/svg+xml'});
  const url = URL.createObjectURL(blob);
  const img = new Image();
  img.onload = ()=>{
    const maxSize = 150;
    const sourceW = Math.max(1, img.naturalWidth || 256);
    const sourceH = Math.max(1, img.naturalHeight || 256);
    const ratio = Math.min(1, maxSize / Math.max(sourceW, sourceH));
    const outW = Math.max(1, Math.round(sourceW * ratio));
    const outH = Math.max(1, Math.round(sourceH * ratio));

    const c = document.createElement('canvas');
    c.width = outW;
    c.height = outH;
    c.getContext('2d').drawImage(img,0,0,c.width,c.height);
    const png = c.toDataURL('image/png');
    URL.revokeObjectURL(url);
    ipc.postMessage(JSON.stringify({type:'css_sprite', data_url: png, css: css.value, svg: txt, meta:{w:outW,h:outH,source_w:sourceW,source_h:sourceH}}));
  };
  img.onerror = ()=> ipc.postMessage('img_error');
  img.src = url;
}
</script>
</body></html>
"""
	web.call("load_html", html)

	# ✅ Inyecta secrets/modelo desde entorno o .env (sin dejarlos hardcodeados)
	var api_key := _get_secret("OPENAI_API_KEY")
	var model := _get_secret("OPENAI_MODEL") # opcional

	if api_key != "":
		_inject_window_var("OPENAI_API_KEY", api_key)
	else:
		push_warning("[WebOverlay] No hay OPENAI_API_KEY. Emmys usará fallback local.")

	if model != "":
		_inject_window_var("OPENAI_MODEL", model)

func _on_web_ipc_message(msg: String) -> void:
	print("[WebOverlay] ipc_message: ", msg)

	if msg == "close":
		close()
		return

	if msg == "html_loaded":
		print("[WebOverlay] HTML cargado")
		if not _web_hydration_payload.is_empty():
			_hydrate_web_editor(_web_hydration_payload)
			_web_hydration_payload = {}
		return

	if msg == "img_error":
		push_warning("[WebOverlay] Error rasterizando SVG")
		return

	var data: Variant = JSON.parse_string(msg)
	if typeof(data) == TYPE_DICTIONARY:
		match String(data.get("type", "")):
			"save_css":
				_save_css_draft(data)
			"css_sprite":
				_save_and_equip_bullet(data)
				close()

func _save_css_draft(data: Dictionary) -> void:
	last_css = String(data.get("css", ""))
	last_svg = String(data.get("svg", ""))
	print("[WebOverlay] CSS draft guardado (edición).")

func _save_and_equip_bullet(data: Dictionary) -> void:
	last_css = String(data.get("css", ""))
	last_svg = String(data.get("svg", ""))

	var data_url := String(data.get("data_url", ""))
	var prefix := "base64,"
	var base64_index := data_url.find(prefix)
	if base64_index == -1:
		push_warning("[WebOverlay] data_url inválida para bullet")
		return

	var bytes := Marshalls.base64_to_raw(data_url.substr(base64_index + prefix.length()))
	if bytes.is_empty():
		push_warning("[WebOverlay] PNG vacío para bullet")
		return

	var dir_path := "user://bullets"
	var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		push_warning("[WebOverlay] No se pudo crear directorio bullets. err=%s" % mkdir_err)
		return

	var image_path := "%s/bullet_current.png" % dir_path
	var profile_path := "%s/bullet_current.json" % dir_path

	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		push_warning("[WebOverlay] PNG inválido para bullet")
		return
	if image.save_png(image_path) != OK:
		push_warning("[WebOverlay] No se pudo guardar imagen bullet")
		return

	var meta: Dictionary = data.get("meta", {})
	var now_iso := Time.get_datetime_string_from_system(true, true)
	var existing_created_at := ""
	if FileAccess.file_exists(profile_path):
		var existing_data = _read_json_file(profile_path)
		if typeof(existing_data) == TYPE_DICTIONARY:
			existing_created_at = String(existing_data.get("created_at", ""))
	if existing_created_at == "":
		existing_created_at = now_iso

	var normalized_properties: Dictionary = _parse_relevant_properties_from_singleton(last_css)
	var locked_properties: PackedStringArray = _get_locked_properties_from_singleton(last_css)
	var profile := {
		"sprite_path": image_path,
		"image_path": image_path,
		"meta": {
			"w": int(meta.get("w", image.get_width())),
			"h": int(meta.get("h", image.get_height()))
		},
		"css_text": last_css,
		"css_rules": _extract_css_rules(last_css),
		"css_properties": normalized_properties,
		"css_locked_properties": locked_properties,
		"css_properties_used": _extract_css_rules(last_css),
		"damage_base": 1,
		"svg_text": last_svg,
		"created_at": existing_created_at,
		"updated_at": now_iso
	}

	var json_file := FileAccess.open(profile_path, FileAccess.WRITE)
	if json_file == null:
		push_warning("[WebOverlay] No se pudo abrir perfil bullet para escritura")
		return
	json_file.store_string(JSON.stringify(profile, "\t"))
	json_file.flush()
	last_bullet_profile_path = profile_path
	print("[WebOverlay] Bullet guardada en %s" % profile_path)
	print("[WebOverlay] profile(user://): %s" % profile_path)
	print("[WebOverlay] profile(abs): %s" % ProjectSettings.globalize_path(profile_path))
	print("[WebOverlay] image(user://): %s" % image_path)
	print("[WebOverlay] image(abs): %s" % ProjectSettings.globalize_path(image_path))
	profile["profile_path"] = profile_path
	_notify_player_to_equip_bullet(profile)

func _notify_player_to_equip_bullet(profile: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("[WebOverlay] No se encontró jugador para equipar bullet")
		return
	if player.has_method("equip_bullet_from_profile"):
		player.call("equip_bullet_from_profile", profile)
	elif player.has_method("equip_bullet_profile"):
		player.call("equip_bullet_profile", profile)
	else:
		push_warning("[WebOverlay] Jugador sin método equip_bullet_from_profile(profile)")

func _read_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	if text.strip_edges() == "":
		return null
	return JSON.parse_string(text)

func _read_bullet_hydration_payload() -> Dictionary:
	var unlock_state: Dictionary = _get_unlock_state_from_singleton()
	var all_properties: PackedStringArray = _get_all_properties_from_singleton()
	var base_payload := {
		"unlock_state": unlock_state,
		"all_properties": all_properties
	}
	var profile_path := "user://bullets/bullet_current.json"
	if not FileAccess.file_exists(profile_path):
		return base_payload
	var raw: Variant = _read_json_file(profile_path)
	if typeof(raw) != TYPE_DICTIONARY:
		return base_payload
	var data: Dictionary = raw
	var css_text := String(data.get("css_text", ""))
	var svg_text := String(data.get("svg_text", ""))
	if css_text == "" and svg_text == "":
		return base_payload
	var out := {
		"css_text": css_text,
		"svg_text": svg_text,
		"unlock_state": unlock_state,
		"all_properties": all_properties
	}
	return out

func _hydrate_web_editor(payload: Dictionary) -> void:
	if payload.is_empty() or not web.has_method("eval"):
		return
	var js := "hydrateFromGodot(%s);" % JSON.stringify(payload)
	web.call_deferred("eval", js)

func _extract_css_rules(text: String) -> PackedStringArray:
	var rules := PackedStringArray()
	for chunk in text.split(";"):
		var pair := chunk.strip_edges()
		if pair == "":
			continue
		var idx := pair.find(":")
		if idx == -1:
			continue
		var key := pair.substr(0, idx).strip_edges().to_lower()
		if key != "":
			rules.append(key)
	return rules

func _get_css_affinity_singleton() -> Node:
	return get_tree().root.get_node_or_null("CssAffinity")

func _get_css_unlocks_singleton() -> Node:
	return get_tree().root.get_node_or_null("CssUnlocks")

func _parse_relevant_properties_from_singleton(css_text: String) -> Dictionary:
	var singleton := _get_css_affinity_singleton()
	if singleton != null and singleton.has_method("parse_relevant_properties"):
		var parsed: Variant = singleton.call("parse_relevant_properties", css_text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}

func _get_locked_properties_from_singleton(css_text: String) -> PackedStringArray:
	var singleton := _get_css_unlocks_singleton()
	if singleton != null and singleton.has_method("get_locked_properties_from_css"):
		var locked: Variant = singleton.call("get_locked_properties_from_css", css_text)
		if locked is PackedStringArray:
			return locked
		if locked is Array:
			return PackedStringArray(locked)
	return PackedStringArray()

func _get_unlock_state_from_singleton() -> Dictionary:
	var singleton := _get_css_unlocks_singleton()
	if singleton != null and singleton.has_method("get_unlock_state"):
		var state: Variant = singleton.call("get_unlock_state")
		if typeof(state) == TYPE_DICTIONARY:
			return state
	return {}

func _get_all_properties_from_singleton() -> PackedStringArray:
	var singleton := _get_css_unlocks_singleton()
	if singleton != null and singleton.has_method("get_all_properties"):
		var all_props: Variant = singleton.call("get_all_properties")
		if all_props is PackedStringArray:
			return all_props
		if all_props is Array:
			return PackedStringArray(all_props)
	return PackedStringArray()
