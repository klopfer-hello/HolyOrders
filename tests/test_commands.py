"""Slash commands and the cast choice, with Forever's first name + surname."""

from helpers import BLESSING as B
from helpers import World


def party(make_sim):
    w = World(make_sim)
    ada = w.pala("Ada")
    dora, dirk = w.bare("Dora", "WARRIOR"), w.bare("Dirk", "WARRIOR")
    w.group([ada, dora, dirk])
    return w, ada, dora, dirk


def is_tank(w, ch, target):
    return w.lua(ch, f'return HolyOrders.Plan.IsTank("{w.name(target)}")')


def test_tank_command_takes_first_name_and_surname(make_sim):
    w, ada, dora, dirk = party(make_sim)
    w.slash(ada, f"/ho tank {dora.first} {dora.surname}")
    assert is_tank(w, ada, dora) is True
    w.slash(ada, f"/ho tank {dirk.first}")  # a unique first name is enough
    assert is_tank(w, ada, dirk) is True


def test_first_name_shared_by_two_members_picks_nobody(make_sim):
    w = World(make_sim)
    ada = w.pala("Ada")
    one, two = w.bare("Dora", "WARRIOR"), w.bare("Dora", "PRIEST")  # different surnames
    w.group([ada, one, two])
    w.slash(ada, "/ho tank Dora")
    assert is_tank(w, ada, one) is False and is_tank(w, ada, two) is False
    w.slash(ada, f"/ho tank Dora-{two.surname}")
    assert is_tank(w, ada, two) is True and is_tank(w, ada, one) is False


def test_override_command_takes_a_surname(make_sim):
    w, ada, dora, dirk = party(make_sim)
    w.slash(ada, f"/ho override {dora.first} {dora.surname} {B['KINGS']}")
    assert w.override(ada, ada, dora) == B["KINGS"]


def test_spec_command_takes_a_surname(make_sim):
    w, ada, dora, dirk = party(make_sim)
    w.slash(ada, f"/ho spec {dora.first} {dora.surname} protection")
    assert w.lua(ada, f'return HolyOrdersDB.specCache["{w.name(dora)}"]') == "protection"


def test_removed_blessings_cannot_be_assigned_by_command(make_sim):
    w, ada, dora, dirk = party(make_sim)
    w.slash(ada, f"/ho assign WARRIOR {B['SALVATION']}")
    w.slash(ada, f"/ho override {dora.first} {B['LIGHT']}")
    w.slash(ada, "/ho request salvation")
    assert w.state(ada) == ""
    assert w.lua(ada, "return HolyOrdersDB.myRequests") is None


def test_expect_needs_a_surname_on_forever(make_sim):
    w, ada, dora, dirk = party(make_sim)
    w.slash(ada, "/ho expect cara")
    assert w.lua(ada, "return HolyOrders.Plan.Expected()") in ([], {}, None)
    w.slash(ada, "/ho expect cara-holt")
    assert w.lua(ada, "return HolyOrders.Plan.Expected()") == ["Cara-Holt"]


def test_clearing_a_spec_tag_reaches_the_other_paladins(make_sim):
    w = World(make_sim)
    ada, bram = w.pala("Ada"), w.pala("Bram")
    dora = w.bare("Dora", "WARRIOR")
    w.group([ada, bram, dora])
    w.slash(ada, f"/ho spec {dora.first} protection")
    w.settle()
    assert is_tank(w, bram, dora) is True
    w.slash(ada, f"/ho spec {dora.first} clear")
    w.settle()
    assert is_tank(w, bram, dora) is False


def test_class_blessing_stays_the_greater_when_an_override_is_next(make_sim):
    # warriors get Might from me, the tank an extra Kings: with Might on everyone,
    # the next cast is Kings on the tank - but the class-wide blessing is still Might
    w, ada, dora, dirk = party(make_sim)
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.set_override(ada, ada, dora, B["KINGS"])
    might = '{ name = "Greater Blessing of Might", duration = 3600, expirationTime = GetTime() + 3000 }'
    w.lua(ada, f'HO_FAKE.buffs["party1"] = {{ {might} }} HO_FAKE.buffs["party2"] = {{ {might} }}')
    assert w.tasks(ada)["WARRIOR"] == f"Blessing of Kings>{w.name(dora)}"
    task = w.lua(ada, "local t = HolyOrders.Engine.tasks.WARRIOR return { t.blessingID, t.classBlessingID }")
    assert task == [B["KINGS"], B["MIGHT"]]
