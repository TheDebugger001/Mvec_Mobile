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
| Account | My account (photo, details, addresses, password), Notifications (tap opens what it is about), Messages, Refunds (opens the live problem-report case), Subscription, Help |
| Seller (`/vendor`) | Overview, Products (editor with discount, photos, attributes; CSV bulk upload), Inventory (adjust, move between stores, stock history), Categories, Orders (next step, cancel, cash received), order detail, manual orders, Customers, Payouts, Transactions, Subscription, Advertisements, Promotions, Reviews, Analytics, Reports, My Stores, Shipping zones, Team / Staff, Settings, Purchases, Quote requests, Find suppliers (catalog ordering), Affiliate program, Delivery & settlement, Refunds (problem-report cases), MVEC Support |
| Supplier (`/supplier`) | Overview with to-do list, Wholesale products, Inventory, Orders, Quote requests, Payments, Transactions, Analytics, Reports, Reviews, Subscription, Team, Settings, Messages, Notifications, Support |
| Affiliate (`/affiliate`) | Dashboard, Promote products (create / copy / share / terminate links), My links, Commissions, Wallet, Withdrawals, Profile, Messages, Notifications, Support; `/track/:code` links credit the affiliate at checkout |
| Courier (`/delivery`) | Dashboard, My deliveries, Delivered (pick up, confirm with the buyer's 6-digit code), Messages, Support |
| Admin (`/admin`) | Overview with "needs your attention", Users (role, block), Sellers and Suppliers (verification review), Affiliates, Orders, Deliveries (courier assignment), Disputes (decide), Payments, Seller payouts, Refunds & withdrawals, MVEC earnings and wallet, Commission rules (with split preview), Financial ledger, Products, Categories, Advertising review, Subscriptions program switch, Analytics, Trust scores, Fraud & risk, Settings (auto-release days), Audit log, Messages, Notifications, Support inbox, Become a Seller |

Navigation: the marketplace has a top bar, left sidebar and a bottom bar with
Home, Shop, For You, Deals and Orders. Every dashboard has its own top bar
(theme, notifications, account), a grouped side menu with the web's sections
(admins see waiting counts) and a bottom bar with the role's four main pages
plus "More". Vendor staff only see the sections their role allows.

Routes use the same paths as the web app (`/shop`, `/product/:id`, `/orders/:id`,
`/vendor/orders/:id`, `/admin/...`), so links in notifications open the same page.

Set `WEB_URL` (dart-define or `.env`) to the website address so shared links
(affiliate links, payment links) point to it.

## Not built yet

- Google sign-in and real-time sockets (messages and cases refresh on open and by polling).

## Checks

```bash
flutter analyze
flutter test      # runs the real screens against a fake backend
```
