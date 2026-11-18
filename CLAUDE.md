# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The Ikiguzi (MVEC) Flutter app: one app for buyers, sellers, suppliers, affiliates, riders and admins. It mirrors `../Mvec_frontend` and calls `../Mvec_backend` under `/api`. The stack is Riverpod, go_router and Dio (`lib/core/api_client.dart`), the same in every role.

## Commands

```bash
flutter pub get
flutter analyze
flutter test                          # all tests (fake backend, no server needed)
flutter test test/rider_test.dart     # one file
flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:4000/api
flutter build apk --release --dart-define=API_BASE_URL=https://api.ikiguzi.com/api --dart-define=WEB_URL=https://ikiguzi.com
```

Settings come only from `--dart-define` (`lib/core/config.dart`). Nothing secret is built into the app. Toolchain: Flutter 3.38.7 / Dart 3.10.

## Layout

- `lib/router.dart`: every route. `/vendor`, `/supplier`, `/affiliate`, `/delivery` and `/admin` are role portals (`portal/portal_shell.dart`, navigation in `core/nav_items.dart`), guarded by the signed-in role.
- `lib/features/<area>/`: one screen per file. Helpers shared inside an area live in `*_shared.dart` / `vendor_data.dart`.
- `lib/portal/kit.dart` holds the portal building blocks: `Loader`, `PortalPage`, `RecordCard`, and `showFormSheet` with `FieldSpec`. `FieldType.pin` is a map pin stored as `{lat, lng}`.
- `lib/widgets/pin_picker.dart` is the map pin (flutter_map + CARTO tiles). Inside forms, a tap sets the pin and a pinch zooms. Drags scroll the page.

## Session rules (`test/session_test.dart`)

- A 401 on a signed-in call ends the session, and a blocked account (403 `ACCOUNT_BLOCKED`) signs out with a reason.
- A 401 with no token (a wrong password) and any 5xx keep the session.
- Show the server's message as is.

## Riders (`lib/features/rider/`)

This is KitchenLink's delivery-worker app, adapted to Ikiguzi parcels.

- **Accounts:** `/rider` signs riders in or up with a phone code. New riders wait for admin approval (`/admin/riders`).
- **Board:** `RiderBoardNotifier` refreshes every 10 s. It shows no offers while a trip is open, because riders carry one parcel at a time.
- **Steps:** the server decides the next step (`allowedNextStatuses`), and each is committed with `SlideToConfirm`. The buyer's 6-digit code completes the parcel.
- **Early offers:** parcels are offered when the buyer pays. `DeliveryJob.waitingForSeller` means the seller is still preparing it, and pickup waits until the parcel is ready. The trip page shows `ParcelProgress` (order placed to delivered) and "Hand it back" before pickup.
- **GPS:** `RiderLocation` runs in the foreground only. Online, it sends a position once a minute. During a trip it streams, sending at most every 4 s after moving 8 m and at least every 15 s (`shouldSendLiveFix`).
- **Riverpod 2:** read `AsyncValue` with `.valueOrNull`, because `.value` throws on an error.
