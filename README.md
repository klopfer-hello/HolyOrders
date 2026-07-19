# HolyOrders

![HolyOrders](media/banner.png)

Paladin blessing coordination for WoW Classic (TBC Anniversary, 2.5.6) —
assign, sync, and cast raid blessings without wasting raid time.

A fully independent, from-scratch implementation.

## Features

- **Remembers your plans.** Blessing assignments are stored per raid roster and
  re-applied automatically when you raid with the same people again.
- **Remembers each member's wishes.** Give someone a specific blessing once and
  HolyOrders remembers it by name — permanently, no matter which paladins are
  in the raid. Auto honors those likings in every future raid, and they sync so
  every paladin plans the same way.
- **Deterministic auto-assign.** One click distributes coverage across the
  paladins present, weighing talents and spell ranks so the stronger buff wins.
  Same raid, same talents → same plan, every time.
- **Solo-paladin mode.** Alone as a paladin? Salvation goes on everyone except
  tanks, automatically.
- **Reliable sync.** The comm protocol is designed so what you see is what every
  paladin sees — assignments don't silently revert or get lost, plan broadcasts
  apply atomically, and out-of-date clients are told to update.
- **Pets included.** Hunter and warlock pets are tracked and buffed properly.
- **Secure cast bar.** A movable, per-duty cast bar shows exactly what to cast
  next; mouse-wheel over a button to change your assignment on the fly.
- **Force rebuff.** One click re-casts everything that isn't fresh before a pull.
- **No-Salvation mode.** Swap Salvation out for an encounter and restore the
  exact plan afterwards, raid-wide.
- **German localization** in addition to English.

## Usage

- `/ho` — open the assignment window
- `/ho auto` — compute assignments for the paladins present
- `/ho help` — list all commands (`/ho help debug` for diagnostics)
- Options: **Interface → AddOns → HolyOrders** (or `/ho opt`)

In the assignment window, click a class or member cell to set a blessing,
right-click to clear, and shift-click to change the cast mode. Set a member's
blessing by hand once and it becomes a remembered preference for every raid.

## Compatibility

For WoW Classic TBC Anniversary (interface 2.5.6). Multi-paladin sync requires
every paladin to run a compatible version; the addon announces in chat when
someone in the group is out of date.

## License

MIT — see [LICENSE](LICENSE).
