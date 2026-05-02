# Hermes → Dime automation plan

Date: 2026-05-01
Repo: `sofitucci/dimeApp`

## Goal

Let Hermes create Dime transactions from Sofia's daily expense workflow without requiring Apple Shortcuts setup.

The forked iOS app remains the system of record. Hermes prepares signed/structured import batches and delivers them to Sofia's phone. The forked app imports the batch into its local Core Data store, then CloudKit sync carries the result across Sofia's Apple devices.

## Hard boundaries

- Personal project only. Do not use Rootstrap accounts, repos, teams, signing, or infrastructure.
- Do not use the original developer's CloudKit container in a personal production build.
- Do not invent categories. Imported rows must match an existing Dime category by ID or exact category name.
- Avoid Apple Shortcuts as a required integration layer.
- Avoid server-side writes to Dime's private CloudKit database; the app must perform the write with its own entitlements.

## Architecture

### Phase 1: Custom URL import bridge

Add a deep-link route handled by the forked app:

```text
dimeapp://importTransactions?payload=<base64url-json>
```

The payload is a JSON batch:

```json
{
  "version": 1,
  "source": "hermes",
  "transactions": [
    {
      "externalId": "ledger-2026-05-01-0001",
      "date": "2026-05-01",
      "amount": 123.45,
      "type": "expense",
      "category": "Groceries",
      "note": "Verdulería"
    }
  ]
}
```

Import rules:

- `externalId` is required for idempotency.
- `amount` must be positive.
- `type` is `expense` or `income`; default is `expense` only if omitted by a trusted generator.
- Recurring fields are intentionally rejected by the external bridge; Hermes imports one-off rows only.
- Batches must use `version: 1`, `source: "hermes"`, and at most 50 transactions.
- `categoryId` is preferred when available.
- `category` is a strict fallback and must match an existing category name for the same transaction type.
- The importer must not create categories.
- Dates accept ISO timestamps and `yyyy-MM-dd` date-only values.
- Imported IDs are remembered in app-group `UserDefaults` to avoid duplicates without changing the Core Data schema.

User experience:

1. Hermes sends Sofia a Dime import link in Telegram.
2. Sofia taps it on the iPhone.
3. Dime opens, validates the source/version, categories, idempotency, and recurrence rules, then shows a confirmation preview.
4. Sofia taps **Import** only if the link came from Hermes.
5. Dime creates valid transactions, skips duplicates, and reports failures in an alert.

This is not fully silent, but it avoids Shortcuts and avoids unsafe CloudKit writes. It is the smallest robust bridge that can be tested before signing and CloudKit changes are finalized.

### Phase 2: Manual Hermes sync button

Add a refresh button on the Log screen, placed to the left of the existing filter icon.

When tapped, Dime:

1. Fetches a pending Hermes batch from the configured `HermesSyncURL` endpoint.
2. Accepts either a direct batch JSON body or a wrapper containing `batch`, `importURL`, or `url`.
3. Validates the same source/version/category/idempotency/recurrence rules as deep-link imports.
4. Shows the same confirmation preview before writing transactions.
5. Imports only after Sofia taps **Import**, then skips already-imported `externalId` values.

The sync endpoint is intentionally configurable instead of hardcoded. It can be set by:

```text
dimeapp://configureHermesSync?url=<https-url-encoded-sync-endpoint>
```

The app requires HTTPS for this endpoint and asks Sofia to confirm the endpoint host before saving it.

### Phase 3: Category export/list bridge

Add a safe category export route/view so Hermes can learn Sofia's exact Dime categories before creating batches. Options:

- Export categories as JSON from Settings.
- Copy category JSON to clipboard.
- Later, publish category IDs to the private sync queue.

### Phase 4: Signed personal build

Prepare Sofia-owned app identifiers:

- Bundle ID: `com.sofitucci.dime`.
- App group: `group.com.sofitucci.dime`.
- CloudKit container: `iCloud.com.sofitucci.dime`.
- Signing team: Sofia's personal Apple Developer account/team.

The source has been moved off the original developer identifiers. Xcode still needs Sofia to choose her personal signing team and let it create/register the app identifiers before device use.

### Phase 5: Hermes cron workflow

Daily flow:

1. Read Sofia's expense sources.
2. Normalize into a candidate transaction batch.
3. Validate category names against the exported Dime category list.
4. Generate deterministic `externalId` values.
5. Publish the pending batch to the configured Hermes sync endpoint and/or deliver a `dimeapp://importTransactions?...` fallback link to Sofia.
6. Optional: keep a local ledger of generated/imported batch IDs.

### Phase 6: Optional background queue

If Sofia later wants fewer taps, add a small authenticated queue and app-side polling/push trigger. The app still writes locally; no external service writes to Dime/CloudKit directly.

## First implementation slice

- Add deep-link batch parser/importer.
- Wire it into `HomeView.onOpenURL`.
- Keep `dimeapp://newExpense` and existing routes unchanged.
- Store imported `externalId` values in app-group defaults.
- Validate `version: 1`, `source: "hermes"`, max 50 transactions, positive amounts, allowed types, existing categories, and non-recurring imports.
- Show a confirmation preview before writing transactions.
- Add a Log-screen refresh button that triggers manual Hermes sync from the configured HTTPS endpoint.
- Report created/skipped/failed counts.

## Verification

- Static verification from this machine: validate XML/plists and inspect diffs.
- Full compile/device verification requires Xcode, signing, and simulator/device setup. Current machine only has Command Line Tools selected, so `xcodebuild` cannot run the iOS project yet.
