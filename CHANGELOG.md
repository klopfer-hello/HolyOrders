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
