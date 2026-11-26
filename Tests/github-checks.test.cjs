const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

let body;
const context = vm.createContext({cra: {session: {fetch: () => ({status: 200, body})}}});
const plugin = vm.runInContext(`(function() {${fs.readFileSync("resources/live-folder-plugins/github/main.js", "utf8")}\n})()`, context);
const parse = html => {
    body = JSON.stringify({payload: {"pullRequestsChecksRoute.Main": {value: html}}});
    return JSON.parse(JSON.stringify(plugin.checks({url: "https://github.com/example/widget/pull/3"})));
};
const fixture = JSON.parse(fs.readFileSync("Tests/Fixtures/LiveFolders/github-checks-events.json", "utf8"));
assert.deepEqual(parse(fixture.payload["pullRequestsChecksRoute.Main"].value), {
    checks: {passed: 3, failed: 0, pending: 0, skipped: 1, failing: []}
});

const html = ["push", "pull_request"].map((event, index) =>
    `<details class="checks-list-item"><summary> CI on: ${event} <span>3</span> </summary>` +
    ["Build", "Test", "Lint"].map(name =>
        `<div class="checks-list-item"><svg aria-label="This job succeeded"></svg>` +
        `<a class="SideNav-subItem" href="/example/widget/actions/runs/${index + 1}/job/1"><span>${name}</span></a></div>`
    ).join("") + "</details>"
).join("");
assert.deepEqual(parse(html), {
    checks: {passed: 6, failed: 0, pending: 0, skipped: 0, failing: []}
});
console.log("GitHub checks summary tests passed");
