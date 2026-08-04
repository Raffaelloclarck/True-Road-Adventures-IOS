import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { getFunctions } from "firebase-admin/functions";
import { buildPayload, buildChatMessagePayload, buildDiscountCodePayload, sendToUser } from "./notifications";

admin.initializeApp();

/**
 * Triggers whenever a new discount code document is created in Firestore.
 * Sends a push notification to all riders so they are immediately aware of
 * the new code and can navigate directly to the Promotions tab to use it.
 */
export const onDiscountCodeCreated = onDocumentCreated(
  "discountCodes/{codeId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // Only notify when the code is active at creation time
    if (!data.isActive) return;

    const code    = (data.code  as string)  ?? "";
    const value   = (data.value as number)  ?? 0;
    const type    = (data.type  as "PERCENTAGE" | "FIXED") ?? "FIXED";
    const description = data.description as string | undefined;

    const payload = buildDiscountCodePayload(code, value, type, description);

    const snapshot = await admin
      .firestore()
      .collection("users")
      .where("isCustomer", "==", true)
      .get();

    if (snapshot.empty) {
      console.log("onDiscountCodeCreated: no riders found — skipping.");
      return;
    }

    const tokens = snapshot.docs.flatMap((doc) => {
      const d = doc.data();
      const t = (d["fcmTokenCustomer"] ?? d["fcmToken"]) as string | undefined;
      return t ? [t] : [];
    });

    if (tokens.length === 0) {
      console.log("onDiscountCodeCreated: no rider FCM tokens found — skipping.");
      return;
    }

    const message: admin.messaging.MulticastMessage = {
      notification: { title: payload.title, body: payload.body },
      data: payload.data,
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
      tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(
      `onDiscountCodeCreated: code=${code} — ` +
      `${response.successCount}/${tokens.length} riders notified.`
    );
  }
);

/**
 * Triggers whenever an existing discount code document is updated in Firestore.
 * Sends a push notification to all riders when a code transitions from
 * inactive to active (i.e. the admin enables a previously disabled code).
 */
export const onDiscountCodeActivated = onDocumentUpdated(
  "discountCodes/{codeId}",
  async (event) => {
    const before = event.data?.before.data();
    const after  = event.data?.after.data();
    if (!before || !after) return;

    // Only fire when isActive flips from false → true
    if (before.isActive === true || after.isActive !== true) return;

    const code    = (after.code  as string)  ?? "";
    const value   = (after.value as number)  ?? 0;
    const type    = (after.type  as "PERCENTAGE" | "FIXED") ?? "FIXED";
    const description = after.description as string | undefined;

    const payload = buildDiscountCodePayload(code, value, type, description);

    const snapshot = await admin
      .firestore()
      .collection("users")
      .where("isCustomer", "==", true)
      .get();

    if (snapshot.empty) {
      console.log("onDiscountCodeActivated: no riders found — skipping.");
      return;
    }

    const tokens = snapshot.docs.flatMap((doc) => {
      const d = doc.data();
      const t = (d["fcmTokenCustomer"] ?? d["fcmToken"]) as string | undefined;
      return t ? [t] : [];
    });

    if (tokens.length === 0) {
      console.log("onDiscountCodeActivated: no rider FCM tokens found — skipping.");
      return;
    }

    const message: admin.messaging.MulticastMessage = {
      notification: { title: payload.title, body: payload.body },
      data: payload.data,
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
      tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(
      `onDiscountCodeActivated: code=${code} — ` +
      `${response.successCount}/${tokens.length} riders notified.`
    );
  }
);

/**
 * Triggers whenever a new user document is created in Firestore.
 * If the user registered with a referral code (referredBy field), finds the
 * owner of that code and credits them with 10 SRD ride credits.
 */
export const onReferralApplied = onDocumentCreated(
  "users/{userId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const referredBy = data.referredBy as string | undefined;
    if (!referredBy || referredBy.trim() === "") return;

    const snap = await admin
      .firestore()
      .collection("users")
      .where("referralCode", "==", referredBy.trim().toUpperCase())
      .limit(1)
      .get();

    if (snap.empty) {
      console.log(`Referral code "${referredBy}" not found — no credits awarded.`);
      return;
    }

    const referrerRef = snap.docs[0].ref;
    await referrerRef.update({
      rideCredits: FieldValue.increment(10),
    });

    console.log(
      `Awarded 10 SRD credits to referrer ${snap.docs[0].id} ` +
      `for referring new user ${event.params.userId}`
    );
  }
);

