"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.stripeWebhook = exports.confirmCashPayment = exports.captureRidePayment = exports.listPaymentMethods = exports.createStripeSetupIntent = exports.createStripePaymentIntent = exports.syncDriverAvailability = exports.redeemDiscountCode = exports.sendAdminNotification = exports.onScheduledRideReminder = exports.onRideChatMessageCreated = exports.onRideUpdated = exports.onRideCreated = exports.onReferralApplied = exports.onDiscountCodeActivated = exports.onDiscountCodeCreated = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const firestore_2 = require("firebase-admin/firestore");
const tasks_1 = require("firebase-functions/v2/tasks");
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const functions_1 = require("firebase-admin/functions");
const notifications_1 = require("./notifications");
admin.initializeApp();
/**
 * Triggers whenever a new discount code document is created in Firestore.
 * Sends a push notification to all riders so they are immediately aware of
 * the new code and can navigate directly to the Promotions tab to use it.
 */
exports.onDiscountCodeCreated = (0, firestore_1.onDocumentCreated)("discountCodes/{codeId}", async (event) => {
    const data = event.data?.data();
    if (!data)
        return;
    // Only notify when the code is active at creation time
    if (!data.isActive)
        return;
    const code = data.code ?? "";
    const value = data.value ?? 0;
    const type = data.type ?? "FIXED";
    const description = data.description;
    const payload = (0, notifications_1.buildDiscountCodePayload)(code, value, type, description);
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
        const t = (d["fcmTokenCustomer"] ?? d["fcmToken"]);
        return t ? [t] : [];
    });
    if (tokens.length === 0) {
        console.log("onDiscountCodeCreated: no rider FCM tokens found — skipping.");
        return;
    }
    const message = {
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
        tokens,
    };
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`onDiscountCodeCreated: code=${code} — ` +
        `${response.successCount}/${tokens.length} riders notified.`);
});
/**
 * Triggers whenever an existing discount code document is updated in Firestore.
 * Sends a push notification to all riders when a code transitions from
 * inactive to active (i.e. the admin enables a previously disabled code).
 */
exports.onDiscountCodeActivated = (0, firestore_1.onDocumentUpdated)("discountCodes/{codeId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    // Only fire when isActive flips from false → true
    if (before.isActive === true || after.isActive !== true)
        return;
    const code = after.code ?? "";
    const value = after.value ?? 0;
    const type = after.type ?? "FIXED";
    const description = after.description;
    const payload = (0, notifications_1.buildDiscountCodePayload)(code, value, type, description);
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
        const t = (d["fcmTokenCustomer"] ?? d["fcmToken"]);
        return t ? [t] : [];
    });
    if (tokens.length === 0) {
        console.log("onDiscountCodeActivated: no rider FCM tokens found — skipping.");
        return;
    }
    const message = {
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
        tokens,
    };
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`onDiscountCodeActivated: code=${code} — ` +
        `${response.successCount}/${tokens.length} riders notified.`);
});
/**
 * Triggers whenever a new user document is created in Firestore.
 * If the user registered with a referral code (referredBy field), finds the
 * owner of that code and credits them with 10 SRD ride credits.
 */
exports.onReferralApplied = (0, firestore_1.onDocumentCreated)("users/{userId}", async (event) => {
    const data = event.data?.data();
    if (!data)
        return;
    const referredBy = data.referredBy;
    if (!referredBy || referredBy.trim() === "")
        return;
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
        rideCredits: firestore_2.FieldValue.increment(10),
    });
    console.log(`Awarded 10 SRD credits to referrer ${snap.docs[0].id} ` +
        `for referring new user ${event.params.userId}`);
});
/**
 * Triggers whenever a new ride document is created in Firestore.
 * Sends an FCM push notification to all online drivers so they are
 * notified even when the driver app is in the background or closed.
 *
 * Idempotency: atomically sets `driverNotifiedAt` on the ride before sending.
 * If the field already exists the function exits immediately, preventing
 * duplicate notifications from Cloud Functions at-least-once retries.
 */
