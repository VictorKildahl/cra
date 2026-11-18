const presentation = {
    folderTitle: "Jira Issues",
    menuTitle: "Issues",
    icon: "icon.svg",
    filters: [
        {id: "assigned", title: "Assigned to Me", enabledByDefault: true},
        {id: "reported", title: "Reported by Me", enabledByDefault: false},
        {id: "watching", title: "Watched by Me", enabledByDefault: false},
        {id: "todo", title: "To Do", enabledByDefault: true},
        {id: "inProgress", title: "In Progress", enabledByDefault: true}
    ],
    groups: {title: "Projects", description: "Projects with issues matching your filters."},
    setup: {
        key: "server",
        title: "Add a Jira Live Folder",
        message: "Enter the address you open Jira at: your Jira Cloud site, or your Jira Data Center server with its path if needed. The folder signs in with this Space’s Profile.",
        placeholder: "https://example.atlassian.net",
        defaultValue: "",
        invalidTitle: "That isn’t a Jira address",
        invalidMessage: "Use the address you open Jira at, like https://example.atlassian.net or https://jira.example.com."
    },
    statusMessages: {
        notSignedIn: "Not signed in to Jira",
        rateLimited: "Jira rate limit exceeded",
        unexpectedPage: "Could not load Jira issues. Check the server address and your access permissions.",
        network: "Failed to update: Jira can’t be reached"
    }
};

function fail(code) { throw new Error(code); }

// A Jira Cloud site lives at its root: an address copied from a Cloud page (…atlassian.net/jira/your-work) keeps only the site.
function serverOf(settings) {
    const cloud = /^(https:\/\/[^\/?#]+\.atlassian\.net)(?:\/|$)/i.exec(settings.server);
    return cloud ? cloud[1] : settings.server;
}

function read(url) {
    const response = cra.session.fetch(url, {headers: {Accept: "application/json"}});
    if (response.status === 0) fail("network");
    if (response.status === 401) fail("notSignedIn");
    if (response.status === 429) fail("rateLimited");
    if (response.status < 200 || response.status >= 300) fail("unexpectedPage");
    if (response.url.split("?")[0] !== url.split("?")[0]) fail("notSignedIn");
    if (/^\s*</.test(response.body)) fail("notSignedIn");
    try { return JSON.parse(response.body); } catch (_) { fail("unexpectedPage"); }
}

function item(issue, server) {
    const fields = issue?.fields;
    if (typeof issue?.id !== "string" || !issue.id ||
        typeof issue.key !== "string" || !/^[A-Za-z][A-Za-z0-9_]*-[1-9][0-9]*$/.test(issue.key) ||
        typeof fields?.summary !== "string" || !fields.summary.trim() ||
        typeof fields.project?.key !== "string" || !fields.project.key ||
        !issue.key.startsWith(fields.project.key + "-") ||
        typeof fields.status?.name !== "string") fail("unexpectedPage");
    const created = typeof fields.created === "string" ?
        Date.parse(fields.created.replace(/([+-]\d{2})(\d{2})$/, "$1:$2")) : NaN;
    return {
        id: issue.id,
        url: server + "/browse/" + encodeURIComponent(issue.key),
        title: issue.key + " · " + fields.summary,
        subtitle: fields.status.name,
        group: fields.project.key,
        createdAt: Number.isFinite(created) ? created / 1000 : null
    };
}

function refresh(input) {
    const clauses = {assigned: "assignee = currentUser()", reported: "reporter = currentUser()", watching: "watcher = currentUser()"};
    const selected = Object.keys(clauses).filter(id => input.filters.includes(id)).map(id => clauses[id]);
    const categories = {todo: "To Do", inProgress: "In Progress"};
    const statuses = Object.keys(categories).filter(id => input.filters.includes(id)).map(id => JSON.stringify(categories[id]));
    if (!selected.length || !statuses.length) return {items: [], actions: [], preservedGroups: []};
    const server = serverOf(input.settings);
    const user = read(server + "/rest/api/2/myself");
    if (!user || user.active === false) fail("notSignedIn");
    // Jira Cloud names users by accountId (its user objects have no `name`) and has retired /search.
    const cloud = typeof user.accountId === "string" && !!user.accountId;
    if (!cloud && (typeof user.name !== "string" || !user.name)) fail("notSignedIn");
    const jql = "statusCategory IN (" + statuses.join(", ") + ") AND (" + selected.join(" OR ") + ") ORDER BY created DESC, key ASC";
    const items = new Map();
    const add = issues => {
        for (const issue of issues) {
            const value = item(issue, server);
            items.set(value.id, value);
        }
        if (items.size > 10000) fail("unexpectedPage");
    };
    const done = () => ({items: [...items.values()], actions: [], preservedGroups: []});
    const query = "jql=" + encodeURIComponent(jql) + "&fields=summary,status,project,created&maxResults=100";
    if (cloud) {
        const seen = new Set();
        let token = null;
        for (let page = 0; page < 100; page++) {
            const response = read(server + "/rest/api/2/search/jql?" + query +
                (token == null ? "" : "&nextPageToken=" + encodeURIComponent(token)));
            if (!response || !Array.isArray(response.issues) ||
                (response.nextPageToken != null && typeof response.nextPageToken !== "string")) fail("unexpectedPage");
            add(response.issues);
            if (response.isLast === true || !response.nextPageToken) return done();
            if (seen.has(response.nextPageToken)) fail("unexpectedPage");
            seen.add(response.nextPageToken);
            token = response.nextPageToken;
        }
        fail("unexpectedPage");
    }
    let startAt = 0;
    for (let page = 0; page < 100; page++) {
        const response = read(server + "/rest/api/2/search?" + query + "&startAt=" + startAt);
        if (!response || !Array.isArray(response.issues) || response.startAt !== startAt ||
            !Number.isInteger(response.maxResults) || response.maxResults <= 0 || response.issues.length > response.maxResults ||
            (response.total != null && (!Number.isInteger(response.total) || response.total < 0))) fail("unexpectedPage");
        const before = items.size;
        add(response.issues);
        startAt += response.issues.length;
        if (!response.issues.length || (response.total != null ? startAt >= response.total : response.issues.length < response.maxResults)) {
            return done();
        }
        if (items.size === before) fail("unexpectedPage");
    }
    fail("unexpectedPage");
}

return {
    describe() { return presentation; },
    refresh,
    signIn(input) {
        const server = serverOf(input.settings);
        return {
            title: "Sign In to Jira…", url: server + "/login.jsp", warning: "Sign back in to Jira.",
            emptyText: "No Jira issues match your filters",
            failureText: "We’re having trouble connecting to Jira; click here to open your issues.",
            failureURL: server + "/issues/",
            instanceLabel: "Jira (" + server.replace(/^https?:\/\//, "") + ")",
            detailLabel: server.replace(/^https?:\/\//, "")
        };
    },
    pageChanged(input) {
        const base = serverOf(input.settings) + "/";
        const onServer = input.url.startsWith(base);
        const signingIn = onServer && input.url.slice(base.length).split("?")[0] === "login.jsp";
        return {state: input.state ?? {}, refreshAfter: onServer && !signingIn ? [2] : [], checkSignIn: onServer && !signingIn};
    }
};
