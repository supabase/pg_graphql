# Security Policy

Thank you for helping keep pg_graphql and its users safe.

## Reporting a vulnerability

Please report suspected vulnerabilities through our HackerOne program:
<https://hackerone.com/supabase>. Please do not open public GitHub issues or
pull requests for security problems.

This repository contains pg_graphql, a Postgres extension that reflects a
GraphQL schema from your SQL schema and resolves GraphQL queries inside the
database. On the hosted Supabase platform it serves the GraphQL endpoint of the
Data API, and anyone can install it in their own Postgres. We accept reports
for both, and we triage them differently (see "Hosted vs. standalone" below).

## What we consider a vulnerability

In general, we want to hear about anything that lets a GraphQL request read or
change data that the calling Postgres role and its Row Level Security (RLS)
policies would not allow through plain SQL, or that lets a role reach more
privilege than it was granted. The problem should be present on the hosted
platform or in a default install.

Examples of what this includes (these are illustrations, not a complete list):

- **Bypassing role permissions or RLS.** A GraphQL query or mutation that reads
  a table or column the role has no privilege on, returns rows an RLS policy
  hides, or writes where the role could not write through SQL.
- **Visibility of hidden entities in the schema.** Tables, columns or functions
  the role has no privilege on appearing in query results or error messages.
- **SQL injection.** GraphQL input, such as arguments, variables, filters or
  aliases, that reaches the generated SQL outside a bound parameter or a quoted
  identifier. pg_graphql passes values as parameters and quotes identifiers it
  reads from the catalog.
- **Privilege escalation in the extension's own functions.** Extension
  functions that run with elevated rights and can be steered by their caller
  into running SQL as the function's owner, or the extension running code that
  a lower role controls with more rights than that role has.
- **Memory-safety bugs.** Crashes or memory corruption in the Rust code that
  can be triggered by an unprivileged role, in particular remote code
  execution. A crash that only affects the caller's own session is not in
  scope.

## What we do not consider a vulnerability

Reports that rely on the behavior below will normally be closed as
informative or not applicable.

**By design**

- **Introspection is off by default and is not an access control.** It is
  opt-in per schema. Enabling it lists the schema, and disabling it does not
  restrict queries or mutations, which are governed by Postgres roles and RLS.
  Reports that a schema with introspection enabled reveals its structure are
  not vulnerabilities.
- **Names are derived from your schema.** Table, column and function names
  appear in the GraphQL schema for roles that can see them. Granting a role
  access to something exposes it.
- **`@graphql` comment directives are configuration.** Setting one requires the
  right to comment on the object. A role that can do that already controls the
  schema.

- **Names that come from the catalog.** Table, column, function and type names
  are read from the database and quoted before use. Creating objects with
  unusual names needs DDL rights, which a role that can do it already holds.

**Customer configuration**

- Tables without RLS, grants to `anon` or `authenticated` that are broader than
  intended, and functions that return more than they should. An RLS bypass must
  be reproduced on a table with correct policies and grants.

**Prerequisites that make the attack pointless**

- The attacker needs a privileged database role, and the result is something
  that role can already do.
- The attacker needs `anon` or `authenticated` to run DDL or open a direct
  database session. The Data API does not provide that, and those roles cannot
  log in.

**Missing hardening or noise**

- **Expensive queries** that stay within `max_rows` and the platform's request
  limits. Show a query that does disproportionate damage compared with the
  equivalent REST or SQL request, and that an unprivileged role can send.

## Out of scope for every Supabase asset

These are excluded program-wide (see also
<https://supabase.com/.well-known/security.txt>). They are repeated here so
you do not need to leave this repository to find them.

- Clickjacking on pages with no sensitive actions.
- Unauthenticated, logout and login CSRF.
- Attacks requiring MITM or physical access to a user's device.
- Attacks requiring social engineering.
- Any activity that could lead to the disruption of our service (DoS).
  This means volumetric attacks, load testing and flooding. A vulnerability in
  our code that lets an unprivileged attacker crash a service or exhaust
  resources for other users or tenants is in scope. Denial of service that only
  affects the attacker's own project, or that needs admin or owner privileges,
  is not.
- Content spoofing and text injection issues without showing an attack vector,
  or without being able to modify HTML/CSS.
- Email spoofing.
- Missing DNSSEC, CAA or CSP headers.
- Lack of Secure or HttpOnly flags on non-sensitive cookies.
- Dead links.
- User enumeration.

## Hosted vs. standalone

On the hosted platform, the boundary is between the roles a customer holds
and the data and privileges their grants and RLS policies allow. On your own
install, the boundary is between the roles you expose GraphQL to and everything
Postgres denies them. Say which one you tested.

## How to write a report that gets triaged quickly

- **Say what you tested, at the top of the report and in the title.** Use one of
  these labels, for example `[Production] ...` in the title and a "Target" line
  at the start of the description:
  - **Production**: the hosted Supabase platform, against a project you own.
    Include the project ref and the role you connected as. Never test another
    customer's project.
  - **Standalone, default configuration**: pg_graphql from this repository, installed in Postgres as the
    documentation describes, with no changed settings. Include the pg_graphql
    and Postgres versions.
  - **Custom configuration**: you changed grants, settings or code. List every
    change and why. We triage these lower.

  Reports that do not say which of the three they are about are slower to
  triage, and are often closed with a request to retest. A finding that works
  only on a custom configuration is not a finding against production.

- **Give a short, runnable PoC.** The schema, grants and RLS policies, the exact
  GraphQL request or SQL, run as the role you name, and the output showing what
  that role could now see or change.
- **State the attacker's starting position and the boundary you crossed.**
  Which role do they start as, and which table, column, row or privilege do
  they reach?
- **Include versions.** The pg_graphql and Postgres versions.
- **One issue per report.** Link variants of the same root cause instead of
  filing each variant separately.
- **Do not send unreviewed AI output.** Reports that were not reproduced by a
  human and that ignore the documentation are closed. AI-assisted analysis is
  fine when you have verified the result.
- **Respond to follow-up questions.** Reports that go quiet after we ask for a
  reproduction are closed.

## Severity

We rate severity by realistic impact. Issues that need an existing privilege,
such as direct database credentials, are rated lower even when they are
valid, and we may fix them as defense in depth.

## Testing and disclosure

These are our program-wide rules. They also apply to AI agents and automated
tools acting on your behalf.

**Testing**

- Do not run automated scanners against other customers' projects. Scanners can
  run up costs for our users, can disrupt services, and our own security
  systems cannot tell hostile reconnaissance from research. If you want to run
  an automated scanner, notify security@supabase.com first and run it only on
  your own Supabase project.
- Do not attack projects that belong to other customers.
- Do not take advantage of a vulnerability you find, for example by downloading
  more data than necessary to demonstrate it, or by deleting or modifying other
  people's data.

**Disclosure**

- Do not reveal the problem to others until we have researched and fixed it and
  informed affected customers.
- If you want to share your research publicly (a conference, a blog or any
  other public forum), send us a draft for review and approval at least 30 days
  before the publication date. Do not include data about Supabase customer
  projects, customers' data, or information about Supabase employees,
  contractors or partners.

**What we promise**

- We will respond to your report within 5 business days with our evaluation and
  an expected resolution date.
- If you have followed these instructions, we will not take legal action against
  you in regard to the report.
- We will handle your report with strict confidentiality and will not pass on
  your personal details to third parties without your permission.
- We will keep you informed of our progress.
- In public information about the problem, we will name you as the discoverer
  unless you prefer otherwise.
