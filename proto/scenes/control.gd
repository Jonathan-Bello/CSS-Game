extends Control

const EmisClientScript = preload("res://proto/scenes/emis_client.gd")
@onready var panel: PanelContainer = $PanelContainer
@onready var web: Control = $PanelContainer/WebView

@export var window_size: Vector2 = Vector2(900, 600)
@export var content_padding: int = 8

var last_css: String = ""
var last_svg: String = ""
var last_bullet_profile_path: String = ""
var _web_hydration_payload: Dictionary = {}
var _emis_client: Node = null
var _emis_conversation_id: String = ""

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

	_ensure_emis_client()
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
  html,body{margin:0;background:transparent;color:#fff;font-family:'Quantico','Orbitron','Rajdhani','Segoe UI',sans-serif}
  .wrap{display:grid;grid-template-rows:auto auto 1fr; height:100vh}
  .bar{display:flex;gap:8px;padding:10px;background:#0b1222e6;border-bottom:1px solid #2b3c64;align-items:center;backdrop-filter:blur(4px)}
  button{background:#4a90e2;border:0;color:#fff;padding:8px 12px;border-radius:8px;cursor:pointer;font-weight:700}
  .btn-secondary{background:#2b3858}
  .btn-warn{background:#7d3142}
  button:disabled{opacity:.5;cursor:wait}
  select{background:#123;color:#fff;border:1px solid #345;border-radius:8px;padding:8px}
  .indicators{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;padding:8px 10px;background:#0b1222cc;border-bottom:1px solid #22314f}
  .pill{background:linear-gradient(145deg,#101a30,#0c1427);border:1px solid #314266;border-radius:10px;padding:10px}
  .pill .label{display:block;font-size:11px;color:#9ab0e8;text-transform:uppercase;letter-spacing:.5px}
  .pill .value{display:block;margin-top:4px;font-size:14px;font-weight:700;color:#e7f0ff}
  .main{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr) minmax(320px,.9fr);gap:10px;padding:10px;box-sizing:border-box;height:100%;min-height:0}
  .workbench{grid-column:1 / span 2;display:grid;grid-template-rows:auto 1fr;gap:10px;min-height:0}
  .editor{display:grid;grid-template-rows:auto auto;gap:10px;min-height:0}
  textarea{width:100%;height:170px;margin:0;background:#0b1222;color:#bfe;border:1px solid #345;border-radius:10px;box-sizing:border-box;padding:10px;font-family:'Quantico',ui-monospace,SFMono-Regular,Menlo,monospace}
  .code-hint{font-size:12px;color:#ffb4bf;margin:0}
  .prop-panel{background:linear-gradient(145deg,#121d34,#0f162a);border:1px solid #314266;border-radius:10px;padding:10px}
  .prop-panel h3{margin:0 0 8px;font-size:13px;color:#d5e4ff}
  .prop-list{display:flex;flex-wrap:wrap;gap:6px;min-height:28px}
  .prop-chip{font-size:12px;padding:3px 8px;border-radius:999px;background:#1f2d4d;color:#acd7ff;border:1px solid #395382}
  .prop-chip.locked{background:#3b1f2c;color:#ff6b81;border:1px solid #8b3647}
  .preview{display:flex;align-items:center;justify-content:center;overflow:hidden;position:relative;background:radial-gradient(circle at 30% 20%, #1a2f59 0%, #0b1222 58%);border:1px solid #314266;border-radius:14px;box-shadow:0 14px 28px rgba(0,0,0,.45);min-height:0}
  .preview #svg{display:block;flex:0 0 auto;max-width:200px;max-height:200px;pointer-events:none}
  .chat-shell{grid-column:3;display:grid;grid-template-rows:auto 1fr auto;gap:8px;background:linear-gradient(145deg,#131e37,#0d1529);border:1px solid #314266;border-radius:14px;padding:12px;box-shadow:0 12px 26px rgba(0,0,0,.35);min-height:0}
  .chat-shell h3{margin:0;font-size:14px;color:#ffd57f}
  .chat-shell p{margin:0;color:#bfd0f5;font-size:12px;line-height:1.45}
  .chat-messages{display:flex;flex-direction:column;gap:8px;overflow:auto;min-height:0;padding-right:2px}
  .chat-bubble{width:fit-content;max-width:min(92%,760px);padding:8px 10px;border-radius:10px;font-size:12px;line-height:1.4;word-break:break-word;white-space:pre-wrap;border:1px solid transparent}
  .chat-bubble.user{margin-left:auto;background:#23406f;color:#e6f1ff;border-color:#36578f}
  .chat-bubble.emis{margin-right:auto;background:#191f34;color:#ffe8b6;border-color:#424f7a}
  .chat-input-row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px}
  .chat-input-row input{background:#0b1222;color:#fff;border:1px solid #345;border-radius:8px;padding:8px}
  .chat-typing{font-size:11px;color:#ffde9f;min-height:16px}
  .chat-typing.hidden{visibility:hidden}
  .preview #svg{margin:12px auto;filter:drop-shadow(0 8px 16px rgba(0,0,0,.45))}
</style></head>
<body>
  <div class="wrap">
	<div class="bar">
	  <select id="tpl" onchange="setTpl(this.value)">
		<option value="box">Caja</option>
		<option value="circle">Círculo</option>
		<option value="star">Estrella</option>
      </select>
	  <button class="btn-secondary" onclick="saveDraft()">Guardar borrador</button>
	  <button onclick="equipBullet()">Equipar como munición</button>
	  <button class="btn-warn" onclick="newBullet()">Nueva bala</button>
	  <button onclick="closeOverlay()">Cerrar</button>
	  <span style="margin-left:auto;font-size:13px;color:#eac435">Mentora IA: Emmys (tono aventurera)</span>
    </div>
	<div class="indicators">
	  <div class="pill"><span class="label">Bala equipada</span><span class="value" id="equipIndicator">No equipada</span></div>
	  <div class="pill"><span class="label">Última actualización</span><span class="value" id="updateIndicator">Sin cambios</span></div>
	  <div class="pill"><span class="label">Propiedades CSS detectadas</span><span class="value" id="countIndicator">0</span></div>
	</div>

	<div class="main">
	  <div class="workbench">
		<div class="editor">
		  <textarea id="css">/* edita el estilo */
svg{width:180px;height:180px}
#shape{fill:#5cf;stroke:#036;stroke-width:8px;filter:drop-shadow(0 6px 10px rgba(0,0,0,.5))}
</textarea>
		  <p class="code-hint">Las propiedades bloqueadas se muestran en rojo y no aplican bonus de ataque.</p>
		  <div class="prop-panel">
			<h3>Propiedades detectadas</h3>
			<div class="prop-list" id="detectedList"></div>
		  </div>
		</div>

		<div class="preview">
		  <svg id="svg" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
			<defs><style id="styleEl"></style></defs>
			<rect id="shape" x="28" y="28" width="200" height="200" rx="24" ry="24"/>
          </svg>
        </div>
      </div>
	  <aside class="chat-shell">
		<h3>💬 Emis (chatbot)</h3>
		<p>Comparte ideas de estilo y daño. Emis responderá con sugerencias para tu bala actual.</p>
		<div id="chatMessages" class="chat-messages"></div>
		<div id="chatTyping" class="chat-typing hidden">Emis escribiendo…</div>
		<div class="chat-input-row">
		  <input id="chatInput" type="text" maxlength="240" placeholder="Pregúntale a Emis sobre este CSS"/>
		  <button id="chatSend">Enviar</button>
		</div>
	  </aside>
    </div>
  </div>

<script>
const css = document.getElementById('css');
const svg = document.getElementById('svg');
const equipIndicator = document.getElementById('equipIndicator');
const updateIndicator = document.getElementById('updateIndicator');
const countIndicator = document.getElementById('countIndicator');
const detectedList = document.getElementById('detectedList');
const chatMessagesEl = document.getElementById('chatMessages');
const chatInputEl = document.getElementById('chatInput');
const chatSendEl = document.getElementById('chatSend');
const chatTypingEl = document.getElementById('chatTyping');
const DEFAULT_CSS = `/* edita el estilo */
svg{width:180px;height:180px}
#shape{fill:#5cf;stroke:#036;stroke-width:8px;filter:drop-shadow(0 6px 10px rgba(0,0,0,.5))}`;
let unlockState = {};
let allProperties = [];
let bulletEquipped = false;
let bulletUpdatedAt = '';
let chatMessages = [{role:'emis', text:'¡Hola! Soy Emis. ¿Qué mejora quieres probar en tu bala?'}];
let chatWaitingReply = false;
const EMIS_CHAT_CONTRACT_VERSION = 'emis_chat_v1';

function getStyleEl(){
  return document.getElementById('styleEl');
}

function clampBulletSize(value){
  const n = Number(value);
  if(!Number.isFinite(n)) return 180;
  return Math.max(10, Math.min(200, Math.round(n)));
}

function readBulletSizeFromCss(rawCss){
  const text = String(rawCss || '');
  const parsePxValue = (name) => {
    const token = `${name}:`;
    const lower = text.toLowerCase();
    const idx = lower.indexOf(token);
    if(idx === -1) return null;
    const tail = lower.slice(idx + token.length).trim();
    let digits = '';
    for(const ch of tail){
      if((ch >= '0' && ch <= '9') || ch === '.'){
        digits += ch;
      }else{
        break;
      }
    }
    if(!digits || !tail.includes('px')){
      return null;
    }
    return Number(digits);
  };
  const width = clampBulletSize(parsePxValue('width') ?? 180);
  const height = clampBulletSize(parsePxValue('height') ?? width);
  return {width, height};
}

function buildPreviewCss(rawCss){
  const size = readBulletSizeFromCss(rawCss);
  let scopedCss = String(rawCss || '');
  scopedCss = scopedCss.split('svg{').join('#svg{');
  scopedCss = scopedCss.split('svg {').join('#svg {');
  scopedCss = scopedCss.split(',svg').join(',#svg');
  scopedCss = scopedCss.split(', svg').join(', #svg');
  return {
    css: `${scopedCss}\n#svg{width:${size.width}px!important;height:${size.height}px!important;max-width:200px!important;max-height:200px!important;min-width:10px!important;min-height:10px!important;}`,
    width: size.width,
    height: size.height
  };
}

function applyCssToPreview(){
  const liveStyle = getStyleEl();
  if(!liveStyle) return;
  const previewCss = buildPreviewCss(css.value);
  liveStyle.textContent = previewCss.css;
  svg.style.width = `${previewCss.width}px`;
  svg.style.height = `${previewCss.height}px`;
  svg.style.maxWidth = '200px';
  svg.style.maxHeight = '200px';
  svg.style.minWidth = '10px';
  svg.style.minHeight = '10px';
  renderDetectedProperties();
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

function setChatWaitingState(waiting){
  chatWaitingReply = Boolean(waiting);
  if(chatInputEl) chatInputEl.disabled = chatWaitingReply;
  if(chatSendEl) chatSendEl.disabled = chatWaitingReply;
  if(chatTypingEl){
    chatTypingEl.classList.toggle('hidden', !chatWaitingReply);
  }
}

function renderChatMessages(){
  if(!chatMessagesEl) return;
  if(!chatMessages.length){
    chatMessagesEl.innerHTML = '<div class="chat-bubble emis">Sin mensajes todavía.</div>';
    return;
  }
  chatMessagesEl.innerHTML = chatMessages.map((message)=>{
    const role = message && message.role === 'user' ? 'user' : 'emis';
    const text = message && typeof message.text === 'string' ? message.text : '';
    return `<div class="chat-bubble ${role}">${escapeHtml(text)}</div>`;
  }).join('');
  chatMessagesEl.scrollTop = chatMessagesEl.scrollHeight;
}

function pushChatMessage(role, text){
  if(typeof text !== 'string') return;
  const normalized = text.trim();
  if(!normalized) return;
  chatMessages.push({role: role === 'user' ? 'user' : 'emis', text: normalized});
  renderChatMessages();
}

function normalizeEmisReplyText(payload){
  if(!payload || typeof payload !== 'object') return '';
  let raw = typeof payload.reply === 'string' ? payload.reply : '';
  if(!raw && typeof payload.message === 'string') raw = payload.message;
  const normalized = String(raw || '').trim();
  if(!normalized) return '';

  if(normalized.startsWith('{') && normalized.includes('"reply"')){
    try{
      const parsed = JSON.parse(normalized);
      if(parsed && typeof parsed.reply === 'string' && parsed.reply.trim()){
        return parsed.reply.trim();
      }
    }catch(_err){
      const extracted = extractReplyFromJsonLikeText(normalized);
      if(extracted){
        return extracted;
      }
    }
  }
  return normalized;
}

function extractReplyFromJsonLikeText(text){
  if(typeof text !== 'string' || !text.includes('"reply"')) return '';
  const marker = '"reply":"';
  const start = text.indexOf(marker);
  if(start === -1) return '';
  let i = start + marker.length;
  let escaped = false;
  let out = '';
  while(i < text.length){
    const ch = text[i];
    if(escaped){
      switch(ch){
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case '"': out += '"'; break;
        case '\\': out += '\\'; break;
        default: out += ch; break;
      }
      escaped = false;
      i += 1;
      continue;
    }
    if(ch === '\\'){
      escaped = true;
      i += 1;
      continue;
    }
    if(ch === '"'){
      break;
    }
    out += ch;
    i += 1;
  }
  return out.trim();
}

async function pushChatMessageTyping(role, text){
  const normalized = String(text || '').trim();
  if(!normalized){
    return;
  }
  const safeRole = role === 'user' ? 'user' : 'emis';
  chatMessages.push({role: safeRole, text: ''});
  renderChatMessages();

  const total = normalized.length;
  const step = total > 260 ? 3 : (total > 120 ? 2 : 1);
  const delayMs = 12;
  for(let i = step; i <= total; i += step){
    chatMessages[chatMessages.length - 1].text = normalized.slice(0, i);
    renderChatMessages();
    await new Promise((resolve)=>setTimeout(resolve, delayMs));
  }
  chatMessages[chatMessages.length - 1].text = normalized;
  renderChatMessages();
}

function sendChatMessage(){
  if(!chatInputEl || chatWaitingReply) return;
  const message = String(chatInputEl.value || '').trim();
  if(!message) return;
  pushChatMessage('user', message);
  chatInputEl.value = '';
  console.log('[Emis] envío:', message);
  setChatWaitingState(true);

  const detectedProps = getDetectedProperties(css ? css.value : '');
  const lockedProps = getLockedPropertiesFromCss(css ? css.value : '');
  const snapshot = {
    ...exportState(),
    detected_properties: detectedProps,
    locked_properties: lockedProps,
    unlock_state: unlockState,
    bullet_equipped: bulletEquipped,
    updated_at: bulletUpdatedAt
  };
  const context = {
    contract_version: EMIS_CHAT_CONTRACT_VERSION,
    history: chatMessages,
    snapshot
  };

  try{
    ipc.postMessage(JSON.stringify({
      type: 'chat_request',
      contract_version: EMIS_CHAT_CONTRACT_VERSION,
      message,
      context
    }));
  }catch(err){
    console.error('[Emis] error enviando prompt', err);
    pushChatMessage('emis', 'No pude enviar tu mensaje. Inténtalo de nuevo.');
    setChatWaitingState(false);
  }
}

window.onEmisReply = async function(payload){
  try{
    if(!payload || typeof payload !== 'object'){
      throw new Error('payload inválido');
    }

    if(payload.error){
      console.error('[Emis] respuesta con error:', payload.error);
      pushChatMessage('emis', 'Tuvimos un problema al responder. Intenta en unos segundos.');
      return;
    }

    const replyText = normalizeEmisReplyText(payload);

    if(!replyText.trim()){
      throw new Error('respuesta vacía');
    }

    console.log('[Emis] recepción:', replyText);
    await pushChatMessageTyping('emis', replyText);
  }catch(err){
    console.error('[Emis] error procesando respuesta', err);
    pushChatMessage('emis', 'No pude entender la respuesta de Emis. Vuelve a intentarlo.');
  }finally{
    setChatWaitingState(false);
    if(chatInputEl) chatInputEl.focus();
  }
};

function getLockedPropertiesFromCss(text){
  const found = getDetectedProperties(text)
    .filter((key)=>!unlockState[key]);
  return found;
}

function getDetectedProperties(text){
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
    if(!seen.has(key)){
      seen.add(key);
      found.push(key);
    }
  }
  return found;
}

function updateIndicators(){
  if(equipIndicator){
    equipIndicator.textContent = bulletEquipped ? 'Equipada ✅' : 'No equipada';
    equipIndicator.style.color = bulletEquipped ? '#88ffb0' : '#ffd2d9';
  }
  if(updateIndicator){
    updateIndicator.textContent = bulletUpdatedAt || 'Sin cambios';
  }
}

function closeOverlay(){
  try{
    ipc.postMessage('close');
    ipc.postMessage(JSON.stringify({type:'close'}));
  }catch(err){
    console.error('No se pudo enviar close por IPC', err);
  }
}

function renderDetectedProperties(){
  const detected = getDetectedProperties(css.value);
  const locked = new Set(getLockedPropertiesFromCss(css.value));

  if(countIndicator){
    countIndicator.textContent = String(detected.length);
  }
  if(detectedList){
    if(!detected.length){
	  detectedList.innerHTML = '<span style="color:#88ffb0;font-size:12px">Sin propiedades detectadas.</span>';
    }else{
      detectedList.innerHTML = detected.map((prop)=>{
        const isLocked = locked.has(prop);
        const cls = isLocked ? 'prop-chip locked' : 'prop-chip';
		return `<span class="${cls}">${escapeHtml(prop)}</span>`;
      }).join('');
    }
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
  bulletEquipped = Boolean(payload.bullet_equipped);
  bulletUpdatedAt = typeof payload.updated_at === 'string' ? payload.updated_at : bulletUpdatedAt;

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
  updateIndicators();
}

function exportState(){
  return {
    css_text: css.value,
    svg_text: new XMLSerializer().serializeToString(svg)
  };
}

renderChatMessages();
if(chatSendEl){
  chatSendEl.addEventListener('click', sendChatMessage);
}
if(chatInputEl){
  chatInputEl.addEventListener('keydown', (event)=>{
    if(event.key === 'Enter'){
      event.preventDefault();
      sendChatMessage();
    }
  });
}
setChatWaitingState(false);
updateIndicators();

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

function saveDraft(){
  const tpl = new XMLSerializer().serializeToString(svg);
  ipc.postMessage(JSON.stringify({type:'save_css', css: css.value, svg: tpl}));
  bulletUpdatedAt = new Date().toISOString();
  updateIndicators();
}

function equipBullet(){
  const bulletSize = readBulletSizeFromCss(css.value);
  const clone = svg.cloneNode(true);
  const cloneStyle = clone.querySelector('#styleEl');
  if(cloneStyle){
    const previewCss = buildPreviewCss(css.value);
    cloneStyle.textContent = previewCss.css;
  }
  const txt = new XMLSerializer().serializeToString(clone);
  const blob = new Blob([txt], {type:'image/svg+xml'});
  const url = URL.createObjectURL(blob);
  const img = new Image();
  img.onload = ()=>{
    const maxSize = 200;
    const sourceW = Math.max(1, img.naturalWidth || 256);
    const sourceH = Math.max(1, img.naturalHeight || 256);
    const targetW = clampBulletSize(bulletSize.width);
    const targetH = clampBulletSize(bulletSize.height);
    const ratio = Math.min(1, maxSize / Math.max(sourceW, sourceH));
    const sampledW = Math.max(1, Math.round(sourceW * ratio));
    const sampledH = Math.max(1, Math.round(sourceH * ratio));
    const outW = clampBulletSize(Math.min(targetW, sampledW));
    const outH = clampBulletSize(Math.min(targetH, sampledH));

    const c = document.createElement('canvas');
    c.width = outW;
    c.height = outH;
    c.getContext('2d').drawImage(img,0,0,c.width,c.height);
    const png = c.toDataURL('image/png');
    URL.revokeObjectURL(url);
    ipc.postMessage(JSON.stringify({type:'equip_bullet', data_url: png, css: css.value, svg: txt, meta:{w:outW,h:outH,source_w:sourceW,source_h:sourceH}}));
    bulletEquipped = true;
    bulletUpdatedAt = new Date().toISOString();
    updateIndicators();
  };
  img.onerror = ()=> ipc.postMessage('img_error');
  img.src = url;
}

function newBullet(){
  document.getElementById('tpl').value = 'box';
  css.value = DEFAULT_CSS;
  setTpl('box');
  bulletEquipped = false;
  bulletUpdatedAt = '';
  updateIndicators();
}
</script>
</body></html>
"""
	web.call("load_html", html)

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
			"close":
				close()
				return
			"save_css":
				_save_css_draft(data)
			"equip_bullet":
				_save_and_equip_bullet(data)
				close()
			"chat_request":
				_handle_chat_request(data)

func _handle_chat_request(data: Dictionary) -> void:
	var raw_message := String(data.get("message", ""))
	var message := raw_message.strip_edges()
	if message == "":
		push_warning("[Emis] chat_request inválido: message vacío")
		_send_emis_reply_to_web({
			"ok": false,
			"error": "message vacío",
			"code": "invalid_response"
		})
		return

	var incoming_context: Dictionary = {}
	var raw_context: Variant = data.get("context", {})
	if typeof(raw_context) == TYPE_DICTIONARY:
		incoming_context = raw_context

	var context := _build_emis_context(incoming_context)
	var payload := _build_emis_payload_for_backend(data, context, message)
	print("[Emis] solicitud -> %s" % JSON.stringify(payload))

	var response: Dictionary = {}
	var client := _get_emis_client()
	if client == null:
		var no_client_msg := "Cliente Emis no disponible"
		push_warning("[Emis] " + no_client_msg)
		response = {"ok": false, "error": no_client_msg, "code": "network"}
	elif client.has_method("request_chat"):
		var result: Variant = await client.call("request_chat", payload)
		if typeof(result) == TYPE_DICTIONARY:
			response = result
		else:
			response = {"ok": false, "error": "Respuesta inválida del cliente Emis", "code": "invalid_response"}
	elif client.has_method("chat_request"):
		var alt_result: Variant = await client.call("chat_request", payload)
		if typeof(alt_result) == TYPE_DICTIONARY:
			response = alt_result
		else:
			response = {"ok": false, "error": "Respuesta inválida del cliente Emis", "code": "invalid_response"}
	else:
		response = {"ok": false, "error": "Cliente Emis sin método de chat compatible", "code": "invalid_response"}

	if not bool(response.get("ok", false)):
		push_warning("[Emis] error <- %s (%s)" % [String(response.get("error", "desconocido")), String(response.get("code", "unknown"))])
	else:
		_update_emis_conversation_id(response)
		print("[Emis] respuesta <- %s" % JSON.stringify(response))
	_send_emis_reply_to_web(response)

func _build_emis_payload_for_backend(data: Dictionary, context: Dictionary, message: String) -> Dictionary:
	var normalized_message := message.substr(0, min(message.length(), 1200))
	var intent_mode := String(data.get("intent_mode", context.get("intent_mode", "auto"))).strip_edges().to_lower()
	if intent_mode != "tutor_css" and intent_mode != "guia_juego":
		intent_mode = "auto"

	var player_context := _build_player_context_for_emis(data, context)
	var css_snapshot_fragment := String(context.get("css_text", last_css)).strip_edges()
	if css_snapshot_fragment.length() > 10000:
		css_snapshot_fragment = css_snapshot_fragment.substr(0, 10000)

	var payload := {
		"message": normalized_message,
		"intent_mode": intent_mode,
		"player_context": player_context,
		"css_snapshot_fragment": css_snapshot_fragment
	}

	if _emis_conversation_id == "":
		_emis_conversation_id = _create_conversation_id()
	if _emis_conversation_id != "":
		payload["conversation_id"] = _emis_conversation_id

	return payload

func _build_player_context_for_emis(data: Dictionary, context: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {}
	var raw_snapshot: Variant = context.get("snapshot", {})
	if typeof(raw_snapshot) == TYPE_DICTIONARY:
		snapshot = raw_snapshot

	var player_context: Dictionary = {}
	player_context["screen"] = String(data.get("screen", context.get("screen", "bullet_creator"))).strip_edges()
	player_context["level"] = String(data.get("level", context.get("level", ""))).strip_edges()
	player_context["objective"] = String(data.get("objective", context.get("objective", ""))).strip_edges()
	player_context["zone_id"] = String(data.get("zone_id", context.get("zone_id", ""))).strip_edges()
	player_context["quest_id"] = String(data.get("quest_id", context.get("quest_id", ""))).strip_edges()
	player_context["quest_step"] = String(data.get("quest_step", context.get("quest_step", ""))).strip_edges()

	var unlocked_css_raw: Variant = data.get("unlocked_css", context.get("unlocked_css", snapshot.get("detected_properties", [])))
	player_context["unlocked_css"] = _to_packed_string_array(unlocked_css_raw)
	player_context["nearby_npcs"] = _to_packed_string_array(data.get("nearby_npcs", context.get("nearby_npcs", [])))
	player_context["available_portals"] = _to_packed_string_array(data.get("available_portals", context.get("available_portals", [])))
	player_context["inventory_tags"] = _to_packed_string_array(data.get("inventory_tags", context.get("inventory_tags", [])))
	player_context["failed_attempts_css"] = _to_packed_string_array(data.get("failed_attempts_css", context.get("failed_attempts_css", [])))
	return player_context

func _create_conversation_id() -> String:
	return "conv_%s_%s" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]

func _update_emis_conversation_id(response: Dictionary) -> void:
	var raw: Dictionary = {}
	var raw_response: Variant = response.get("raw", {})
	if typeof(raw_response) == TYPE_DICTIONARY:
		raw = raw_response

	var from_raw := String(raw.get("conversation_id", "")).strip_edges()
	if from_raw != "":
		_emis_conversation_id = from_raw
		return

	var from_top_level := String(response.get("conversation_id", "")).strip_edges()
	if from_top_level != "":
		_emis_conversation_id = from_top_level

func _to_packed_string_array(raw: Variant) -> PackedStringArray:
	if raw is PackedStringArray:
		return raw
	if raw is Array:
		var mapped := PackedStringArray()
		for item in raw:
			var value := String(item).strip_edges().to_lower()
			if value != "":
				mapped.append(value)
		return mapped
	return PackedStringArray()

func _build_emis_context(data_from_js: Dictionary) -> Dictionary:
	# Contrato estable emis_chat_v1:
	# {
	#   contract_version: String,
	#   css_text: String,
	#   svg_text: String,
	#   bullet_equipped: bool,
	#   updated_at: String,
	#   detected_properties: PackedStringArray,
	#   css_rules: PackedStringArray,
	#   locked_properties: PackedStringArray,
	#   unlock_state: Dictionary,
	#   all_properties: PackedStringArray,
	#   history: Array[Dictionary]?,
	#   snapshot: Dictionary
	# }
	var context := data_from_js.duplicate(true)
	var hydration := _read_bullet_hydration_payload()
	var snapshot: Dictionary = {}
	var raw_snapshot: Variant = context.get("snapshot", {})
	if typeof(raw_snapshot) == TYPE_DICTIONARY:
		snapshot = raw_snapshot

	var css_text := String(snapshot.get("css_text", String(context.get("css_text", context.get("css", "")))))
	if css_text == "":
		css_text = String(hydration.get("css_text", last_css))

	var svg_text := String(snapshot.get("svg_text", String(context.get("svg_text", context.get("svg", "")))))
	if svg_text == "":
		svg_text = String(hydration.get("svg_text", ""))
	if svg_text == "":
		svg_text = last_svg

	var detected_from_js := _to_packed_string_array(snapshot.get("detected_properties", context.get("detected_properties", [])))
	var detected_backend := _extract_css_rules(css_text)
	var detected_properties := detected_from_js if not detected_from_js.is_empty() else detected_backend

	var locked_from_js := _to_packed_string_array(snapshot.get("locked_properties", context.get("locked_properties", [])))
	var locked_backend := _get_locked_properties_from_singleton(css_text)
	var locked_properties := locked_from_js if not locked_from_js.is_empty() else locked_backend

	var unlock_state := _get_unlock_state_from_singleton()
	var unlock_state_from_js: Variant = snapshot.get("unlock_state", context.get("unlock_state", {}))
	if typeof(unlock_state_from_js) == TYPE_DICTIONARY:
		var from_js_dict: Dictionary = unlock_state_from_js
		if not from_js_dict.is_empty():
			unlock_state = from_js_dict

	var bullet_equipped := bool(snapshot.get("bullet_equipped", context.get("bullet_equipped", hydration.get("bullet_equipped", false))))
	var updated_at := String(snapshot.get("updated_at", context.get("updated_at", hydration.get("updated_at", ""))))

	context["contract_version"] = String(context.get("contract_version", "emis_chat_v1"))
	context["css_text"] = css_text
	context["svg_text"] = svg_text
	context["css"] = css_text
	context["svg"] = svg_text
	context["bullet_equipped"] = bullet_equipped
	context["updated_at"] = updated_at
	context["detected_properties"] = detected_properties
	context["css_rules"] = detected_backend
	context["locked_properties"] = locked_properties
	context["unlock_state"] = unlock_state
	context["all_properties"] = _get_all_properties_from_singleton()

	context["snapshot"] = {
		"css_text": css_text,
		"svg_text": svg_text,
		"detected_properties": detected_properties,
		"locked_properties": locked_properties,
		"unlock_state": unlock_state,
		"bullet_equipped": bullet_equipped,
		"updated_at": updated_at
	}
	return context

func _ensure_emis_client() -> void:
	if is_instance_valid(_emis_client):
		return
	_emis_client = EmisClientScript.new()
	_emis_client.name = "EmisClient"
	add_child(_emis_client)
	if _emis_client.has_method("add_to_group"):
		_emis_client.call("add_to_group", "emis_client")
	print("[Emis] Cliente local inicializado")

func _get_emis_client() -> Node:
	if is_instance_valid(_emis_client):
		return _emis_client

	var root := get_tree().root
	if root == null:
		return null
	var by_name := root.get_node_or_null("EmisClient")
	if by_name != null:
		return by_name
	var by_group := get_tree().get_first_node_in_group("emis_client")
	if by_group != null:
		return by_group
	return null

func _send_emis_reply_to_web(payload: Dictionary) -> void:
	if not web.has_method("eval"):
		push_warning("[Emis] WebView sin método eval para responder")
		return
	var safe_payload := payload
	if safe_payload.is_empty():
		safe_payload = {"error": "Respuesta vacía del backend Emis"}
	var js := "window.onEmisReply(%s);" % JSON.stringify(safe_payload)
	web.call_deferred("eval", js)

func _save_css_draft(data: Dictionary) -> void:
	last_css = String(data.get("css", ""))
	last_svg = String(data.get("svg", ""))
	var dir_path := "user://bullets"
	var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		push_warning("[WebOverlay] No se pudo crear directorio de borradores. err=%s" % mkdir_err)
		return

	var draft_path := "%s/bullet_draft.json" % dir_path
	var now_iso := Time.get_datetime_string_from_system(true, true)
	var draft := {
		"css_text": last_css,
		"svg_text": last_svg,
		"updated_at": now_iso
	}
	var draft_file := FileAccess.open(draft_path, FileAccess.WRITE)
	if draft_file == null:
		push_warning("[WebOverlay] No se pudo guardar borrador editable")
		return
	draft_file.store_string(JSON.stringify(draft, "\t"))
	draft_file.flush()
	print("[WebOverlay] CSS draft persistido en %s" % draft_path)

func _save_and_equip_bullet(data: Dictionary) -> void:
	last_css = String(data.get("css", ""))
	last_svg = String(data.get("svg", ""))
	_save_css_draft(data)

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
		"all_properties": all_properties,
		"bullet_equipped": false,
		"updated_at": ""
	}
	var draft_path := "user://bullets/bullet_draft.json"
	var profile_path := "user://bullets/bullet_current.json"
	var css_text := ""
	var svg_text := ""
	var updated_at := ""
	var bullet_equipped := false

	if FileAccess.file_exists(draft_path):
		var draft_raw: Variant = _read_json_file(draft_path)
		if typeof(draft_raw) == TYPE_DICTIONARY:
			var draft_data: Dictionary = draft_raw
			css_text = String(draft_data.get("css_text", ""))
			svg_text = String(draft_data.get("svg_text", ""))
			updated_at = String(draft_data.get("updated_at", ""))

	if FileAccess.file_exists(profile_path):
		var profile_raw: Variant = _read_json_file(profile_path)
		if typeof(profile_raw) == TYPE_DICTIONARY:
			var profile_data: Dictionary = profile_raw
			bullet_equipped = true
			if updated_at == "":
				updated_at = String(profile_data.get("updated_at", ""))
			if css_text == "":
				css_text = String(profile_data.get("css_text", ""))
			if svg_text == "":
				svg_text = String(profile_data.get("svg_text", ""))

	base_payload["bullet_equipped"] = bullet_equipped
	base_payload["updated_at"] = updated_at
	if css_text != "":
		base_payload["css_text"] = css_text
	if svg_text != "":
		base_payload["svg_text"] = svg_text
	return base_payload

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
