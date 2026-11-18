#!/usr/bin/env python3
"""scripts/sponsors.py: who a release owes a thank-you. No network.

18 Nov 2026: @saivan raised their sponsorship from $5 to $15 a month the day after 0.1.46
thanked them. The script counted that thank-you for the whole year, so a sponsor who pays
more was never named again.

18 Nov 2026: the tiers changed. Backer ($15) no longer promises to be asked first (nobody
was), it's named twice a year; Insider ($30) every quarter; Patron ($60) every release.
Thank you ($3) is named once, when the sponsor joins; one-time tiers in the next release.
"""
import datetime as dt
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "sponsors", Path(__file__).resolve().parents[1] / "scripts/sponsors.py")
sponsors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sponsors)

RELEASES = """export const releases = [
  {
    version: "0.1.46",
    date: "2026-11-17",
    sponsors: [
      { login: "saivan", name: "theChosenOne" },
    ],
  },
  {
    version: "0.1.45",
    date: "2026-11-16",
  },
];
"""
TODAY = dt.date(2026, 11, 18)


def tier(price, one_time=False):
    return {"name": f"${price} a month", "monthlyPriceInDollars": price, "isOneTime": one_time}


def change(login, old, new, when):
    return {"timestamp": when, "previousSponsorsTier": old, "sponsorsTier": new, "sponsor": {"login": login}}


class ThankedTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "releases.ts"
        self.path.write_text(RELEASES)

    def tearDown(self):
        self.dir.cleanup()

    def thanked(self, raised=None, today=TODAY, days=365):
        return sponsors.thanked_within(["theChosenOne", "saivan"], days, raised, self.path, today)

    def test_a_release_this_year_counts(self):
        self.assertTrue(self.thanked())

    def test_a_year_later_they_are_due_again(self):
        self.assertFalse(self.thanked(today=dt.date(2027, 11, 18)))

    def test_a_raise_after_the_thank_you_makes_them_due(self):
        self.assertFalse(self.thanked(raised="2026-11-18"))

    def test_a_release_on_the_day_of_the_raise_counts(self):
        self.assertTrue(self.thanked(raised="2026-11-17"))

    def test_twice_a_year_is_due_after_half_a_year(self):
        self.assertTrue(self.thanked(today=dt.date(2027, 5, 17), days=182))
        self.assertFalse(self.thanked(today=dt.date(2027, 5, 19), days=182))

    def test_every_quarter_is_due_after_three_months(self):
        self.assertTrue(self.thanked(today=dt.date(2027, 2, 15), days=91))
        self.assertFalse(self.thanked(today=dt.date(2027, 2, 17), days=91))

    def test_named_when_they_joined_counts_for_good(self):
        self.assertTrue(self.thanked(today=dt.date(2036, 11, 18), days=sponsors.notes_every([THANK_YOU])))

    def test_every_release_is_always_due(self):
        self.assertFalse(self.thanked(today=dt.date(2026, 11, 17), days=0))


THANK_YOU = "**Thank you** — Your name in the release notes when you join. Thank you for helping keep Cra free and independent."
SUPPORTER = "**Supporter** — Your name in the release notes once a year, and a Sponsor badge on your GitHub profile."
BACKER = "**Backer** — Everything in Supporter, plus your name in the release notes twice a year."
INSIDER = "**Insider** — Everything in Backer, plus your name in the release notes every quarter."
PATRON = "**Patron** — Everything in Insider, plus your name in the notes of every release while you sponsor."


class EveryTests(unittest.TestCase):
    def test_the_most_often_of_their_tiers_wins(self):
        self.assertEqual(sponsors.notes_every([SUPPORTER]), 365)
        self.assertEqual(sponsors.notes_every([SUPPORTER, BACKER]), 182)
        self.assertEqual(sponsors.notes_every([SUPPORTER, BACKER, INSIDER]), 91)
        self.assertEqual(sponsors.notes_every([SUPPORTER, BACKER, INSIDER, PATRON]), 0)

    def test_thank_you_is_named_once(self):
        self.assertRegex(THANK_YOU, sponsors.PERKS["notes"][0])
        self.assertGreater(sponsors.notes_every([THANK_YOU]), 365 * 50)
        self.assertEqual(sponsors.notes_every([THANK_YOU, SUPPORTER]), 365)

    def test_no_frequency_means_once_a_year(self):
        self.assertEqual(sponsors.notes_every(["**Thank you** — Keeps the lights on.", None]), 365)

    def test_patron_counts_as_a_release_notes_perk(self):
        self.assertRegex(PATRON, sponsors.PERKS["notes"][0])


class RaiseTests(unittest.TestCase):
    def test_only_monthly_raises_count_and_the_latest_wins(self):
        raises = sponsors.latest_raises([
            change("saivan", tier(5), tier(15), "2026-11-18T00:58:00Z"),
            change("saivan", tier(3), tier(5), "2026-11-10T00:00:00Z"),
            change("down", tier(15), tier(5), "2026-11-18T00:00:00Z"),
            change("once", tier(5), tier(50, one_time=True), "2026-11-18T00:00:00Z"),
            change("ghost", tier(5), tier(15), "2026-11-18T00:00:00Z") | {"sponsor": None},
        ])
        self.assertEqual(list(raises), ["saivan"])
        self.assertEqual(raises["saivan"]["timestamp"], "2026-11-18T00:58:00Z")


if __name__ == "__main__":
    unittest.main()
