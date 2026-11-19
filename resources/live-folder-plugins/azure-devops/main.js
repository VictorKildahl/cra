const presentation = {
    folderTitle: "Pull Requests",
    menuTitle: "Pull Requests",
    icon: "icon.svg",
    filters: [
        {id: "authored", title: "My Pull Requests", enabledByDefault: true},
        {id: "review", title: "Review Requests", enabledByDefault: true}
    ],
    groups: {title: "Repositories", description: "Repositories with active pull requests."},
    setup: {
        key: "server",
        title: "Add an Azure DevOps Live Folder",
        message: "Enter your organization’s address, or your Azure DevOps Server collection. The folder signs in with this Space’s Profile.",
        placeholder: "https://dev.azure.com/example",
        defaultValue: "",
        invalidTitle: "That isn’t an Azure DevOps address",
        invalidMessage: "Use the address you open Azure DevOps at, like https://dev.azure.com/example."
    },
    statusMessages: {
        notSignedIn: "Not signed in to Azure DevOps",
        rateLimited: "Azure DevOps rate limit exceeded",
        unexpectedPage: "Could not load pull requests. Check the organization’s address and your access.",
        network: "Failed to update: Azure DevOps can’t be reached"
    }
};

// Server 2020 and newer, and the cloud, all answer 6.0.
const apiVersion = "6.0";
const pageSize = 100;

function fail(code) { throw new Error(code); }

// The organization's root: an address copied from any page (…/Project/_git/repo/pullrequest/1) keeps
// only dev.azure.com/<org> or <org>.visualstudio.com. A Server collection is taken as entered.
function serverOf(settings) {
    const cloud = /^(https:\/\/dev\.azure\.com\/[^\/?#]+)(?:[\/?#]|$)/i.exec(settings.server) ??
        /^(https:\/\/[^\/?#.]+\.visualstudio\.com)(?:[\/?#]|$)/i.exec(settings.server);
    return cloud ? cloud[1] : settings.server;
}

function read(url) {
    // Without this header a signed-out request is sent to Microsoft's sign-in page instead of answering 401.
    const response = cra.session.fetch(url, {headers: {Accept: "application/json", "X-TFS-FedAuthRedirect": "Suppress"}});
    if (response.status === 0) fail("network");
    if (response.status === 401) fail("notSignedIn");
    if (response.status === 429) fail("rateLimited");
    if (response.status < 200 || response.status >= 300) fail("unexpectedPage");
    if (response.url.split("?")[0] !== url.split("?")[0]) fail("notSignedIn");
    // 203 with the sign-in page is how an expired session answers some requests.
    if (/^\s*</.test(response.body)) fail("notSignedIn");
    try { return JSON.parse(response.body); } catch (_) { fail("unexpectedPage"); }
}

function text(value) { return typeof value === "string" && value.trim() !== ""; }

function item(request, server) {
    const repo = request?.repository;
    if (!Number.isInteger(request?.pullRequestId) || request.pullRequestId <= 0 ||
        typeof request.title !== "string" || request.status !== "active" ||
        !text(repo?.name) || !text(repo.project?.name) ||
        (request.createdBy != null && typeof request.createdBy.displayName !== "string")) fail("unexpectedPage");
    const url = server + "/" + encodeURIComponent(repo.project.name) + "/_git/" + encodeURIComponent(repo.name) +
        "/pullrequest/" + request.pullRequestId;
    const created = Date.parse(request.creationDate);
    return {
        id: url,
        url,
        title: request.title,
        subtitle: request.createdBy?.displayName || null,
        group: repo.project.name === repo.name ? repo.name : repo.project.name + "/" + repo.name,
        createdAt: Number.isFinite(created) ? created / 1000 : null
    };
}

// Arc's review requests leave once you've reviewed: a pull request stays while your own vote is
// still "No vote", and one you opened yourself belongs to My Pull Requests.
function awaitsReview(request, me) {
    if (request.createdBy?.id === me) return false;
    const mine = Array.isArray(request.reviewers) ? request.reviewers.find(r => r?.id === me) : null;
    return !mine || mine.vote === 0;
}

function refresh(input) {
    const wanted = presentation.filters.filter(f => input.filters.includes(f.id));
    if (!wanted.length) return {items: [], actions: [], preservedGroups: []};
    const server = serverOf(input.settings);
    const connection = read(server + "/_apis/connectionData");
    const me = connection?.authenticatedUser?.id;
    if (!text(me) || /anonymous/i.test(connection.authenticatedUser.descriptor ?? "")) fail("notSignedIn");
    const criteria = {authored: "searchCriteria.creatorId", review: "searchCriteria.reviewerId"};
    const items = new Map();
    for (const filter of wanted) {
        for (let page = 0; page < 50; page++) {
            const response = read(server + "/_apis/git/pullrequests?searchCriteria.status=active&" + criteria[filter.id] + "=" +
                encodeURIComponent(me) + "&$top=" + pageSize + "&$skip=" + page * pageSize + "&api-version=" + apiVersion);
            if (!response || !Array.isArray(response.value)) fail("unexpectedPage");
            for (const request of response.value) {
                const value = item(request, server);
                if (filter.id === "review" && !awaitsReview(request, me)) continue;
                items.set(value.id, value);
            }
            if (items.size > 10000) fail("unexpectedPage");
            if (response.value.length < pageSize) break;
            if (page === 49) fail("unexpectedPage");
        }
    }
    return {
        items: [...items.values()].sort((a, b) => (b.createdAt ?? -Infinity) - (a.createdAt ?? -Infinity) ||
            (a.url < b.url ? -1 : a.url > b.url ? 1 : 0)),
        actions: [],
        preservedGroups: []
    };
}

function label(server) { return server.replace(/^https?:\/\//, ""); }

return {
    describe() { return presentation; },
    refresh,
    signIn(input) {
        const server = serverOf(input.settings);
        return {
            title: "Sign In to Azure DevOps…", url: server, warning: "Sign back in to Azure DevOps.",
            emptyText: "Pull requests from you and your team will show up here automatically",
            failureText: "We’re having trouble connecting to Azure DevOps; click here to see your Pull Requests.",
            failureURL: server + "/_pulls",
            instanceLabel: "Azure DevOps (" + label(server) + ")",
            detailLabel: label(server)
        };
    },
    // Opening, creating or reviewing a pull request refreshes the folder, as Dia's GitHub folder does.
    pageChanged(input) {
        // Organization and collection names ignore case: dev.azure.com/Acme is dev.azure.com/acme.
        const base = (serverOf(input.settings) + "/").toLowerCase();
        const onServer = input.url.toLowerCase().startsWith(base);
        return {state: input.state ?? {}, refreshAfter: onServer ? [2] : [], checkSignIn: onServer};
    }
};
