#!/usr/bin/env python3
"""Close Ideas that didn't find support, so the category only holds live ideas.

    scripts/ideas-housekeeping.py            close what's due
    scripts/ideas-housekeeping.py --dry-run  only list it

An open discussion in Ideas is closed as outdated, with a comment saying why, when it
is older than DAYS and has fewer than VOTES upvotes (the author's own counts as one).
Pinned discussions and ideas labelled `planned` are never closed. Ideas that ship or
are declined are closed by hand when that happens (see the "Start here" post).

Runs weekly from .github/workflows/ideas-housekeeping.yml. Needs a token that can
write discussions (GH_TOKEN, as for gh).
"""
import datetime as dt
import json
import subprocess
import sys

REPO = "VictorKildahl/cra"
CATEGORY = "ideas"
DAYS = 60
VOTES = 5
KEEP_LABEL = "planned"

COMMENT = f"""Closing this idea: it has been open for {DAYS} days with fewer than {VOTES} upvotes, \
so not enough people are asking for it yet. This keeps [Ideas](https://github.com/{REPO}/discussions/categories/ideas) \
to the ones people want most.

If it still matters to you, comment with what you'd use it for, and it can be reopened."""


def graphql(query, **variables):
    args = ["gh", "api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        args += ["-F" if isinstance(value, int) else "-f", f"{key}={value}"]
    out = subprocess.run(args, check=True, capture_output=True, text=True).stdout
    return json.loads(out)["data"]


def open_ideas():
    owner, name = REPO.split("/")
    query = """
    query($owner: String!, $name: String!, $slug: String!) {
      repository(owner: $owner, name: $name) {
        pinnedDiscussions(first: 10) { nodes { discussion { id } } }
        discussionCategory(slug: $slug) { id }
      }
    }"""
    repo = graphql(query, owner=owner, name=name, slug=CATEGORY)["repository"]
    pinned = {n["discussion"]["id"] for n in repo["pinnedDiscussions"]["nodes"]}
    category = repo["discussionCategory"]["id"]

    page = """
    query($owner: String!, $name: String!, $category: ID!, $after: String) {
      repository(owner: $owner, name: $name) {
        discussions(first: 100, after: $after, categoryId: $category, states: OPEN) {
          pageInfo { hasNextPage endCursor }
          nodes { id number title createdAt upvoteCount labels(first: 20) { nodes { name } } }
        }
      }
    }"""
    after = None
    while True:
        variables = dict(owner=owner, name=name, category=category)
        if after:
            variables["after"] = after
        found = graphql(page, **variables)["repository"]["discussions"]
        for d in found["nodes"]:
            if d["id"] not in pinned:
                yield d
        if not found["pageInfo"]["hasNextPage"]:
            return
        after = found["pageInfo"]["endCursor"]


def due(idea, now):
    created = dt.datetime.fromisoformat(idea["createdAt"].replace("Z", "+00:00"))
    labels = {label["name"] for label in idea["labels"]["nodes"]}
    return now - created >= dt.timedelta(days=DAYS) and idea["upvoteCount"] < VOTES and KEEP_LABEL not in labels


def close(idea):
    graphql(
        "mutation($id: ID!, $body: String!) { addDiscussionComment(input: {discussionId: $id, body: $body}) { clientMutationId } }",
        id=idea["id"], body=COMMENT,
    )
    graphql(
        "mutation($id: ID!) { closeDiscussion(input: {discussionId: $id, reason: OUTDATED}) { clientMutationId } }",
        id=idea["id"],
    )


def main():
    dry_run = "--dry-run" in sys.argv[1:]
    now = dt.datetime.now(dt.timezone.utc)
    closing = [idea for idea in open_ideas() if due(idea, now)]
    for idea in closing:
        print(f"{'would close' if dry_run else 'closing'} #{idea['number']} ({idea['upvoteCount']} votes): {idea['title']}")
        if not dry_run:
            close(idea)
    if not closing:
        print("no ideas due")


if __name__ == "__main__":
    main()
