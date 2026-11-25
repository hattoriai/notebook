# Changelog

All notable changes to Notebook are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Notebook follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Before 1.0, a minor version (0.3.0) adds features, migrations or
settings, and a patch version (0.2.1) fixes bugs and security problems.

Each version says what to do when you upgrade to it, under **Upgrading**.
How to deploy a version is in the
[self-hosting guide](guides/self-hosting.md#upgrade).

## [Unreleased]

## [0.2.0] - 2026-11-25

The first release. Before it, Notebook was deployed from `main`.

### Upgrading

Nothing to do: deploy the `v0.2.0` tag as you deployed `main`. A notebook
deployed from `main` before 2026-11-25 should upgrade, for the security
updates below.

### Included

- Four kinds of page: texts, boards, tables, and databases seen as a
  table, a board, a calendar or a chart. Each is a live room.
- Spaces (everyone's, each person's private one, and teams with members
  and roles), sharing of a page or a folder, icons and images.
- Comments and mentions, an Inbox, a bell and emails.
- Search and a command palette (⌘K).
- Publishing: a page on the web, or a folder as a blog with a feed, at an
  address of your own.
- Agents through the MCP server, with Pause and Stop, and the notebook's
  own bots, powered by Claude, within a monthly budget.
- Invite-only sign-ups, and files on the server's disk or in an
  S3-compatible bucket.
- A deploy with Kamal, on one server, with one SQLite file.

### Security

- Updated dependencies with published advisories: Phoenix 1.8.17,
  Phoenix LiveView 1.2.15, Plug 1.20.4, DBConnection 2.10.3 and idna
  8.0.0 ([#79](https://github.com/hattoriai/notebook/pull/79)).

### Added

- The MIT License ([#80](https://github.com/hattoriai/notebook/pull/80)).
- A security policy, for reporting a vulnerability privately
  ([#80](https://github.com/hattoriai/notebook/pull/80)).
- CI on each pull request: the format, the compiler with warnings as
  errors, Credo, the tests and Dialyzer
  ([#78](https://github.com/hattoriai/notebook/pull/78),
  [#81](https://github.com/hattoriai/notebook/pull/81),
  [#83](https://github.com/hattoriai/notebook/pull/83)), and a guide for
  contributing.

[Unreleased]: https://github.com/hattoriai/notebook/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/hattoriai/notebook/releases/tag/v0.2.0
