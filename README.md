# MVEC Mobile

Flutter mobile app for the MVEC marketplace. It mirrors `Mvec_frontend` (React)
and talks to the existing `Ikiguzi_backend` REST API. Nothing is mocked: every
screen reads and writes through the real `/api` endpoints.

**Stack:** Flutter · Riverpod (state) · go_router (routes) · Dio (HTTP) ·
flutter_secure_storage (session token) · flutter_svg (the web app's thin icons).

## Run

```bash
# 1. Start the backend (in Ikiguzi_backend): npm run dev   -> http://localhost:4000
# 2. Point the app at it, then run:
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<host>:4000/api
```

`API_BASE_URL` resolves in this order: `--dart-define`, `API_BASE_URL` in `.env`,
then `http://localhost:4000/api`. On the Android emulator a `localhost` URL is
rewritten to `10.0.2.2` automatically; on a real phone use your machine's LAN
IP or the hosted URL.

## What is built

| Area | Screens |
| --- | --- |
| Auth | Sign in (email or phone + password, or a texted code), Create account (buyer / vendor / affiliate), Forgot password (code → new password), expired-session and blocked-account handling |
| Marketplace | Home (hero carousel, categories, deals, popular, stores), Shop (search, category, sale, stock, sort), For You, Deals, Stores and store page (follow), Product details (gallery, reviews, compare), Cart, Wishlist, Checkout (pickup or delivery, fee quote, coupon, guest phone verification), Payment (MoMo / card / K-Pay), Orders, Order details (timeline, delivery code, cancel, review, report a problem) |
| Account | My account (photo, details, addresses, password), Notifications, Messages, Refunds, Subscription, Help |

Navigation: top bar (menu on the left; theme switch, wishlist, cart and account
on the right; search below), left sidebar, and a bottom bar with exactly Home,
Shop, For You, Deals and Orders.

Routes use the same paths as the web app (`/shop`, `/product/:id`, `/orders/:id`,
`/payment/:id`, `/buyer/*`, ...).

## Not built yet

- Role dashboards (admin, vendor, affiliate, delivery): their routes exist, are
  guarded by role, and show a "Dashboard coming next" page.
- Supplier role: out of scope for now.
- Google sign-in, affiliate `/track/:code` deep link, real-time sockets
  (messages refresh by polling instead).

## Checks

```bash
flutter analyze
flutter test      # runs the real screens against a fake backend
```
