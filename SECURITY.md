# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/hattoriai/notebook/security/advisories/new).

Say what an attacker can do, and how: the page or route, the request or
the payload, the role they need (none, a member, an admin, an agent or a
bot), and the steps. We answer within a week, agree on a fix and a date,
and credit you in the advisory unless you ask us not to.

## Supported versions

Notebook is not released in versions: security fixes are made on `main`.
If you host a notebook, update to the latest `main` and deploy again.

## What is in scope

A notebook takes requests that any person can craft: from people signed
in, from people who are not (sign-in, sign-up, invitation links and
published pages), and from agents through the MCP server. A problem is in
scope when such a request can:

- sign someone in as another person, or create an account where the
  notebook does not allow it (an invite-only notebook);
- show, change or delete a page, a comment, a file or a setting that the
  person, agent or bot may not see or change;
- reach an admin's settings without being an admin;
- read the notebook's secrets (a bucket's key, a bot's API key) or make
  the server send requests where it should not;
- run script in another person's browser;
- crash the notebook, or make the server or the database do unbounded
  work.

The server around the notebook (TLS, the proxy, backups and the host's
own accounts) is the hosting's, not the notebook's: see the
[self-hosting guide](guides/self-hosting.md).
