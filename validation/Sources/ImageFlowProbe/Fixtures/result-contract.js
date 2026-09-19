// Offline DOM contract: synthetic nodes, no requests, no private endpoints called.
(() => {
  const root = document.createElement('section');
  document.body.append(root);
  const checks = [];
  const fileID = src => src.match(/file[-_][A-Za-z0-9]+/)?.[0];
  function select({conversation, expectedConversation, responseID, baseline, stable}) {
    if (conversation !== expectedConversation || root.querySelector('[data-testid="stop-button"]')) return [];
    const response = Array.from(root.querySelectorAll('[data-message-author-role="assistant"]'))
      .find(el => el.dataset.messageId === responseID);
    if (!response) return [];
    const candidates = Array.from(response.querySelectorAll('img')).filter(img => {
      const src = img.currentSrc || img.src;
      return fileID(src) && !baseline.has(fileID(src)) && !baseline.has(src);
    });
    if (!candidates.length || candidates.some(img => !img.complete || img.naturalWidth <= 0 ||
        img.naturalHeight <= 0 || (stable[img.currentSrc || img.src] ?? 0) < 5)) return [];
    return candidates.map(img => fileID(img.currentSrc || img.src));
  }
  function turn(role, id) {
    const el = document.createElement('div');
    el.dataset.messageAuthorRole = role; el.dataset.messageId = id;
    root.append(el); return el;
  }
  function picture(parent, id, query = '', complete = true) {
    const img = document.createElement('img');
    const src = `https://fixture.invalid/content?id=${id}${query}`;
    // Override properties without setting the actual src attribute: no network.
    Object.defineProperties(img, {
      src: {value: src}, currentSrc: {value: src},
      naturalWidth: {value: 512}, naturalHeight: {value: 512},
      complete: {value: complete, configurable: true}
    });
    parent.append(img); return img;
  }
  function check(name, actual, expected) {
    checks.push({name, passed: JSON.stringify(actual) === JSON.stringify(expected),
                 detail: 'synthetic DOM contract, not current ChatGPT selectors'});
  }
  picture(turn('assistant', 'old'), 'file_old');
  picture(turn('user', 'request'), 'file_reference');
  const response = turn('assistant', 'new');
  const a = picture(response, 'file_newA');
  const b = picture(response, 'file_newB');
  const stale = picture(response, 'file_old', '&token=changed');
  const args = {conversation: 'conv-a', expectedConversation: 'conv-a', responseID: 'new',
    baseline: new Set(['file_old']), stable: {[a.src]: 6, [b.src]: 6, [stale.src]: 6}};
  check('result-multiple-new-images-only', select(args), ['file_newA', 'file_newB']);
  check('result-wrong-conversation-rejected', select({...args, conversation: 'conv-b'}), []);
  check('result-missing-response-rejected', select({...args, responseID: 'absent'}), []);
  check('result-user-reference-rejected', select({...args, responseID: 'request'}), []);
  check('result-url-token-change-still-old-file', select({...args, responseID: 'old',
    stable: {'https://fixture.invalid/content?id=file_old': 6}}), []);
  const stop = document.createElement('button'); stop.dataset.testid = 'stop-button'; root.append(stop);
  check('result-generation-active-rejected', select(args), []); stop.remove();
  Object.defineProperty(a, 'complete', {value: false, configurable: true});
  check('result-incomplete-decode-rejected', select(args), []);
  Object.defineProperty(a, 'complete', {value: true, configurable: true});
  check('result-progressive-url-not-settled', select({...args, stable: {...args.stable, [a.src]: 0}}), []);
  root.remove();
  return checks;
})();
