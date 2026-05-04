/**
 * seed_admin.js
 *
 * Sets up the admin account in Firestore.
 * Run once after the user has signed in at least once via the Rider app.
 *
 * Usage:
 *   npm install firebase-admin   (if not already installed)
 *   node scripts/seed_admin.js
 *
 * Requires: GOOGLE_APPLICATION_CREDENTIALS env var pointing to your
 *           Firebase service account key JSON file.
 *           Download it from: Firebase Console → Project Settings →
 *           Service Accounts → Generate new private key
 */

const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();

const ADMIN_EMAIL = "raffaelloclarck@trueroadadventures.com";

async function seedAdmin() {
  // Find the user by email in Firebase Auth
  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(ADMIN_EMAIL);
  } catch (e) {
    console.error(
      `User ${ADMIN_EMAIL} not found in Firebase Auth.\n` +
        `Make sure this account has signed in via the Rider app at least once.`
    );
    process.exit(1);
  }

  const uid = userRecord.uid;
  console.log(`Found user: ${uid} (${ADMIN_EMAIL})`);

  const ref = db.collection("users").doc(uid);
  const doc = await ref.get();

  if (doc.exists) {
    await ref.update({
      role: "ADMIN",
      isApproved: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`Updated existing user → role: ADMIN`);
  } else {
    await ref.set({
      email: ADMIN_EMAIL,
      displayName: userRecord.displayName ?? "Admin",
      role: "ADMIN",
      isApproved: true,
      isOnline: false,
      hasCompletedOnboarding: true,
      completedRides: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      preferredLanguage: "nl",
      marketingOptIn: false,
    });
    console.log(`Created new user document → role: ADMIN`);
  }

  console.log(`Done. ${ADMIN_EMAIL} can now log in as admin via the Rider app.`);
  process.exit(0);
}

seedAdmin().catch((e) => {
  console.error(e);
  process.exit(1);
});