exports.onRideCreated = (0, firestore_1.onDocumentCreated)("rides/{rideId}", async (event) => {
    const data = event.data?.data();
    if (!data)
        return;
    // Only notify for rides that are actively searching for a driver
    if (data.status !== "SEARCHING")
        return;
    const rideId = event.params.rideId;
    const rideRef = admin.firestore().collection("rides").doc(rideId);
    // Atomically claim the notification slot — only one function execution wins.
    try {
        await admin.firestore().runTransaction(async (tx) => {
            const snap = await tx.get(rideRef);
            if (!snap.exists)
                throw new Error("ride-not-found");
            if (snap.data()?.driverNotifiedAt)
                throw new Error("already-notified");
            tx.update(rideRef, { driverNotifiedAt: firestore_2.FieldValue.serverTimestamp() });
        });
    }
    catch (err) {
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
    const payload = (0, notifications_1.buildPayload)("SEARCHING", rideId);
    if (!payload)
        return;
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
    const seenTokens = new Set();
    const notifications = snapshot.docs
        .filter((doc) => {
        const token = (doc.data()["fcmTokenDriver"] ?? doc.data()["fcmToken"] ?? "");
        if (!token || seenTokens.has(token))
            return false;
        seenTokens.add(token);
        return true;
    })
        .map((doc) => (0, notifications_1.sendToUser)(doc.id, payload, "DRIVER"));
    await Promise.all(notifications);
    console.log(`Notified ${notifications.length} unique driver device(s) of new ride ${rideId} (${snapshot.size} online drivers total)`);
});
/**
 * Triggers whenever a ride document changes in Firestore.
 * Compares the previous and new `status` field and sends FCM push
 * notifications to the appropriate party (rider, driver, or both).
 * When a scheduled ride is accepted, also enqueues a Cloud Tasks reminder
 * for 1 hour before the scheduled time.
 */
exports.onRideUpdated = (0, firestore_1.onDocumentUpdated)("rides/{rideId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const previousStatus = before.status;
    const newStatus = after.status;
    // Only act when the status field actually changed
    if (previousStatus === newStatus)
        return;
    const rideId = event.params.rideId;
    const customerId = after.customerId;
    const driverId = after.driverId;
    // These statuses only concern the rider
    const riderStatuses = ["ACCEPTED", "ARRIVED", "PICKED_UP", "COMPLETED"];
    if (riderStatuses.includes(newStatus) && customerId) {
        const payload = (0, notifications_1.buildPayload)(newStatus, rideId);
        if (payload) {
            await (0, notifications_1.sendToUser)(customerId, payload, "CUSTOMER");
        }
        // When a scheduled ride is accepted, enqueue a 1-hour-before reminder for the driver
        if (newStatus === "ACCEPTED" && driverId) {
            const scheduledAtMs = after.scheduledAt;
            if (scheduledAtMs) {
                const reminderMs = scheduledAtMs - 60 * 60 * 1000;
                if (reminderMs > Date.now()) {
                    const queue = (0, functions_1.getFunctions)().taskQueue("onScheduledRideReminder");
                    await queue.enqueue({ rideId, driverId, scheduledAtMs }, { scheduleTime: new Date(reminderMs) });
                    console.log(`Scheduled ride reminder enqueued for driver ${driverId}, ` +
                        `ride ${rideId} at ${new Date(reminderMs).toISOString()}`);
                }
            }
        }
        return;
    }
    // Cancellation notifies both rider and driver
    if (newStatus === "CANCELLED") {
        const payload = (0, notifications_1.buildPayload)("CANCELLED", rideId);
        if (payload) {
            const tasks = [];
            if (customerId)
                tasks.push((0, notifications_1.sendToUser)(customerId, payload, "CUSTOMER"));
            if (driverId)
                tasks.push((0, notifications_1.sendToUser)(driverId, payload, "DRIVER"));
            await Promise.all(tasks);
        }
    }
});
const CHAT_ALLOWED_STATUSES = new Set(["ACCEPTED", "ARRIVED", "PICKED_UP"]);
/**
 * Sends a push to the ride counterparty when a new chat message is created
 * under rides/{rideId}/messages.
 */
