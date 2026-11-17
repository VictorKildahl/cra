#!/usr/bin/env python3
"""Writes a release's two Sparkle feeds for one CPU (docs/release.md, "Channels"; GitHub #476):

  appcast<suffix>.xml         what every Cra reads, and the New channel: the newest release, which only a Cra on
                              Chrome's engine may install (sparkle:minimumUpdateVersion), then the Stable one
  appcast-stable<suffix>.xml  the Stable channel: the Stable release alone

usage: appcast-feeds.py <out dir> <suffix> <newest feed> <newest version> <stable feed> <stable version>

Each feed is an appcast holding that version's <item> (a release's own appcast.xml does). Items are copied as they
are, signature and release notes included; only minimumUpdateVersion is set or dropped.
"""
import re
import sys

FIRST_ENGINE_BUILD = "202611161309"  # Cra 0.1.44; CraCore's AppcastRelease.firstEngineBuild

HEADER = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Cra</title>
    <link>https://crabrowser.app/release-notes</link>
"""
FOOTER = """  </channel>
</rss>
"""
MINIMUM = re.compile(r"\n\s*<sparkle:minimumUpdateVersion>[^<]*</sparkle:minimumUpdateVersion>")


def item(path, version):
    text = open(path, encoding="utf-8").read()
    for match in re.finditer(r"[ \t]*<item>.*?</item>\n?", text, re.S):
        block = match.group(0)
        if re.search(r"<sparkle:shortVersionString>\s*%s\s*</sparkle:shortVersionString>" % re.escape(version), block):
            return MINIMUM.sub("", block if block.endswith("\n") else block + "\n")
    sys.exit("appcast-feeds: no Cra %s in %s" % (version, path))


def engine_only(block):
    return re.sub(r"(\n(\s*)<sparkle:shortVersionString>[^<]*</sparkle:shortVersionString>)",
                  r"\1\n\2<sparkle:minimumUpdateVersion>%s</sparkle:minimumUpdateVersion>" % FIRST_ENGINE_BUILD,
                  block, count=1)


def main():
    out, suffix, newest_feed, newest_version, stable_feed, stable_version = sys.argv[1:7]
    stable = item(stable_feed, stable_version)
    if newest_version == stable_version:
        main_items = stable
    else:
        main_items = engine_only(item(newest_feed, newest_version)) + stable
    for name, items in (("appcast%s.xml" % suffix, main_items), ("appcast-stable%s.xml" % suffix, stable)):
        with open("%s/%s" % (out, name), "w", encoding="utf-8") as f:
            f.write(HEADER + items + FOOTER)
        print("Wrote %s/%s" % (out, name))


main()
