# Repository Guidelines

## Project Overview

Mastodon is a **free, open-source social network server** based on [ActivityPub](https://www.w3.org/TR/activitypub/). It is a Ruby on Rails monolith with a React/Redux SPA frontend, a standalone Node.js streaming server, PostgreSQL, Redis, and optional Elasticsearch.

- **Version**: 4.5.x (see `lib/mastodon/version.rb`)
- **License**: AGPL-3.0-or-later
- **Upstream**: https://github.com/mastodon/mastodon

## Architecture & Data Flow

```
                    ┌──────────────────────────────┐
                    │      Rails Monolith (Puma)    │
                    │  ┌──────────┐ ┌────────────┐ │
  Client ──HTTP/WS──▶│  │Controllers│ │  Services  │ │──▶ PostgreSQL
                    │  └──────────┘ └─────┬──────┘ │    (primary DB)
                    │        │            │        │
                    │        ▼            ▼        │
                    │  ┌──────────┐ ┌────────────┐ │
                    │  │  Models   │ │  Workers   │ │──▶ Sidekiq ──▶ Redis
                    │  └──────────┘ └─────┬──────┘ │
                    └─────────────────────┼────────┘
                                          │ Redis pub/sub
                    ┌─────────────────────▼────────┐
                    │   Streaming Server (Node.js)  │
                    │   Express + ws + ioredis      │
                    │   Port 4000 / Unix socket     │
                    └──────────────┬───────────────┘
                                   │ WebSocket / SSE
                                   ▼
                                 Client
```

**Data flow for a new status**:

1. Client POSTs to REST API → `StatusesController#create`
2. Controller calls `PostStatusService.new.call(account, text, ...)`
3. Service creates `Status` record, processes media, creates mentions
4. `FanOutOnWriteService` delivers to home feeds (Redis) and publishes to Redis channels
5. Sidekiq `ActivityPub::DeliveryWorker` fans out to remote servers via HTTP
6. Streaming server picks up Redis pub/sub, pushes to connected WebSocket/SSE clients

**Key subsystems**:

- **Federation**: `ActivityPub::ProcessAccountService`, `ActivityPub::DeliveryWorker`, `app/lib/activitypub/` — full ActivityPub server-to-server protocol
- **Streaming**: `streaming/` — standalone Node.js (ESM) server; Express + `ws` for WebSocket + SSE; direct PostgreSQL for OAuth token validation; `ioredis` pub/sub
- **Search**: Chewy (Elasticsearch adapter); 5 indices in `app/chewy/`; optional but used in production
- **CLI**: `tootctl` — Thor-based CLI at `lib/mastodon/cli/`; 15 subcommands for admin operations

## Key Directories

| Directory          | Purpose                                                                                                                              |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `app/models/`      | ActiveRecord models (~130 files). Heavy use of concerns. `app/models/concerns/` has shared mixins (Remotable, Paginable, Cacheable). |
| `app/services/`    | Service objects (~70 files). All inherit from `BaseService`. `app/services/activitypub/` for federation.                             |
| `app/controllers/` | Rails controllers: `api/v1/`, `api/v2/`, `admin/`, `auth/`, `activitypub/`, `settings/`, `oauth/`                                    |
| `app/workers/`     | Sidekiq workers (~70 files): `activitypub/`, `scheduler/`, `fasp/`, `web/`, `webhooks/`                                              |
| `app/serializers/` | ActiveModel::Serializer classes: `rest/` (REST API), `activitypub/` (JSON-LD), `web/` (push)                                         |
| `app/policies/`    | Custom policy objects (NOT Pundit gem) — predicate methods returning booleans                                                        |
| `app/javascript/`  | React 18 + Redux Toolkit SPA. `mastodon/` core app, `entrypoints/` Vite inputs, `styles/` SCSS                                       |
| `app/views/`       | Server-rendered ERB/Haml views (auth, admin, mailers, settings pages)                                                                |
| `app/chewy/`       | Elasticsearch index definitions (5 indices)                                                                                          |
| `lib/mastodon/`    | Core domain: Snowflake IDs, migration helpers, Redis config, Sidekiq middleware, CLI                                                 |
| `lib/paperclip/`   | Custom Paperclip processors (transcoding, blurhash, color extraction, thumbnails)                                                    |
| `lib/tasks/`       | Rake tasks: `mastodon:setup`, `db:encryption:init`, branding/emoji generation                                                        |
| `config/`          | Rails config, routes (split: `routes/api.rb`, `routes/admin.rb`, `routes/settings.rb`), initializers                                 |
| `spec/`            | RSpec test suite mirroring `app/` structure (~500+ spec files)                                                                       |
| `streaming/`       | Standalone Node.js streaming server (Express + ws + ioredis)                                                                         |
| `db/`              | Migrations (482 total) in `db/migrate/` and `db/post_migrate/`, schema at `db/schema.rb`                                             |

## Storage & Paperclip Subsystem

Mastodon uses **kt-paperclip** for all file attachments. Active Storage is **explicitly disabled** (`config/application.rb:8` comments out `require 'active_storage/engine'`).

### Storage Backends

Four storage backends, selected via environment variables in `config/initializers/paperclip.rb`:

| Backend                        | Gate                 | Gem                         | Adapter                   |
| ------------------------------ | -------------------- | --------------------------- | ------------------------- |
| **AWS S3** (and S3-compatible) | `S3_ENABLED=true`    | `aws-sdk-s3 ~> 1.123`       | `Paperclip::Storage::S3`  |
| **OpenStack Swift**            | `SWIFT_ENABLED=true` | `fog-openstack ~> 1.0`      | `Paperclip::Storage::Fog` |
| **Azure Blob Storage**         | `AZURE_ENABLED=true` | `jd-paperclip-azure ~> 3.0` | `:azure`                  |
| **Local filesystem**           | _(fallback)_         | _(none)_                    | `:filesystem`             |

**Default**: `storage: :fog` (overridden by env gates). The filesystem fallback uses `PAPERCLIP_ROOT_PATH` (default: `:rails_root/public/system`) and `PAPERCLIP_ROOT_URL` (default: `/system`).

#### Key S3 Env Vars

| Var                                    | Default       | Purpose                                                                                     |
| -------------------------------------- | ------------- | ------------------------------------------------------------------------------------------- |
| `S3_ENABLED`                           | —             | **Required gate** (`== 'true'`)                                                             |
| `S3_BUCKET`                            | —             | **Required** bucket name                                                                    |
| `AWS_ACCESS_KEY_ID`                    | —             | **Required** access key                                                                     |
| `AWS_SECRET_ACCESS_KEY`                | —             | **Required** secret key                                                                     |
| `S3_REGION`                            | `us-east-1`   | AWS region                                                                                  |
| `S3_ENDPOINT`                          | —             | Custom endpoint (MinIO, DigitalOcean Spaces) — triggers `force_path_style` + `:s3_path_url` |
| `S3_ALIAS_HOST` / `S3_CLOUDFRONT_HOST` | —             | CDN/custom domain (switches to `:s3_alias_url`)                                             |
| `S3_PERMISSION`                        | `public-read` | ACL; empty string = no ACL                                                                  |
| `S3_STORAGE_CLASS`                     | —             | e.g. `STANDARD_IA`, `INTELLIGENT_TIERING`                                                   |
| `S3_MULTIPART_THRESHOLD`               | 15 MB         | Multipart upload threshold                                                                  |
| `S3_BATCH_DELETE_LIMIT`                | 1000          | Max per-batch S3 delete (in `app/lib/attachment_batch.rb`)                                  |
| `S3_BATCH_DELETE_RETRY`                | 3             | Retry count for batch deletes                                                               |

**S3 compatibility workaround**: `Paperclip::Storage::S3Extensions` monkey-patches `copy_to_local_file` with `single_request` mode and disabled checksum mode — gated by `S3_FORCE_SINGLE_REQUEST` and `S3_ENABLE_CHECKSUM_MODE` env vars. This is needed for some non-AWS S3 providers (#16822, #26394).

#### Swift Connection Caching

`config/initializers/fog_connection_cache.rb` provides thread-local Fog connection caching, keyed on credential hash. Only loaded when `SWIFT_ENABLED=true`.

### Paperclip Path Interpolations

Default path pattern (`config/initializers/paperclip.rb:6`):

```
:prefix_url:class/:attachment/:id_partition/:style/:filename
```

Custom interpolations:

- **`:filename`** — preserves original filename for `:original` style; builds from basename + extension for variants
- **`:prefix_path`** / **`:prefix_url`** — inserts `cache/` prefix when `storage_schema_version >= 1` AND the record is remote (non-local). This separates cached remote media from local uploads on disk.

### Custom Paperclip Processors (`lib/paperclip/`)

| File                                      | Class                              | Purpose                                                                                                                                                                                               |
| ----------------------------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `vips_lazy_thumbnail.rb`                  | `VipsLazyThumbnail`                | **Primary image processor** (libvips). GIF animation preservation, 60fps/3000-frame limits, 32-color palette, metadata stripping for remote files, geometry/pixel-based resizing                      |
| `lazy_thumbnail.rb`                       | `LazyThumbnail`                    | **Fallback image processor** (ImageMagick). Only loaded when `MASTODON_USE_LIBVIPS=false`. Geometry, pixel, format, and metadata-stripping logic                                                      |
| `transcoder.rb`                           | `Transcoder`                       | Video/audio transcoding via ffmpeg. H.264+AAC encoding, passthrough optimization (skips re-encode for compatible codecs), VFR detection, GIFV classification                                          |
| `gif_transcoder.rb`                       | `GifTranscoder`                    | Converts animated GIFs to MP4. Uses `GifReader` (custom Ruby GIF parser) to detect animation before transcoding                                                                                       |
| `blurhash_transcoder.rb`                  | `BlurhashTranscoder`               | Generates Blurhash placeholders. Uses libvips `thumbnail` (when enabled) or ImageMagick `convert` to extract pixel data                                                                               |
| `color_extractor.rb`                      | `ColorExtractor`                   | Extracts dominant/contrasting/accent colors from images for UI theming. Uses libvips or ImageMagick histogram analysis with W3C contrast calculations                                                 |
| `image_extractor.rb`                      | `ImageExtractor`                   | Extracts a preview PNG from audio files using ffmpeg (for `:original` style only)                                                                                                                     |
| `type_corrector.rb`                       | `TypeCorrector`                    | Fixes file extension and content type mismatch on `:original` style (e.g., ensures `.mp4` extension for transcoded videos)                                                                            |
| `response_with_limit_adapter.rb`          | `ResponseWithLimitAdapter`         | IO adapter for remote file downloads with size limits. Used by `Remotable` concern. Streams chunks, enforces byte limit, truncates long filenames                                                     |
| `attachment_extensions.rb`                | `AttachmentExtensions`             | Monkey-patches `Paperclip::Attachment` with: storage schema versioning, delayed processing (skips `:original` style when `delay_processing?`), circuit breaker via Stoplight for object storage saves |
| `url_generator_extensions.rb`             | `UrlGeneratorExtensions`           | Adds `for_as_default(style_name)` for default/placeholder URL generation                                                                                                                              |
| `media_type_spoof_detector_extensions.rb` | `MediaTypeSpoofDetectorExtensions` | Extends content type detection with Marcel for MP3 (`audio/mpeg`) and AVIF files that `file` command misreports as `application/octet-stream`                                                         |

### Image Processing: libvips vs ImageMagick

- **Gate**: `MASTODON_USE_LIBVIPS` env var — defaults to `true`; set to `'false'` to disable
- **When libvips is enabled**: uses `VipsLazyThumbnail`; higher upload limits (8MB vs 2MB for avatars/headers); blocks all foreign loaders except JPEG, PNG, WebP, HEIF, NSGIF
- **When disabled**: falls back to `LazyThumbnail` (ImageMagick); ImageMagick security policy loaded from `config/imagemagick/`
- **Vips security** (`config/initializers/vips.rb`): `VIPS_BLOCK_UNTRUSTED=true`, blocks all `VipsForeign` operations, then selectively unblocks JPEG/PNG/WebP/HEIF/GIF loaders and PNG/JPEG/WebP savers
- **Vips version requirement**: >= 8.13 (aborts on boot otherwise)

### Models Using Paperclip Attachments

All attachment models `include Attachmentable` which hooks validation callbacks for dimension checking, content type correction, filename obfuscation, and extension normalization.

#### `MediaAttachment` — Most Complex

Two attachments: **`file`** (primary media) and **`thumbnail`** (preview image for video/audio).

`file` has **dynamic styles and processors** based on content type:

| Content Type                             | Styles                   | Processors                                                 | Result                             |
| ---------------------------------------- | ------------------------ | ---------------------------------------------------------- | ---------------------------------- |
| `image/gif`                              | `VIDEO_CONVERTED_STYLES` | `[:gif_transcoder, :blurhash_transcoder]`                  | Animated GIF → MP4 + blurhash      |
| `video/webm`, `video/quicktime`          | `VIDEO_CONVERTED_STYLES` | `[:transcoder, :blurhash_transcoder, :type_corrector]`     | WebM/MOV → MP4 (H.264+AAC)         |
| `image/heic`, `image/heif`, `image/avif` | `IMAGE_CONVERTED_STYLES` | `[:lazy_thumbnail, :blurhash_transcoder, :type_corrector]` | HEIC/AVIF → JPEG                   |
| `image/*` (standard)                     | `IMAGE_STYLES`           | `[:lazy_thumbnail, :blurhash_transcoder, :type_corrector]` | Original + small (640px) thumbnail |
| `video/mp4`, `video/ogg`                 | `VIDEO_STYLES`           | `[:transcoder, :blurhash_transcoder, :type_corrector]`     | MP4 original + small PNG thumbnail |
| `audio/*`                                | `AUDIO_STYLES`           | `[:image_extractor, :transcoder, :type_corrector]`         | MP3 original                       |

`thumbnail` always uses `[:lazy_thumbnail, :blurhash_transcoder, :color_extractor]` with `THUMBNAIL_STYLES`.

**Processing pipeline**: Upload → validation (dimensions: 7680x4320 max images, 3840x2160 max video; file size; content type) → `delay_processing?` check → if large media (video/GIF/audio), enqueue `PostProcessMediaWorker` with state `queued → in_progress → complete/failed`; else process inline → `set_meta` (dimensions, frame rate, duration) via `after_post_process`.

**Video-specific limits**: `MAX_VIDEO_MATRIX_LIMIT = 8_294_400` (3840x2160), `MAX_VIDEO_FRAME_RATE = 120`, `MAX_VIDEO_FRAMES = 36_000` (≈5min at 120fps), `VIDEO_LIMIT = 99.megabytes`.

**Passthrough optimization**: `VIDEO_PASSTHROUGH_OPTIONS` skips re-encoding when the source is already H.264 + AAC + yuv420p — uses `-c:v copy -c:a copy` instead.

#### Other Attachment Models

| Model                 | Attachment | Processors                                                 | Styles                                                                                   | Limits                        |
| --------------------- | ---------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------- |
| `Account`             | `avatar`   | `[:lazy_thumbnail]`                                        | 400x400 original; static PNG for GIFs                                                    | 8MB/2MB (vips/IM)             |
| `Account`             | `header`   | `[:lazy_thumbnail]`                                        | 1500x500 (pixel-limited); static PNG for GIFs                                            | 8MB/2MB (vips/IM)             |
| `CustomEmoji`         | `image`    | `[:lazy_thumbnail]`                                        | Static PNG style for animated GIFs                                                       | 256KB                         |
| `PreviewCard`         | `image`    | `[:lazy_thumbnail, :blurhash_transcoder]`                  | 500px-wide original; small (400px) thumbnail                                             | 8MB/2MB (vips/IM)             |
| `SiteUpload`          | `file`     | `[:lazy_thumbnail, :blurhash_transcoder, :type_corrector]` | Many fixed-size styles (favicon: 16-48px; app icon: 36-1024px; thumbnail: 1200x630 + 2x) | —                             |
| `Backup`              | `dump`     | _(none)_                                                   | _(none)_                                                                                 | Application content type only |
| `PreviewCardProvider` | `icon`     | _(none)_                                                   | Static PNG style                                                                         | 1MB                           |

### Remote Attachment Fetching (`Remotable` Concern)

`app/models/concerns/remotable.rb` provides a DSL for fetching attachments from remote URLs:

```ruby
remotable_attachment :avatar, LIMIT, suppress_errors: true, download_on_assign: true
```

- Downloads via `Request.new(:get, url).perform` → wraps response in `ResponseWithLimit` → processed by `ResponseWithLimitAdapter` (streaming download with byte limit)
- Options: `suppress_errors` (default `true` — swallows fetch failures), `download_on_assign` (default `true` — auto-downloads when remote URL is set), `attribute_name` (custom column name)
- Generated methods: `download_<name>!`, `<name>_remote_url=`, `reset_<name>!`
- Error handling distinguishes transient network errors (retry) from permanent errors (skip)
- Used by: `Account` (avatar, header), `MediaAttachment` (file, thumbnail), `CustomEmoji` (image), `PreviewCard` (image), `PreviewCardProvider` (icon)

### Storage Schema Versioning

- `CURRENT_STORAGE_SCHEMA_VERSION = 1` (defined in `lib/mastodon/cli/upgrade.rb`)
- Each attachment record stores `storage_schema_version` (0 or 1)
- `AttachmentExtensions#assign_attributes` auto-sets to 1 on new uploads
- **`cache/` prefix**: For version ≥1 on remote (non-local) records, the `:prefix_path`/`:prefix_url` interpolators insert `cache/` into the storage path — separates cached remote media from local uploads
- **Upgrade tool**: `tootctl upgrade storage-schema` migrates existing files to the new path layout; supports S3 (copy+delete objects) and filesystem (`FileUtils.mv`); Fog and Azure are not supported for this operation

### Permission Management

`UpdateMediaAttachmentsPermissionsService` toggles between public/private ACLs on media:

- **S3**: `attachment.s3_object(style).acl.put(acl: ...)` — sets `public-read` or `private`
- **Filesystem**: `FileUtils.chmod(mask & ~File.umask, path)` — `0666` for public, `0600` for private
- **Fog/Azure**: not supported (returns early)
- After permission change, `CacheBusterWorker` purges CDN cache for affected URLs

**Callers**: `SuspendAccountService` (privatizes), `UnsuspendAccountService` (publishes), `RemoveStatusService#remove_media` (privatizes on soft-delete instead of destroying)

### Media Cleanup & Lifecycle

#### Batch File Deletion (`AttachmentBatch`)

`app/lib/attachment_batch.rb` handles bulk deletion of Paperclip files:

- `delete` — removes DB records without touching files (for orphan cleanup)
- `clear` — removes files from storage (S3 batch delete API via `delete_objects`, filesystem `FileUtils.rm`) then nullifies Paperclip columns
- Configurable: `S3_BATCH_DELETE_LIMIT` (default 1000), `S3_BATCH_DELETE_RETRY` (default 3)

#### Vacuum System

`Scheduler::VacuumScheduler` (daily Sidekiq job) runs these vacuum operations:

| Vacuum Class                     | What It Cleans                                                                    |
| -------------------------------- | --------------------------------------------------------------------------------- |
| `Vacuum::MediaAttachmentsVacuum` | Orphaned unattached media (>1 day old), cached remote media past retention period |
| `Vacuum::PreviewCardsVacuum`     | Cached preview card images past retention period                                  |
| `Vacuum::BackupsVacuum`          | Expired user backup archives                                                      |
| `Vacuum::StatusesVacuum`         | Statuses past content retention period                                            |
| `Vacuum::AccessTokensVacuum`     | Expired/revoked OAuth tokens and grants                                           |
| `Vacuum::FeedsVacuum`            | Inactive home and list timeline feeds (Redis)                                     |
| `Vacuum::ImportsVacuum`          | Old/unconfirmed imports                                                           |

Retention periods come from admin settings (`content_retention_policy`).

#### CLI Tools (`tootctl media`)

| Command                        | Purpose                                                                                              |
| ------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `tootctl media remove`         | Remove cached remote media (with `--prune_profiles` for avatars/headers, `--days` for age threshold) |
| `tootctl media remove-orphans` | Scan storage for files not belonging to any record and delete them                                   |
| `tootctl media refresh`        | Re-download remote media (per account, domain, or status)                                            |
| `tootctl media usage`          | Calculate disk space used by media                                                                   |
| `tootctl media lookup URL`     | Find which record a media URL belongs to                                                             |

#### Cache Busting

- `MediaAttachment#prepare_cache_bust!` (before_destroy) records all attachment style URLs
- `MediaAttachment#bust_cache!` (after_destroy) enqueues `CacheBusterWorker` for each URL
- `UpdateMediaAttachmentsPermissionsService` also busts cache after ACL changes
- Configurable via `config/cache_buster.yml`

### Circuit Breaker on Object Storage

`AttachmentExtensions#save` wraps `super` in a Stoplight circuit breaker (`'object-storage'`):

- **Cool-off**: 30 seconds
- **Threshold**: 10 failures
- **Tracked errors**: `Seahorse::Client::NetworkingError`
- This prevents object storage outages from cascading into application-wide failures — saves fail fast instead of blocking request threads

### Test Conventions for Paperclip

- Paperclip post-processing is **stubbed by default** in tests
- Use `:attachment_processing` RSpec metadata tag to enable real processing
- A stubbed `Seahorse::Client::NetworkingError` constant is defined in `paperclip.rb` initializer for environments where `aws-sdk-s3` is not loaded
- A stubbed `Vips::Error` constant is defined in `vips.rb` initializer for environments without libvips

## Development Commands

### Setup

```bash
bin/setup          # Full setup: bundle install, yarn install, db:prepare, restart
```

### Running the app

```bash
bin/dev             # Start all services (web, sidekiq, streaming, vite) via Procfile.dev
# Individually:
bundle exec puma -C config/puma.rb     # Rails on port 3000
bundle exec sidekiq                     # Background jobs
yarn workspace @mastodon/streaming start # Streaming on port 4000
yarn dev                                # Vite dev server (HMR)
```

### Testing

```bash
bin/rspec                                    # Full suite (excludes :js, :search, :streaming tags)
bin/rspec spec/models/account_spec.rb        # Single file
bin/rspec spec/models/account_spec.rb:42     # Single example
bin/rspec --tag js                           # Include browser tests (Playwright)
flatware rspec                               # Parallel across all CPUs
```

### Linting & Static Analysis

```bash
bundle exec rubocop                # Ruby linting
yarn lint:js                       # ESLint (JavaScript/TypeScript)
yarn lint:css                      # Stylelint (CSS/SCSS)
bundle exec haml-lint              # HAML linting
yarn typecheck                     # TypeScript type checking (tsc --noEmit)
bundle exec brakeman               # Security analysis
bundle exec bundler-audit          # Dependency vulnerability scan
yarn format                        # Prettier auto-format
yarn format:check                  # Prettier check-only
```

### JavaScript Build

```bash
yarn dev                           # Vite dev server
yarn build:development             # Development build
yarn build:production              # Production build
```

## Code Conventions & Common Patterns

### Service Objects (Primary Business Logic Pattern)

- Every service inherits from `BaseService` (`app/services/base_service.rb`)
- Single entry point: `def call(...)` — invoked as `MyService.new.call(args)`
- Stateless; return values vary (created record, boolean, or void)
- Key examples: `PostStatusService`, `NotifyService`, `FanOutOnWriteService`, `ResolveAccountService`

### Model Concerns

- Models decomposed via concerns in `app/models/concerns/`
- `Remotable` DSL for remote attachment fetching: `remotable_attachment :avatar, LIMIT`
- `Account::Interactions` for follow/block/mute relationship methods
- `Status::Visibility` for visibility enum helpers, `Status::ThreadingConcern` for reply threading

### Serialization

- **REST API**: `ActiveModel::Serializer` with `scope: current_user`, snake_case keys, in `app/serializers/rest/`
- **ActivityPub**: `ActivityPub::Serializer` subclass, JSON-LD `@context`, camelCase keys via `ActivityPub::Adapter`, in `app/serializers/activitypub/`
- **Web push**: Standard AMS, in `app/serializers/web/`
- **Inline rendering**: `app/lib/inline_renderer.rb` for Redis pub/sub payloads without full request cycle

### Authorization (Custom, NOT Pundit)

- `ApplicationPolicy` at `app/policies/application_policy.rb` — constructor takes `(current_account, record)`
- Predicate methods: `show?`, `destroy?`, `update?`, `reblog?`, `favourite?`
- Admin controllers include `Authorization` concern and call `authorize` in every action
- `StatusPolicy#show?` is the most complex — visibility-based access control

### Workers (Sidekiq)

- All workers `include Sidekiq::Worker` directly (no base class except `Fasp::BaseWorker`)
- `ExponentialBackoff` concern for retry with jitter
- `ActivityPub::DeliveryWorker` uses `stoplight` circuit breaker for failing inboxes
- Schedulers in `app/workers/scheduler/` for periodic tasks

### Snowflake IDs

- Custom 48-bit millisecond-timestamp IDs via `Mastodon::Snowflake` (`lib/mastodon/snowflake.rb`)
- Defined via `timestamp_id('table_name')` in migrations and schema
- Table-name-hashed sequence data for privacy

### Frontend Patterns

- **React 18** functional components with hooks (`.tsx`), legacy class-based `PureComponent` (`.jsx`)
- **Redux Toolkit 2.x** with `redux-immutable` — state tree is `Immutable.Map`/`Record`
- **Active migration** from Immutable.js patterns to plain JS objects + typed RTK
- **Selectors**: Factory functions (`makeGetStatus`, `makeGetNotification`) returning memoized per-instance selectors
- **API calls**: Axios client at `app/javascript/mastodon/api.ts`; per-resource modules in `api/` directory
- **i18n**: `react-intl` with locale JSON files in `app/javascript/mastodon/locales/`
- **Styling**: SCSS partials in `app/javascript/styles/`; `application.scss` entry; theme support (light, contrast)
- **Entry points**: `app/javascript/entrypoints/` — `application.ts`, `admin.tsx`, `public.tsx`, `embed.tsx`, `share.tsx`

### Error Handling

- Custom exception hierarchy in `lib/exceptions.rb` — 15 error classes
- `Mastodon::SidekiqMiddleware` wraps jobs with socket cleanup on error
- `stoplight` gem used for circuit breaking on ActivityPub delivery
- `strong_migrations` gem enforces safe migration practices

### Form Objects

- `app/models/form/` contains non-AR validation objects: `AccountBatch`, `Import`, `AdminSettings`, `DeleteConfirmation`

## Important Files

| File                                         | Role                                                                                                   |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `config/application.rb`                      | Rails application configuration                                                                        |
| `config/routes.rb`                           | Master routes; delegates to `config/routes/api.rb`, `admin.rb`, `settings.rb`, `web_app.rb`, `fasp.rb` |
| `config/settings.yml`                        | Application settings schema                                                                            |
| `config/sidekiq.yml`                         | Sidekiq queues and concurrency                                                                         |
| `config/database.yml`                        | PostgreSQL config (primary/replica in all environments)                                                |
| `config/puma.rb`                             | Puma web server configuration                                                                          |
| `db/schema.rb`                               | Database schema (80 tables, ActiveRecord 8.0)                                                          |
| `app/models/account.rb`                      | Central model (~500 lines, extensive concerns)                                                         |
| `app/models/status.rb`                       | Core content model (~500 lines)                                                                        |
| `app/services/post_status_service.rb`        | Status creation pipeline                                                                               |
| `app/services/notify_service.rb`             | Notification dispatch logic                                                                            |
| `app/services/fan_out_on_write_service.rb`   | Feed fan-out and streaming broadcast                                                                   |
| `app/workers/activitypub/delivery_worker.rb` | Federation delivery with circuit breaker                                                               |
| `app/policies/application_policy.rb`         | Custom policy base class                                                                               |
| `app/chewy/accounts_index.rb`                | Account search index (edge-ngram)                                                                      |
| `lib/mastodon/snowflake.rb`                  | ID generation                                                                                          |
| `lib/mastodon/migration_helpers.rb`          | Zero-downtime migration tools (~750 lines)                                                             |
| `lib/mastodon/cli/main.rb`                   | `tootctl` CLI entry point                                                                              |
| `streaming/index.js`                         | Streaming server entry point                                                                           |
| `vite.config.mts`                            | Vite build configuration                                                                               |
| `app/javascript/mastodon/store/`             | Redux store configuration                                                                              |
| `app/javascript/mastodon/api.ts`             | Base Axios API client                                                                                  |

## Runtime / Tooling Preferences

| Aspect                      | Value                                                                                                        |
| --------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Ruby version                | 3.4.7 (`.ruby-version`; constrains `>= 3.2.0, < 3.5.0` in Gemfile)                                           |
| Node version                | 24.10 (`.nvmrc`; requires `>=20` in `package.json`)                                                          |
| Package manager             | **Yarn 4.10.3** (Yarn Berry v4) — do NOT use npm                                                             |
| Package workspaces          | Root `.` and `streaming/`                                                                                    |
| Rails version               | 8.0                                                                                                          |
| Database                    | PostgreSQL (adapter `pg ~> 1.5`)                                                                             |
| Background jobs             | Sidekiq (< 9) with `sidekiq-scheduler` and `sidekiq-unique-jobs`                                             |
| Frontend build              | Vite 7 via `vite_rails ~> 3.0`                                                                               |
| Asset pipeline              | Propshaft (NOT Sprockets)                                                                                    |
| CSS preprocessing           | SCSS, linted with Stylelint                                                                                  |
| HTML templating             | Haml (linted with `haml-lint`) + ERB                                                                         |
| TypeScript                  | ~5.9.0, typecheck via `tsc --noEmit`                                                                         |
| Formatter (JS/CSS/Markdown) | Prettier (single quotes, `jsxSingleQuote: true`)                                                             |
| Ruby linter                 | RuboCop with plugins: capybara, i18n, performance, rails, rspec, rspec_rails                                 |
| JS linter                   | ESLint v9 flat config with typescript-eslint, react, react-hooks, jsx-a11y, import, jsdoc, promise, formatjs |
| Pre-commit                  | Husky runs `yarn lint-staged`                                                                                |
| Docker                      | Multi-service via `docker-compose.yml` (PG 14, Redis 7, ES 7.10 OSS)                                         |
| CI                          | GitHub Actions (`.github/workflows/`)                                                                        |
| i18n                        | Rails-i18n + `i18n-tasks`; 80+ locale files in `config/locales/`                                             |

## Testing & QA

### Framework

- **RSpec 3.13** with `rspec-rails 8.0`
- **Fabrication 3.0** for test factories (NOT FactoryBot). Fabricators in `spec/fabricators/` (~85 files)
  - Each fabricator smoke-tested via `spec/fabrication/fabricators_spec.rb` (creates 2 records per fabricator, asserts validity)
- **WebMock 3.26** for HTTP stubbing (disables external network except localhost + Chewy host)
- **Playwright** (via `capybara-playwright-driver`) for browser system tests
- **DatabaseCleaner** for test database state management

### Test Organization

```
spec/
  models/         (~85 model specs + concerns)
  controllers/    (api v1/v2, admin, auth, oauth, settings, activitypub)
  services/       (~70 service specs)
  workers/        (~70 worker specs)
  lib/            (~100 unit specs)
  requests/       (~150 integration specs)
  system/         (~40 browser specs)
  policies/       (~35 policy specs)
  validators/     (~20 validator specs)
  presenters/, helpers/, mailers/, serializers/, routing/, views/, chewy/, search/
```

### Running Tests

```bash
bin/rspec                                    # Excludes :js, :search, :streaming by default
bin/rspec --tag js                           # Include Playwright browser tests
bin/rspec --tag search                       # Include Elasticsearch-dependent tests
bin/rspec --tag streaming                    # Include streaming server integration tests
flatware rspec                               # Parallel across all CPUs
```

### Test Conventions

- Sidekiq runs in **fake mode** by default; use `:inline_jobs` metadata tag for inline execution
- Paperclip post-processing stubbed by default; use `:attachment_processing` metadata for real processing
- DNS stubbed globally via `Resolv::DNS` (except system specs)
- `spec/support/` has custom helpers for: signed requests, streaming server management, WebSocket client, Capybara config, OmniAuth mocks, search data management, feature flags
- Shared examples in `spec/support/examples/` (~15 files covering concerns and API patterns)
- `simplecov` + `simplecov-lcov` for coverage; `rspec-github` for PR annotations

### Frontend Testing

- Storybook configured in `.storybook/` with `@storybook/addon-vitest` for visual regression
- Chromatic for visual regression testing
- Test utilities in `app/javascript/testing/`: `factories.ts`, `rendering.tsx`, MSW mock handlers in `api.ts`
