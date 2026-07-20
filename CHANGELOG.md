# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.21.1] - 2026-07-20

### Fixed
- Minimap button position: it used a fixed radius that only fit the default
  minimap and sat inside a resized (larger) one. The radius now follows the
  minimap's actual size so the button hugs the edge at any size, handles square
  minimaps, and re-places shortly after login to catch minimap resizer addons.

## [0.21.0] - 2026-07-20

Sync protocol stays v4. The buff-request message now carries an ordered list;
a 0.20.x client simply shows "no request" from a 0.21 requester (graceful) —
otherwise fully compatible.

### Added
- Ranked buff requests: request a prioritised *list* of blessings for yourself
  instead of a single one. The request window is now a ranked picker — click
  blessings in priority order (each shows a rank badge), click again to remove.
  The list is shown in the assignment window as mini blessing icons with rank
  badges on each member's row (the full list is in the member tooltip), and the
  auto-planner honours your highest castable preference, still behind tank
  protection and eligibility.
- Opt-in "Share assignments with legacy blessing addons": broadcasts your own
  blessing plan in the wire format of an older third-party blessing addon, so
  raiders still running it see your assignments during a transition. Off by
  default; emit-only (it never reads their state).

### Changed
- The buff-request window now wears the shared panel skin (dark rounded panel
  with a thin gold border, gold title and buttons), matching the assignment
  window and fly-out, with legible gold rank badges.

### Fixed
- Long member/class row labels no longer overflow into the cell columns — row
  labels are bounded to their area and truncate instead of spilling over.
- A half-constructed assignment window (if creation is interrupted) no longer
  cascades into repeated errors on every refresh.

## [0.20.0] - 2026-07-20

Sync protocol stays v4 — this release is compatible with 0.17.x–0.19.x. The new
sync messages (auras, buff requests, spec tags) are additive and older clients
simply ignore them.

### Added
- Paladin aura assignment: each paladin's aura is assignable and mouse-wheel
  adjustable (your own column offers the auras you actually know), shown as a
  strip in the assignment window and as a button on the cast bar, and synced to
  the group. The aura button greys out when the correct aura is already active.
- Per-class fly-out on the cast bar: hover a class button to see every member of
  that class with their assigned blessing and a live status border — green has
  it, red assigned-but-missing, yellow requested, neutral when out of range.
  Left-click a row casts that member's single blessing, mouse-wheel re-assigns
  it, right-click clears — all synced exactly like the assignment window. It is
  an out-of-combat tool and closes when combat starts.
- Buff requests for non-paladins: request a blessing for yourself and the
  paladins see it as a yellow-framed badge on the cast bar, in the fly-out and
  in the assignment window.
- Expand/collapse-all-classes toggle in the assignment window header.
- Scale options for the cast bar and for the windows (Interface Options).
- The assignment window remembers its on-screen position across sessions.

### Changed
- Visual redesign of the cast bar: the handle is now a gem node that doubles as
  an overall status light (green all covered, yellow expiring, red missing, and
  red while a force-rebuff is running); cast buttons are rounded with the timer
  overlaid larger on the icon. Ctrl-drag moves the handle and the separate
  lock/unlock toggle is gone.
- The assignment window and the class fly-out share a new lean look: a dark
  rounded panel with a thin gold border, a blue title gem, a gold close button,
  gold-labelled buttons, a gold seam under the title, and the crest in the
  corner. Every colour comes from one shared palette.
- Clearer cast-mode tags in the assignment window: A (auto), G (greater),
  S (single) — larger and colour-coded so they read on any blessing icon.
- Larger blessing icons in the assignment window (rows grow to fit).
- Quieter chat by default: routine status messages are off unless you enable
  them; open-edit is on by default.
- Windows now sit at the standard panel strata, so higher-priority windows
  (calendar and the like) draw cleanly over them instead of bleeding through.

### Fixed
- The golden handle stays on top when the bar is set to keep above other windows.
- Saturated handle status colours so red reads as red, not orange.
- Fly-out edits now show up in the assignment window (the affected class row
  expands so the per-member override is visible).
