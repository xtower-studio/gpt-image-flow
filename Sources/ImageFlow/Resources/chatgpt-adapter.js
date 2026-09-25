// Runs only in the worker's authenticated chatgpt.com main frame.
if (location.hostname !== 'chatgpt.com') throw new Error('unexpected-origin');
const composer = () => document.querySelector('#prompt-textarea,textarea[data-id="root"],div[contenteditable="true"].ProseMirror');
const composerForm = () => composer()?.closest('form');
const send = () => composerForm()?.querySelector('button[type="submit"][aria-label="보내기"],button[type="submit"][aria-label="Send"]') || document.querySelector('button[data-testid="send-button"],button[data-testid="composer-send-button"],button[aria-label="Send prompt"],button[aria-label="프롬프트 보내기"]');
const enabled = el => !!el && !el.disabled && el.getAttribute('aria-disabled') !== 'true';
const fileID = s => s.match(/file[-_][A-Za-z0-9]+/)?.[0] || s;
const reasoningPill = () => composerForm()?.querySelector('button[data-composer-navigation-target="reasoning"]') || document.querySelector('[data-composer-transition-slot="trailing"] button.__composer-pill[aria-haspopup="menu"]') || Array.from((composer()?.closest('form') || document).querySelectorAll('button.__composer-pill')).find(el => /Instant|추론|Thinking|Reasoning|High|Standard|Light|Extended|Heavy|Pro|Max|Medium|Low|최대|낮|중간|높|표준/i.test(el.innerText));
if (operation === 'openReasoning') {
  const pill = reasoningPill();
  if (!pill) return JSON.stringify({ok:false});
  if(pill.getAttribute('aria-expanded') !== 'true') {pill.focus();pill.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',code:'ArrowDown',bubbles:true,cancelable:true}));}
  return JSON.stringify({ok:true});
}
if (operation === 'setReasoning') {
  const value = Number(payload.level);
  const slider = document.querySelector('[role="slider"][aria-valuenow]');
  if(!slider || !Number.isInteger(value) || value < Number(slider.getAttribute('aria-valuemin')) || value > Number(slider.getAttribute('aria-valuemax'))) throw new Error('reasoning-slider-unavailable');
  slider.focus();
  slider.dispatchEvent(new KeyboardEvent('keydown',{key:'Home',code:'Home',bubbles:true,cancelable:true}));
  await new Promise(resolve=>setTimeout(resolve,40));
  for(let n=0;n<value;n++) {
    document.querySelector('[role="slider"][aria-valuenow]')?.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',code:'ArrowRight',bubbles:true,cancelable:true}));
    await new Promise(resolve=>setTimeout(resolve,40));
  }
  const applied = Number(document.querySelector('[role="slider"]')?.getAttribute('aria-valuenow') ?? -1);
  if(applied !== value) throw new Error('reasoning-not-applied');
  document.querySelector('[role="slider"]')?.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));
  return JSON.stringify({level:applied,label:reasoningPill()?.innerText || ''});
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const plusButton = () => composerForm()?.querySelector('button[data-composer-navigation-target="add-context"],button[data-testid="composer-plus-btn"]');
const toolPillSelector = '[data-system-hint-type="picture_v2"],[data-inline-selection-pill][data-id="picture_v2"]';
const imageModeActive = () => !!composer()?.querySelector(toolPillSelector) ||
  Array.from(composerForm()?.querySelectorAll('button[aria-label]') || []).some(el =>
    !composer()?.contains(el) && /^(이미지 생성 제거|이미지 만들기 제거|Remove (?:Create image|Create images|Image generation))$/i.test(el.getAttribute('aria-label')));
