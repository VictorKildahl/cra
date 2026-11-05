// Runs only in Cra's isolated world. The proposed address stays in the native browser UI
// until the user accepts it. The binding belongs to this world and to opted-in browsers.
(() => {
  const cra = window.__cra;
  if (!cra || cra.signupConfigure || window !== window.top) return;
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
  if (location.protocol !== 'https:' && !(location.protocol === 'http:' && loopback)) return;

  let listeners, field, fieldObserver, layoutObserver, sizeObserver, gesture;
  let anchor, pendingAnchor, timer, menuTimer, revision = 0;
  const report = payload => {
    if (typeof window.craSignupField === 'function') window.craSignupField(payload);
  };
  const dismiss = () => {
    clearTimeout(timer);
    clearTimeout(menuTimer);
    layoutObserver?.disconnect();
    fieldObserver?.disconnect();
    sizeObserver?.disconnect();
    fieldObserver = layoutObserver = sizeObserver = null;
    field = gesture = null;
    if (anchor && !pendingAnchor) report('');
    anchor = pendingAnchor = null;
  };

  // Only an empty, editable field under the pointer could receive an accepted address.
  function bounds(input) {
    if (!(input instanceof HTMLInputElement) || !input.isConnected || document.activeElement !== input ||
        !['email', 'text'].includes(input.type) || input.readOnly || input.matches(':disabled, [aria-disabled="true"]') ||
        input.value !== '' || input.closest('[inert], [aria-hidden="true"]') ||
        !input.checkVisibility({opacityProperty: true, visibilityProperty: true})) return null;
    const r = input.getBoundingClientRect();
    const left = Math.max(0, r.left), right = Math.min(innerWidth, r.right);
    const top = Math.max(0, r.top), bottom = Math.min(innerHeight, r.bottom);
    if (right - left < 12 || bottom - top < 8 ||
        document.elementFromPoint((left + right) / 2, (top + bottom) / 2) !== input) return null;
    return r;
  }

  function hint(text) {
    return (text || '').slice(0, 256).replace(/[^\s@<>]+@[^\s@<>]+/g, 'email example')
      .replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 100);
  }
  const labels = node => [node.getAttribute('aria-label'),
    ...(node.getAttribute('aria-labelledby') || '').split(/\s+/).slice(0, 3).filter(Boolean)
      .map(id => document.getElementById(id)?.textContent),
    ...Array.from(node.labels || []).slice(0, 2).map(label => label.textContent)].filter(Boolean).map(hint).join(' ');
  function fieldHints(input) {
    const parts = {type: input.type, autocomplete: input.autocomplete, label: labels(input),
      name: input.name, id: input.id, placeholder: input.placeholder};
    return Object.entries(parts).filter(([, v]) => v).map(([k, v]) => k + ': ' + hint(v)).join('\n');
  }

  // Scope signup evidence to this field's own form or dialog. A newsletter in the
  // footer must not inherit "Create account" from a different form on the page.
  function signupContext(input) {
    const scoped = input.form || input.closest('[role="form"], dialog, [role="dialog"]');
    const root = scoped || input.closest('main, article, section') || document.body;
    if (!root) return false;
    const headings = Array.from(root.querySelectorAll('h1,h2,legend,[role="heading"]')).slice(0, 6);
    const buttons = Array.from(root.querySelectorAll('button, input[type="submit"]')).slice(0, 16);
    const heading = [root.getAttribute('aria-label'), ...headings.map(n => n.textContent)].map(hint).join(' ');
    const buttonText = n => hint(n.textContent || n.getAttribute('aria-label') || n.getAttribute('value'));
    const wording = [heading, ...buttons.map(buttonText)].join(' ');
    if (/newsletter|invite|invitation|recipient|share (?:this |with)|send (?:a )?gift|subscribe/i.test(wording)) return false;
    if (root.querySelector('input[autocomplete~="current-password" i]') ||
        /forgot|reset password|change password|recover(?:y| account)/i.test(heading)) return false;
    const signup = /\b(sign[ -]?up|register|registration|create (?:your |an? |new )?account|join now)\b/i;
    if (signup.test(heading) || root.querySelector('input[autocomplete~="new-password" i]')) return true;
    const submit = root.querySelector('button[type="submit"], input[type="submit"]');
    const signIn = /\b(log[ -]?in|sign[ -]?in|password reset|forgot password)\b/i;
    if (signIn.test(heading) || (submit && signIn.test(buttonText(submit)))) return false;
    if (submit && signup.test(buttonText(submit))) return true;
    // Many pages place the heading just outside the form, or show an email-only first step.
    const pageNames = [location.pathname.split('/').pop(), document.title].map(hint).join(' ');
    return (signup.test(pageNames) && document.forms.length <= 1) ||
      (signup.test(wording) && !signIn.test(wording));
  }

  // Bitwarden hosts its menu in a closed shadow root inside a top-layer popover.
  // Respect any open popup beside the field. Its contents belong to the provider.
  function competingMenu(input, r) {
    const menus = document.querySelectorAll(':popover-open, [role="listbox"], iframe[src^="chrome-extension://"]');
    return Array.from(menus).some(menu => {
      if (menu.contains(input) || !menu.checkVisibility({opacityProperty:true, visibilityProperty:true})) return false;
      // The closed shadow's iframe can float outside its otherwise zero-sized host.
      // Hit-test where a list would open, leaving an in-field password-manager icon alone.
      const x = Math.min(r.right - 4, Math.max(0, r.left) + 24);
      if ([r.bottom + 8, r.top - 8].some(y => {
        const hit = document.elementFromPoint(x, y);
        return hit && (hit === menu || menu.contains(hit));
      })) return true;
      const b = menu.getBoundingClientRect();
      return b.width > 60 && b.height > 20 && b.left < r.right && b.right > r.left &&
        b.top < r.bottom + 16 && b.bottom > r.top - 16;
    });
  }

  function details(input) {
    const r = bounds(input);
    if (!r || !signupContext(input) || competingMenu(input, r)) return null;
    const hints = fieldHints(input);
    if (/one-time-code|verification|passcode|password|\botp\b|recipient|invite|friend|referr(?:al|er)|billing|shipping|promo.?code/i.test(hints)) return null;
    return {url:location.origin, signup:true, hints, x:r.x, y:r.y,
      width:r.width, height:r.height, viewportWidth:innerWidth, viewportHeight:innerHeight};
  }
  // Subpixel rounding, fonts finishing loading and small viewport corrections should
  // not tear down the native button during a click. Compare with the published anchor
  // rather than the last sample so many small shifts still trigger repositioning.
  function sameGeometry(a, b) {
    return ['x', 'y', 'width', 'height'].every(k => Math.abs(a[k] - b[k]) <= 3) &&
      ['viewportWidth', 'viewportHeight'].every(k => Math.abs(a[k] - b[k]) <= 4);
  }
  function publish(metadata) {
    anchor = {...metadata, token:gesture + ':' + crypto.randomUUID()};
    pendingAnchor = null;
    report(JSON.stringify(anchor));
  }
  function checkLayout(settled = false) {
    if (!anchor) return;
    const current = details(field);
    if (!current || current.hints !== anchor.hints || current.url !== anchor.url) { dismiss(); return; }
    if (!pendingAnchor && sameGeometry(anchor, current)) return;
    if (pendingAnchor && sameGeometry(pendingAnchor, current)) {
      if (settled) publish(current);
      return;
    }
    // Reject the old token immediately. While the same focused field is still moving,
    // debounce just its replacement. Every ordinary dismissal cancels this timer too.
    if (!pendingAnchor) report('');
    pendingAnchor = current;
    clearTimeout(timer);
    timer = setTimeout(() => checkLayout(true), 120);
  }
  function offer(input) {
    if (!bounds(input)) { dismiss(); return; }
    dismiss();
    field = input;
    gesture = crypto.randomUUID();
    timer = setTimeout(() => {
      const metadata = details(input);
      if (!metadata) { dismiss(); return; }
      publish(metadata);
      const recheck = () => checkLayout();
      fieldObserver = new MutationObserver(recheck);
      fieldObserver.observe(input, {attributes:true, attributeFilter:['type','readonly','disabled','hidden','style','class','autocomplete']});
      // A field can be removed or moved by its ancestors. Avoid watching unrelated
      // subtrees or reading character data.
      for (let parent = input.parentElement; parent; parent = parent.parentElement) {
        fieldObserver.observe(parent, {childList:true, attributes:true, attributeFilter:['style','class','hidden']});
      }
      layoutObserver = new PerformanceObserver(recheck);
      layoutObserver.observe({type:'layout-shift'});
      sizeObserver = new ResizeObserver(recheck);
      sizeObserver.observe(input);
    }, 140);
  }

  cra.signupDismiss = expected => {
    // The native Escape may arrive while the replacement anchor is settling. Both
    // belong to the same click, but a later deliberate click starts a new gesture.
    if (!gesture || typeof expected !== 'string' || !expected.startsWith(gesture + ':')) return false;
    dismiss();
    return true;
  };
  cra.signupMatches = expected => {
    if (!anchor || pendingAnchor || expected !== anchor.token) return false;
    checkLayout();
    return !!anchor && !pendingAnchor && expected === anchor.token;
  };
  cra.signupFill = (expected, email) => {
    const target = field;
    if (!listeners || typeof email !== 'string' || !cra.signupMatches(expected)) return false;
    dismiss();
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(target, email);
    target.dispatchEvent(new Event('input', {bubbles:true, composed:true}));
    target.dispatchEvent(new Event('change', {bubbles:true}));
    return true;
  };

  cra.signupConfigure = (enabled, update = 0) => {
    if (revision > update) return;
    revision = update;
    if (!enabled) {
      dismiss(); listeners?.abort(); listeners = null;
      return;
    }
    if (listeners || typeof window.craSignupField !== 'function') return;
    listeners = new AbortController();
    const on = (name, fn) => window.addEventListener(name, fn, {capture:true, passive:true, signal:listeners.signal});
    on('click', e => { if (e.isTrusted && e.button === 0) offer(e.composedPath()[0]); });
    on('keyup', e => { if (e.isTrusted && e.key === 'Tab') offer(document.activeElement); });
    on('keydown', e => { if (e.key === 'Escape' || e.key === 'Tab') dismiss(); });
    on('beforeinput', dismiss); on('input', dismiss); on('focusout', dismiss);
    on('blur', e => { if (e.target === window) dismiss(); });
    on('resize', () => checkLayout());
    for (const name of ['scroll','pagehide','popstate','hashchange','visibilitychange']) on(name, dismiss);
    on('toggle', () => {
      if (!field) return;
      const check = () => { if (field && competingMenu(field, field.getBoundingClientRect())) dismiss(); };
      check();
      // Providers may size the iframe just after opening its popover.
      clearTimeout(menuTimer);
      if (field) menuTimer = setTimeout(check, 200);
    });
  };
  cra.signupConfigure(typeof window.craSignupField === 'function');
})();
