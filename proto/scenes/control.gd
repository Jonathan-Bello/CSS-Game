extends Control

@onready var panel: PanelContainer = $PanelContainer
@onready var web: Control = $PanelContainer/WebView

@export var window_size: Vector2 = Vector2(900, 600)
@export var content_padding: int = 8

var last_css: String = ""
var last_svg: String = ""

func _ready() -> void:
	add_to_group("web_overlay")
	visible = false
	panel.visible = false
	web.visible = false

	# Estado seguro WebView2
	web.set("url", "about:blank")
	web.set("transparent", true)
	web.set("devtools", true)

	if not web.is_connected("ipc_message", Callable(self, "_on_web_ipc_message")):
		web.connect("ipc_message", Callable(self, "_on_web_ipc_message"))

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

signal overlay_opened
signal overlay_closed

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
	web.call_deferred("focus") # el teclado al WebView mientras está abierto
	_emit_overlay_opened()
	print("[WebOverlay] open -> HTML cargado, focus defer")


func close() -> void:
	print("[WebOverlay] close()")

	# 1) Quita el foco del WebView y devuélvelo a la escena/juego
	# (según la versión del plugin, una de estas existe; llamamos varias de forma segura)
	if web.has_method("focus_parent"):
		web.call_deferred("focus_parent")
	if web.has_method("unfocus"):
		web.call_deferred("unfocus")
	# Fuerza a que ningún Control tenga foco
	get_viewport().gui_release_focus()

	# 2) Oculta el overlay y deja de interceptar input
	web.visible = false
	panel.visible = false
	visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 3) Limpia contenido para próximas aperturas
	web.set("html", "")
	web.set("url", "about:blank")

	# 4) (Opcional) avisa a Player que puede volver a moverse
	_emit_overlay_closed()


func _input(ev: InputEvent) -> void:
	if visible and ev.is_action_pressed("ui_cancel"):
		close()

