"""Sync between HolyOrders users: every client must end up showing the same plan."""

import pytest
from helpers import BLESSING as B
from helpers import World


@pytest.fixture
def party(make_sim):
    """Three HolyOrders paladins and a HolyOrders warrior in a party; Ada leads."""
    w = World(make_sim)
    ada, bram, cara = w.pala("Ada"), w.pala("Bram"), w.pala("Cara")
    dora = w.member("Dora", "WARRIOR")
    w.group([ada, bram, cara, dora])
    return w, ada, bram, cara, dora


def raid_of(make_sim, paladins=4, others=4, **opts):
    """A raid of HolyOrders paladins plus bare members; the first paladin leads."""
    w = World(make_sim, **opts)
    names = ["Ada", "Bram", "Cara", "Dana", "Egon", "Finn", "Gwen", "Hale"]
    palas = [w.pala(n) for n in names[:paladins]]
    classes = ["WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "DRUID", "WARLOCK", "SHAMAN"]
    rest = [w.bare(f"Mem{chr(65 + i)}", classes[i % len(classes)]) for i in range(others)]
    w.group(palas + rest, raid=True)
    return w, palas, rest


# --- party ---------------------------------------------------------------------------


def test_everyone_knows_everyone(party):
    w, ada, bram, cara, dora = party
    assert w.peers(ada) == [w.name(bram), w.name(cara)]
    assert w.peers(dora) == [w.name(ada), w.name(bram), w.name(cara)]
    assert w.whisper_errors() == []


def test_own_assignment_reaches_everyone(party):
    w, ada, bram, cara, dora = party
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    for ch in (bram, cara, dora):
        assert w.assigned(ch, ada, "WARRIOR") == B["MIGHT"]
    w.assert_in_sync()


def test_editing_another_paladins_row_in_a_party(party):
    w, ada, bram, cara, dora = party
    w.assign(bram, cara, "PRIEST", B["WISDOM"])  # a party has no ranks: everyone may edit
    w.settle()
    assert w.assigned(cara, cara, "PRIEST") == B["WISDOM"]
    w.assert_in_sync()


def test_clearing_an_assignment_reaches_everyone(party):
    w, ada, bram, cara, dora = party
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    w.assign(ada, ada, "WARRIOR", 0)
    w.settle()
    assert w.assigned(bram, ada, "WARRIOR") is None
    w.assert_in_sync()


def test_member_override_syncs_and_clears(party):
    w, ada, bram, cara, dora = party
    w.set_override(ada, ada, dora, B["KINGS"])
    w.settle()
    assert w.override(bram, ada, dora) == B["KINGS"]
    w.set_override(bram, ada, dora, 0)
    w.settle()
    assert w.override(ada, ada, dora) is None
    w.assert_in_sync()


def test_tank_mark_syncs(party):
    w, ada, bram, cara, dora = party
    assert w.toggle_tank(bram, dora) is True
    w.settle()
    for ch in (ada, cara, dora):
        assert w.lua(ch, f'return HolyOrders.Plan.IsTank("{w.name(dora)}")') is True
    w.assert_in_sync()


def test_aura_syncs(party):
    w, ada, bram, cara, dora = party
    w.set_aura(ada, ada, 2)
    w.settle()
    assert w.lua(cara, f'return HolyOrders.Plan.GetAura("{w.name(ada)}")') == 2
    w.assert_in_sync()


def test_auto_plan_by_the_leader_reaches_everyone(party):
    w, ada, bram, cara, dora = party
    w.slash(ada, "/ho auto")
    w.settle()
    state = w.assert_in_sync()
    assert "C " in state  # the plan is not empty


def test_auto_plan_by_a_non_leader_keeps_everyone_in_sync(party):
    w, ada, bram, cara, dora = party
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.assign(cara, cara, "PRIEST", B["WISDOM"])
    w.settle()
    w.slash(bram, "/ho auto")  # no lead: only Bram's own row may change for the others
    w.settle(40)
    w.assert_in_sync()
    assert w.assigned(bram, ada, "WARRIOR") == B["MIGHT"]


def test_two_paladins_editing_the_same_row_at_once_converge(party):
    w, ada, bram, cara, dora = party
    w.assign(ada, cara, "WARRIOR", B["MIGHT"])
    w.assign(bram, cara, "WARRIOR", B["KINGS"])
    w.settle(30)
    w.assert_in_sync()


def test_two_paladins_editing_different_cells_of_a_row_at_once_converge(party):
    w, ada, bram, cara, dora = party
    w.assign(ada, cara, "WARRIOR", B["MIGHT"])
    w.assign(bram, cara, "PRIEST", B["WISDOM"])
    w.settle(30)
    w.assert_in_sync()


def test_owner_and_another_paladin_editing_the_row_at_once_converge(party):
    w, ada, bram, cara, dora = party
    w.assign(cara, cara, "WARRIOR", B["MIGHT"])
    w.assign(ada, cara, "PRIEST", B["WISDOM"])
    w.settle(30)
    w.assert_in_sync()


def test_edits_during_a_reload_are_caught_up(party):
    w, ada, bram, cara, dora = party
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    w.sim.logout(cara)
    w.assign(ada, ada, "WARRIOR", B["KINGS"])
    w.assign(bram, bram, "PRIEST", B["WISDOM"])
    w.settle()
    w.sim.login(cara)
    w.settle(40)
    w.assert_in_sync()
    assert w.assigned(cara, ada, "WARRIOR") == B["KINGS"]


def test_late_joiner_gets_the_existing_plan(make_sim):
    w = World(make_sim)
    ada, bram, cara = w.pala("Ada"), w.pala("Bram"), w.pala("Cara")
    w.group([ada, bram])
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.assign(bram, bram, "PRIEST", B["WISDOM"])
    w.set_aura(bram, bram, 1)
    w.settle()
    w.group([ada, bram, cara])
    w.settle(20)
    w.assert_in_sync()
    assert w.assigned(cara, ada, "WARRIOR") == B["MIGHT"]
    assert w.whisper_errors() == []


def test_leaver_is_forgotten_as_peer(party):
    w, ada, bram, cara, dora = party
    w.sim.leave_group(cara)
    w.settle()
    assert w.peers(ada) == [w.name(bram)]
    assert w.peers(cara) == []


def test_non_paladin_request_reaches_the_paladins(party):
    w, ada, bram, cara, dora = party
    w.lua(dora, f"HolyOrders.Comm.SendRequest({{ {B['KINGS']}, {B['MIGHT']} }})")
    w.settle()
    for ch in (ada, bram, cara):
        assert w.lua(ch, f'return HolyOrders.Comm.requests["{w.name(dora)}"]') == [B["KINGS"], B["MIGHT"]]


def test_request_survives_the_requesters_reload(party):
    w, ada, bram, cara, dora = party
    w.lua(dora, f"HolyOrders.Comm.SendRequest({{ {B['KINGS']} }})")
    w.settle()
    w.reload(dora)
    w.settle(30)
    assert w.lua(ada, f'return HolyOrders.Comm.requests["{w.name(dora)}"]') == [B["KINGS"]]


def test_low_level_paladin_announces_what_they_can_cast(make_sim):
    w = World(make_sim)
    ada, bram = w.pala("Ada"), w.pala("Bram", level=10)  # level 10: Might only
    w.group([ada, bram])
    caps = w.lua(ada, f'return HolyOrders.Comm.peers["{w.name(bram)}"].caps')
    assert caps[B["MIGHT"] - 1]["known"] is True
    assert caps[B["WISDOM"] - 1]["known"] is False
    assert caps[B["KINGS"] - 1]["known"] is False
    assert w.lua(ada, f'return HolyOrders.Planner.IsAvailable("{w.name(bram)}", {B["KINGS"]})') is False


def test_many_overrides_in_one_row_survive_a_plan_broadcast(make_sim):
    # a row too large for one message is split and reassembled
    w, palas, rest = raid_of(make_sim, paladins=2, others=24)
    ada, bram = palas
    for target in rest:
        w.lua(ada, f'HolyOrders.Plan.Active().player["{w.name(ada)}"] = HolyOrders.Plan.Active().player["{w.name(ada)}"] or {{}}')
        w.lua(ada, f'HolyOrders.Plan.Active().player["{w.name(ada)}"]["{w.name(target)}"] = {B["KINGS"]}')
    assert w.lua(ada, "return HolyOrders.Comm.SendPlanApply()") is True
    w.settle(60)
    w.assert_in_sync()
    assert w.override(bram, ada, rest[-1]) == B["KINGS"]


# --- raid ----------------------------------------------------------------------------


def test_raid_leader_plan_reaches_every_paladin(make_sim):
    w, palas, rest = raid_of(make_sim, paladins=6, others=10)
    w.slash(palas[0], "/ho auto")
    w.settle(90)
    state = w.assert_in_sync()
    assert state.count("C ") >= 6
    assert w.stats()["refused"] == {}


def test_raid_greeting_storm_loses_no_message(make_sim):
    w, palas, rest = raid_of(make_sim, paladins=8, others=12)
    w.settle(120)
    assert w.stats()["refused"] == {}
    for p in palas:
        assert len(w.peers(p)) == 7, f"{p.first} sees {w.peers(p)}"
    assert w.whisper_errors() == []


def test_raid_member_cannot_edit_a_closed_row(make_sim):
    w, palas, rest = raid_of(make_sim, paladins=3, others=2)
    ada, bram, cara = palas
    w.lua(cara, "HolyOrders.db.options.openEdit = false HolyOrders.Comm.SendHello()")
    w.settle()
    me, owner = w.name(bram), w.name(cara)
    assert w.lua(bram, f'return HolyOrders.Comm.CanEdit("{me}", "{owner}")') is False
    assert w.lua(ada, f'return HolyOrders.Comm.CanEdit("{w.name(ada)}", "{owner}")') is True  # the leader may
    # a forged edit from Bram is dropped by every receiver
    w.lua(bram, f'HolyOrders.Plan.SetClassAssignment("{owner}", "MAGE", {B["WISDOM"]})')
    w.settle()
    assert w.assigned(cara, cara, "MAGE") is None
    assert w.assigned(ada, cara, "MAGE") is None


def test_raid_member_may_edit_an_open_row(make_sim):
    w, palas, rest = raid_of(make_sim, paladins=3, others=2)
    ada, bram, cara = palas
    w.assign(bram, cara, "MAGE", B["WISDOM"])  # open edit is the default
    w.settle()
    assert w.assigned(cara, cara, "MAGE") == B["WISDOM"]
    w.assert_in_sync()


def test_plan_broadcast_from_a_raid_member_is_ignored(make_sim):
    w, palas, rest = raid_of(make_sim, paladins=3, others=2)
    ada, bram, cara = palas
    w.assign(ada, ada, "MAGE", B["WISDOM"])
    w.settle()
    assert w.lua(bram, "return HolyOrders.Comm.SendPlanApply()") is False
    w.assert_in_sync()


def test_stored_plan_comes_back_for_the_same_paladins(make_sim):
    w = World(make_sim)
    ada, bram = w.pala("Ada"), w.pala("Bram")
    dora = w.bare("Dora", "WARRIOR")
    w.group([ada, bram, dora])
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.assign(ada, bram, "WARRIOR", B["KINGS"])
    w.settle()
    w.slash(ada, "/ho plan save")
    saved = w.state(ada)
    w.sim.disband(ada.group)
    w.settle()
    # a different evening: the plan was changed for another group in between
    w.assign(ada, ada, "WARRIOR", B["WISDOM"])
    w.lua(ada, "HolyOrders.Plan.Active().meta.dirty = nil")
    w.group([ada, bram, dora])
    w.settle(30)
    assert w.state(ada) == saved
    w.assert_in_sync()


# --- the same on the classic client ------------------------------------------------------


def test_classic_client_party_syncs(make_sim):
    w = World(make_sim, classic=True)
    ada, bram = w.pala("Ada"), w.pala("Bram")
    dora = w.member("Dora", "WARRIOR")
    w.group([ada, bram, dora])
    assert w.peers(ada) == [w.name(bram)]
    w.assign(ada, ada, "WARRIOR", B["SALVATION"])
    w.set_override(bram, bram, dora, B["KINGS"])
    w.settle()
    assert w.assigned(bram, ada, "WARRIOR") == B["SALVATION"]
    w.assert_in_sync()
    assert w.whisper_errors() == []


# --- conflicts and slow messages -------------------------------------------------------


def test_forged_edit_is_undone_on_the_forgers_own_client(make_sim):
    w, palas, rest = raid_of(make_sim, paladins=3, others=2)
    ada, bram, cara = palas
    w.lua(cara, "HolyOrders.db.options.openEdit = false HolyOrders.Comm.SendHello()")
    w.settle()
    w.assign(cara, cara, "MAGE", B["KINGS"])
    w.settle()
    w.lua(bram, f'HolyOrders.Plan.SetClassAssignment("{w.name(cara)}", "MAGE", {B["WISDOM"]})')
    w.settle(30)
    # Cara's client refused it and told everyone what her row really is
    assert w.assigned(bram, cara, "MAGE") == B["KINGS"]
    w.assert_in_sync()


def test_slow_older_row_does_not_undo_a_newer_edit(make_sim):
    # messages take 10-12 s here: Cara's row is under way when Ada edits it
    w = World(make_sim, latency=(10.0, 12.0))
    ada, bram, cara = w.pala("Ada"), w.pala("Bram"), w.pala("Cara")
    w.group([ada, bram, cara], settle=120)
    w.assign(cara, cara, "WARRIOR", B["MIGHT"])
    w.settle(60)
    w.lua(cara, "HolyOrders.Comm.SendFull()")
    w.settle(1)
    w.assign(ada, cara, "PRIEST", B["WISDOM"])
    w.settle(120)
    assert w.assigned(ada, cara, "PRIEST") == B["WISDOM"]
    w.assert_in_sync()


def test_owner_who_missed_an_edit_still_has_the_last_word(make_sim):
    w = World(make_sim)
    ada, bram, cara = w.pala("Ada"), w.pala("Bram"), w.pala("Cara")
    w.group([ada, bram, cara])
    w.assign(cara, cara, "WARRIOR", B["MIGHT"])
    w.settle()
    w.sim.logout(cara)
    w.assign(ada, cara, "PRIEST", B["WISDOM"])  # Cara is offline and never gets this
    w.settle()
    w.sim.login(cara)
    w.settle(60)
    w.assert_in_sync()
    assert w.assigned(cara, cara, "WARRIOR") == B["MIGHT"]


def test_two_coordinators_editing_a_row_of_a_paladin_without_the_addon(make_sim):
    w = World(make_sim)
    ada, bram = w.pala("Ada"), w.pala("Bram")
    lena = w.bare("Lena", "PALADIN")
    dora = w.member("Dora", "WARRIOR")
    w.group([ada, bram, lena, dora])
    w.assign(ada, lena, "WARRIOR", B["MIGHT"])
    w.assign(bram, lena, "WARRIOR", B["KINGS"])
    w.settle(30)
    w.assert_in_sync()
    w.assign(ada, lena, "PRIEST", B["WISDOM"])
    w.assign(bram, lena, "MAGE", B["WISDOM"])
    w.settle(30)
    w.assert_in_sync()


def test_preplanned_paladin_keeps_the_plan_on_arrival(make_sim):
    w = World(make_sim)
    ada, bram, cara = w.pala("Ada"), w.pala("Bram"), w.pala("Cara")
    # Cara still carries assignments from an older group
    w.lua(cara, f'HolyOrders.Plan.SetClassAssignment("{w.name(cara)}", "ROGUE", {B["KINGS"]})')
    w.group([ada, bram])
    w.slash(ada, f"/ho expect {cara.first} {cara.surname}")
    w.assign(ada, cara, "WARRIOR", B["MIGHT"])
    w.settle()
    w.group([ada, bram, cara])
    w.settle(60)
    w.assert_in_sync()
    assert w.assigned(cara, cara, "WARRIOR") == B["MIGHT"]
    assert w.assigned(cara, cara, "ROGUE") is None


def test_classic_no_salvation_mode_swaps_and_restores(make_sim):
    w = World(make_sim, classic=True)
    ada, bram = w.pala("Ada"), w.pala("Bram")
    rolf, pia = w.bare("Rolf", "ROGUE"), w.bare("Pia", "PRIEST")
    w.group([ada, bram, rolf, pia], raid=True)
    w.assign(ada, ada, "ROGUE", B["SALVATION"])
    w.assign(ada, bram, "PRIEST", B["SALVATION"])
    w.settle()
    before = w.assert_in_sync()
    w.slash(ada, "/ho nosalv")
    w.settle(30)
    during = w.assert_in_sync()
    assert f" {B['SALVATION']} " not in during
    w.slash(ada, "/ho nosalv")
    w.settle(30)
    assert w.assert_in_sync() == before


# --- restricted content -----------------------------------------------------------------


@pytest.mark.parametrize("secrets", ["encounter", "instance"])
def test_sync_survives_unreadable_unit_data(make_sim, secrets):
    # the modern client can hide other players' unit data from addons (in an
    # instance, or during a boss fight): a roster scan then must not empty the
    # roster, or every later message would be dropped as "from a stranger"
    w = World(make_sim, secrets=secrets)
    ada, bram = w.pala("Ada"), w.pala("Bram")
    dora = w.member("Dora", "WARRIOR")
    w.group([ada, bram, dora])
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.settle()
    w.sim.enter_instance([ada, bram, dora], "Molten Core")
    w.settle()
    w.sim.event(ada, "GROUP_ROSTER_UPDATE")
    w.sim.kill_boss([ada, bram, dora], 663, "Lucifron", duration=60)  # roster events during the fight
    w.assign(bram, bram, "WARRIOR", B["KINGS"])
    w.settle(30)
    assert len(w.roster(ada)) == 3
    w.assert_in_sync()
    assert w.assigned(ada, bram, "WARRIOR") == B["KINGS"]
