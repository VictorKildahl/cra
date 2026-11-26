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
        unexpectedPage: "Failed to update: unexpected GitHub response", network: "Failed to update: GitHub can’t be reached"
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
    const details = {};
    if (typeof d.isDraft === "boolean") details.draft = d.isDraft;
    else if (d.displayState === "DRAFT" || d.state === "DRAFT") details.draft = true;
    if (Number.isInteger(d.commentCount) && d.commentCount >= 0) details.commentCount = d.commentCount;
    if (Array.isArray(d.labels)) details.labels = d.labels.filter(label =>
        label && typeof label.name === "string" && label.name.trim()).slice(0, 10).map(label =>
        ({name: label.name, ...(typeof label.color === "string" ? {color: label.color} : {})}));
    if (Number.isInteger(d.taskListItemCount) && d.taskListItemCount > 0 &&
        Number.isInteger(d.completeTaskListItemCount) && d.completeTaskListItemCount >= 0 && d.completeTaskListItemCount <= d.taskListItemCount)
        details.tasks = {done: d.completeTaskListItemCount, total: d.taskListItemCount};
    return {id: url, url, title: plain(title), subtitle: login(d.author) ?? login(d.user) ?? d.author_name ?? d.authorLogin ?? null,
        group, createdAt: date(d.createdAt ?? d.created_at ?? d.created), updatedAt: date(d.updatedAt ?? d.updated_at ?? d.updated),
        ...(typeof d.headSha === "string" && /^[0-9a-f]{40}$/i.test(d.headSha) ? {revision: d.headSha} : {}),
        ...(Object.keys(details).length ? {details} : {})};
}
// The folder holds open pull requests (drafts too), whatever else GitHub's answer carries (#523).
function isOpen(d) {
    const state = String(d.state ?? "").toLowerCase();
    return state !== "merged" && state !== "closed" && d.merged !== true && d.closed !== true &&
        !(d.mergedAt ?? d.merged_at ?? d.closedAt ?? d.closed_at);
}
function walk(root, visitor, limit, depth = 0) {
    if (!root || typeof root !== "object" || depth >= limit) return;
    if (visitor(root)) return;
    for (const child of Object.values(root)) walk(child, visitor, limit, depth + 1);
}
function parseJSON(root) {
    const items = [];
    walk(root, value => { const item = parseItem(value); if (item && isOpen(value)) items.push(item); return !!item; }, 40);
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
        if (chunks.length > 1 && /octicon-git-(merge|pull-request-closed)(?![\w-])/.test(chunk)) continue;
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
    const sso = ssoOrganizations(body);
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
    return {...parsed, sso: [...new Set(sso)], ssoKnown: path.startsWith("/search") || /"(protected_org_logins|sso_organizations)"/.test(body)};
}
// Organisations whose pull requests wait for SAML single sign-on: GitHub's search names them in
// `protected_org_logins`, the pulls page in its layout's `sso_organizations` (what Arc reads), older
// pages link to /orgs/<org>/sso.
function ssoOrganizations(body) {
    const orgs = matches(/\/orgs\/([A-Za-z0-9_.-]+)\/sso/g, body).map(m => m[1]);
    for (const m of matches(/"protected_org_logins"\s*:\s*\[([^\]]*)\]/g, body))
        orgs.push(...matches(/"([A-Za-z0-9_.-]+)"/g, m[1]).map(v => v[1]));
    for (const m of matches(/"sso_organizations"\s*:\s*\[([^\]]*)\]/g, body))
        orgs.push(...matches(/"login"\s*:\s*"([A-Za-z0-9_.-]+)"/g, m[1]).map(v => v[1]));
    return orgs;
}
// The pulls page's JSON lists pull requests but not the organisations waiting for SSO (#521): when no
// answer said, the page itself does. Best effort: the searches already decided the folder's items.
function pageSSO() {
    try {
        const response = cra.session.fetch("https://github.com/pulls", {headers: {Accept: "text/html"}});
        return response.status >= 200 && response.status < 300 && /^https:\/\/github\.com\/pulls(?:[?#]|$)/.test(response.url)
            ? ssoOrganizations(response.body) : [];
    } catch (_) { return []; }
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
            previous.revision ??= item.revision;
            previous.details ??= item.details;
        } else items.set(item.url, item);
    }
    const sso = pages.flatMap(page => page.sso);
    if (pages.length && !pages.some(page => page.ssoKnown)) sso.push(...pageSSO());
    const orgs = [...new Set(sso)].sort();
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
// Suites also carry checks-list-item; only the entries with job names count.
function parseChecks(html) {
    const starts = matches(/<[a-z][a-z0-9-]*\b[^>]*class="[^"]*"[^>]*>/gi, html)
        .filter(m => (attribute("class", m[0]) ?? "").split(/\s+/).includes("checks-list-item"));
    const checks = {passed: 0, failed: 0, pending: 0, skipped: 0, failing: []};
    const states = {
        "This job succeeded": "passed", "This check passed": "passed",
        "This job failed": "failed", "This check failed": "failed",
        "This job is pending": "pending", "This check is pending": "pending",
        "This job is queued": "pending", "This job is in progress": "pending", "This check is in progress": "pending",
        "This job was skipped": "skipped", "This check was skipped": "skipped"
    };
    const sections = matches(/<summary\b[^>]*>([\s\S]*?)<\/summary>/gi, html)
        .map(m => ({index: m.index, title: plain(m[1]).replace(/ \d+$/, "")}));
    const jobs = new Map();
    for (let i = 0; i < starts.length; i++) {
        const chunk = html.slice(starts[i].index + starts[i][0].length, starts[i + 1]?.index ?? html.length);
        // details and summary are suite headings, never jobs.
        if (/^<(?:details|summary)\b/i.test(starts[i][0])) continue;
        const link = matches(/<a\b([^>]*)>([\s\S]*?)<\/a>/g, chunk)
            .find(m => (attribute("class", m[1]) ?? "").split(/\s+/).includes("SideNav-subItem"));
        const icons = matches(/<svg\b[^>]*>/g, chunk).map(m => attribute("aria-label", m[0])).filter(v => v != null);
        if (!link || icons.length !== 1 || !Object.prototype.hasOwnProperty.call(states, icons[0])) return {};
        const name = /<span\b[^>]*>([\s\S]*?)<\/span>/.exec(link[2]);
        if (!name || !plain(name[1])) return {};
        const title = plain(name[1]);
        const run = /\/actions\/runs\/(\d+)\//.exec(attribute("href", link[1]) ?? "");
        const runID = run ? BigInt(run[1]) : 0n;
        const section = sections.filter(section => section.index < starts[i].index).at(-1)?.title;
        const key = JSON.stringify([section || null, title]);
        if (!jobs.has(key) || runID > jobs.get(key).runID) {
            jobs.set(key, {name: title, state: states[icons[0]], runID, index: i});
        }
    }
    for (const job of [...jobs.values()].sort((a, b) => a.index - b.index)) {
        checks[job.state]++;
        if (job.state === "failed" && checks.failing.length < 3) checks.failing.push(job.name);
    }
    return checks.passed + checks.failed + checks.pending + checks.skipped ? {checks} : {};
}
function checks(input) {
    if (typeof input.url !== "string" || !/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/\d+$/.test(input.url)) return {};
    try {
        const response = cra.session.fetch(input.url + "/checks", {headers: {
            Accept: "application/json", "X-Requested-With": "XMLHttpRequest", "GitHub-Verified-Fetch": "true"
        }});
        if (response.status < 200 || response.status >= 300 ||
            /\/(?:login|session)(?:[/?#]|$)|\/sso(?:[/?#]|$)/.test(response.url)) return {};
        const root = JSON.parse(response.body);
        const html = root?.payload?.["pullRequestsChecksRoute.Main"]?.value;
        if (typeof html !== "string" || /<form\b[^>]*action="\/session"|<title>Sign in|\/orgs\/[^/]+\/sso/.test(html)) return {};
        return parseChecks(html);
    } catch (_) { return {}; }
}
return {
    migrate(input) {
        const bits = input.filter?.attributes?.rawValue ?? input.filter?.attributes ?? 7;
        return {settings: {}, filters: ["authored", "review", "teamReview"].filter((_, i) => bits & [1, 2, 4][i]),
            state: input.enterprise ? {enterprise: input.enterprise} : {}};
    },
    describe() { return presentation; }, refresh, checks,
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
