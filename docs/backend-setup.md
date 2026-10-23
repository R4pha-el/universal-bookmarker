# Backend setup

Device-only saving requires no server. Authentication and sync require a Supabase project configured with this schema and functions. Use a disposable development project first.

## Apply the schema

Install the current Supabase CLI, sign in, and run from the repository root:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Review pending migrations before applying them to an existing project. `supabase/migrations/202610220001_library.sql` creates metadata, owner policies, mutation/change RPCs, cleanup/deletion records, and the private `originals` bucket with a 25 MiB limit. It expects standard Supabase `auth` and `storage` schemas. Do not apply it to an unrelated production database.

## Configure email codes

Enable email authentication and allow signups if new users should be created. The client calls `/auth/v1/otp` with `create_user: true` and verifies an email token. Set the applicable email template to show `{{ .Token }}` so users can enter the code; a link-only message does not match this UI.

Configure SMTP for delivery beyond provider development limits. Test new and existing accounts, expired codes, and rate limits. Password and social login are not implemented.

## Deploy account functions

```sh
supabase functions deploy delete-account
supabase functions deploy cleanup-originals
```

Both functions read `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from the server runtime. Hosted Supabase normally supplies these reserved variables; verify availability without printing values. Never put a service-role key in client configuration or Git.

`supabase/config.toml` disables gateway JWT checking for these handlers because each explicitly verifies the bearer token against Auth before using server privileges. Preserve that verification. Callers cannot choose the account being deleted or cleaned up.

Deletion freezes writes, removes the owner's Storage originals, and deletes the Auth user last. Failure leaves the account frozen with a retryable error. Cleanup drains at most 100 queued original deletions per call; foreground sync invokes it opportunistically. Monitor persistent failures and drain remaining jobs.

## Configure iOS

Copy `ios/Configuration/Secrets.example.xcconfig` to the ignored `Secrets.xcconfig` beside it. Supply unique bundle identifiers, App Group, Apple team, project URL, and the **client publishable key**. The example's `https:/$()/` form preserves URL slashes through xcconfig parsing.

Enable matching App Group capabilities and signing profiles for the app and Share extension. Run the main app once before using Share capture.

## Validate a disposable deployment

- Sign in on two clients; create, edit, move, and delete while online and offline.
- Confirm account A cannot read or mutate account B's metadata or originals.
- Retry interrupted uploads and mutations; confirm no duplicates or overwrites.
- Edit concurrently and verify conflict resolution preserves the chosen edit.
- Delete a collection and confirm its items remain.
- Queue a Share capture, change accounts, and confirm its original destination remains fixed.
- Delete an account with originals; confirm Storage removal precedes Auth deletion and retry a simulated failure.

Local tests use PGlite PostgreSQL with auth/storage fixtures and injected function HTTP responses. They do not validate hosted Auth, Storage, SMTP, or the edge runtime. See [build status](build-status.md).
