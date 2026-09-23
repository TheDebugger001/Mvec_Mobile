# MVEC Admin Mobile (`Mvec_Mobile`)

Flutter super-admin console for the MVEC marketplace. Port of the web
`Mvec_frontend` admin, talking to `Mvec_backend`.

**Stack:** Flutter 3.29 / Dart 3.7 · Riverpod (state) · go_router (routing) ·
Dio (HTTP) · flutter_secure_storage (session)

---

## Quickstart

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:4000/api
```

Sign in with the seeded super-admin (from the backend `.env`):
`admin@gmail.com` / `admin!`. The screen shows a **Dev quick-login** button in
development builds.

> The backend must be running first. See `Mvec_backend/README.md` — the short
> version is `npm install && npm run setup && npm run dev`.

### Useful commands

| Command                                     | Purpose                         |
| ------------------------------------------- | ------------------------------- |
| `flutter run`                               | run on connected device/emulator|
| `flutter run --dart-define=API_BASE_URL=…`  | point at a different backend     |
| `flutter analyze`                           | lint — must be clean            |
| `flutter test`                              | run widget tests                 |
| `flutter build apk --debug`                 | Android build                    |

Environment overrides (all optional, via `--dart-define`):

- `API_BASE_URL` (default `http://localhost:4000/api`)
- `ADMIN_EMAIL` / `ADMIN_PASSWORD` (dev quick-login only)

> Emulator note: `localhost` is the device itself — use
> `http://10.0.2.2:4000/api` on the Android emulator or your machine's LAN IP
> on a real device.

---

## Project structure

```
lib/
  main.dart            app entry — MvecAdminApp
  core/                theme, utils, api_client, api_config, nav, router
  models/              plain data classes (user, party, catalog)
  services/            API wrappers (admin_service, platform_service)
  providers/           Riverpod providers (auth, admin)
  widgets/             shared UI kit (smart_table, charts, common, mv_icon)
  screens/
    layout/            admin_shell (drawer + topbar shell)
    auth/              login
    <module>/          one folder per admin page (one file each)
test/                  widget tests
```

**Every admin page is its own file under `lib/screens/<module>/`.** The 36
modules are wired in `lib/core/router.dart` (routes) and
`lib/core/nav_items.dart` (drawer groups).

---

## Team conventions (avoid merge conflicts)

1. **One module = one file.** Edit only the screen you own
   (e.g. `screens/orders/orders_screen.dart`). These almost never collide.

2. **Shared files are the only merge hotspots** — touch them only when adding a
   whole new page, and keep the diff to a couple of lines:
   - `core/router.dart` — add one import + one `GoRoute`
   - `core/nav_items.dart` — add one `NavItem`
   - `pubspec.yaml` — coordinate before adding deps

3. **Reuse the shared kit, don't rebuild it.** Widgets in `lib/widgets/`
   (`PageHead`, `MetricCard`, `DataCard`, `SmartTable`, `StatusChip`,
   `LoadingState`, …) already match the design system. If a page needs a new
   shared widget, add it to `widgets/` in your PR so others can reuse it.

4. **Server data flows through providers.** Add/extend a `FutureProvider` in
   `providers/admin_providers.dart` (or a module service) rather than calling
   Dio from inside a widget.

5. **Branching:** branch off `main` (`feat/<module>`), keep PRs small, rebase
   before pushing. Existing shared branches: `feature/home-screen`, `paccy`.

6. **Must pass before pushing:**
   ```bash
   flutter analyze && flutter test
   ```

---

## Backend endpoints used

Data comes from `Mvec_backend` (Express, base `/api`). Admin routes
(`/api/admin/*`) require a `super_admin` JWT from `POST /api/auth/login`.
`Mvec_backend/swagger.yaml` is outdated — the files in
`Mvec_backend/src/routes/` are the source of truth.