func _load_editor_html() -> void:
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
  .main{display:grid;grid-template-columns:2fr 1fr;gap:12px;padding:8px;box-sizing:border-box;height:100%}
  .editor{display:grid;grid-template-rows:auto 1fr;gap:8px}
  textarea{width:100%;height:160px;margin:0;background:#0b1222;color:#bfe;border:1px solid #345;border-radius:8px;box-sizing:border-box;padding:8px}
  .preview{display:flex;align-items:center;justify-content:center;background:linear-gradient(145deg,#0f1b33,#0b1222);border:1px solid #243049;border-radius:12px;box-shadow:0 8px 26px rgba(0,0,0,.4)}
  svg{display:block;margin:12px auto;filter:drop-shadow(0 8px 16px rgba(0,0,0,.45))}
  .chat{display:flex;flex-direction:column;gap:8px;background:#0b1222cc;border:1px solid #243049;border-radius:12px;padding:10px;box-shadow:0 10px 24px rgba(0,0,0,.35)}
  .chat header{display:flex;align-items:center;gap:8px;font-weight:bold;letter-spacing:.5px}
  .chat header span{font-size:12px;color:#b2c7ff}
  .log{flex:1;overflow:auto;display:flex;flex-direction:column;gap:8px;padding-right:4px}
  .msg{display:grid;gap:4px;background:#111b33b8;border:1px solid #243049;border-radius:10px;padding:8px}
  .msg.user{border-color:#4a90e2}
  .msg.ai{border-color:#66ffa6}
  .msg .who{font-size:12px;color:#9fb2e7;display:flex;align-items:center;gap:6px}
  .msg.ai .who{color:#7af7bd}
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
          <span style="margin-left:auto;font-size:13px;color:#9fb2e7">Mentora IA: Lumina (tono aventurera)</span>
    </div>
        <div class="main">
                <div class="editor">
                        <textarea id="css">/* edita el estilo */
svg{width:180px;height:180px}
#shape{fill:#5cf;stroke:#036;stroke-width:8px;filter:drop-shadow(0 6px 10px rgba(0,0,0,.5))}
</textarea>
                        <div class="preview">
                          <svg id="svg" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
                                        <defs><style id="styleEl"></style></defs>
                                        <rect id="shape" x="28" y="28" width="200" height="200" rx="24" ry="24"/>
      </svg>
    </div>
                </div>
                <div class="chat">
                        <header>💬 Lumina, guardiana CSS <span>(consejos breves + ejemplos)</span></header>
                        <div class="log" id="log"></div>
                        <form id="chatForm">
                                <input id="msg" type="text" placeholder="Pregúntame sobre sombras, gradientes, animaciones..." autocomplete="off" />
                                <button type="submit">Pedir consejo</button>
                        </form>
                        <p class="aside-note">Lumina responde como un personaje del juego y se apoya en tu CSS actual para dar tips accionables.</p>
                </div>
        </div>
  </div>

<script>
const css = document.getElementById('css');
const styleEl = document.getElementById('styleEl');
const svg = document.getElementById('svg');
const log = document.getElementById('log');
const form = document.getElementById('chatForm');
const msg = document.getElementById('msg');

styleEl.textContent = css.value;
css.addEventListener('input', ()=> styleEl.textContent = css.value);
ipc.postMessage('html_loaded');

const persona = {
        name: 'Lumina',
        role: 'guardiana CSS del bastión de sprites'
};

function addMsg(kind, text){
        const box = document.createElement('div');
        box.className = `msg ${kind}`;
        box.innerHTML = `<div class="who">${kind==='ai' ? '🦊 ' + persona.name : '🧑 Tú'}</div><div class="bubble">${text}</div>`;
        log.appendChild(box);
        log.scrollTop = log.scrollHeight;
}

function analyzeCssHints(code){
        const hints = [];
        if(/box-shadow/i.test(code)) hints.push('tu sombra puede ganar dramatismo con valores múltiples: box-shadow: 0 4px 12px rgba(0,0,0,.35), 0 0 0 3px rgba(92,207,255,.2);');
        if(/linear-gradient/i.test(code)) hints.push('combina gradientes con colores vecinos (#5cf → #82e0ff) para conservar legibilidad.');
        if(/animation/i.test(code)) hints.push('recuerda animation-fill-mode: forwards; para que el estado final se mantenga.');
        if(/stroke-width/i.test(code)) hints.push('usa stroke-linejoin: round; para que las esquinas se sientan más “soft”.');
        if(!hints.length) hints.push('puedes añadir glow con filter: drop-shadow(0 0 12px rgba(92,207,255,.55));');
        return hints.join(' ');
}

function craftReply(question){
        const cssNow = css.value;
        const focus = question.toLowerCase();
        let hook = 'Aquí Lumina en la torre de estilo: ';
        if(focus.includes('gradiente')||focus.includes('gradient')) hook += 'veo que buscas transiciones suaves entre colores. ';
        else if(focus.includes('sombra')||focus.includes('shadow')) hook += 'las sombras cuentan la historia de la luz. ';
        else if(focus.includes('anim')) hook += 'una animación corta añade vida al sprite. ';
        else hook += 'vamos a pulir este sprite con un truco rápido. ';
        const hint = analyzeCssHints(cssNow);
        const sample = '`#shape { transition: 160ms ease; transform-origin: 50% 60%; }`';
        return `${hook}${hint} Prueba también ${sample} para darle carácter de aventurera.`;
}

function sendToAI(evt){
        evt.preventDefault();
        const q = msg.value.trim();
        if(!q) return;
        addMsg('user', q);
        msg.value = '';
        form.querySelector('button').disabled = true;
        setTimeout(()=>{
                const reply = craftReply(q);
                addMsg('ai', reply);
                form.querySelector('button').disabled = false;
                ipc.postMessage(JSON.stringify({type:'ai_chat', question:q, css: css.value}));
        }, 260);
}

form.addEventListener('submit', sendToAI);
addMsg('ai', '¡Salud, creador! Soy Lumina. Dame tu duda CSS y te doy un tip que suene a aventura.');

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
  document.getElementById('styleEl').textContent = css.value;
}

function saveCSS(){
  const tpl = new XMLSerializer().serializeToString(svg);
  ipc.postMessage(JSON.stringify({type:'save_css', css: css.value, svg: tpl}));
}

function makeSprite(){
  // incrusta CSS en el SVG y lo rasteriza a PNG
  const clone = svg.cloneNode(true);
  clone.querySelector('#styleEl').textContent = css.value;
  const txt = new XMLSerializer().serializeToString(clone);
  const blob = new Blob([txt], {type:'image/svg+xml'});
  const url = URL.createObjectURL(blob);
  const img = new Image();
  img.onload = ()=>{
    const c = document.createElement('canvas');
    c.width = img.naturalWidth || 256;
    c.height = img.naturalHeight || 256;
    c.getContext('2d').drawImage(img,0,0,c.width,c.height);
    const png = c.toDataURL('image/png');
    URL.revokeObjectURL(url);
    ipc.postMessage(JSON.stringify({type:'css_sprite', data_url: png, css: css.value, svg: txt, meta:{w:c.width,h:c.height}}));
  };
  img.onerror = ()=> ipc.postMessage('img_error');
  img.src = url;
}
</script>
</body></html>
"""
	web.call("load_html", html)

func _on_web_ipc_message(msg: String) -> void:
	print("[WebOverlay] ipc_message: ", msg)
	if msg == "close":
		close(); return
	if msg == "html_loaded":
		print("[WebOverlay] HTML cargado"); return
	if msg == "img_error":
		push_warning("[WebOverlay] Error rasterizando SVG"); return

	var data = JSON.parse_string(msg)
	if typeof(data) == TYPE_DICTIONARY:
		match String(data.get("type","")):
			"save_css":
				last_css = String(data.css)
				last_svg = String(data.svg)
				print("[WebOverlay] CSS guardado (memoria).")
			"css_sprite":
				last_css = String(data.css)
				last_svg = String(data.svg)
				_create_sprite_from_data_url(String(data.data_url))
				close()

func _create_sprite_from_data_url(data_url: String) -> void:
	var prefix := "base64,"
	var i := data_url.find(prefix)
	if i == -1:
		push_warning("[WebOverlay] data_url inválida"); return
	var b64 := data_url.substr(i + prefix.length())
	var bytes: PackedByteArray = Marshalls.base64_to_raw(b64)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		push_warning("[WebOverlay] PNG inválido"); return
	var tex := ImageTexture.create_from_image(img)

	# Crear seguidor y pegarlo al jugador
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.position = Vector2(28,-32)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		var follower = CssFollower.new()
		follower.name = "CssFollower_%d" % randi()
		player.add_child(follower)
		player.call_deferred("_ensure_follow_manager") # por si aún no existe
		follower.add_child(sprite)
	else:
		get_tree().current_scene.add_child(sprite)