/**
 * Triggers whenever a new ride document is created in Firestore.
 * Sends an FCM push notification to all online drivers so they are
 * notified even when the driver app is in the background or closed.
 *
 * Idempotency: atomically sets `driverNotifiedAt` on the ride before sending.
 * If the field already exists the function exits immediately, preventing
 * duplicate notifications from Cloud Functions at-least-once retries.
 */
export const onRideCreated = onDocumentCreated(
  "rides/{rideId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // Only notify for rides that are actively searching for a driver
    if (data.status !== "SEARCHING") return;

    const rideId = event.params.rideId;
    const rideRef = admin.firestore().collection("rides").doc(rideId);

    // Atomically claim the notification slot — only one function execution wins.
    try {
      await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(rideRef);
        if (!snap.exists) throw new Error("ride-not-found");
        if (snap.data()?.driverNotifiedAt) throw new Error("already-notified");
        tx.update(rideRef, { driverNotifiedAt: FieldValue.serverTimestamp() });
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg === "already-notified") {
        console.log(`onRideCreated: duplicate execution suppressed for ride ${rideId}`);
        return;
      }
      if (msg === "ride-not-found") {
        console.log(`onRideCreated: ride ${rideId} not found — skipping`);
        return;
      }
      throw err;
    }

    const payload = buildPayload("SEARCHING", rideId);
    if (!payload) return;

    // Fetch all drivers that are currently online
    const snapshot = await admin
      .firestore()
      .collection("users")
      .where("isDriver", "==", true)
      .where("isOnline", "==", true)
      .get();

    if (snapshot.empty) {
      console.log("No online drivers found for ride", rideId);
      return;
    }

    // Deduplicate by FCM token so a driver who is logged in on multiple accounts
    // (or has multiple user documents sharing the same device token) only receives
    // one notification per ride request.
    const seenTokens = new Set<string>();
    const notifications = snapshot.docs
      .filter((doc) => {
        const token = (doc.data()["fcmTokenDriver"] ?? doc.data()["fcmToken"] ?? "") as string;
        if (!token || seenTokens.has(token)) return false;
        seenTokens.add(token);
        return true;
      })
      .map((doc) => sendToUser(doc.id, payload, "DRIVER"));

    await Promise.all(notifications);
    console.log(
      `Notified ${notifications.length} unique driver device(s) of new ride ${rideId} (${snapshot.size} online drivers total)`
    );
  }
);

/**
 * Triggers whenever a ride document changes in Firestore.
 * Compares the previous and new `status` field and sends FCM push
 * notifications to the appropriate party (rider, driver, or both).
 * When a scheduled ride is accepted, also enqueues a Cloud Tasks reminder
 * for 1 hour before the scheduled time.
 */
export const onRideUpdated = onDocumentUpdated(
  "rides/{rideId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const previousStatus = before.status as string;
    const newStatus = after.status as string;

    // Only act when the status field actually changed
    if (previousStatus === newStatus) return;

    const rideId = event.params.rideId;
    const customerId = after.customerId as string | undefined;
    const driverId = after.driverId as string | undefined;

    // These statuses only concern the rider
    const riderStatuses = ["ACCEPTED", "ARRIVED", "PICKED_UP", "COMPLETED"];
    if (riderStatuses.includes(newStatus) && customerId) {
      const payload = buildPayload(newStatus, rideId);
      if (payload) {
        await sendToUser(customerId, payload, "CUSTOMER");
      }

      // When a scheduled ride is accepted, enqueue a 1-hour-before reminder for the driver
      if (newStatus === "ACCEPTED" && driverId) {
        const scheduledAtMs = after.scheduledAt as number | undefined;
        if (scheduledAtMs) {
          const reminderMs = scheduledAtMs - 60 * 60 * 1000;
          if (reminderMs > Date.now()) {
            const queue = getFunctions().taskQueue("onScheduledRideReminder");
            await queue.enqueue(
              { rideId, driverId, scheduledAtMs },
              { scheduleTime: new Date(reminderMs) }
            );
            console.log(
              `Scheduled ride reminder enqueued for driver ${driverId}, ` +
              `ride ${rideId} at ${new Date(reminderMs).toISOString()}`
            );
          }
        }
      }

      return;
    }

    // Cancellation notifies both rider and driver
    if (newStatus === "CANCELLED") {
      const payload = buildPayload("CANCELLED", rideId);
      if (payload) {
        const tasks: Promise<void>[] = [];
        if (customerId) tasks.push(sendToUser(customerId, payload, "CUSTOMER"));
        if (driverId) tasks.push(sendToUser(driverId, payload, "DRIVER"));
        await Promise.all(tasks);
      }
    }
  }
);

