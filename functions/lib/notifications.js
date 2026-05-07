"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildPayload = buildPayload;
exports.buildChatMessagePayload = buildChatMessagePayload;
exports.getFcmToken = getFcmToken;
exports.buildDiscountCodePayload = buildDiscountCodePayload;
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
const CHAT_PREVIEW_MAX_LEN = 80;
/**
 * FCM payload for a new in-ride chat message.
 * Recipient is inferred server-side from ride participants; client uses data.screen === "chat".
 */
function buildChatMessagePayload(rideId, rawText, senderIsCustomer) {
    const preview = rawText.length <= CHAT_PREVIEW_MAX_LEN
        ? rawText
        : `${rawText.slice(0, CHAT_PREVIEW_MAX_LEN)}…`;
    const who = senderIsCustomer ? "Je passagier" : "Je chauffeur";
    return {
        title: "Nieuw bericht",
        body: `${who}: ${preview}`,
        data: {
            rideId,
            screen: "chat",
        },
    };
}
/**
 * Fetches the FCM token for a user from Firestore.
 * Uses the role-specific field (fcmTokenDriver / fcmTokenCustomer) when provided,
 * falling back to the legacy fcmToken field for users who have not yet updated their app.
 */
async function getFcmToken(userId, role) {
    const doc = await admin.firestore().collection("users").doc(userId).get();
    if (!doc.exists)
        return null;
    const data = doc.data();
    if (role === "DRIVER") {
        return (data["fcmTokenDriver"] ?? null);
    }
    return (data["fcmTokenCustomer"] ?? null);
}
/**
 * Builds an FCM payload announcing a new discount code to riders.
 * The `screen` data field is set to "promotions" so the app can deep-link
 * directly to the Promotions tab when the notification is tapped.
 */
function buildDiscountCodePayload(code, value, type, description) {
    const valueLabel = type === "PERCENTAGE"
        ? `${value}% korting`
        : `SRD ${value} korting`;
    const body = description?.trim()
        ? `${description.trim()} — gebruik code ${code} in de app.`
        : `${valueLabel} op je rit. Gebruik code ${code} in de app.`;
    return {
        title: `Nieuwe kortingscode: ${code}`,
        body,
        data: { screen: "promotions" },
    };
}
/**
 * Sends an FCM push notification to a single user.
 * Pass recipientRole ("DRIVER" or "CUSTOMER") so the correct app-specific token is used.
 * Silently skips when the user has no registered token.
 */
async function sendToUser(userId, payload, recipientRole) {
    const token = await getFcmToken(userId, recipientRole);
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
                    alert: {
                        title: payload.title,
                        body: payload.body,
                    },
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