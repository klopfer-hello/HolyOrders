"""Sync between paladins on WoW Forever, where characters have a surname.

Forever quirks the simulator reproduces (measured in game):
- UnitName(unit) returns the surname in the realm slot -> HO.FullName = "First-Surname"
- CHAT_MSG_ADDON senders arrive as "First Surname" (with a space)
- whispers to "First Surname-Realm" fail with "No player named ... is currently playing."
"""

import os

import pytest

TESTS = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(TESTS)
FAKES = os.path.join(TESTS, "fakes", "HOSimFakes")

FOREVER = dict(secrets="off", profile="fast", unitname_returns_surname=True)

# records system chat lines (the "No player named" whisper failures)
SYSLOG = r"""
HO_SYS = {}
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:SetScript("OnEvent", function(_, _, text) HO_SYS[#HO_SYS + 1] = text end)
"""


def party(make_sim, names, **opts):
    sim = make_sim([FAKES, ADDON], **{**FOREVER, **opts})
    chars = [sim.char(sim.account(), first, surname, cls="PALADIN") for first, surname in names]
    for c in chars:
        sim.lua(c, SYSLOG)
    sim.group(chars)
    sim.advance(seconds=30)
    return sim, chars


def peers(sim, ch):
    return sorted(sim.lua(ch, "local t = {} for k in pairs(HolyOrders.Comm.peers) do t[#t + 1] = k end return t") or [])


def no_player_errors(sim, chars):
    lines = []
    for c in chars:
        lines += [s for s in (sim.lua(c, "return HO_SYS") or []) if "No player named" in s]
    return lines


def assigned(sim, ch, owner, cls):
    return sim.lua(ch, f"""
        local row = HolyOrders.Plan.Active().class["{owner}"]
        return row and row.{cls} and row.{cls}.id""")


def test_sender_name_matches_roster_name(make_sim):
    sim, (ada, bram) = party(make_sim, [("Ada", "Quill"), ("Bram", "Holt")])
    assert sim.lua(ada, "return HolyOrders.FullName('party1')") == "Bram-Holt"
    assert sim.lua(ada, "return HolyOrders.SenderName('Bram Holt')") == "Bram-Holt"
    assert sim.lua(ada, "return HolyOrders.SenderName('Bram Holt-SimRealm')") == "Bram-Holt"


def test_paladins_see_each_other_and_not_themselves(make_sim):
    sim, (ada, bram) = party(make_sim, [("Ada", "Quill"), ("Bram", "Holt")])
    assert peers(sim, ada) == ["Bram-Holt"]
    assert peers(sim, bram) == ["Ada-Quill"]


def test_greeting_whispers_reach_the_other_paladin(make_sim):
    sim, chars = party(make_sim, [("Ada", "Quill"), ("Bram", "Holt")])
    sim.advance(seconds=60)  # failed whispers answer late
    assert no_player_errors(sim, chars) == []


def test_sync_command_gets_answers_without_whisper_errors(make_sim):
    sim, (ada, bram, cara) = party(make_sim, [("Ada", "Quill"), ("Bram", "Holt"), ("Cara", "Vell")])
    sim.lua(bram, 'HolyOrders.Plan.SetClassAssignment("Bram-Holt", "WARRIOR", 3)')
    sim.advance(seconds=10)
    sim.reload(ada)  # Ada lost the session state; /ho sync must restore it
    sim.lua(ada, SYSLOG)
    sim.advance(seconds=10)
    sim.slash(ada, "/ho sync")
    sim.advance(seconds=60)
    assert no_player_errors(sim, [ada, bram, cara]) == []
    assert assigned(sim, ada, "Bram-Holt", "WARRIOR") == 3
    assert peers(sim, ada) == ["Bram-Holt", "Cara-Vell"]


def test_assignment_by_one_paladin_shows_for_the_others(make_sim):
    sim, (ada, bram, cara) = party(make_sim, [("Ada", "Quill"), ("Bram", "Holt"), ("Cara", "Vell")])
    sim.lua(ada, 'HolyOrders.Plan.SetClassAssignment("Ada-Quill", "PRIEST", 1)')
    sim.lua(ada, 'HolyOrders.Plan.SetClassAssignment("Ada-Quill", "WARRIOR", 2)')
    sim.advance(seconds=10)
    for other in (bram, cara):
        assert assigned(sim, other, "Ada-Quill", "PRIEST") == 1
        assert assigned(sim, other, "Ada-Quill", "WARRIOR") == 2


def test_expect_accepts_a_name_with_surname(make_sim):
    sim, (ada, _) = party(make_sim, [("Ada", "Quill"), ("Bram", "Holt")])
    sim.slash(ada, "/ho expect Dora Fenn")
    assert "Dora-Fenn" in sim.lua(ada, "return HolyOrders.Plan.Expected()")


def test_names_without_surname_still_sync(make_sim):
    # classic-style names: realm-less sender, FullName = "Name-Realm"
    sim, (ada, bram) = party(make_sim, [("Ada", None), ("Bram", None)], unitname_returns_surname=False)
    assert peers(sim, ada) == ["Bram-SimRealm"]
    sim.lua(ada, 'HolyOrders.Plan.SetClassAssignment("Ada-SimRealm", "MAGE", 1)')
    sim.advance(seconds=10)
    assert assigned(sim, bram, "Ada-SimRealm", "MAGE") == 1
    assert no_player_errors(sim, [ada, bram]) == []
