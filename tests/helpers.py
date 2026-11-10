"""Shared scenario helpers for the HolyOrders simulator tests.

A `World` builds a simulated group out of three kinds of clients:
- `pala()` / `member()`: clients running HolyOrders (plus the test fakes),
- `legacy()`: a paladin running only the older third-party blessing addon's
  wire (a recorder; its messages are sent by hand with `legacy_send`),
- `bare()`: a client without any blessing addon.

The default is WoW Forever (characters have a surname, no Salvation, no pets);
`World(make_sim, classic=True)` makes HolyOrders take its classic-client code
paths instead (legacy API, realm-style names, Salvation and Light exist).
"""

import os

TESTS = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(TESTS)
FAKES = os.path.join(TESTS, "fakes", "HOSimFakes")
CLASSIC = os.path.join(TESTS, "fakes", "HOSimClassic")
LEGACY = os.path.join(TESTS, "fakes", "HOSimLegacy")

SURNAMES = ["Quill", "Holt", "Vell", "Fenn", "Marsh", "Dray", "Lowe", "Pike", "Reed", "Stone", "Thorn", "Wade"]
LEGACY_PREFIX = "PLPWR"


class World:
    def __init__(self, make_sim, classic=False, **opts):
        self.classic = classic
        # HO_SIM_PROFILE=realistic reruns every scenario with the 55-77 s message
        # latency measured on the Forever beta; waits stretch accordingly
        options = dict(
            secrets="off", profile=os.environ.get("HO_SIM_PROFILE", "fast"), unitname_returns_surname=not classic
        )
        options.update(opts)
        self.time_scale = 25 if options["profile"] == "realistic" else 1
        self.sim = make_sim([CLASSIC, FAKES, LEGACY, ADDON], **options)
        self.ho_addons = (["HOSimClassic"] if classic else []) + ["HOSimFakes", "HolyOrders"]
        self.chars = []

    # --- characters ----------------------------------------------------------------
    def _char(self, first, cls, addons, level=60):
        surname = None if self.classic else SURNAMES[len(self.chars) % len(SURNAMES)]
        ch = self.sim.char(self.sim.account(), first, surname, cls=cls, level=level, addons=addons)
        self.chars.append(ch)
        return ch

    def pala(self, first, level=60, bridge=False):
        """A paladin running HolyOrders; bridge=True turns the legacy broadcast on."""
        ch = self._char(first, "PALADIN", self.ho_addons, level)
        if bridge:
            self.enable_bridge(ch)
        return ch

    def member(self, first, cls="WARRIOR", bridge=False):
        """A non-paladin running HolyOrders (requests, or a coordinator)."""
        ch = self._char(first, cls, self.ho_addons)
        if bridge:
            self.enable_bridge(ch)
        return ch

    def legacy(self, first, cls="PALADIN"):
        """A client that only speaks the legacy blessing addon's wire."""
        return self._char(first, cls, ["HOSimLegacy"])

    def bare(self, first, cls="WARRIOR"):
        return self._char(first, cls, [])

    def enable_bridge(self, ch):
        self.lua(ch, "HolyOrders.db.options.legacyBroadcast = true HolyOrders.Interop.SetEnabled(true)")

    def name(self, ch):
        """The name HolyOrders knows this character by."""
        return f"{ch.first}-{self.sim.opt['realm']}" if self.classic else f"{ch.first}-{ch.surname}"

    # --- group and time ------------------------------------------------------------
    def group(self, chars, raid=None, settle=30):
        """Groups the characters (first = leader) and lets greetings and syncs land."""
        g = self.sim.group(chars, raid=raid)
        self.settle(settle)
        return g

    def settle(self, seconds=15):
        self.sim.advance(seconds=seconds * self.time_scale)

    def reload(self, ch):
        self.sim.reload(ch)

    # --- reading a client ----------------------------------------------------------
    def lua(self, ch, code):
        return self.sim.lua(ch, code)

    def state(self, ch):
        """The whole plan as this client shows it (canonical text, no revisions)."""
        return self.lua(ch, "return HO_TEST.State()") or ""

    def peers(self, ch):
        return self.lua(ch, "return HO_TEST.Peers()") or []

    def roster(self, ch):
        return self.lua(ch, "return HO_TEST.Roster()") or []

    def tasks(self, ch):
        return self.lua(ch, "return HO_TEST.Tasks()") or {}

    def chat(self, ch):
        return self.lua(ch, "return HO_TEST.chat") or []

    def whisper_errors(self, chars=None):
        """ "No player named ..." lines any client got back for a whisper."""
        lines = []
        for ch in chars or self.ho_chars():
            lines += [s for s in (self.lua(ch, "return HO_TEST.sys") or []) if "No player named" in s]
        return lines

    def ho_chars(self):
        return [c for c in self.chars if c.addons and "HolyOrders" in c.addons and c.online]

    def assigned(self, ch, owner, cls):
        """Blessing id `owner` holds for a class, as client `ch` sees it."""
        return self.lua(
            ch,
            f"""local row = HolyOrders.Plan.Active().class["{self.name(owner)}"]
                return row and row.{cls} and row.{cls}.id""",
        )

    def override(self, ch, owner, target):
        return self.lua(
            ch,
            f"""local row = HolyOrders.Plan.Active().player["{self.name(owner)}"]
                return row and row["{self.name(target)}"]""",
        )

    def assert_in_sync(self, chars=None):
        """Every HolyOrders client shows exactly the same plan."""
        chars = chars or self.ho_chars()
        states = {ch.first: self.state(ch) for ch in chars}
        first = chars[0].first
        for who, state in states.items():
            assert state == states[first], f"{who} differs from {first}:\n--- {first}\n{states[first]}\n--- {who}\n{state}"
        return states[first]

    # --- editing through a client ----------------------------------------------------
    def assign(self, ch, owner, cls, blessing, mode=None):
        mode_arg = f', "{mode}"' if mode else ""
        self.lua(ch, f'HolyOrders.Plan.SetClassAssignment("{self.name(owner)}", "{cls}", {blessing}{mode_arg})')

    def set_override(self, ch, owner, target, blessing):
        self.lua(ch, f'HolyOrders.Plan.SetPlayerOverride("{self.name(owner)}", "{self.name(target)}", {blessing})')

    def set_aura(self, ch, owner, aura):
        self.lua(ch, f'HolyOrders.Plan.SetAura("{self.name(owner)}", {aura})')

    def toggle_tank(self, ch, target):
        return self.lua(ch, f'return HolyOrders.Plan.ToggleTank("{self.name(target)}")')

    def slash(self, ch, text):
        self.sim.slash(ch, text)

    # --- the legacy addon's side ---------------------------------------------------
    def legacy_rx(self, ch, clear=False):
        """Messages a legacy client received: [(sender, channel, message), ...]."""
        rx = [tuple(m) for m in (self.lua(ch, "return HO_LEGACY.rx") or [])]
        if clear:
            self.lua(ch, "HO_LEGACY.rx = {}")
        return rx

    def legacy_msgs(self, ch, kind=None, clear=False):
        msgs = [m[2] for m in self.legacy_rx(ch, clear)]
        return [m for m in msgs if kind is None or m.split(" ")[0] == kind]

    def legacy_send(self, ch, message, channel=None, target=None):
        if channel is None:
            channel = "RAID" if ch.group and ch.group.raid else "PARTY"
        return self.sim.raw_send(ch, LEGACY_PREFIX, message, channel, target)

    def stats(self):
        return self.sim.stats


BLESSING = dict(WISDOM=1, MIGHT=2, KINGS=3, SALVATION=4, LIGHT=5, SANCTUARY=6)
