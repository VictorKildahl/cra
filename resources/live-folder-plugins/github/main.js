const presentation = {
    folderTitle: "Pull Requests", menuTitle: "Pull Requests", icon: "icon.svg",
    filters: [
        {id: "authored", title: "Created by Me", enabledByDefault: true},
        {id: "review", title: "Review Requests", enabledByDefault: true},
        {id: "teamReview", title: "Team Review Requests", enabledByDefault: true}
    ],
    groups: {title: "Repositories", description: "This list is generated based on your currently active pull requests."},
    statusMessages: {
        notSignedIn: "Not signed in to GitHub", rateLimited: "GitHub rate limit exceeded",
        unexpectedPage: "Failed to update: unexpected GitHub response", network: "GitHub can’t be reached"
    }
};

let currentState = {};
function fail(code) { throw Object.assign(new Error(code), {state: currentState}); }
function matches(pattern, text) { return [...text.matchAll(pattern)]; }
function unique(items) {
    const seen = new Set();
    return items.filter(item => {
        const key = item.url.toLowerCase();
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
    });
}
function entities(text) {
    const names = {lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " "};
    return text.replace(/&(lt|gt|quot|apos|nbsp);/g, (_, name) => names[name])
        .replace(/&#(x?)([0-9a-fA-F]+);/g, (original, hex, digits) => {
            const value = parseInt(digits, hex ? 16 : 10);
            return value >= 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff)
                ? String.fromCodePoint(value) : original;
        }).replace(/&amp;/g, "&");
}
function plain(text) { return entities(text.replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim(); }
function login(value) { return value?.login || value?.displayLogin || value?.display_login || null; }
function date(value) {
    const seconds = typeof value === "number" ? (value > 1e11 ? value / 1000 : value) : Date.parse(value) / 1000;
    return Number.isFinite(seconds) ? seconds : null;
}
function pullPath(link) {
    const m = /(?:^|github\.com)\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/pull\/(\d+)/.exec(link);
    return m ? {owner: m[1], repo: m[2], number: Number(m[3])} : null;
}
function repository(value) {
    if (typeof value === "string") return value.split("/").length === 2 ? value : null;
    if (!value || typeof value !== "object") return null;
    if (value.repository) return repository(value.repository);
    const nwo = value.nameWithOwner ?? value.name_with_owner ?? value.full_name;
    if (nwo) return repository(nwo);
    const owner = login(value.owner) ?? (typeof value.owner === "string" ? value.owner : null) ?? value.owner_login ?? value.ownerLogin;
    return owner && value.name ? owner + "/" + value.name : null;
}
function parseItem(d) {
    const type = d.__typename ?? d.type ?? "";
    if (type && type !== "PullRequest" && !String(type).toLowerCase().includes("pull")) return null;
    const number = Number(d.number ?? d.num);
    const title = d.title ?? d.hl_title ?? d.titleHTML;
    if (!Number.isInteger(number) || typeof title !== "string") return null;
    const link = [d.url, d.permalink, d.html_url, d.resourcePath, d.path, d.href].find(v => typeof v === "string");
    const path = link ? pullPath(link) : null;
    const group = path?.number === number ? path.owner + "/" + path.repo :
        repository(d.repository ?? d.repo ?? d.repoNameWithOwner ?? d.repository_nwo);
    if (!group) return null;
    if (!(link?.includes("/pull/") || type === "PullRequest" || d.isDraft != null || d.is_draft != null ||
        d.reviewDecision != null || d.pull_request != null || d.issue?.issue?.pull_request_id != null ||
        d.reviewable_state != null || d.merged != null || d.num != null)) return null;
    const url = "https://github.com/" + group + "/pull/" + number;
    return {id: url, url, title: plain(title), subtitle: login(d.author) ?? login(d.user) ?? d.author_name ?? d.authorLogin ?? null,
        group, createdAt: date(d.createdAt ?? d.created_at ?? d.created), updatedAt: date(d.updatedAt ?? d.updated_at ?? d.updated)};
}
function walk(root, visitor, limit, depth = 0) {
    if (!root || typeof root !== "object" || depth >= limit) return;
    if (visitor(root)) return;
    for (const child of Object.values(root)) walk(child, visitor, limit, depth + 1);
}
function parseJSON(root) {
    const items = [];
    walk(root, value => { const item = parseItem(value); if (item) items.push(item); return !!item; }, 40);
    let viewer = null;
    walk(root, value => {
        if (viewer) return true;
        for (const key of ["viewer", "currentUser", "current_user"]) viewer ||= login(value[key]);
        viewer ||= value.current_user_login || value.viewerLogin || null;
        return !!viewer;
    }, 12);
    return {items: unique(items), viewer};
}
function attribute(name, tag) { return new RegExp('(?:^|\\s)' + name + '="([^"]*)"').exec(tag)?.[1] ?? null; }
function meta(name, html) {
    for (const m of matches(/<meta\b[^>]*>/g, html)) {
        if (attribute("name", m[0]) === name) return entities(attribute("content", m[0]) ?? "");
    }
    return null;
}
function parseHTML(html) {
    const chunks = html.split("js-issue-row"), items = [];
    for (const chunk of chunks.length > 1 ? chunks.slice(1) : chunks) {
        for (const m of matches(/<a\b([^>]*)>([\s\S]*?)<\/a>/g, chunk)) {
            const href = attribute("href", m[1]), path = href ? pullPath(href) : null;
            if (!path || !href.endsWith("/pull/" + path.number) ||
                !(attribute("data-hovercard-type", m[1]) === "pull_request" || /markdown-title|js-navigation-open/.test(m[1]))) continue;
            const title = plain(m[2]);
            if (!title) continue;
            const author = /<a\b[^>]*data-hovercard-type="user"[^>]*>([\s\S]*?)<\/a>/.exec(chunk)?.[1];
            const url = "https://github.com/" + path.owner + "/" + path.repo + "/pull/" + path.number;
            items.push({id: url, url, title, subtitle: author ? plain(author) : null, group: path.owner + "/" + path.repo,
                createdAt: date(/<relative-time[^>]*datetime="([^"]+)"/.exec(chunk)?.[1])});
            if (chunks.length > 1) break;
        }
    }
    return unique(items);
}
function read(url) {
    const response = cra.session.fetch(url, {headers: {Accept: "application/json", "X-Requested-With": "XMLHttpRequest", "GitHub-Verified-Fetch": "true"}});
    const body = response.body, path = response.url.replace(/^https?:\/\/[^/]+/, "").split(/[?#]/)[0];
    const enterprise = /^\/enterprises\/([^/]+)\/sso$/.exec(path)?.[1];
    if (enterprise) currentState.enterprise = enterprise;
    if (response.status === 0) fail("network");
    if (path === "/login" || path.startsWith("/session") || /^\/(enterprises|orgs)\/[^/]+\/sso$/.test(path)) fail("notSignedIn");
    if (response.status === 429 || (response.status === 403 && /rate limit/i.test(body))) fail("rateLimited");
    if (response.status === 401 || (body.length < 2000 && /authenticate you/i.test(body)) || body.includes('"logged_in":false')) fail("notSignedIn");
    if (response.status < 200 || response.status >= 300) fail("unexpectedPage");
    const elsewhere = path && !path.startsWith("/pulls") && !path.startsWith("/search");
    const sso = matches(/\/orgs\/([A-Za-z0-9_.-]+)\/sso/g, body).map(m => m[1]);
    for (const m of matches(/"protected_org_logins"\s*:\s*\[([^\]]*)\]/g, body))
        sso.push(...matches(/"([A-Za-z0-9_.-]+)"/g, m[1]).map(v => v[1]));
    let parsed;
    if (/^[\s]*[\[{]/.test(body)) {
        try { parsed = parseJSON(JSON.parse(body)); } catch (_) { fail("unexpectedPage"); }
        if (!parsed.items.length && elsewhere) fail("unexpectedPage");
    } else {
        parsed = {items: [], viewer: meta("user-login", body) ?? meta("octolytics-actor-login", body)};
        if (!parsed.viewer && body.includes('name="user-login"')) fail("notSignedIn");
        let sawPayload = false;
        for (const m of matches(/<script[^>]*type="application\/json"[^>]*>([\s\S]*?)<\/script>/g, body)) {
            let payload;
            try { payload = JSON.parse(m[1]); } catch (_) { continue; }
            sawPayload = true;
            const result = parseJSON(payload);
            parsed.viewer ||= result.viewer;
            parsed.items.push(...result.items);
        }
        if (!parsed.items.length) parsed.items = parseHTML(body);
        parsed.items = unique(parsed.items);
        if (!parsed.items.length && (elsewhere || (!sawPayload && !body.includes("blankslate")))) fail("unexpectedPage");
    }
    return {...parsed, sso: [...new Set(sso)]};
}
function search(query) {
    let first, error;
    try {
        first = read("https://github.com/pulls?q=" + encodeURIComponent(query));
        if (first.items.length) return first;
    } catch (e) { if (e.message !== "unexpectedPage") throw e; error = e; }
    try { return read("https://github.com/search?q=" + encodeURIComponent(query) + "&type=pullrequests"); }
    catch (_) { if (first) return first; throw error; }
}
function refresh(input) {
    currentState = {...input.state};
    const queries = {authored: "author:@me", review: "user-review-requested:@me", teamReview: "review-requested:@me"};
    const pages = [];
    let failure;
    for (const filter of presentation.filters) {
        if (!input.filters.includes(filter.id)) continue;
        try { pages.push({filter: filter.id, ...search("is:pr is:open archived:false " + queries[filter.id] + " sort:updated-desc")}); }
        catch (e) { if (failure?.message !== "notSignedIn") failure = e; }
    }
    if (failure) throw failure;
    const viewer = pages.find(page => page.viewer)?.viewer;
    const items = new Map();
    for (const page of pages) for (const item of page.items) {
        if (!item.subtitle && page.filter === "authored") item.subtitle = viewer ?? null;
        const previous = items.get(item.url);
        if (previous) {
            previous.subtitle ??= item.subtitle;
            previous.createdAt ??= item.createdAt;
            previous.updatedAt ??= item.updatedAt;
        } else items.set(item.url, item);
    }
    const orgs = [...new Set(pages.flatMap(page => page.sso))].sort();
    return {
        items: [...items.values()].sort((a, b) => {
            const left = a.createdAt ?? a.updatedAt, right = b.createdAt ?? b.updatedAt;
            return left != null && right != null ? right - left : 0;
        }),
        actions: orgs.map(org => ({title: "Sign In to " + org + " with SSO…", url: "https://github.com/orgs/" + org + "/sso"})),
        actionMessage: orgs.length ? "SSO ensures all of your organizations’ PRs appear" : null,
        warning: orgs.length ? "Login with SSO to unlock this folder" : null,
        preservedGroups: (input.groups ?? []).filter(group => orgs.some(org => group.toLowerCase().startsWith(org.toLowerCase() + "/")))
    };
}
return {
    migrate(input) {
        const bits = input.filter?.attributes?.rawValue ?? input.filter?.attributes ?? 7;
        return {settings: {}, filters: ["authored", "review", "teamReview"].filter((_, i) => bits & [1, 2, 4][i]),
            state: input.enterprise ? {enterprise: input.enterprise} : {}};
    },
    describe() { return presentation; }, refresh,
    signIn(input) {
        return {title: "Sign In to GitHub…", warning: "Sign back in to GitHub.",
            emptyText: "Pull requests from you and your team will show up here automatically",
            failureText: "We’re having trouble connecting to GitHub; click here to see your Pull Requests.",
            failureURL: "https://github.com/pulls", instanceLabel: "GitHub",
            url: input.state?.enterprise ? "https://github.com/enterprises/" + encodeURIComponent(input.state.enterprise) + "/sso" : "https://github.com/login?return_to=%2Fpulls"};
    },
    pageChanged(input) {
        const enterprise = /^https:\/\/github\.com\/enterprises\/([^/?#]+)\/sso(?:[?#]|$)/.exec(input.url)?.[1];
        const path = pullPath(input.url), previous = input.previousURL ?? "";
        const created = path && previous.startsWith("https://github.com/" + path.owner + "/" + path.repo + "/compare");
        const reviewed = path && input.url.includes("#pullrequestreview-") && !previous.includes("#pullrequestreview-");
        return {state: enterprise ? {enterprise} : input.state ?? {}, refreshAfter: created || reviewed ? [5, 45] : [],
            checkSignIn: input.url.startsWith("https://github.com/")};
    }
};
