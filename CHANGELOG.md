# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.0] - 2026-07-19

### Changed
- Auto-assign now scores full buff strength: improvement talents (dominant),
  then spell rank, then greater-version knowledge — the paladin with the
  stronger Might gets the Might. Capabilities exchange spell ranks (protocol
  v3: everyone must update for cross-paladin scoring to work).

## [0.13.1] - 2026-07-19

### Fixed
- The cast bar position was not restored correctly after a reload: the saved
  offsets were re-applied against the wrong anchor point. The full anchor is
  now saved. Re-drag the bar once; from then on the position sticks.

## [0.13.0] - 2026-07-19

### Added
- German localization (deDE): window, bar, options, minimap tooltips and the
  frequent chat messages; slash-command output stays English.
- Mouse wheel over a cast bar button cycles your class assignment (out of
  combat); the change syncs to the group and the assignment window instantly.

## [0.12.0] - 2026-07-19

### Added
- Pets appear in the assignment window under their class (labeled with their
  owner) and can be given per-pet overrides like any member.

### Fixed
- The options window's close button was blocked by the drag header — clicks
  only landed next to it.

## [0.11.0] - 2026-07-19

### Added
- `/ho plan clear` deletes all stored plans (with a confirm step; the active
  plan is untouched).

## [0.10.0] - 2026-07-19

### Added
- Option "Prefer greater blessings even for single members": the auto cast
  mode normally uses 10-minute singles below 2 class members (saves symbols);
  with this on, greater is cast whenever it is known — the 30-minute duration
  wins over reagent thrift.

## [0.9.1] - 2026-07-19

### Fixed
- Tanks could still receive Salvation: the engine now refuses to resolve a
  greater Salvation over any class containing a tank (even when the tank was
  marked after planning; an explicitly forced greater mode is respected), and
  the party planner applies the same tank rules as the raid branch.
- Protection-tagged players (manual or inspect-inferred) now count as tanks
  everywhere: Salvation protection, Kings singles, planner and window display.

## [0.9.0] - 2026-07-19

### Added
- Cast bar growth direction: right, left, down or up (options panel or
  `/ho bar grow <dir>`); the drag handle stays at the origin end.

## [0.8.0] - 2026-07-19

### Added
- Range-aware rotation: out-of-range members no longer block the cast
  rotation — they are skipped (and shown in the tooltip) until they come
  close. Greater blessings pick a nearby anchor, which covers distant class
  members anyway.

## [0.7.0] - 2026-07-19

### Added
- No-Salvation mode state is synced: every client's "No Salv" button shows
  the active state, and any lead can revert — the paladin holding the
  snapshot restores the exact pre-encounter plan and broadcasts it.

## [0.6.1] - 2026-07-19

### Fixed
- Greater blessings were downgraded to 10-minute singles when members carried
  per-member overrides identical to the class assignment (left over from
  earlier edits). Such redundant overrides no longer block greater casts and
  are cleaned from the plan on every Auto run.

## [0.6.0] - 2026-07-19

### Added
- Minimap button (drag to move; click: window, right-click: force rebuff,
  shift-click: options).
- Options panel (`/ho opt` or shift-click the minimap button): cast bar
  visibility/lock, open edit, pet buffing (hunter/warlock toggles and pet
  blessing choice), minimap button, debug trace.
- Inspect-based spec inference: empty spec tags are filled automatically by
  inspecting members in range (manual tags always win).
- `/ho report`: announce missing blessings to the group.

### Changed
- Pets are buffed with the configured pet blessing (default Might) by the
  paladin covering their base class; warlock pets are opt-in.

## [0.5.0] - 2026-07-19

### Added
- Salvation in parties: class preferences now include Salvation for DPS
  roles, and multi-paladin parties plan each class's top preferences across
  the paladins (e.g. two paladins → Kings/Wisdom/Might plus Salvation).

### Changed
- Cast bar buttons: left-click casts the planned blessing (greater when
  planned), right-click always casts the 10-minute single on the same target.

## [0.4.0] - 2026-07-19

### Changed
- Sync protocol v2: compact wire encoding (single-character class/mode codes,
  ~4x smaller rows) keeps every message safely under WoW's 255-byte addon
  message cap; oversized messages are refused and logged instead of silently
  lost. Protocol v1 clients (0.3.0 and older) are ignored — update everyone.

## [0.3.0] - 2026-07-19

### Added
- Sync debugging: `/ho trace` logs every sent/received sync message;
  `/ho getlog <player>` pulls a group member's recent HolyOrders log over the
  addon channel into your own SavedVariables — no file exchange needed.

## [0.2.0] - 2026-07-19

### Added
- No-Salvation encounter mode (`/ho nosalv` or the window's "No Salv" button):
  swaps every Salvation assignment for a substitute blessing and restores the
  exact previous plan when toggled off; broadcast raid-wide by leads.

## [0.1.0] - 2026-07-19

First shareable pre-release: full solo workflow plus multi-paladin sync.
For WoW Classic TBC Anniversary (2.5.6). Not yet battle-tested in raids.

### Added
- Project scaffold.
- Blessing data with runtime spellbook resolution (locale-safe, no rank tables).
- Own talent scanning (improvement ranks via icon matching, spec summary).
- Roster scanning: party/raid, pets with owner mapping, subgroups, MAINTANK roles.
- Debug commands: `/ho spells`, `/ho roster`.
- Blessing plans: active plan persists across reloads; stored plans per paladin
  roster with silent re-apply on exact match and suggestion on similar rosters.
- Plan commands: `/ho plan show|save|list|apply|delete`, `/ho assign`,
  `/ho override`, `/ho tank`.
- Deterministic auto-planner (`/ho auto`): blessing coverage by talent score,
  solo-raid Salvation mode with tank protection, per-member preference singles.
- Class/spec blessing preferences with shipped defaults; `/ho spec` tags a
  member's spec for the planner.
- Persistent debug log in SavedVariables (command errors, roster/planner/plan
  events); `/ho log [n|clear]` and `/ho dump` state snapshot for offline
  analysis.

- Cast engine: per-class next-target/next-spell selection (missing first, then
  soonest expiring; override and tank rules applied; greater vs normal by mode).
- Secure cast bar: movable, lockable, per-duty buttons with counts and timers;
  combat-consistent display. `/ho bar lock|unlock|show|hide|reset`.
- Force rebuff (`/ho rebuff` or right-click the bar handle): pre-pull sweep
  that re-casts every assigned buff older than 2 minutes; ends automatically
  when everything is fresh. Handle glows red while active.
- Addon-list icon (`IconTexture`) and README banner artwork.
- Multi-paladin sync: revision-numbered per-paladin rows, capture-at-send
  debounced edits, explicit clear broadcasts, atomic plan application
  (auto-plan and stored-plan loads broadcast as one unit), capability
  exchange (known blessings + talents feed the auto-planner), symmetric
  edit permissions (self / lead / open-edit). Commands: `/ho sync`,
  `/ho peers`, `/ho openedit`, `/ho ping`.
- Assignment window (`/ho win`): class-grid layout — rows are classes
  (expandable to members), columns are paladins; click cycles blessings,
  right-click clears, shift-click cycles cast mode; member rows edit
  overrides, tank flags (right-click name) and spec tags (click name).
  Auto/Rebuff/Save header buttons; ESC closes.

### Fixed
- Unicode arrows replaced with ASCII in chat output (rendered as boxes).
- Rank-less blessings (Salvation, Kings) no longer show an empty rank.
- Case-insensitive name lookup for `/ho override|tank|spec`; tank no longer
  accepts names outside the roster.
