# supabase-rls-testing-example

A Postgres schema with Row Level Security and a pgTAP test suite that proves the access rules hold. It is the database layer of a class-enrolment and shop system, extracted from a larger Next.js app (the app itself is not included).

The point of the repository is the tests: instead of clicking around as different users and hoping, each rule is checked in SQL, as the role that would break it.

All data is fictional. Comments inside the SQL files are in Hong Kong Cantonese.

## Who can see what

| Role | Can read | Can write |
|---|---|---|
| Anonymous | Public catalogue: courses, classes, coaches, venues, products, site settings | Custom-order requests only. Guest enrolment and ordering go through `security definer` functions |
| Member (parent) | Their own profile, students, enrolments, attendance, points, orders, custom requests | Their own profile and students, and enrolments for their own students |
| Coach | Students, enrolments and attendance for the classes they are assigned to | Attendance (mark and amend) for those classes |
| Admin | Everything | Everything |

Every table has RLS enabled (18 tables, 69 `create policy` statements across the migrations). Admin gets one `for all` policy per table; everyone else gets narrow policies. Writes that need several steps, such as guest enrolment or placing an order, are single database functions with explicit `grant execute` lines, so the application never needs elevated table access.

## What the tests check

```text
supabase/tests/
  member_isolation.test.sql   Two members, each with students, enrolments, attendance,
                              points, orders and requests. Member A can neither read nor
                              modify any of member B's rows. (38 assertions)
  admin_coach.test.sql        Coach can mark attendance only for their own classes;
                              admin-only operations; first-enrolment points; venue permissions.
  shop.test.sql               Orders, points redemption limits, stock and points changes on
                              pay / ship / cancel, custom-order quotes.
  hk_phone.test.sql           Phone normalisation function and the triggers that apply it.
  badges.test.sql             Who may award and read skill badges.
```

110 planned assertions in total. Each file runs inside a transaction and rolls back, so a run leaves no data behind.

## Run it

Requires Node (for `npx`) and Docker Desktop.

```bash
npx supabase start          # starts a local Postgres + API stack
npx supabase db reset       # applies 29 migrations, then seed.sql
npx supabase test db        # runs the pgTAP suite
```

Expected: five files `ok`, `Result: PASS`.

`seed.sql` creates fictional accounts for the local database only: `admin@educasketball.test`, `coach@educasketball.test` and `member@educasketball.test`, all with the password `Demo1234!`. Do not reuse that pattern anywhere real.

## Things worth reading

- `migrations/…_rls.sql`: the policy design, with the principles written at the top of the file.
- `migrations/…_function_grants.sql`: which roles may call which functions. Postgres grants execute to `public` by default, so this file revokes and re-grants deliberately.
- `migrations/…_phone_login_key.sql`: a fix for a leak in an earlier version. A phone-to-email lookup callable by anonymous users made it possible to harvest member emails. It now needs a server-side secret kept in a `private` schema that anon and authenticated roles cannot read; without the secret, phone login is disabled. No secret is in this repository.
- `tests/member_isolation.test.sql`: how to test a policy, not just a page.

## Limits

- The schema comes from a demo app, so it also contains demo-mode helpers (a nightly reset, simulated payment). They are not needed for the RLS design and a real deployment would remove them.
- Policies are tested for the roles in this project. There is no generic framework here.
- The phone login endpoint is open to anonymous callers when the secret is set; a production system should add rate limiting.

## Licence

MIT