const CHAT_ALLOWED_STATUSES = new Set(["ACCEPTED", "ARRIVED", "PICKED_UP"]);

/**
 * Sends a push to the ride counterparty when a new chat message is created
 * under rides/{rideId}/messages.
 */
export const onRideChatMessageCreated = onDocumentCreated(
  "rides/{rideId}/messages/{messageId}",
  async (event) => {
    const msg = event.data?.data();
    if (!msg) return;

    const rideId = event.params.rideId;
    const text = typeof msg.text === "string" ? msg.text.trim() : "";
    const senderId = typeof msg.senderId === "string" ? msg.senderId : "";
    if (!text || !senderId) {
      console.log(`onRideChatMessageCreated: missing text/sender ride=${rideId}`);
      return;
    }

    const rideSnap = await admin.firestore().collection("rides").doc(rideId).get();
    if (!rideSnap.exists) {
      console.log(`onRideChatMessageCreated: ride not found ${rideId}`);
      return;
    }

    const ride = rideSnap.data()!;
    const status = ride.status as string | undefined;
    if (!status || !CHAT_ALLOWED_STATUSES.has(status)) {
      console.log(`onRideChatMessageCreated: skip status=${status ?? "?"} ride=${rideId}`);
      return;
    }

    const customerId = ride.customerId as string | undefined;
    const driverId = ride.driverId as string | undefined;
    if (!customerId || !driverId) {
      console.log(`onRideChatMessageCreated: missing participants ride=${rideId}`);
      return;
    }

    let recipientId: string | undefined;
    let senderIsCustomer: boolean | undefined;

    if (senderId === customerId) {
      recipientId = driverId;
      senderIsCustomer = true;
    } else if (senderId === driverId) {
      recipientId = customerId;
      senderIsCustomer = false;
    } else {
      console.log(
        `onRideChatMessageCreated: sender ${senderId} not participant ride=${rideId}`
      );
      return;
    }

    const payload = buildChatMessagePayload(rideId, text, senderIsCustomer);
    // Recipient is the counterparty: customer sends → driver receives, and vice versa
    const recipientRole = senderIsCustomer ? "DRIVER" : "CUSTOMER";
    await sendToUser(recipientId, payload, recipientRole);
    console.log(
      `onRideChatMessageCreated: notified ${recipientId} for ride=${rideId} message=${event.params.messageId}`
    );
  }
);

/**
 * Fires 1 hour before a scheduled ride starts.
 * Sends an FCM push notification to the driver as a reminder.
 */
export const onScheduledRideReminder = onTaskDispatched(
  { retryConfig: { maxAttempts: 3 } },
  async (req) => {
    const { rideId, driverId, scheduledAtMs } = req.data as {
      rideId: string;
      driverId: string;
      scheduledAtMs: number;
    };
    const payload = buildPayload("SCHEDULED_REMINDER", rideId, scheduledAtMs);
    if (payload) {
      await sendToUser(driverId, payload, "DRIVER");
    }
  }
);

/**
 * Callable function for admins to broadcast a custom push notification.
 * Accepts { title, body, target } where target is "all" | "riders" | "drivers".
 * Verifies the caller has role == "ADMIN" before sending.
 */