- The class icon draws above the status border on the cast bar.

## [0.19.0] - 2026-07-19

Sync protocol stays v4 — this release is compatible with 0.17.x/0.18.x; the
new sync messages are additive and older clients simply ignore them.

### Added
- Persistent per-member blessing preferences ("likings"): assigning a member a
  blessing by hand (window click or `/ho override`) now remembers that wish by
  character name, permanently and independent of which paladins are present.
  Auto honors it in every future raid, still behind tank protection and
  castability, and it syncs to the other paladins so everyone's Auto computes
  the same plan. New `/ho prefs` lists and clears remembered likings; the
  member tooltip shows them.
- Explicit "none" state on the cast bar: mouse-wheeling now cycles
  ...blessing → none → blessing. Landing on "none" keeps a visible placeholder
  button (nothing is cast) instead of the button — or the whole bar —
  disappearing, so you can wheel straight back to a blessing. The state
  persists across reloads; a full removal is still a right-click in the
  assignment window.
- Mouse-wheel scrolling in the assignment window, so a fully expanded 40-man
  roster stays reachable.
- Option "Keep cast bar above other windows" for setups whose unit-frame
  addons would otherwise hide the bar.

### Changed
- Options now live in the standard Blizzard Interface Options (Interface →
  AddOns → HolyOrders) instead of a custom window; `/ho opt` and shift-clicking
  the minimap button open them there.
- Bare `/ho` opens the assignment window. The command list moved to `/ho help`
  (player commands) with diagnostics under `/ho help debug`.
- The cast bar now sits below standard UI panels by default, so windows like
  the calendar draw over it; opt back into the raised layer with the new
  option above.

### Fixed
- Auto could produce an empty plan (and a vanishing bar) for a paladin who
  cannot cast the top class preference — for example without Blessing of Kings
  talented; the planner now falls through the whole preference chain.
- Auto no longer leaves a member unbuffed because an absent paladin's leftover
  override still occupied them; stale overrides of paladins not in the raid are
  pruned before planning.
- Sync messages that would exceed the addon-message size cap are now split into
  ordered fragments and reassembled instead of being dropped — a paladin with
  many per-member overrides no longer loses part of a plan.
- Stale peer entries are pruned when members leave the group.
- On a refresh, a class-wide greater blessing is recast before override or pet
  singles that the greater would immediately overwrite.

## [0.18.0] - 2026-07-19

### Added
- Version guard messages: when sync is disabled because of incompatible
  protocol versions, chat now says WHO is outdated (you or the other paladin)
  and where to download the update. When a group member runs a newer but
  still compatible release, you get a one-time update hint per session —
  sync keeps working in that case.

(Sync is, and stays, hard-gated on the protocol version: any release that
changes the sync format bumps it, and mismatched clients ignore each other's
messages entirely — mixed protocols can never half-apply anything.)

## [0.17.0] - 2026-07-19

Results of the second full adversarial review. **Sync protocol v4 — breaking:
all paladins in the group must update together** (older versions are announced
in chat as incompatible, same as the v3 bump).

### Fixed

Sync:
- Loading a stored plan rolled the sync revision counters back to save time —
  afterwards every edit and plan broadcast from that client was silently
  rejected by the whole group. Stored plans no longer carry revision state.
- Plan broadcasts could apply partially when racing a pending edit (tank list
  changed, rows kept); they are now authoritative snapshots applied atomically
  or not at all, including an explicit row for every paladin so a de-assigned
  paladin's stale duty can no longer resurrect.
- The tank list rode inside the broadcast's final message and could exceed the
  addon-message size cap — the whole plan apply then silently vanished for the
  raid. It now travels in its own chunked messages.
- Players outside the group could edit plans and tank flags by whisper; all
  state-changing messages now require the sender to be a current group member.
- Message bursts are rate-limited (classic clients silently drop floods), and
  remote log pulls have a per-requester cooldown.
- Malformed revision values are rejected; two message paths that applied older
  revisions backwards are consistent with the rest.
- Tank flags send immediately, and a received plan snapshot cancels pending
  tank sends — a debounce race could invert a tank click group-wide.

