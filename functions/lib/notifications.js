"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildPayload = buildPayload;
exports.getFcmToken = getFcmToken;
exports.sendToUser = sendToUser;
const admin = require("firebase-admin");
/**
 * Maps a RideStatus rawValue to an FCM notification payload.
 * Returns null for statuses that do not trigger a push notification.
 * Pass scheduledAtMs (epoch ms) for the SCHEDULED_REMINDER case.
 */
function buildPayload(status, rideId, scheduledAtMs) {
    switch (status) {
        case "SEARCHING":
            return {
                title: "Nieuwe rit aangevraagd!",
                body: "Er is een nieuwe ritaanvraag beschikbaar. Tik om te bekijken.",
                data: { rideId, screen: "home" },
            };
        case "ACCEPTED":
            return {
                title: "Chauffeur gevonden!",
                body: "Je chauffeur is onderweg naar de ophaallocatie.",
                data: { rideId, screen: "activeRide" },
            };
        case "ARRIVED":
            return {
                title: "Chauffeur is gearriveerd",
                body: "Je chauffeur staat klaar op de ophaallocatie.",
                data: { rideId, screen: "activeRide" },
            };
        case "PICKED_UP":
            return {
                title: "Rit gestart",
                body: "Geniet van je True Road Adventure!",
                data: { rideId, screen: "activeRide" },
            };
        case "COMPLETED":
            return {
                title: "Rit afgerond",
                body: "Beoordeel je rit-ervaring.",
                data: { rideId, screen: "activeRide" },
            };
        case "CANCELLED":
            return {
                title: "Rit geannuleerd",
                body: "De rit is geannuleerd.",
                data: { rideId, screen: "home" },
            };
        case "SCHEDULED_REMINDER": {
            const time = scheduledAtMs
                ? new Date(scheduledAtMs).toLocaleTimeString("nl-NL", {
                    hour: "2-digit",
                    minute: "2-digit",
                })
                : "binnenkort";
            return {
                title: "Geplande rit over 1 uur",
                body: `Je hebt een geplande rit om ${time}. Zorg dat je klaar bent.`,
                data: { rideId, screen: "activeRide" },
            };
        }
        default:
            return null;
    }
}
/** Fetches the FCM token for a user from Firestore. */
async function getFcmToken(userId) {
    const doc = await admin.firestore().collection("users").doc(userId).get();
    if (!doc.exists)
        return null;
    return doc.data()?.fcmToken ?? null;
}
/**
 * Sends an FCM push notification to a single user.
 * Silently skips when the user has no registered token.
 */
async function sendToUser(userId, payload) {
    const token = await getFcmToken(userId);
    if (!token) {
        console.log(`No FCM token for user ${userId} — skipping notification.`);
        return;
    }
    const message = {
        token,
        notification: {
            title: payload.title,
            body: payload.body,
        },
        data: payload.data,
        apns: {
            payload: {
                aps: {
                    sound: "default",
                    badge: 1,
                },
            },
        },
    };
    try {
        const messageId = await admin.messaging().send(message);
        console.log(`Notification sent to ${userId}: ${messageId}`);
    }
    catch (error) {
        console.error(`Failed to send notification to ${userId}:`, error);
    }
}
//# sourceMappingURL=notifications.js.map