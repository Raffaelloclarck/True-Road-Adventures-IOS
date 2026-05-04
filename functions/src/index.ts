import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { getFunctions } from "firebase-admin/functions";
import { buildPayload, sendToUser } from "./notifications";

admin.initializeApp();

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
 */
export const onRideCreated = onDocumentCreated(
  "rides/{rideId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // Only notify for rides that are actively searching for a driver
    if (data.status !== "SEARCHING") return;

    const rideId = event.params.rideId;
    const payload = buildPayload("SEARCHING", rideId);
    if (!payload) return;

    // Fetch all drivers that are currently online
    const snapshot = await admin
      .firestore()
      .collection("users")
      .where("role", "==", "DRIVER")
      .where("isOnline", "==", true)
      .get();

    if (snapshot.empty) {
      console.log("No online drivers found for ride", rideId);
      return;
    }

    const notifications = snapshot.docs.map((doc) =>
      sendToUser(doc.id, payload)
    );
    await Promise.all(notifications);
    console.log(
      `Notified ${snapshot.size} online driver(s) of new ride ${rideId}`
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
        await sendToUser(customerId, payload);
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
        if (customerId) tasks.push(sendToUser(customerId, payload));
        if (driverId) tasks.push(sendToUser(driverId, payload));
        await Promise.all(tasks);
      }
    }
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
      await sendToUser(driverId, payload);
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
    query = query.where("role", "==", "CUSTOMER");
  } else if (target === "drivers") {
    query = query.where("role", "==", "DRIVER");
  }

  const snapshot = await query.get();
  if (snapshot.empty) {
    return { sent: 0 };
  }

  const message: admin.messaging.MulticastMessage = {
    notification: { title, body },
    apns: { payload: { aps: { sound: "default", badge: 1 } } },
    tokens: snapshot.docs
      .map((doc) => doc.data().fcmToken as string | undefined)
      .filter((t): t is string => !!t),
  };

  if (message.tokens.length === 0) {
    return { sent: 0 };
  }

  const response = await admin.messaging().sendEachForMulticast(message);
  console.log(
    `Admin notification sent by ${uid}: ${response.successCount}/${message.tokens.length} delivered`
  );
  return { sent: response.successCount, total: message.tokens.length };
});
