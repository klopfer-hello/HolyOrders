"""The bridge to the older third-party blessing addon ("legacy" clients).

HolyOrders only EMITS that addon's messages (own row, pushes of other rows,
overrides, auras) and answers its pull request; it never takes plan state from
it. A legacy client here is a recorder: the tests read what reached it and
send its messages by hand.

Wire reference (from the written protocol note):
  SELF <caps>@<grid>      caps: 6 blessings x (rank, talent) hex or "nn";
                          grid: 9 classes, blessing number or "n", in the order
                          WARRIOR ROGUE PRIEST DRUID PALADIN HUNTER MAGE WARLOCK SHAMAN
  PASSIGN <name>@<grid>   another paladin's row
  NASSIGN <e>@<e>...      up to 5 overrides, each "<paladin> <class#> <target> <blessing#>"
  ASELF <caps>@<aura#>    own aura; AASSIGN <name> <aura#> another paladin's
  REQ                     pull request
"""

import pytest
from helpers import BLESSING as B
from helpers import World


@pytest.fixture
def mixed(make_sim):
    """Ada (HolyOrders, bridge on, leader), Lena (legacy paladin), Dora (no addon)."""
    w = World(make_sim)
    ada = w.pala("Ada", bridge=True)
    lena = w.legacy("Lena")
    dora = w.bare("Dora", "WARRIOR")
    w.group([ada, lena, dora])
    w.legacy_rx(lena, clear=True)
    return w, ada, lena, dora


def last(msgs):
    assert msgs, "no such message arrived"
    return msgs[-1]


def test_bridge_is_off_by_default(make_sim):
    w = World(make_sim)
    ada, lena = w.pala("Ada"), w.legacy("Lena")
    w.group([ada, lena])
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    assert w.legacy_rx(lena) == []


