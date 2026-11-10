"""What changed for paladins on WoW Forever, and what must stay as it was on
the classic client:

- Blessings of Salvation, Light and Sanctuary are gone (only Wisdom, Might and
  Kings are left): nothing may plan, offer or request them.
- Pets cannot be blessed any more: they are no targets and appear nowhere.
"""

from helpers import BLESSING as B
from helpers import World

GONE = (B["SALVATION"], B["LIGHT"], B["SANCTUARY"])


def planned_ids(w, ch):
    """Every blessing id that appears anywhere in the plan this client shows."""
    ids = set()
    for line in w.state(ch).splitlines():
        parts = line.split(" ")
        if parts[0] == "C":
            ids.add(int(parts[3]))
        elif parts[0] == "P":
            ids.add(int(parts[3]))
    return ids


def classes_covered_by(w, ch, owner):
    return {line.split(" ")[2]: int(line.split(" ")[3]) for line in w.state(ch).splitlines() if line.startswith(f"C {w.name(owner)} ")}


def add_pet(w, ch, unit, name="Wolf", cls="WARRIOR"):
    w.lua(ch, f'HO_FAKE.pets["{unit}"] = {{ name = "{name}", class = "{cls}" }}')
    w.sim.event(ch, "UNIT_PET", unit)
    w.settle(5)


# --- removed blessings ---------------------------------------------------------------


def test_solo_paladin_plans_without_salvation(make_sim):
    w = World(make_sim)
    ada = w.pala("Ada")
    others = [w.bare("Wanda", "WARRIOR"), w.bare("Rolf", "ROGUE"), w.bare("Pia", "PRIEST"), w.bare("Mia", "MAGE")]
    w.group([ada] + others)
    w.slash(ada, "/ho auto")
    w.settle()
    ids = planned_ids(w, ada)
    assert ids and not ids & set(GONE), ids
    covered = classes_covered_by(w, ada, ada)
    assert covered["WARRIOR"] == B["KINGS"]
    assert covered["ROGUE"] == B["MIGHT"]
    assert covered["PRIEST"] == B["WISDOM"]
    assert covered["MAGE"] == B["WISDOM"]


def test_raid_plan_gives_every_paladin_a_blessing(make_sim):
    # three paladins, three blessings left: Kings, Might and Wisdom, one each
    w = World(make_sim)
    palas = [w.pala(n) for n in ("Ada", "Bram", "Cara")]
    rest = [w.bare(f"Mem{c}", cls) for c, cls in zip("ABCDEFG", ["WARRIOR", "ROGUE", "PRIEST", "MAGE", "DRUID", "HUNTER", "WARLOCK"])]
    w.group(palas + rest, raid=True)
    w.slash(palas[0], "/ho auto")
    w.settle(60)
    w.assert_in_sync()
    main = set()
    for p in palas:
        covered = classes_covered_by(w, palas[0], p)
        assert covered, f"{p.first} got no assignment at all"
        main |= set(covered.values())
    assert main == {B["KINGS"], B["MIGHT"], B["WISDOM"]}
    assert not planned_ids(w, palas[0]) & set(GONE)


def test_paladin_without_the_addon_is_not_given_a_removed_blessing(make_sim):
    w = World(make_sim)
    ada = w.pala("Ada")
    lena, lars, lore = w.bare("Lena", "PALADIN"), w.bare("Lars", "PALADIN"), w.bare("Lore", "PALADIN")
    rest = [w.bare(f"Mem{c}", cls) for c, cls in zip("ABCDE", ["WARRIOR", "ROGUE", "PRIEST", "MAGE", "DRUID"])]
    w.group([ada, lena, lars, lore] + rest, raid=True)
    for gone in GONE:
        assert w.lua(ada, f'return HolyOrders.Planner.IsAvailable("{w.name(lena)}", {gone})') is False
    assert w.lua(ada, f'return HolyOrders.Planner.IsAvailable("{w.name(lena)}", {B["KINGS"]})') is True
    w.slash(ada, "/ho auto")
    w.settle()
    assert not planned_ids(w, ada) & set(GONE)


def test_removed_blessings_cannot_be_requested(make_sim):
    w = World(make_sim)
    ada, dora = w.pala("Ada"), w.member("Dora", "WARRIOR")
    w.group([ada, dora])
    w.lua(dora, f"HolyOrders.Comm.SendRequest({{ {B['SALVATION']}, {B['KINGS']}, {B['LIGHT']} }})")
    w.settle()
    assert w.lua(dora, "return HolyOrdersDB.myRequests") == [B["KINGS"]]
    assert w.lua(ada, f'return HolyOrders.Comm.requests["{w.name(dora)}"]') == [B["KINGS"]]
    assert w.lua(dora, "return HolyOrders.Request.Offered()") == [B["WISDOM"], B["MIGHT"], B["KINGS"]]


