# Payments — setup & architecture

## Supported methods (phase 1)

| Method | When charged | Notes |
|--------|--------------|-------|
| **Cash** | Driver confirms after ride | `confirmCashPayment` Cloud Function |
| **Card** (Visa/Mastercard/Apple Pay) | Authorized at booking, captured at completion | Stripe PaymentSheet |
| **Ride credits** | Deducted at booking | Fully covered rides → `paymentStatus = PAID` |

## Required configuration

### 1. Stripe account
Create a Stripe account with a supported merchant country (e.g. Netherlands or US via Stripe Atlas).

### 2. Firebase secrets
```bash
firebase functions:secrets:set STRIPE_SECRET_KEY
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
```

### 3. Environment variables (Cloud Functions)
| Variable | Default | Description |
|----------|---------|-------------|
| `STRIPE_CURRENCY` | `usd` | Charge currency (SRD is not supported on all Stripe accounts) |
| `STRIPE_SRD_TO_USD_RATE` | `0.028` | Converts SRD fares to Stripe amount |

### 4. iOS xcconfig
Set `PAYMENT_PUBLIC_KEY` to your Stripe **publishable** key in `Configs/Rider.*.xcconfig`.

### 5. Stripe webhook
Point Stripe webhook to:
```
https://us-central1-<project-id>.cloudfunctions.net/stripeWebhook
```
Events: `payment_intent.succeeded`, `payment_intent.payment_failed`

### 6. Stripe iOS SDK (optional but recommended)
Add via Swift Package Manager:
```
https://github.com/stripe/stripe-ios
```
Product: **StripePaymentSheet**

Without the SDK, card flows return `stripeNotLinked` — cash and credits still work.

## Cloud Functions

| Function | Caller | Purpose |
|----------|--------|---------|
| `createStripePaymentIntent` | Rider | Authorize estimated fare (manual capture) |
| `createStripeSetupIntent` | Rider | Save card in profile |
| `listPaymentMethods` | Rider | List saved cards |
| `captureRidePayment` | Rider | Capture final fare after trip |
| `confirmCashPayment` | Driver | Mark cash ride as paid |
| `stripeWebhook` | Stripe | Sync `paymentStatus` in Firestore |

## Firestore fields

### `rides/{rideId}`
- `paymentMethod`: `CASH` | `CARD` | `CREDITS`
- `paymentStatus`: `PENDING` | `PAID` | `FAILED` | `CASH`
- `paymentIntentId`: Stripe PaymentIntent id (card rides)
- `currency`: `SRD`

### `users/{userId}`
- `stripeCustomerId`: Stripe Customer id

## Flow diagrams

### Card ride
1. Rider selects **Card** → ride created
2. `createStripePaymentIntent` + PaymentSheet (authorize hold)
3. Driver completes ride → `captureRidePayment` with final fare
4. Webhook sets `paymentStatus = PAID`

### Cash ride
1. Rider selects **Cash** → ride created (`paymentStatus = PENDING`)
2. Driver completes ride → cash confirmation overlay
3. Driver taps **Cash received** → `confirmCashPayment` → `paymentStatus = CASH`
