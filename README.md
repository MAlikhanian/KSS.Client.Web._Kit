# _Kit — the chrome every domain app copies from

**Not a git repository. Not a dependency. Not imported by anything.**

A domain project is fully standalone: it owns every file it needs and builds with
this folder deleted from the disk. `_Kit` exists for one reason — so the ~1,300
chrome files that all 13 apps share do not have to be maintained thirteen times
by hand.

Think of it the way `Contract\Sample\` works for documents: a read-only template
you copy from, never edit in place.

## Usage

```powershell
.\sync-kit.ps1 -Project Person          # scaffold or refresh one project
.\sync-kit.ps1 -Project Person,Company  # several
.\sync-kit.ps1 -All                     # every domain
.\sync-kit.ps1 -All -WhatIf             # show what would change, touch nothing
```

## What is in `template\`

| Path | What |
|---|---|
| `components\ui\` | the 80 primitives |
| `components\common\` | container, person-search, screen-loader, captcha, … |
| `app\components\layouts\demo1\` | sidebar, header, toolbar, breadcrumb |
| `app\components\partials\` | topbar menus, dialogs, mega-menu |
| `providers\` | settings, theme, i18n, auth, query, tooltips |
| `css\` | `styles.css`, `config.reui.css`, `demos\demo1.css` |
| `lib\` `hooks\` `config\` `types\` | utilities |
| `public\fonts\` `public\media\` | fonts and images |
| `*.tmpl` | rendered per domain — see below |

Nothing in here knows what a Person or a Company is. It is the shell of an app.

## Templates

Files ending `.tmpl` are rendered rather than copied; the suffix is dropped and
three tokens are substituted from the table in `sync-kit.ps1`:

| Token | Example |
|---|---|
| `__DOMAIN__` | `person` — must equal the `ZONES` key and the `basePath` |
| `__DOMAIN_TITLE__` | `Persons` |
| `__DEVPORT__` | `3010` |

| Template | Becomes |
|---|---|
| `package.json.tmpl` | `package.json` — **no Prisma** (54 deps, not 57) |
| `next.config.mjs.tmpl` | `next.config.mjs` — `basePath: '/<domain>'` |
| `Dockerfile.tmpl` | `Dockerfile` — Prisma stages removed |
| `app\layout.tsx.tmpl` | `app\layout.tsx` — root + protected layouts merged |
| `app\app-shell.tsx.tmpl` | `app\app-shell.tsx` — session guard + chrome |

## Deliberate divergence: `.kitignore`

A domain is allowed to differ. List the paths it owns and a sync will never
overwrite them:

```
# Spm\.kitignore
css/demos/demo1.css        # SPM uses a wider sidebar for the ops console
app/components/layouts/demo1/components/header.tsx
```

`-Force` overrides it. `app\layout.tsx` is protected automatically — if the
project already has one, the Kit version lands as `app\layout.kit.tsx` for you
to merge, rather than silently replacing a layout the domain wrote.

## Three deliberate differences from the Shell

These are not oversights; each removes a dependency a standalone app must not have.

1. **`providers\modules-provider.tsx` is a pass-through.** The Shell's version
   wraps the app in the Metronic store-client cart context. A domain app has no
   shop, and importing it drags in the store demo's context, its three sheets and
   their assets. Kept as a pass-through so a domain has one known place to mount
   its own cross-cutting providers.

2. **`header.tsx` drops the `StoreClientTopbar` branch.** It rendered only when
   `pathname.startsWith('/store-client')`, which can never match inside an app
   running under its own `basePath`. Dead code that imported a whole demo.

3. **`auth-provider.tsx` pins `SessionProvider` to `/api/auth`.** The Shell
   derives it from `NEXT_PUBLIC_BASE_PATH`; a domain app must not, or it resolves
   to `/<domain>/api/auth` and the app starts trying to own the session. The
   Shell owns `/`, and domain apps are proxied onto the same origin, so the
   Shell's endpoints sit at `/api/auth` with no prefix.

## What is NOT here, and why

`components\common\company-info\` and `components\common\person-info\` live in
the Shell's shared folder but import from `brokerages\components` and
`person\edit\components`. They are domain code wearing a shared coat. Under the
standalone model each domain that needs them takes its own copy — `Company\` and
`Members\` for `company-info`, `Members\` for `person-info`.

## The one thing to watch

`css\demos\demo1.css` holds `--sidebar-default-width: 280px` and
`--header-height: 70px`. Those values exist in all 13 apps. If one drifts, the
sidebar visibly jumps when a user crosses from `/person` to `/company` — no test
catches it, only a person's eyes. Change it here and run `-All`.

Tenant branding does not have this problem: logo, banner and colours are fetched
as data at runtime, so all apps read one source of truth regardless of their
chrome copy.