export const sendAdminNotification = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Je moet ingelogd zijn.");
  }

  const callerDoc = await admin.firestore().collection("users").doc(uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "ADMIN") {
    throw new HttpsError("permission-denied", "Alleen admins mogen meldingen versturen.");
  }

  const { title, body, target } = request.data as {
    title: string;
    body: string;
    target: "all" | "riders" | "drivers";
  };

  if (!title?.trim() || !body?.trim()) {
    throw new HttpsError("invalid-argument", "Titel en bericht zijn verplicht.");
  }

  let query: admin.firestore.Query = admin.firestore().collection("users");
  if (target === "riders") {
    query = query.where("isCustomer", "==", true);
  } else if (target === "drivers") {
    query = query.where("isDriver", "==", true);
  }

  const snapshot = await query.get();
  if (snapshot.empty) {
    return { sent: 0 };
  }

  // Pick the role-specific token field; for "all" collect tokens from both fields
  const tokens = snapshot.docs.flatMap((doc) => {
    const data = doc.data();
    if (target === "drivers") {
      const t = (data["fcmTokenDriver"] ?? data["fcmToken"]) as string | undefined;
      return t ? [t] : [];
    }
    if (target === "riders") {
      const t = (data["fcmTokenCustomer"] ?? data["fcmToken"]) as string | undefined;
      return t ? [t] : [];
    }
    // "all": include both app tokens when a user has both, deduplicated
    const set = new Set<string>();
    const d = data["fcmTokenDriver"] as string | undefined;
    const c = data["fcmTokenCustomer"] as string | undefined;
    const legacy = data["fcmToken"] as string | undefined;
    if (d) set.add(d);
    if (c) set.add(c);
    if (!d && !c && legacy) set.add(legacy);
    return Array.from(set);
  });

  if (tokens.length === 0) {
    return { sent: 0 };
  }

  const message: admin.messaging.MulticastMessage = {
    notification: { title, body },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
    tokens,
  };

  const response = await admin.messaging().sendEachForMulticast(message);
  console.log(
    `Admin notification sent by ${uid}: ${response.successCount}/${tokens.length} delivered`
  );
  return { sent: response.successCount, total: tokens.length };
});

// ---------------------------------------------------------------------------
// Availability schedule helpers
// ---------------------------------------------------------------------------

/**
 * Returns the lowercase weekday name ("monday" … "sunday") for `date`
 * evaluated in the given IANA timezone.
 */
function getWeekday(date: Date, tz: string): string {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    weekday: "long",
  });
  return formatter.format(date).toLowerCase();
}

/**
 * Returns true when `date` falls within [startHHMM, endHHMM) in `tz`.
 * Handles overnight slots (e.g. 22:00 – 06:00) correctly.
 */
function isWithinSlot(
  date: Date,
  tz: string,
  startHHMM: string,
  endHHMM: string
): boolean {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  })
    .formatToParts(date)
    .reduce<Record<string, string>>((acc, p) => {
      acc[p.type] = p.value;
      return acc;
    }, {});

  const nowMinutes =
    parseInt(parts["hour"] ?? "0", 10) * 60 +
    parseInt(parts["minute"] ?? "0", 10);

  const [sh, sm] = startHHMM.split(":").map(Number);
  const [eh, em] = endHHMM.split(":").map(Number);
  const startMinutes = sh * 60 + sm;
  const endMinutes   = eh * 60 + em;

  if (startMinutes <= endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }
  // Overnight slot
  return nowMinutes >= startMinutes || nowMinutes < endMinutes;
}

/**
 * Runs every 5 minutes. For every driver with `availabilityEnabled == true`,
 * compares the current local time against their weekly schedule and updates
 * `isOnline` in Firestore when it differs.
 *
 * Drivers who have NOT enabled the schedule keep their manual toggle behaviour.
 */
/**
 * Callable function to redeem a discount code.
 * Accepts { code, context, fare? } where context is "ride" | "credits".
 * Atomically validates the code, increments usage, optionally adds rideCredits.
 * Returns { type, value, discountAmount }.
 */
