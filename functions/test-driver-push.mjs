/**
 * Test script — sends a "new ride available" push notification to all drivers
 * whose Firestore document has an fcmToken (regardless of online status).
 *
 * Usage:
 *   node functions/test-driver-push.mjs
 *
 * Requires: GOOGLE_APPLICATION_CREDENTIALS or firebase-admin default credentials.
 * Run from the project root so the Admin SDK can auto-detect the project.
 */

import { createRequire } from "module";
const require = createRequire(import.meta.url);

const admin = require("./node_modules/firebase-admin/lib/index.js");

admin.initializeApp({ projectId: "true-road-adventures" });

const db = admin.firestore();
const messaging = admin.messaging();

const TEST_RIDE_ID = "test-push-" + Date.now();

const payload = {
  notification: {
    title: "🚗 Test: Nieuwe rit beschikbaar",
    body:  "Dit is een testmelding van de TRA admin. Tik om te openen.",
  },
  data: {
    rideId: TEST_RIDE_ID,
    screen: "home",
  },
  apns: {
    payload: {
      aps: {
        alert: {
          title: "🚗 Test: Nieuwe rit beschikbaar",
          body:  "Dit is een testmelding van de TRA admin. Tik om te openen.",
        },
        sound: "default",
        badge:  1,
      },
    },
  },
};

async function run() {
  console.log("Fetching drivers from Firestore…");

  const snap = await db
    .collection("users")
    .where("role", "==", "DRIVER")
    .get();

  if (snap.empty) {
    console.log("No driver documents found.");
    return;
  }

  const tokens = snap.docs
    .map((d) => ({ id: d.id, token: d.data().fcmToken }))
    .filter((d) => typeof d.token === "string" && d.token.length > 0);

  console.log(`Found ${snap.size} driver(s), ${tokens.length} with FCM token.`);

  if (tokens.length === 0) {
    console.log(
      "No FCM tokens stored yet. " +
      "Make sure a driver has logged in on a physical device and granted push permission."
    );
    return;
  }

  for (const { id, token } of tokens) {
    try {
      const msgId = await messaging.send({ ...payload, token });
      console.log(`  ✓ driver ${id}  →  messageId: ${msgId}`);
    } catch (err) {
      console.error(`  ✗ driver ${id}  →  ${err.message}`);
    }
  }

  console.log("Done.");
}

run().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
