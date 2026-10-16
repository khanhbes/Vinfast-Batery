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
CATALOG_RESEARCH_POLL_SECONDS=60
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

## Vehicle photos and showroom (Task 122)

Official photos are uploaded by an administrator from the dashboard
(`/catalog` → editor → "Phòng trưng bày xe"). Every upload requires the
rights confirmation and stores a credit, source URL and licence note.

**Storage.** `web/vehicle_media.py` writes to Azure Blob when
`VEHICLE_MEDIA_ACCOUNT` is set (account `vfmediaf1c11a09`, container
`vehicle-media`, public read by URL only, no listing, shared-key access
disabled). The API writes with its user-assigned managed identity
(`AZURE_CLIENT_ID`, role *Storage Blob Data Contributor* on the container).
Infrastructure: `deploy/azure/vehicle-media.bicep`, script
`deploy/azure/16-vehicle-media.ps1` (compile + what-if by default, `-Apply`,
`-ConfigureApi`). Without the variable the legacy Firebase Storage backend is
used (the Spark project has no bucket, so uploads would fail).

**Processing.** Images (≤ 10 MB, ≤ 8000 px, worked at ≤ 2560 px) keep their
alpha channel. A light studio backdrop is removed automatically unless
`removeBackground=false`; photos whose border is not mostly a light backdrop
(median colour ≥ 200 per channel) are left unchanged. The algorithm
(`vehicle_media.remove_light_background`, scipy `ndimage`; numpy-only fallback):
1. estimates the backdrop colour from the border median, then clears pixels
   within a tolerance of *that* colour and connected to the border — pale
   bodies (mint, pearl) a few levels darker than the backdrop are kept;
2. clears the floor shadow: the backdrop darkened with the same tint, smooth,
   only in the lowest 20 % of the subject, plus the grey transition rim;
3. applies a short soft matte on the subject side and unmixes the backdrop
   tint, so no light halo shows on the app's dark stage.
Enclosed areas (e.g. floor seen between wheel spokes, white logos) are kept on
purpose: they share the grey of silver discs and forks. For a perfect cut-out
upload a transparent PNG with background removal off. Single images are trimmed to the
subject on a transparent 16:10 canvas; 360° angle frames keep one shared
framing so the spin does not jitter. Each image is stored as WebP 320 / 768 /
1280 px under `vehicle-catalog/<catalogId>/<kind>/[<colorId>/]<sha256[:12]>/`
with `Cache-Control: immutable`.

**Schema.** `media.showroom = { defaultColorId, colors: [{ id, name,
swatchHex, angles: [asset…] }] }` — at most 8 colours and 36 angles per
colour; assets carry `thumbnailUrl/mediumUrl/heroUrl` (HTTPS only), `checksum`,
`credit`, `sourceUrl`, `licenseNote`, `backgroundRemoved`. The primary image
(`media.thumbnailUrl/heroUrl`) is the first angle of the default colour, else
the legacy 2D photo, else the 3D render.

**API.** `POST /api/admin/vehicle-catalog/<id>/media` with `kind=angle` plus
`colorId` (lowercase, digits, dashes), `colorName`, `swatchHex`, optional
`angleIndex`; `PUT /api/admin/vehicle-catalog/<id>/showroom` renames/recolours,
reorders angles by checksum (never accepts new URLs), deletes and sets the
default colour. Publishing copies `media` into the public record and into each
linked vehicle's `catalogSnapshot`.

**App.** `VehicleShowroomData` (`app/lib/data/models/vehicle_showroom.dart`)
parses the showroom (or the legacy single image). `VehicleShowroomView` shows
a 2.5D stage (tilt, reflection, pinch zoom) and enables the 360° drag when a
colour has ≥ 12 angles, after pre-caching frames (disk cache via
`cached_network_image`). Entry points: Overview hero, vehicle spec detail,
garage and survey thumbnails.