exports.onRideChatMessageCreated = (0, firestore_1.onDocumentCreated)("rides/{rideId}/messages/{messageId}", async (event) => {
    const msg = event.data?.data();
    if (!msg)
        return;
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
    const ride = rideSnap.data();
    const status = ride.status;
    if (!status || !CHAT_ALLOWED_STATUSES.has(status)) {
        console.log(`onRideChatMessageCreated: skip status=${status ?? "?"} ride=${rideId}`);
        return;
    }
    const customerId = ride.customerId;
    const driverId = ride.driverId;
    if (!customerId || !driverId) {
        console.log(`onRideChatMessageCreated: missing participants ride=${rideId}`);
        return;
    }
    let recipientId;
    let senderIsCustomer;
    if (senderId === customerId) {
        recipientId = driverId;
        senderIsCustomer = true;
    }
    else if (senderId === driverId) {
        recipientId = customerId;
        senderIsCustomer = false;
    }
    else {
        console.log(`onRideChatMessageCreated: sender ${senderId} not participant ride=${rideId}`);
        return;
    }
    const payload = (0, notifications_1.buildChatMessagePayload)(rideId, text, senderIsCustomer);
    // Recipient is the counterparty: customer sends → driver receives, and vice versa
    const recipientRole = senderIsCustomer ? "DRIVER" : "CUSTOMER";
    await (0, notifications_1.sendToUser)(recipientId, payload, recipientRole);
    console.log(`onRideChatMessageCreated: notified ${recipientId} for ride=${rideId} message=${event.params.messageId}`);
});
/**
 * Fires 1 hour before a scheduled ride starts.
 * Sends an FCM push notification to the driver as a reminder.
 */
exports.onScheduledRideReminder = (0, tasks_1.onTaskDispatched)({ retryConfig: { maxAttempts: 3 } }, async (req) => {
    const { rideId, driverId, scheduledAtMs } = req.data;
    const payload = (0, notifications_1.buildPayload)("SCHEDULED_REMINDER", rideId, scheduledAtMs);
    if (payload) {
        await (0, notifications_1.sendToUser)(driverId, payload, "DRIVER");
    }
});
/**
 * Callable function for admins to broadcast a custom push notification.
 * Accepts { title, body, target } where target is "all" | "riders" | "drivers".
 * Verifies the caller has role == "ADMIN" before sending.
 */
