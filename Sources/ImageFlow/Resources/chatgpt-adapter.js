// Runs only in the worker's authenticated chatgpt.com main frame.
if (location.hostname !== 'chatgpt.com') throw new Error('unexpected-origin');
const composer = () => document.querySelector('#prompt-textarea,textarea[data-id="root"],div[contenteditable="true"].ProseMirror');
const send = () => document.querySelector('button[data-testid="send-button"],button[data-testid="composer-send-button"],button[aria-label="Send prompt"],button[aria-label="프롬프트 보내기"]');
const enabled = el => !!el && !el.disabled && el.getAttribute('aria-disabled') !== 'true';
const fileID = s => s.match(/file[-_][A-Za-z0-9]+/)?.[0] || s;
const reasoningPill = () => document.querySelector('[data-composer-transition-slot="trailing"] button.__composer-pill[aria-haspopup="menu"]') || Array.from((composer()?.closest('form') || document).querySelectorAll('button.__composer-pill')).find(el => /Instant|추론|Thinking|Reasoning|High|Standard|Light|Extended|Heavy|Pro|Max|Medium|Low|최대|낮|중간|높|표준/i.test(el.innerText));
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
const imageModeActive = () => !!composer()?.querySelector('[data-system-hint-type="picture_v2"],[data-inline-selection-pill][data-id="picture_v2"]');
if (operation === 'imageMode') {
  if (imageModeActive()) return JSON.stringify({ok:true});
  const plus = document.querySelector('button[data-testid="composer-plus-btn"],button#composer-plus-btn');
  if (!plus) throw new Error('image-mode-menu-unavailable');
  if (plus.getAttribute('aria-expanded') !== 'true') {
    plus.focus();
    plus.click();
    await new Promise(resolve=>setTimeout(resolve,150));
    if (plus.getAttribute('aria-expanded') !== 'true') plus.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',code:'ArrowDown',bubbles:true,cancelable:true}));
  }
  let choice;
  for (let attempt=0; attempt<20; attempt++) {
    choice = Array.from(document.querySelectorAll('button,[role="menuitem"],[role="option"],[role="button"],[tabindex]')).find(el =>
      el.getClientRects().length && /^(Create (an )?image|이미지 만들기)(\s|$)/i.test(el.innerText.trim()) && enabled(el));
    if (choice) break;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  if (!choice) throw new Error('image-mode-choice-unavailable');
  choice.click();
  for (let attempt=0; attempt<20; attempt++) {
    if (imageModeActive()) return JSON.stringify({ok:true});
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  throw new Error('image-mode-not-applied');
}
if (operation === 'verifyImageMode') {
  if (!imageModeActive()) throw new Error('image-mode-not-applied');
  return JSON.stringify({ok:true});
}
if (operation === 'snapshot') {
  const assistants = Array.from(document.querySelectorAll('[data-message-author-role="assistant"]'));
  const users = Array.from(document.querySelectorAll('[data-message-author-role="user"]'));
  // Current ChatGPT image cards may have no assistant role wrapper. Require an
  // explicit generated-image label in that layout; never treat arbitrary main images as outputs.
  const candidates = Array.from(document.querySelectorAll('main img')).filter(img =>
    !img.closest('[data-message-author-role="user"],form') &&
    (img.closest('[data-message-author-role="assistant"]') || /generated image|생성된 이미지|生成的图片/i.test(img.alt || '')));
  const allImages = candidates.map(img => ({
    url: img.currentSrc || img.src, fileID: fileID(img.currentSrc || img.src),
    responseID: img.closest('[data-message-id]')?.dataset.messageId || `image-${fileID(img.currentSrc || img.src)}`,
    width: img.naturalWidth, height: img.naturalHeight, complete: img.complete
  })).filter(img => /estuary|oaiusercontent|backend-api\/[^?]*content/.test(img.url));
  const images = Array.from(new Map(allImages.map(image => [image.fileID, image])).values());
  const alerts = Array.from(document.querySelectorAll('[role="alert"]')).map(el => el.innerText).join('\n');
  const lastAssistant = assistants.at(-1);
  const reply = lastAssistant ? Array.from(lastAssistant.querySelectorAll('.markdown,[data-message-content]')).filter(el=>!el.parentElement?.closest('.markdown,[data-message-content]')).map(el=>el.innerText).join('\n\n').trim() : '';
  const serviceError = /something went wrong|error generating|image generation failed|이미지 생성.*(실패|오류)|문제가 발생/i.test(alerts) ? alerts : '';
  const limitation = /you.ve reached.*limit|too many requests|rate limit|사용 한도에 도달|생성 한도에 도달|너무 많은 요청/i.test(alerts + '\n' + reply);
  const login = !!document.querySelector('[data-testid="login-button"]');
  return JSON.stringify({
    path: location.pathname, ready: !!composer() && !login, login,
    generating: !!document.querySelector('button[data-testid="stop-button"],button[aria-label*="Stop streaming"],button[aria-label*="생성 중지"],button[aria-label*="응답 중지"],button[aria-label*="Stop"],[data-is-streaming="true"]'),
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
  const input = document.querySelector('input[type="file"]');
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
  if (url.protocol !== 'https:' || !(url.hostname === 'chatgpt.com' || url.hostname.endsWith('.oaiusercontent.com') || url.hostname.endsWith('.oaidusercontent.com'))) throw new Error('unexpected-image-origin');
  const response = await fetch(url.href, {credentials:'include'});
  if (!response.ok) throw new Error(`download-http-${response.status}`);
  const blob = await response.blob();
  if (blob.size > 50*1024*1024 || !blob.type.startsWith('image/')) throw new Error('invalid-image-response');
  const data = await new Promise((resolve,reject) => { const reader = new FileReader(); reader.onload=()=>resolve(reader.result); reader.onerror=reject; reader.readAsDataURL(blob); });
  return JSON.stringify({base64:data.split(',')[1], mime:blob.type, size:blob.size});
}
throw new Error('unsupported-operation');
