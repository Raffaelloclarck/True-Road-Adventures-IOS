import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import Stripe from "stripe";

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

/** Stripe billing currency (SRD is not supported on all accounts — use `usd` or `eur`). */
const STRIPE_CURRENCY = process.env.STRIPE_CURRENCY ?? "usd";
/** Multiplier to convert a fare stored in SRD into the Stripe charge currency. */
const SRD_TO_STRIPE_RATE = parseFloat(process.env.STRIPE_SRD_TO_USD_RATE ?? "0.028");

function stripeClient(secret: string): Stripe {
  return new Stripe(secret, { apiVersion: "2025-02-24.acacia" });
}

function toStripeAmount(amountSrd: number): number {
  const normalized = Math.max(amountSrd, 0);
  if (STRIPE_CURRENCY === "srd") {
    return Math.round(normalized * 100);
  }
  return Math.round(normalized * SRD_TO_STRIPE_RATE * 100);
}

async function getOrCreateStripeCustomer(
  stripe: Stripe,
  uid: string
): Promise<string> {
  const userRef = admin.firestore().collection("users").doc(uid);
  const snap = await userRef.get();
  const existing = snap.data()?.stripeCustomerId as string | undefined;
  if (existing) return existing;

  const user = snap.data() ?? {};
  const customer = await stripe.customers.create({
    email: user.email as string | undefined,
    name: user.displayName as string | undefined,
    metadata: { firebaseUid: uid },
  });
  await userRef.set({ stripeCustomerId: customer.id }, { merge: true });
  return customer.id;
}

/**
 * Creates (or reuses) a manual-capture PaymentIntent for card rides.
 * Called when the rider books a ride or when capture is needed at trip end.
 */
export const createStripePaymentIntent = onCall(
  { secrets: [stripeSecretKey], region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const { rideId, amount, currency } = request.data as {
      rideId?: string;
      amount?: number;
      currency?: string;
    };

    if (amount == null || amount <= 0) {
      throw new HttpsError("invalid-argument", "Positive amount is required.");
    }

    const stripe = stripeClient(stripeSecretKey.value());
    const customerId = await getOrCreateStripeCustomer(stripe, uid);
    const stripeAmount = toStripeAmount(amount);
    const chargeCurrency = currency ?? STRIPE_CURRENCY;

    if (!rideId) {
      const intent = await stripe.paymentIntents.create({
        amount: stripeAmount,
        currency: chargeCurrency,
        customer: customerId,
        automatic_payment_methods: { enabled: true },
        metadata: { firebaseUid: uid },
      });
      return { clientSecret: intent.client_secret, paymentIntentId: intent.id };
    }

    const rideRef = admin.firestore().collection("rides").doc(rideId);
    const rideSnap = await rideRef.get();
    if (!rideSnap.exists) throw new HttpsError("not-found", "Ride not found.");
    const ride = rideSnap.data()!;
    if (ride.customerId !== uid) {
      throw new HttpsError("permission-denied", "Only the rider can authorize payment.");
    }

    const existingIntentId = ride.paymentIntentId as string | undefined;
    if (existingIntentId) {
      const existing = await stripe.paymentIntents.retrieve(existingIntentId);
      if (existing.status === "requires_capture" || existing.status === "succeeded") {
        return {
          clientSecret: existing.client_secret,
          paymentIntentId: existing.id,
        };
      }
    }

    const intent = await stripe.paymentIntents.create({
      amount: stripeAmount,
      currency: chargeCurrency,
      customer: customerId,
      capture_method: "manual",
      automatic_payment_methods: { enabled: true },
      metadata: { rideId, firebaseUid: uid },
    });

    await rideRef.update({
      paymentIntentId: intent.id,
      paymentStatus: "PENDING",
      updatedAt: Date.now(),
    });

    return {
      clientSecret: intent.client_secret,
      paymentIntentId: intent.id,
    };
  }
);

/** SetupIntent so riders can save a card for future rides. */
export const createStripeSetupIntent = onCall(
  { secrets: [stripeSecretKey], region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const stripe = stripeClient(stripeSecretKey.value());
    const customerId = await getOrCreateStripeCustomer(stripe, uid);
    const setup = await stripe.setupIntents.create({
      customer: customerId,
      automatic_payment_methods: { enabled: true },
    });

    return { clientSecret: setup.client_secret };
  }
);

