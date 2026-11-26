(() => {
    function disableLoaderWall(script) {
        // Some publishers also enable the failed SDK's wall in their hydration data.
        const source = script.textContent;
        if (!source.includes('"adBlockWallEnabled"') || !source.includes('"adShieldEnabled"')) return;
        // Preserve the source spelling of all other fields (including large JSON numbers).
        // Change a unique boolean only after confirming its sibling identifies this SDK.
        const flag = /"adBlockWallEnabled"\s*:\s*true\b/g;
        const matches = source.match(flag);
        if (matches?.length !== 1) return;
        try {
            let found = false;
            JSON.parse(source, (_key, value) => {
                if (value?.adShieldEnabled === true && value.adBlockWallEnabled === true) found = true;
                return value;
            });
            if (!found) return;
            script.textContent = source.replace(flag, match => match.slice(0, -4) + 'false');
        } catch {
            // Leave malformed page data untouched.
        }
    }

    const loaderSelector = 'script[data-sdk][onerror][nowprocket][src]';
    const isLoader = script => script instanceof HTMLScriptElement
        && script.matches(loaderSelector) && script.src.startsWith('https://html-load.com/');
    let loaderFailed = false;

    // Deferred page modules may read the initial state before Chromium delivers the
    // asynchronous script error. The interactive transition precedes those modules.
    document.addEventListener('readystatechange', () => {
        if (document.readyState !== 'interactive') return;
        if (!loaderFailed && !Array.from(document.querySelectorAll(loaderSelector)).some(isLoader)) return;
        for (const script of document.querySelectorAll('script[type="application/json"]')) {
            disableLoaderWall(script);
        }
    }, { once: true });

    window.addEventListener('error', event => {
        const script = event.target;
        if (!event.isTrusted || !isLoader(script)) return;
        loaderFailed = true;
        // Suppress just this inline failure callback. Other listeners still receive the error.
        script.removeAttribute('onerror');
    }, true);
})();