exports.sendAdminNotification = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Je moet ingelogd zijn.");
    }
    const callerDoc = await admin.firestore().collection("users").doc(uid).get();
    if (!callerDoc.exists || callerDoc.data()?.role !== "ADMIN") {
        throw new https_1.HttpsError("permission-denied", "Alleen admins mogen meldingen versturen.");
    }
    const { title, body, target } = request.data;
    if (!title?.trim() || !body?.trim()) {
        throw new https_1.HttpsError("invalid-argument", "Titel en bericht zijn verplicht.");
    }
    let query = admin.firestore().collection("users");
    if (target === "riders") {
        query = query.where("isCustomer", "==", true);
    }
    else if (target === "drivers") {
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
            const t = (data["fcmTokenDriver"] ?? data["fcmToken"]);
            return t ? [t] : [];
        }
        if (target === "riders") {
            const t = (data["fcmTokenCustomer"] ?? data["fcmToken"]);
            return t ? [t] : [];
        }
        // "all": include both app tokens when a user has both, deduplicated
        const set = new Set();
        const d = data["fcmTokenDriver"];
        const c = data["fcmTokenCustomer"];
        const legacy = data["fcmToken"];
        if (d)
            set.add(d);
        if (c)
            set.add(c);
        if (!d && !c && legacy)
            set.add(legacy);
        return Array.from(set);
    });
    if (tokens.length === 0) {
        return { sent: 0 };
    }
    const message = {
        notification: { title, body },
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
        tokens,
    };
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Admin notification sent by ${uid}: ${response.successCount}/${tokens.length} delivered`);
    return { sent: response.successCount, total: tokens.length };
});
// ---------------------------------------------------------------------------
// Availability schedule helpers
// ---------------------------------------------------------------------------
/**
 * Returns the lowercase weekday name ("monday" … "sunday") for `date`
 * evaluated in the given IANA timezone.
 */
function getWeekday(date, tz) {
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
function isWithinSlot(date, tz, startHHMM, endHHMM) {
    const parts = new Intl.DateTimeFormat("en-US", {
        timeZone: tz,
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    })
        .formatToParts(date)
        .reduce((acc, p) => {
        acc[p.type] = p.value;
        return acc;
    }, {});
    const nowMinutes = parseInt(parts["hour"] ?? "0", 10) * 60 +
        parseInt(parts["minute"] ?? "0", 10);
    const [sh, sm] = startHHMM.split(":").map(Number);
    const [eh, em] = endHHMM.split(":").map(Number);
    const startMinutes = sh * 60 + sm;
    const endMinutes = eh * 60 + em;
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
exports.redeemDiscountCode = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Je moet ingelogd zijn.");
    }
    const { code, context, fare } = request.data;
    if (!code?.trim()) {
        throw new https_1.HttpsError("invalid-argument", "Kortingscode is verplicht.");
    }
    const db = admin.firestore();
    const codeUpper = code.trim().toUpperCase();
    const snap = await db
        .collection("discountCodes")
        .where("code", "==", codeUpper)
        .limit(1)
        .get();
    if (snap.empty) {
        throw new https_1.HttpsError("not-found", "discount.code.invalid");
    }
    const codeDoc = snap.docs[0];
    const data = codeDoc.data();
    if (!data.isActive) {
        throw new https_1.HttpsError("failed-precondition", "discount.code.invalid");
    }
    const expiresAt = data.expiresAt;
    if (expiresAt < Date.now()) {
        throw new https_1.HttpsError("failed-precondition", "discount.code.expired");
    }
    const maxUses = data.maxUses;
    const currentUses = data.currentUses ?? 0;
    if (maxUses !== undefined && currentUses >= maxUses) {
        throw new https_1.HttpsError("resource-exhausted", "discount.code.max_uses_reached");
    }
    const oncePerUser = data.oncePerUser ?? false;
    const usedByUserIds = data.usedByUserIds ?? [];
    if (oncePerUser && usedByUserIds.includes(uid)) {
        throw new https_1.HttpsError("already-exists", "discount.code.already_used");
    }
    const minFare = data.minFare;
    if (context === "ride" && minFare !== undefined && (fare ?? 0) < minFare) {
        throw new https_1.HttpsError("failed-precondition", "discount.code.min_fare");
    }
    const codeType = data.type;
    const codeValue = data.value;
    const rideFare = fare ?? 0;
    let discountAmount;
    if (codeType === "PERCENTAGE") {
        discountAmount = Math.floor(rideFare * codeValue / 100);
    }
    else {
        discountAmount = Math.min(codeValue, rideFare);
    }
    await db.runTransaction(async (tx) => {
        const freshSnap = await tx.get(codeDoc.ref);
        const freshData = freshSnap.data();
        const freshUses = freshData.currentUses ?? 0;
        const freshMax = freshData.maxUses;
        if (freshMax !== undefined && freshUses >= freshMax) {
            throw new https_1.HttpsError("resource-exhausted", "discount.code.max_uses_reached");
        }
        const update = {
            currentUses: firestore_2.FieldValue.increment(1),
        };
        if (oncePerUser) {
            update["usedByUserIds"] = firestore_2.FieldValue.arrayUnion(uid);
        }
        tx.update(codeDoc.ref, update);
        if (context === "credits") {
            const userRef = db.collection("users").doc(uid);
            tx.update(userRef, { rideCredits: firestore_2.FieldValue.increment(discountAmount > 0 ? discountAmount : codeValue) });
        }
    });
    console.log(`redeemDiscountCode: uid=${uid} code=${codeUpper} context=${context} discountAmount=${discountAmount}`);
    return { type: codeType, value: codeValue, discountAmount };
});
exports.syncDriverAvailability = (0, scheduler_1.onSchedule)("every 5 minutes", async () => {
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
        const tz = data.availabilityTimezone ?? "America/Paramaribo";
        const weekday = getWeekday(now, tz);
        const slot = (data.availability ?? {})[weekday];
        let shouldBeOnline = false;
        if (slot?.isEnabled && slot.startTime && slot.endTime) {
            shouldBeOnline = isWithinSlot(now, tz, slot.startTime, slot.endTime);
        }
        if (data.isOnline !== shouldBeOnline) {
            await doc.ref.update({ isOnline: shouldBeOnline });
            console.log(`syncDriverAvailability: driver ${doc.id} → isOnline=${shouldBeOnline} (${weekday}, tz=${tz})`);
        }
    });
    await Promise.all(updates);
    console.log(`syncDriverAvailability: checked ${snapshot.size} driver(s)`);
});
var payments_1 = require("./payments");
Object.defineProperty(exports, "createStripePaymentIntent", { enumerable: true, get: function () { return payments_1.createStripePaymentIntent; } });
Object.defineProperty(exports, "createStripeSetupIntent", { enumerable: true, get: function () { return payments_1.createStripeSetupIntent; } });
Object.defineProperty(exports, "listPaymentMethods", { enumerable: true, get: function () { return payments_1.listPaymentMethods; } });
Object.defineProperty(exports, "captureRidePayment", { enumerable: true, get: function () { return payments_1.captureRidePayment; } });
Object.defineProperty(exports, "confirmCashPayment", { enumerable: true, get: function () { return payments_1.confirmCashPayment; } });
Object.defineProperty(exports, "stripeWebhook", { enumerable: true, get: function () { return payments_1.stripeWebhook; } });
//# sourceMappingURL=index.js.map