/** Lists saved card payment methods for the signed-in rider. */
export const listPaymentMethods = onCall(
  { secrets: [stripeSecretKey], region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const userSnap = await admin.firestore().collection("users").doc(uid).get();
    const customerId = userSnap.data()?.stripeCustomerId as string | undefined;
    if (!customerId) return { methods: [] };

    const stripe = stripeClient(stripeSecretKey.value());
    const pms = await stripe.paymentMethods.list({
      customer: customerId,
      type: "card",
    });

    const methods = pms.data.map((pm) => ({
      id: pm.id,
      brand: pm.card?.brand ?? "card",
      last4: pm.card?.last4 ?? "????",
      expMonth: pm.card?.exp_month ?? 0,
      expYear: pm.card?.exp_year ?? 0,
    }));

    return { methods };
  }
);

/**
 * Captures the authorized PaymentIntent after the ride completes.
 * Adjusts the capture amount when the final fare differs from the estimate.
 */
export const captureRidePayment = onCall(
  { secrets: [stripeSecretKey], region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const { rideId, amount } = request.data as { rideId?: string; amount?: number };
    if (!rideId || amount == null) {
      throw new HttpsError("invalid-argument", "rideId and amount are required.");
    }

    const rideRef = admin.firestore().collection("rides").doc(rideId);
    const rideSnap = await rideRef.get();
    if (!rideSnap.exists) throw new HttpsError("not-found", "Ride not found.");
    const ride = rideSnap.data()!;
    if (ride.customerId !== uid) {
      throw new HttpsError("permission-denied", "Only the rider can capture payment.");
    }

    const intentId = ride.paymentIntentId as string | undefined;
    if (!intentId) {
      throw new HttpsError("failed-precondition", "No payment authorization on this ride.");
    }

    const stripe = stripeClient(stripeSecretKey.value());
    const intent = await stripe.paymentIntents.retrieve(intentId);
    const captureAmount = toStripeAmount(amount);

    let result: Stripe.PaymentIntent;
    if (intent.status === "requires_capture") {
      result = await stripe.paymentIntents.capture(intentId, {
        amount_to_capture: Math.min(captureAmount, intent.amount),
      });
    } else if (intent.status === "succeeded") {
      result = intent;
    } else {
      throw new HttpsError("failed-precondition", `PaymentIntent status: ${intent.status}`);
    }

    await rideRef.update({
      paymentStatus: "PAID",
      updatedAt: Date.now(),
    });

    return { status: result.status, paymentIntentId: result.id };
  }
);

/** Driver confirms cash was received at the end of a cash ride. */
export const confirmCashPayment = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const { rideId } = request.data as { rideId?: string };
    if (!rideId) throw new HttpsError("invalid-argument", "rideId is required.");

    const rideRef = admin.firestore().collection("rides").doc(rideId);
    const rideSnap = await rideRef.get();
    if (!rideSnap.exists) throw new HttpsError("not-found", "Ride not found.");
    const ride = rideSnap.data()!;

    if (ride.driverId !== uid) {
      throw new HttpsError("permission-denied", "Only the assigned driver can confirm cash.");
    }
    if (ride.paymentMethod !== "CASH") {
      throw new HttpsError("failed-precondition", "This ride is not a cash ride.");
    }
    if (ride.status !== "COMPLETED") {
      throw new HttpsError("failed-precondition", "Ride must be completed first.");
    }

    await rideRef.update({
      paymentStatus: "CASH",
      updatedAt: Date.now(),
    });

    return { ok: true };
  }
);

/** Stripe webhook — keeps Firestore in sync when capture succeeds or payment fails. */
export const stripeWebhook = onRequest(
  { secrets: [stripeSecretKey, stripeWebhookSecret], region: "us-central1" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const stripe = stripeClient(stripeSecretKey.value());
    const sig = req.headers["stripe-signature"];
    if (!sig) {
      res.status(400).send("Missing stripe-signature");
      return;
    }

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        sig,
        stripeWebhookSecret.value()
      );
    } catch (err) {
      console.error("stripeWebhook signature error:", err);
      res.status(400).send("Invalid signature");
      return;
    }

    const db = admin.firestore();

    switch (event.type) {
      case "payment_intent.succeeded": {
        const intent = event.data.object as Stripe.PaymentIntent;
        const rideId = intent.metadata?.rideId;
        if (rideId) {
          await db.collection("rides").doc(rideId).update({
            paymentStatus: "PAID",
            paymentIntentId: intent.id,
            updatedAt: Date.now(),
          });
        }
        break;
      }
      case "payment_intent.payment_failed": {
        const intent = event.data.object as Stripe.PaymentIntent;
        const rideId = intent.metadata?.rideId;
        if (rideId) {
          await db.collection("rides").doc(rideId).update({
            paymentStatus: "FAILED",
            updatedAt: Date.now(),
          });
        }
        break;
      }
      default:
        break;
    }

    res.json({ received: true });
  }
);