export const redeemDiscountCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Je moet ingelogd zijn.");
  }

  const { code, context, fare } = request.data as {
    code: string;
    context: "ride" | "credits";
    fare?: number;
  };

  if (!code?.trim()) {
    throw new HttpsError("invalid-argument", "Kortingscode is verplicht.");
  }

  const db = admin.firestore();
  const codeUpper = code.trim().toUpperCase();

  const snap = await db
    .collection("discountCodes")
    .where("code", "==", codeUpper)
    .limit(1)
    .get();

  if (snap.empty) {
    throw new HttpsError("not-found", "discount.code.invalid");
  }

  const codeDoc = snap.docs[0];
  const data = codeDoc.data();

  if (!data.isActive) {
    throw new HttpsError("failed-precondition", "discount.code.invalid");
  }

  const expiresAt = data.expiresAt as number;
  if (expiresAt < Date.now()) {
    throw new HttpsError("failed-precondition", "discount.code.expired");
  }

  const maxUses = data.maxUses as number | undefined;
  const currentUses = (data.currentUses as number) ?? 0;
  if (maxUses !== undefined && currentUses >= maxUses) {
    throw new HttpsError("resource-exhausted", "discount.code.max_uses_reached");
  }

  const oncePerUser = data.oncePerUser as boolean ?? false;
  const usedByUserIds = (data.usedByUserIds as string[]) ?? [];
  if (oncePerUser && usedByUserIds.includes(uid)) {
    throw new HttpsError("already-exists", "discount.code.already_used");
  }

  const minFare = data.minFare as number | undefined;
  if (context === "ride" && minFare !== undefined && (fare ?? 0) < minFare) {
    throw new HttpsError("failed-precondition", "discount.code.min_fare");
  }

  const codeType = data.type as "PERCENTAGE" | "FIXED";
  const codeValue = data.value as number;
  const rideFare = fare ?? 0;

  let discountAmount: number;
  if (codeType === "PERCENTAGE") {
    discountAmount = Math.floor(rideFare * codeValue / 100);
  } else {
    discountAmount = Math.min(codeValue, rideFare);
  }

  await db.runTransaction(async (tx) => {
    const freshSnap = await tx.get(codeDoc.ref);
    const freshData = freshSnap.data()!;
    const freshUses = (freshData.currentUses as number) ?? 0;
    const freshMax  = freshData.maxUses as number | undefined;
    if (freshMax !== undefined && freshUses >= freshMax) {
      throw new HttpsError("resource-exhausted", "discount.code.max_uses_reached");
    }

    const update: Record<string, unknown> = {
      currentUses: FieldValue.increment(1),
    };
    if (oncePerUser) {
      update["usedByUserIds"] = FieldValue.arrayUnion(uid);
    }
    tx.update(codeDoc.ref, update);

    if (context === "credits") {
      const userRef = db.collection("users").doc(uid);
      tx.update(userRef, { rideCredits: FieldValue.increment(discountAmount > 0 ? discountAmount : codeValue) });
    }
  });

  console.log(
    `redeemDiscountCode: uid=${uid} code=${codeUpper} context=${context} discountAmount=${discountAmount}`
  );

  return { type: codeType, value: codeValue, discountAmount };
});

export const syncDriverAvailability = onSchedule("every 5 minutes", async () => {
  const now = new Date();

  const snapshot = await admin
    .firestore()
    .collection("users")
    .where("isDriver", "==", true)
    .where("availabilityEnabled", "==", true)
    .get();

  if (snapshot.empty) {
    console.log("syncDriverAvailability: no drivers with schedule enabled");
    return;
  }

  const updates = snapshot.docs.map(async (doc) => {
    const data = doc.data();
    const tz: string = data.availabilityTimezone ?? "America/Paramaribo";
    const weekday = getWeekday(now, tz);
    const slot = (data.availability ?? {})[weekday] as
      | { isEnabled?: boolean; startTime?: string; endTime?: string }
      | undefined;

    let shouldBeOnline = false;
    if (slot?.isEnabled && slot.startTime && slot.endTime) {
      shouldBeOnline = isWithinSlot(now, tz, slot.startTime, slot.endTime);
    }

    if ((data.isOnline as boolean) !== shouldBeOnline) {
      await doc.ref.update({ isOnline: shouldBeOnline });
      console.log(
        `syncDriverAvailability: driver ${doc.id} → isOnline=${shouldBeOnline} (${weekday}, tz=${tz})`
      );
    }
  });

  await Promise.all(updates);
  console.log(`syncDriverAvailability: checked ${snapshot.size} driver(s)`);
});

export {
  createStripePaymentIntent,
  createStripeSetupIntent,
  listPaymentMethods,
  captureRidePayment,
  confirmCashPayment,
  stripeWebhook,
} from "./payments";
