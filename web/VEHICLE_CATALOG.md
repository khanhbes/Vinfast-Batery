# Global EV Catalog operations

The Global EV Catalog is the source of truth for vehicle identity and technical
specifications used by the admin dashboard and mobile app. Users may personalize
their nickname, license plate, ODO, SOC, and SoH; battery, charging, and
performance data are resolved from the latest published catalog revision.

## Lifecycle

1. An administrator creates a draft manually or starts a research job.
2. Research suggestions are reviewed field by field. Conflicting or derived
   values retain their source and verification state.
3. Publishing validates required fields and uniqueness, records an immutable
   revision, updates the public catalog, and increments
   `VehicleCatalogMeta/current`.
4. The app observes the global revision and refreshes its last-known-good cache.
   A running trip or charging session continues with the revision captured when
   it started.
5. Archiving hides a configuration from new selections. Existing linked vehicles
   keep resolving the last published specification.

Only these collections are public to authenticated mobile clients:

- `VehicleCatalog`
- `VehicleCatalogMeta`

Drafts, research jobs, revisions, identity keys, manufacturer configuration,
and writes to catalog media are server-only.

## Required environment

The API and worker use the normal Firebase Admin configuration. Never commit an
Admin service-account JSON file.

Optional research configuration:

```text
GEMINI_API_KEY=...
GEMINI_CATALOG_MODEL=gemini-2.5-flash
CATALOG_RESEARCH_DAILY_LIMIT=50
CATALOG_RESEARCH_POLL_SECONDS=4
```

Without `GEMINI_API_KEY`, official HTTPS URL/PDF imports continue to work. Add a
manufacturer and its approved official domains from the dashboard before
starting a research job. URL imports reject private/link-local addresses,
unsafe redirects, oversized responses, and unsupported MIME types.

## Run locally

From `web`:

```powershell
python server.py
python catalog_research_worker.py
```

Or start the API, dashboard, AI service, and catalog worker through the provided
Docker Compose configuration.

## Seed and migration

The migration imports the existing 11 VinFast definitions and produces a report
for current user vehicles. It defaults to a read-only dry run:

```powershell
python scripts/migrate_vehicle_catalog.py
```

Review all `ambiguous` and `unmatched` rows. Apply only after verifying the
Firebase project and creating a backup:

```powershell
python scripts/migrate_vehicle_catalog.py --apply
```

The migration preserves personal vehicle data and does not guess ambiguous
matches. During the compatibility period, each publish also projects the current
technical values into `VinFastModelSpecs` for older app versions.

## Deploy Firebase policy

From `web` after authenticating Firebase CLI:

```powershell
firebase deploy --only firestore:rules,firestore:indexes,storage
```

The dashboard route is `/catalog`. Catalog APIs require a Firebase ID token and
the existing admin claim/access policy; mobile vehicle creation accepts only a
published `catalogId`, and the backend derives all technical defaults.

## Release checklist

- Run `python -m pytest` from `web`.
- Run `npm run lint` and `npm run build` from `web/dashboard`.
- Run `flutter analyze` and `flutter test` from `app`.
- Dry-run the migration and resolve ambiguous/unmatched vehicles.
- Deploy Firestore indexes/rules and Storage rules before enabling the UI.
- Start one catalog research worker in production.
- Publish a test draft and confirm the app refreshes without changing personal
  fields on the linked vehicle.
