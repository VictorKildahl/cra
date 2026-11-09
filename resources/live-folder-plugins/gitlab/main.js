const presentation = {
    folderTitle: "Merge Requests",
    menuTitle: "Merge Requests",
    icon: "icon.svg",
    filters: [
        {id: "authored", title: "My Merge Requests", enabledByDefault: true},
        {id: "review", title: "Review Requests", enabledByDefault: true},
        {id: "assigned", title: "Assigned to Me", enabledByDefault: true}
    ],
    groups: {title: "Projects", description: "Projects with active merge requests."},
    setup: {
        key: "server",
        title: "Add a GitLab Live Folder",
        message: "Enter your GitLab’s address, or leave it empty for GitLab.com. The folder signs in with this Space’s Profile.",
        placeholder: "https://gitlab.com",
        defaultValue: "https://gitlab.com",
        invalidTitle: "That isn’t a GitLab address",
        invalidMessage: "Use the address you open GitLab at, like https://gitlab.example.com."
    },
    statusMessages: {
        notSignedIn: "Not signed in to GitLab",
        rateLimited: "GitLab rate limit exceeded",
        unexpectedPage: "Failed to update: unexpected GitLab response",
        network: "GitLab can’t be reached"
    }
};

function fail(code) { throw new Error(code); }

function read(url) {
    const response = cra.session.fetch(url, {headers: {Accept: "application/json"}});
    if (response.status === 0) fail("network");
    if (response.status === 401) fail("notSignedIn");
    if (response.status === 429) fail("rateLimited");
    if (response.status < 200 || response.status >= 300) fail("unexpectedPage");
    if (response.url.split("?")[0] !== url.split("?")[0]) fail("notSignedIn");
    try { return JSON.parse(response.body); } catch (_) { fail("unexpectedPage"); }
}

function item(request, server) {
    if (!request || !Number.isInteger(request.iid) || request.iid <= 0 ||
        typeof request.title !== "string" || typeof request.web_url !== "string" ||
        !request.web_url.startsWith(server + "/") ||
        !["opened", "merged", "closed"].includes(request.state)) fail("unexpectedPage");
    const boundary = request.web_url.lastIndexOf("/-/merge_requests/");
    const group = request.web_url.slice(server.length + 1, boundary);
    if (boundary < 0 || !group.includes("/")) fail("unexpectedPage");
    if (request.author != null && typeof request.author.username !== "string") fail("unexpectedPage");
    const created = Date.parse(request.created_at);
    return {
        id: request.web_url,
        url: request.web_url,
        title: request.title,
        subtitle: request.author?.username ?? null,
        group,
        createdAt: Number.isFinite(created) ? created / 1000 : null
    };
}

function refresh(input) {
    const server = input.settings.server;
    const user = read(server + "/api/v4/user");
    if (!user || !Number.isInteger(user.id)) fail("unexpectedPage");
    const items = new Map();
    const scopes = {authored: "created_by_me", review: "all", assigned: "assigned_to_me"};
    for (const filter of presentation.filters) {
        if (!input.filters.includes(filter.id)) continue;
        for (let page = 1; page <= 50; page++) {
            const url = server + "/api/v4/merge_requests?state=opened&scope=" + scopes[filter.id] +
                "&order_by=created_at&sort=desc&per_page=100&page=" + page +
                (filter.id === "review" ? "&reviewer_id=" + user.id : "");
            const rows = read(url);
            if (!Array.isArray(rows)) fail("unexpectedPage");
            for (const row of rows) {
                const value = item(row, server);
                items.set(value.id, value);
            }
            if (rows.length < 100) break;
            if (page === 50) fail("unexpectedPage");
        }
    }
    return {
        items: [...items.values()].sort((a, b) => (b.createdAt ?? -Infinity) - (a.createdAt ?? -Infinity) ||
            (a.url < b.url ? -1 : a.url > b.url ? 1 : 0)),
        actions: [],
        preservedGroups: []
    };
}

return {
    migrate(input) {
        const bits = input.filter?.attributes?.rawValue ?? input.filter?.attributes ?? 11;
        return {settings: {server: input.serverURL ?? "https://gitlab.com"},
            filters: ["authored", "review", "assigned"].filter((_, i) => bits & [1, 2, 8][i]), state: {}};
    },
    pageChanged(input) { return {state: input.state ?? {}, refreshAfter: [], checkSignIn: false}; },
    describe() { return presentation; },
    refresh,
    signIn(input) {
        return {title: "Sign In to GitLab…", url: input.settings.server + "/users/sign_in",
            warning: "Sign back in to GitLab.",
            emptyText: "Merge requests from you and your team will show up here automatically",
            failureText: "We’re having trouble connecting to GitLab; click here to see your Merge Requests.",
            failureURL: input.settings.server + "/dashboard/merge_requests",
            instanceLabel: "GitLab (" + input.settings.server.replace(/^https?:\/\//, "") + ")",
            detailLabel: input.settings.server.replace(/^https?:\/\//, "")};
    },
    instanceLabel(input) { return "GitLab (" + input.settings.server.replace(/^https?:\/\//, "") + ")"; }
};
