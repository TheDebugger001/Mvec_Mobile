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
flutter build apk --release --dart-define-from-file=dart_defines.local.json
flutter test test/narrow_screens_test.dart   # every page on a 360 px phone with 130% text
```

Settings come only from `--dart-define` (`lib/core/config.dart`). The release values, Firebase included, live in `dart_defines.local.json`, which git ignores; keep it off git. Toolchain: Flutter 3.38.7 / Dart 3.10.

## Layout

- `lib/router.dart`: every route. `/vendor`, `/supplier`, `/affiliate`, `/delivery` and `/admin` are role portals (`portal/portal_shell.dart`, navigation in `core/nav_items.dart`), guarded by the signed-in role.
- `lib/features/<area>/`: one screen per file. Helpers shared inside an area live in `*_shared.dart` / `vendor_data.dart`.
- `lib/portal/kit.dart` holds the portal building blocks: `Loader`, `PortalPage`, `RecordCard`, and `showFormSheet` with `FieldSpec`. `FieldType.pin` is a map pin stored as `{lat, lng}`.
- `lib/widgets/pin_picker.dart` is the map pin (flutter_map + CARTO tiles). Inside forms, a tap sets the pin and a pinch zooms. Drags scroll the page.

## Session rules (`test/session_test.dart`)

- A 401 on a signed-in call ends the session, and a blocked account (403 `ACCOUNT_BLOCKED`) signs out with a reason.
- A 401 with no token (a wrong password) and any 5xx keep the session.
- Show the server's message as is.

## Marketplace features

- **Products:** `Product` carries `deal`, `variants`, `variantOptions` and `sellerBadges`. `forVariant()` makes the cart line for one size or colour, with its id as `"productId~variantId"`. The UI bits are in `features/marketplace/product_extras.dart`.
- **Returns:** `features/returns/returns_pages.dart` covers the order section, `/account/returns`, and `ReturnsBoardPage` for sellers, suppliers and admins.
- **Advertise here:** `/advertise` (`features/marketplace/advertise_page.dart`), reached from a hero slide. `AdBookingsAdminSection` sits on the admin Advertising page.
- **Push:** `core/push.dart` uses `firebase_messaging` and is off unless the build sets `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID` and `FIREBASE_PROJECT_ID`. It registers after sign-in and unregisters before sign-out. A tap opens the notification's `link`.

## Riders (`lib/features/rider/`)

This is KitchenLink's delivery-worker app, adapted to Ikiguzi parcels.

- **Accounts:** `/rider` signs riders up with a phone code and a password they choose, or signs them in with a code. With the password they also use the normal sign-in page. New riders wait for admin approval (`/admin/riders`).
- **Board:** `RiderBoardNotifier` refreshes every 10 s. It shows no offers while a trip is open, because riders carry one parcel at a time.
- **Offers from notifications:** a "New delivery" or "parcel waiting near you" notification opens `/delivery/offers/:id` (`rider_offer_page.dart`, `GET /rider/deliveries/:id`) with accept, decline, or go online.
- **Districts:** riders pick several (`DistrictsPicker`). Riders last seen near the store, or working its district, are woken for a parcel even when offline.
- **Steps:** the server decides the next step (`allowedNextStatuses`), and each is committed with `SlideToConfirm`. The buyer's 6-digit code completes the parcel.
- **Offers:** a parcel is offered to riders once the seller marks the order preparing (or ready), never at payment. `DeliveryJob.waitingForSeller` means the seller is still preparing it, and pickup waits until the parcel is ready. The trip page shows `ParcelProgress` (order placed to delivered) and "Hand it back" before pickup.
- **GPS:** `RiderLocation` runs in the foreground only. Online, it sends a position once a minute. During a trip it streams, sending at most every 4 s after moving 8 m and at least every 15 s (`shouldSendLiveFix`).
- **Riverpod 2:** read `AsyncValue` with `.valueOrNull`, because `.value` throws on an error.

## Shared widgets

- `widgets/auto_payout_card.dart` ("Get paid automatically", `/api/auto-payouts`) is on the seller, supplier, affiliate and rider payout pages.
- `widgets/district_dropdown.dart` lists Rwanda's districts under their province. It's used for rider sign-up, the rider's "Where you deliver" card and onboarding.
- Every `FieldType.pin` and the address sheet offer "Use my location". Products from suppliers show `BulkFlag` ("Supplier · bulk").
- `PinPicker(searchText:)` shows "Find on map" and follows the typed street (`/api/geo/search`) until the pin is placed by hand (checkout and saved addresses).
- `widgets/location_prompt.dart`: once per account after sign-in, buyers, sellers, suppliers and riders are asked to share their location (`POST /api/geo/me` fills empty pins). `LastPin` keeps it for checkout's starting pin.
- `/orders` and `/orders/:id` signed out show `FollowOrders` (`features/marketplace/follow_orders.dart`): phone, then a text code, then the orders.
- A seller's parcel that no rider took shows "Deliver it myself" (`OrderLiveTracking`, `POST /orders/vendor/:id/self-deliver`).
