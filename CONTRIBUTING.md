# Contributing to Notebook

Thank you for helping. This page says what to open (an issue, a pull
request, or a security report) and what a pull request needs. How to run
the notebook locally is in [guides/development.md](guides/development.md),
and how to host one is in [guides/self-hosting.md](guides/self-hosting.md).

Notebooks run in production, holding people's pages. A change is reviewed
with that in mind: how it upgrades a running notebook matters as much as
what it adds.

## Questions, bugs and ideas

- **A bug.** Open an issue with the bug report form: the steps, what you
  expected and what happened.
- **An idea or a change of behaviour.** Open an issue with the feature
  request form, and say the problem before the solution.
- **A security problem.** Do not open an issue. See
  [SECURITY.md](SECURITY.md).

Search the open and closed issues first: the idea may already be planned,
or turned down for a reason given there.

## When a pull request needs an issue first

Open an issue, and agree on the change there, before a pull request that:

- adds a feature, a page, a setting or an environment variable;
- changes sign-in, accounts, invitations, permissions or anything else
  about who can see or do what;
- adds a migration, or changes what is stored and how;
- adds a dependency;
- touches many files, or needs a design decision.

A pull request does not need an issue when it is small and its reason is
plain from the diff: a typo, a broken link, a wrong sentence in a guide,
or a bug fix with a test that fails without it. When in doubt, open the
issue: a short discussion costs less than a pull request that is not
merged.

A pull request with an issue says so: `Fixes #123` or `Closes #123`.

## A pull request

- **One change.** A feature, a formatting pass over unrelated files and a
  config tweak are three pull requests. Each is reviewed and reverted on
  its own.
- **Why, not only what.** The description says the problem the change
  solves, for whom, and what happened before it.
- **Tests.** A bug fix has a test that fails on `main` and passes with
  the fix. A feature has tests of what it does, and of its errors.
- **Upgrades.** A migration runs on a notebook that already has data, and
  a new setting has a default that keeps today's behaviour. Say in the
  description what an admin has to do, if anything, when they upgrade.
- **Docs.** A change an admin or a user can see updates the README or the
  guide it belongs to.
- **The checks pass.** CI runs them on every pull request; run them first:

  ```sh
  mix precommit
  ```

  It compiles with warnings as errors, unlocks unused dependencies,
  formats the code and runs the tests. CI runs the same checks, but with
  `mix format --check-formatted` and `mix deps.unlock --check-unused`, so
  it fails rather than changing your files.

The pull request template has these as a checklist.

## Style

Match the code around your change: its naming, its comments and the way
its guides are written. [AGENTS.md](AGENTS.md) has the project's
conventions for Phoenix, LiveView, Ecto and the templates. `mix format`
settles the rest.

## License

By contributing, you agree that your contribution is released under the
MIT License of the project (see [LICENSE](LICENSE)).