Planning and casting:
- Spec tags inferred by inspection were client-local, so a paladin whose
  client had not inspected the tank could still cast Salvation on them;
  protection tags now sync to the group.
- Auto-assigned single overrides could go to a paladin whose own greater
  blessing covers the same class — every greater refresh wiped their single.
  Caster selection avoids these paladins when possible, and pending greater
  casts hold back override singles on the same class.
- Party auto-planning could compute different casters on different clients
  (party unit order is client-relative); members are processed in a
  deterministic order now.
- No-Salvation mode: enabling with no Salvation in the plan is refused (a
  racing second lead would snapshot an already-swapped plan), roster changes
  no longer auto-apply a stored Salvation-bearing plan while the mode is
  active, and a demoted snapshot holder can still broadcast a lead-requested
  revert.
- Greater-blessing decisions count only members that can actually be cast on
  (offline/dead members no longer waste a Symbol of Kings), and the force
  rebuff sweep ends even while unreachable members are missing buffs.
- Only hunter and warlock pets are considered for pet buffs — temporary pets
  (shadowfiends, water elementals) no longer prompt endless buffing.

Interface:
- Moving or resetting the cast bar in combat no longer triggers the Blizzard
  protected-action error (reset defers to combat end).
- Member override cells were drawn shifted right of their paladin's column.
- Cast bar timer text no longer overlaps the next button in vertical layouts,
  and switching the growth direction keeps the handle in place.
- Paladin names with umlauts no longer truncate into garbled column headers.
- Open tooltips refresh when the button or cell under the cursor is
  reassigned; the class tooltip's greater-vs-singles prediction uses the
  engine's real verdict.
- The mouse wheel on a bar button that shows only a single-member override no
  longer creates a class-wide duty out of nothing.
- Long German option labels wrap, the options panel live-refreshes while
  open, and plan/pet toggles update an open assignment window.

### Changed
- Sync protocol v4 (breaking): plan broadcasts are atomic snapshots; tank
  lists and spec tags have their own message types.

## [0.16.0] - 2026-07-19

Results of a full adversarial code review before v1.0.

### Fixed
- A Lua error inside the auto-planner could silently disable ALL outgoing
  sync for the rest of the session; the bulk-edit suspension is now
  error-safe.
- Pet buffing was broken for common raid compositions (pets were tied to
  their pseudo-class needing a player row, and player eligibility rules
  excluded them); pet duties now follow the OWNER's class everywhere.
- Auto-overrides concentrated on one paladin and could push their sync row
  over the message size cap (silent loss); they are now spread round-robin.
- Roster changes could silently overwrite unsaved plan edits with a stored
  plan; unsaved edits are now kept and the stored plan offered instead.
- Tank flagging is lead/assist-gated on the sender side too (was silently
  rejected by receivers, desyncing plans).
- Spec inspection no longer starves for members who come into range later,
  no longer fights the Blizzard inspect window, cleans up its session on
  timeout, and stops re-inspecting specs without preference mappings.
- "Unknown" placeholder names during zoning can no longer poison roster
  signatures and stored plan keys (rescan is scheduled instead).
- Greater blessings automatically fall back to singles with zero Symbols of
  Kings; non-lead Auto now says the plan stays local and syncs at least the
  own row; various smaller hardening fixes (early-message guard, stale
  plan-list deletes, remote-log growth).

### Changed
- Settings and plans are now stored PER CHARACTER (paladin alts no longer
  overwrite each other). Existing account-wide data is not migrated —
  re-apply your few settings once after updating.

## [0.15.1] - 2026-07-19

### Fixed
- Incompatible protocol versions in the group are now announced in chat
  (once per sender) instead of being silently ignored — mixed-version groups
  looked like "sync randomly broken".

## [0.15.0] - 2026-07-19

### Added
- Member rows show the effective blessing: cells without an override display
  the blessing inherited from the class assignment (dimmed), including pets
  and tank exceptions; the tooltip names the inherited source.

### Fixed
- Wheel-cycling on the bar threw a hidden error and only refreshed the UI on
  the next ticker; it now updates bar and window immediately.

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