def test_own_row_is_announced(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.assign(ada, ada, "PRIEST", B["WISDOM"])
    w.settle()
    # Forever: Wisdom, Might, Kings known (rank 1, no talent); the rest unknown
    assert last(w.legacy_msgs(lena, "SELF")) == "SELF 101010nnnnnn@2n1nnnnnn"


def test_own_row_on_the_classic_client(make_sim):
    w = World(make_sim, classic=True)
    ada, lena = w.pala("Ada", bridge=True), w.legacy("Lena")
    w.group([ada, lena])
    w.assign(ada, ada, "ROGUE", B["SALVATION"])
    w.settle()
    # classic: Salvation and Light exist too
    assert last(w.legacy_msgs(lena, "SELF")) == "SELF 1010101010nn@n4nnnnnnn"


def test_explicit_none_reads_as_unassigned(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    w.lua(ada, f'HolyOrders.Plan.SetClassNone("{w.name(ada)}", "WARRIOR")')
    w.settle()
    assert last(w.legacy_msgs(lena, "SELF")).endswith("@nnnnnnnnn")


def test_legacy_paladins_row_is_pushed_to_them(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, lena, "MAGE", B["WISDOM"])
    w.assign(ada, lena, "WARRIOR", B["KINGS"])
    w.settle()
    assert last(w.legacy_msgs(lena, "PASSIGN")) == "PASSIGN Lena@3nnnnn1nn"


def test_cleared_row_is_pushed_as_empty(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, lena, "MAGE", B["WISDOM"])
    w.settle()
    w.assign(ada, lena, "MAGE", 0)
    w.settle()
    assert last(w.legacy_msgs(lena, "PASSIGN")) == "PASSIGN Lena@nnnnnnnnn"


def test_overrides_are_pushed_five_per_message(make_sim):
    w = World(make_sim)
    ada, lena = w.pala("Ada", bridge=True), w.legacy("Lena")
    targets = [w.bare(f"War{c}", "WARRIOR") for c in "ABCDEFG"]
    w.group([ada, lena] + targets, raid=True)
    for t in targets:
        w.set_override(ada, lena, t, B["KINGS"])
    w.settle()
    msgs = w.legacy_msgs(lena, "NASSIGN")[-2:]
    entries = [e for m in msgs for e in m[len("NASSIGN ") :].split("@")]
    assert [len(m.split("@")) for m in msgs] == [5, 2]
    assert entries == [f"Lena 1 War{c} 3" for c in "ABCDEFG"]  # "<paladin> <class 1=warrior> <target> <kings>"


def test_aura_is_announced_and_pushed(mixed):
    w, ada, lena, dora = mixed
    w.set_aura(ada, ada, 2)
    w.set_aura(ada, lena, 1)
    w.assign(ada, lena, "MAGE", B["WISDOM"])  # aura edits ride on the next row broadcast
    w.settle()
    # Devotion, Retribution, Concentration known at 60; the rest unknown
    assert last(w.legacy_msgs(lena, "ASELF")) == "ASELF 101010nnnnnnnnnn@2"
    assert last(w.legacy_msgs(lena, "AASSIGN")) == "AASSIGN Lena 1"


def test_pull_request_is_answered_even_when_nothing_changed(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    w.legacy_rx(lena, clear=True)
    w.legacy_send(lena, "REQ")
    w.settle()
    assert w.legacy_msgs(lena, "SELF") == ["SELF 101010nnnnnn@2nnnnnnnn"]


def test_whispered_pull_request_is_answered_by_whisper(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    w.legacy_rx(lena, clear=True)
    w.legacy_send(lena, "REQ", "WHISPER", f"{ada.first}-{ada.surname}")
    w.settle()
    answers = [m for m in w.legacy_rx(lena) if m[2].startswith("SELF")]
    assert [m[1] for m in answers] == ["WHISPER"]
    assert w.whisper_errors([ada]) == []


def test_unchanged_plan_is_not_resent_on_roster_events(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    w.legacy_rx(lena, clear=True)
    for _ in range(5):
        w.sim.event(ada, "GROUP_ROSTER_UPDATE")
        w.settle(5)
    assert w.legacy_msgs(lena, "SELF") == []
    assert w.legacy_msgs(lena, "PASSIGN") == []


def test_legacy_announcement_of_a_held_row_is_answered_with_a_new_push(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, lena, "MAGE", B["WISDOM"])
    w.settle()
    w.legacy_rx(lena, clear=True)
    # Lena's client announces its own (empty) row, which wiped our push on the others
    w.legacy_send(lena, "SELF 101010nnnnnn@nnnnnnnnn")
    w.settle()
    assert w.legacy_msgs(lena, "PASSIGN") == ["PASSIGN Lena@nnnnnn1nn"]


def test_coordinator_on_another_class_pushes_rows(make_sim):
    w = World(make_sim)
    dora = w.member("Dora", "WARRIOR", bridge=True)  # leads and plans, cannot bless
    lena, lars = w.legacy("Lena"), w.legacy("Lars")
    w.group([dora, lena, lars])
    w.assign(dora, lena, "WARRIOR", B["MIGHT"])
    w.assign(dora, lars, "WARRIOR", B["KINGS"])
    w.settle()
    assert w.legacy_msgs(lars, "SELF") == []  # no row of her own to announce
    pushes = set(w.legacy_msgs(lars, "PASSIGN")[-2:])
    assert pushes == {"PASSIGN Lena@2nnnnnnnn", "PASSIGN Lars@3nnnnnnnn"}


def test_legacy_messages_never_change_the_plan(mixed):
    w, ada, lena, dora = mixed
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.assign(ada, lena, "MAGE", B["WISDOM"])
    w.settle()
    before = w.state(ada)
    for msg in ("SELF 101010nnnnnn@333333333", "PASSIGN Ada@111111111", "NASSIGN Ada 1 Dora 3", "CLEAR", "ASELF nn@3"):
        w.legacy_send(lena, msg)
    w.settle()
    assert w.state(ada) == before


def test_legacy_clients_are_listed(mixed):
    w, ada, lena, dora = mixed
    w.legacy_send(lena, "SELF 101010nnnnnn@nnnnnnnnn")
    w.legacy_send(lena, "FREEASSIGN YES")
    w.settle()
    clients = w.lua(ada, "return HolyOrders.Interop.LegacyClients()")
    assert clients == [{"name": w.name(lena), "pally": True, "freeassign": True}]


def test_big_raid_push_loses_no_message(make_sim):
    w = World(make_sim)
    ada = w.pala("Ada", bridge=True)
    legacy = [w.legacy(n) for n in ("Lena", "Lars", "Lore", "Lutz", "Lina", "Leif", "Lisa")]
    rest = [w.bare(f"War{c}", "WARRIOR") for c in "ABCDEFGHIJKL"]
    w.group([ada] + legacy + rest, raid=True)
    for i, pal in enumerate(legacy):
        w.assign(ada, pal, "WARRIOR", B["MIGHT"] if i % 2 else B["KINGS"])
        w.assign(ada, pal, "MAGE", B["WISDOM"])
    for t in rest:
        w.set_override(ada, legacy[0], t, B["KINGS"])
    w.settle(90)
    assert w.stats()["refused"] == {}
    got = w.legacy_msgs(legacy[-1], "PASSIGN")
    for i, pal in enumerate(legacy):
        expect = f"PASSIGN {pal.first}@{2 if i % 2 else 3}nnnnn1nn"
        assert expect in got, expect
    entries = [e for m in w.legacy_msgs(legacy[-1], "NASSIGN") for e in m[len("NASSIGN ") :].split("@")]
    assert {e.split(" ")[2] for e in entries} == {t.first for t in rest}


def test_two_bridges_do_not_fight(make_sim):
    # two HolyOrders paladins with the bridge on hold the same synced plan:
    # both push the same content, and neither keeps re-sending
    w = World(make_sim)
    ada, bram = w.pala("Ada", bridge=True), w.pala("Bram", bridge=True)
    lena = w.legacy("Lena")
    w.group([ada, bram, lena])
    w.assign(ada, lena, "MAGE", B["WISDOM"])
    w.settle(30)
    w.legacy_rx(lena, clear=True)
    w.settle(120)
    assert w.legacy_msgs(lena, "PASSIGN") == []
    assert w.legacy_msgs(lena, "SELF") == []