const writePrompt = (prompt, withPill) => {
  const el = composer();
  if (!el || el.tagName === 'TEXTAREA' || !el.isContentEditable) throw new Error('image-composer-unavailable');
  el.focus();
  const paragraphs = prompt.split('\n').map(line => {
    const p = document.createElement('p'); p.textContent = line; return p;
  });
  if (withPill) {
    const pill = document.createElement('span');
    for (const [key, value] of Object.entries({
      contenteditable:'false', 'data-inline-selection-pill':'', 'data-id':'picture_v2',
      'data-symbol':'ecosystemMention', 'data-keyword':'이미지 만들기',
      'data-system-hint-type':'picture_v2',
      class:'inline-flex items-center gap-1 rounded-md bg-token-main-surface-secondary px-2 py-0.5 text-sm font-medium select-none'
    })) pill.setAttribute(key, value);
    pill.textContent = '이미지 만들기';
    paragraphs[0].prepend(pill, document.createTextNode('\u00a0'));
  }
  el.replaceChildren(...paragraphs);
  el.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertHTML'}));
  el.dispatchEvent(new Event('change', {bubbles:true}));
};
const selectImageTool = async () => {
  if (imageModeActive()) return;
  const plus = plusButton();
  if (!enabled(plus)) throw new Error('image-tool-menu-unavailable');
  if (plus.getAttribute('aria-expanded') !== 'true') plus.click();
  const deadline = Date.now() + 4000;
  while (Date.now() < deadline) {
    // Only actionable tool-menu entries. Never click sidebar image navigation,
    // conversation text, or a suggestion that might submit its own prompt.
    const items = Array.from(document.querySelectorAll('button[data-list-navigation-item="true"],[role="menu"] [role="menuitem"]'));
    const item = items.find(el => enabled(el) && el.getClientRects().length &&
      [el, ...el.querySelectorAll('span')].some(label => /^(이미지 생성|이미지 만들기|Create image|Create images|Image generation)$/i.test(label.textContent.trim())));
    if (item) { item.click(); break; }
    await delay(100);
  }
  for (let i = 0; i < 20; i++) {
    if (imageModeActive()) { await delay(250); if (imageModeActive()) return; }
    await delay(100);
  }
  throw new Error('image-mode-not-applied');
};
if (operation === 'composeImage') {
  if (typeof payload.prompt !== 'string' || !payload.prompt.trim()) throw new Error('image-prompt-empty');
  // September 2026 markdown composer rejects the legacy inline pill schema.
  // Keep direct injection for older editors; use the actual tool control on new ones.
  const modern = !!composer()?.hasAttribute('data-composer-markdown');
  writePrompt(payload.prompt, !modern);
  await delay(300);
  if (!imageModeActive()) {
    // Remove any rejected pill's leftover label before using the native tool.
    writePrompt(payload.prompt, false);
    await delay(150);
    await selectImageTool();
  }
  if (!imageModeActive()) throw new Error('image-mode-not-applied');
  return JSON.stringify({ok:true});
}
if (operation === 'verifyImageMode') {
  if (!imageModeActive()) throw new Error('image-mode-not-applied');
  return JSON.stringify({ok:true});
}
if (operation === 'generationMetadata') {
  const id = location.pathname.match(/^\/c\/([0-9a-f-]{36})$/i)?.[1];
  if (!id) throw new Error('metadata-conversation-unavailable');
  // Authentication stays inside this WKWebView. Return only per-image evidence.
  const authResponse = await fetch('/api/auth/session', {credentials:'include'});
  if (!authResponse.ok) throw new Error('metadata-session-unavailable');
  const session = await authResponse.json();
  if (typeof session.accessToken !== 'string') throw new Error('metadata-session-unavailable');
  const response = await fetch('/backend-api/conversation/' + id, {
    credentials:'include', headers:{Authorization:'Bearer ' + session.accessToken}
  });
  if (!response.ok) throw new Error('metadata-http-' + response.status);
  const conversation = await response.json();
  const mapping = conversation.mapping || {};
  const branch = [], seen = new Set();
  let cursor = conversation.current_node;
  while (cursor && mapping[cursor] && !seen.has(cursor)) {
    seen.add(cursor); branch.push(mapping[cursor]); cursor = mapping[cursor].parent;
  }
  const images = new Map();
  const scalar = v => typeof v === 'string' || typeof v === 'number' ? String(v) : null;
  for (const node of branch.reverse()) {
    const message = node.message;
    if (!['assistant','tool'].includes(message?.author?.role)) continue;
    for (const part of message?.content?.parts || []) {
      if (part?.content_type !== 'image_asset_pointer' || typeof part.asset_pointer !== 'string') continue;
      const id = part.asset_pointer.match(/file[-_][A-Za-z0-9]+/)?.[0];
      if (!id) continue;
      const gen = part.metadata?.generation;
      const record = {fileID:id,messageID:message.id || '',genSize:scalar(gen?.gen_size),genSizeV2:scalar(gen?.gen_size_v2)};
      const existing = images.get(id);
      if (!existing) images.set(id, record);
      else {
        for (const key of ['genSize','genSizeV2']) {
          if (existing[key] && record[key] && existing[key] !== record[key]) existing[key] = 'conflict';
          else if (!existing[key] && record[key]) { existing[key] = record[key]; existing.messageID = record.messageID; }
        }
      }
    }
  }
  return JSON.stringify({images:Array.from(images.values())});
}
// Current galleries render one large preview and the remaining originals in
// thumbnail buttons. Identify both by their explicit gallery controls, not size.
const generatedImageIdentity = img => {
  if (img.closest('form,[data-message-author-role="user"],[data-user-message-bubble],[data-chatgpt-search-unit-key$=":user"]')) return null;
  const message = img.closest('[data-message-id],[data-chatgpt-search-message-ids]');
  const responseID = (message?.getAttribute('data-message-id') || message?.getAttribute('data-chatgpt-search-message-ids') || '').trim().split(/\s+/)[0];
  const preview = img.closest('[data-testid="generated-image-preview"]');
  const thumbnail = img.closest('[role="group"][aria-label="생성된 이미지"] button,[role="group"][aria-label="Generated images"] button');
  const control = preview || thumbnail;
  if (!responseID || !control) return null;
  const numbered = control.getAttribute('aria-label')?.match(/^(?:생성된 이미지|(?:Show )?Generated image)\s+(\d+)(?: 표시)?$/i);
  const ordinal = numbered ? Number(numbered[1]) - 1 : preview ? Array.from(message.querySelectorAll('[data-testid="generated-image-preview"] img')).indexOf(img) : -1;
  return ordinal >= 0 ? {responseID, fileID:`generated-${responseID}-${ordinal}`} : null;
};
if (operation === 'snapshot') {
  const userSelector = '[data-message-author-role="user"],[data-user-message-bubble],[data-chatgpt-search-unit-key$=":user"]';
  const assistants = Array.from(document.querySelectorAll('[data-message-author-role="assistant"],main [data-chatgpt-search-message-ids]')).filter(el => !el.closest(userSelector));
  const users = Array.from(document.querySelectorAll('[data-message-author-role="user"],[data-user-message-bubble]'));
  // Current ChatGPT image cards may have no assistant role wrapper. Require an
  // explicit generated-image label in that layout; never treat arbitrary main images as outputs.
  const candidates = Array.from(document.querySelectorAll('main img')).filter(img =>
    !img.closest(userSelector + ',form') &&
    (generatedImageIdentity(img) || img.closest('[data-message-author-role="assistant"]') || /generated image|생성된 이미지|生成的图片/i.test(img.alt || '')));
  const allImages = candidates.map(img => {
    const url = img.currentSrc || img.src;
    const identity = generatedImageIdentity(img);
    const responseID = identity?.responseID || img.closest('[data-message-id]')?.dataset.messageId;
    // Blob URLs change after reloading; message identity survives recovery.
    const blob = url.startsWith('blob:https://chatgpt.com/');
    const id = blob && identity ? identity.fileID : fileID(url);
    return {url, fileID:id, responseID:responseID || `image-${id}`,
      width:img.naturalWidth, height:img.naturalHeight, complete:img.complete,
      supported:blob ? !!identity : /estuary|oaiusercontent|backend-api\/[^?]*content/.test(url)};
  }).filter(img => img.supported);
  const images = Array.from(new Map(allImages.map(image => [image.fileID, image])).values());
  const alerts = Array.from(document.querySelectorAll('[role="alert"]')).map(el => el.innerText).join('\n');
  const lastAssistant = assistants.at(-1);
  const replySelector = '.markdown,[data-message-content],[data-markdown-text-style="assistant-message"]';
  const reply = lastAssistant ? Array.from(lastAssistant.querySelectorAll(replySelector)).filter(el=>!el.parentElement?.closest(replySelector)).map(el=>el.innerText).join('\n\n').trim() : '';
  const serviceError = /something went wrong|error generating|image generation failed|이미지 생성.*(실패|오류)|문제가 발생/i.test(alerts) ? alerts : '';
  const limitation = /you.ve reached.*limit|too many requests|rate limit|사용 한도에 도달|생성 한도에 도달|너무 많은 요청/i.test(alerts + '\n' + reply);
  const login = !!document.querySelector('[data-testid="login-button"]');
  return JSON.stringify({
    path: location.pathname, ready: !!composer() && !login && (!composer().hasAttribute('data-composer-markdown') || (enabled(plusButton()) && enabled(reasoningPill()))), login,
    generating: !!document.querySelector('button[data-testid="stop-button"],button[aria-label*="Stop streaming"],button[aria-label*="생성 중지"],button[aria-label*="응답 중지"],button[aria-label*="Stop"],form button[aria-label="중지"],form button[aria-label="응답 중지"],[data-is-streaming="true"]'),
    assistantCount: Math.max(assistants.length, images.length), userCount: users.length, reply: reply.slice(0, 60000), serviceError,
    composerEmpty: !(composer()?.innerText || composer()?.value || '').trim(),
    sendEnabled: enabled(send()), limitation, images,
    fileInputs: document.querySelectorAll('input[type="file"]').length
  });
}
if (operation === 'type') {
  const el = composer(); if (!el) throw new Error('composer-missing'); el.focus();
  if (el.tagName === 'TEXTAREA') {
    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
    setter.call(el, payload.prompt);
  } else {
    el.replaceChildren(...payload.prompt.split('\n').map(line => { const p = document.createElement('p'); p.textContent = line; return p; }));
  }
  el.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText', data:payload.prompt}));
  el.dispatchEvent(new Event('change', {bubbles:true}));
  return JSON.stringify({ok:true});
}
if (operation === 'attach') {
  const input = Array.from((composerForm() || document).querySelectorAll('input[type="file"]')).find(el => enabled(el) && /image\//.test(el.accept)) || Array.from((composerForm() || document).querySelectorAll('input[type="file"]')).find(enabled);
  if (!input) throw new Error('file-input-missing');
  input.value = ''; input.click(); return JSON.stringify({ok:true});
}
if (operation === 'attachments') {
  const el = composer();
  const form = el?.closest('form') || el?.parentElement?.parentElement?.parentElement;
  const previews = form ? Array.from(form.querySelectorAll('img')).filter(img => img.naturalWidth > 0 && !/avatar/.test(img.src)) : [];
  const removeButtons = form ? Array.from(form.querySelectorAll('button')).filter(button => /remove.*(file|attachment)|첨부.*제거|파일.*제거|remove attachment/i.test(button.getAttribute('aria-label') || '')) : [];
  const busy = form ? !!form.querySelector('[role="progressbar"],[aria-busy="true"]') : false;
  return JSON.stringify({count:Math.max(previews.length, removeButtons.length), busy, sendEnabled:enabled(send())});
}
if (operation === 'submit') {
  if (!imageModeActive()) throw new Error('image-mode-not-applied');
  const button = send(); if (!enabled(button)) throw new Error('send-unavailable');
  button.click(); return JSON.stringify({ok:true});
}
if (operation === 'download') {
  const url = new URL(payload.url, location.href);
  const generatedBlob = url.protocol === 'blob:' && url.origin === location.origin && Array.from(document.querySelectorAll('main img')).some(img => (img.currentSrc || img.src) === url.href && generatedImageIdentity(img));
  if (!generatedBlob && (url.protocol !== 'https:' || !(url.hostname === 'chatgpt.com' || url.hostname.endsWith('.oaiusercontent.com') || url.hostname.endsWith('.oaidusercontent.com')))) throw new Error('unexpected-image-origin');
  const response = await fetch(url.href, {credentials:'include'});
  if (!response.ok) throw new Error(`download-http-${response.status}`);
  const blob = await response.blob();
  if (blob.size > 50*1024*1024 || !blob.type.startsWith('image/')) throw new Error('invalid-image-response');
  const data = await new Promise((resolve,reject) => { const reader = new FileReader(); reader.onload=()=>resolve(reader.result); reader.onerror=reject; reader.readAsDataURL(blob); });
  return JSON.stringify({base64:data.split(',')[1], mime:blob.type, size:blob.size});
}
throw new Error('unsupported-operation');
