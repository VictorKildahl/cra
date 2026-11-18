#!/usr/bin/env python3
"""scripts/sponsors.py: who a release owes a thank-you. No network.

18 Nov 2026: @saivan raised their sponsorship from $5 to $15 a month the day after 0.1.46
thanked them. The script counted that thank-you for the whole year, so a sponsor who pays
more was never named again.
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

    def thanked(self, raised=None, today=TODAY):
        return sponsors.thanked_in_past_year(["theChosenOne", "saivan"], raised, self.path, today)

    def test_a_release_this_year_counts(self):
        self.assertTrue(self.thanked())

    def test_a_year_later_they_are_due_again(self):
        self.assertFalse(self.thanked(today=dt.date(2027, 11, 18)))

    def test_a_raise_after_the_thank_you_makes_them_due(self):
        self.assertFalse(self.thanked(raised="2026-11-18"))

    def test_a_release_on_the_day_of_the_raise_counts(self):
        self.assertTrue(self.thanked(raised="2026-11-17"))


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