def test_tank_gets_kings(make_sim):
    w = World(make_sim)
    ada = w.pala("Ada")
    wanda, pia = w.bare("Wanda", "WARRIOR"), w.bare("Pia", "PRIEST")
    w.group([ada, wanda, pia])
    w.toggle_tank(ada, wanda)
    w.slash(ada, "/ho auto")
    w.settle()
    assert classes_covered_by(w, ada, ada)["WARRIOR"] == B["KINGS"]


def test_classic_client_still_plans_salvation(make_sim):
    w = World(make_sim, classic=True)
    ada = w.pala("Ada")
    wanda, rolf, pia = w.bare("Wanda", "WARRIOR"), w.bare("Rolf", "ROGUE"), w.bare("Pia", "PRIEST")
    w.group([ada, wanda, rolf, pia])
    w.toggle_tank(ada, wanda)
    w.slash(ada, "/ho auto")
    w.settle()
    covered = classes_covered_by(w, ada, ada)
    assert covered["ROGUE"] == B["SALVATION"]
    assert covered["PRIEST"] == B["SALVATION"]
    assert covered["WARRIOR"] == B["KINGS"]  # the tank never gets Salvation
    assert w.lua(ada, f"return HolyOrders.Request.Offered()") == [1, 2, 3, 4, 5, 6]


# --- pets ------------------------------------------------------------------------------


def test_pets_are_no_targets_on_forever(make_sim):
    w = World(make_sim)
    ada, hugo = w.pala("Ada"), w.bare("Hugo", "HUNTER")
    w.group([ada, hugo])
    w.assign(ada, ada, "HUNTER", B["MIGHT"])
    add_pet(w, ada, "partypet1")
    assert w.roster(ada) == [w.name(ada), w.name(hugo)]
    assert w.tasks(ada) == {"HUNTER": f"Greater Blessing of Might>{w.name(hugo)}"} or w.tasks(ada) == {
        "HUNTER": f"Blessing of Might>{w.name(hugo)}"
    }


def test_pets_are_still_blessed_on_the_classic_client(make_sim):
    w = World(make_sim, classic=True)
    ada, hugo = w.pala("Ada"), w.bare("Hugo", "HUNTER")
    w.group([ada, hugo])
    w.assign(ada, ada, "HUNTER", B["MIGHT"])
    add_pet(w, ada, "partypet1")
    assert "pet:Wolf-SimRealm" in w.roster(ada)
    # the hunter has the blessing already: the pet is what is left to do
    w.lua(ada, 'HO_FAKE.buffs["party1"] = { { name = "Blessing of Might", duration = 600, expirationTime = GetTime() + 500 } }')
    assert w.tasks(ada) == {"HUNTER": "Blessing of Might>Wolf-SimRealm"}


# --- casting --------------------------------------------------------------------------


def test_next_cast_follows_the_assignment(make_sim):
    w = World(make_sim)
    ada = w.pala("Ada")
    wanda, wilma, pia = w.bare("Wanda", "WARRIOR"), w.bare("Wilma", "WARRIOR"), w.bare("Pia", "PRIEST")
    w.group([ada, wanda, wilma, pia])
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.assign(ada, ada, "PRIEST", B["WISDOM"])
    tasks = w.tasks(ada)
    assert tasks["WARRIOR"].startswith("Greater Blessing of Might>")  # two warriors: the class-wide one
    assert tasks["PRIEST"] == f"Blessing of Wisdom>{w.name(pia)}"  # a single priest: the plain one


def test_buffed_members_need_nothing(make_sim):
    w = World(make_sim)
    ada, pia = w.pala("Ada"), w.bare("Pia", "PRIEST")
    w.group([ada, pia])
    w.assign(ada, ada, "PRIEST", B["WISDOM"])
    w.lua(ada, 'HO_FAKE.buffs["party1"] = { { name = "Blessing of Wisdom", duration = 3600, expirationTime = GetTime() + 3000 } }')
    assert w.tasks(ada) == {"PRIEST": "->-"}
    # under five minutes left: time to refresh
    w.lua(ada, 'HO_FAKE.buffs["party1"][1].expirationTime = GetTime() + 200')
    assert w.tasks(ada) == {"PRIEST": f"Blessing of Wisdom>{w.name(pia)}"}


def test_without_symbols_only_plain_blessings_are_cast(make_sim):
    w = World(make_sim)
    ada = w.pala("Ada")
    wanda, wilma = w.bare("Wanda", "WARRIOR"), w.bare("Wilma", "WARRIOR")
    w.group([ada, wanda, wilma])
    w.assign(ada, ada, "WARRIOR", B["MIGHT"])
    w.lua(ada, "HO_FAKE.symbols = 0")
    assert w.tasks(ada)["WARRIOR"].startswith("Blessing of Might>")
