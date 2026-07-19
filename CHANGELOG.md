# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Fixed
- Unicode arrows replaced with ASCII in chat output (rendered as boxes).
- Rank-less blessings (Salvation, Kings) no longer show an empty rank.
- Case-insensitive name lookup for `/ho override|tank|spec`; tank no longer
  accepts names outside the roster.
