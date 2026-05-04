/**
 * fix_pending_driver.js
 *
 * Sets a user's role to DRIVER with isApproved: false so they appear
 * in the admin pending-drivers list.
 *
 * Usage:
 *   node scripts/fix_pending_driver.js
 *
 * Requires: GOOGLE_APPLICATION_CREDENTIALS env var pointing to your
 *           Firebase service account key JSON file.
 */

const admin = require("./node_modules/firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();

const TARGET_EMAIL = "raffaelloclarck@gmail.com";

async function fixPendingDriver() {
  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(TARGET_EMAIL);
  } catch (e) {
    console.error(
      `User ${TARGET_EMAIL} not found in Firebase Auth.\n` +
        `Make sure this account has signed in via the app at least once.`
    );
    process.exit(1);
  }

  const uid = userRecord.uid;
  console.log(`Found user: ${uid} (${TARGET_EMAIL})`);

  const ref = db.collection("users").doc(uid);
  const doc = await ref.get();

  if (doc.exists) {
    const data = doc.data();
    console.log(`Current Firestore data: role=${data.role}, isApproved=${data.isApproved}`);
    await ref.update({
      role: "DRIVER",
      isApproved: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`Updated → role: DRIVER, isApproved: false`);
  } else {
    await ref.set({
      email: TARGET_EMAIL,
      displayName: userRecord.displayName ?? "",
      role: "DRIVER",
      isApproved: false,
      isOnline: false,
      hasCompletedOnboarding: false,
      completedRides: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      preferredLanguage: "nl",
      marketingOptIn: false,
    });
    console.log(`Created new user document → role: DRIVER, isApproved: false`);
  }

  console.log(`Done. ${TARGET_EMAIL} will now appear in the admin pending-drivers list.`);
  process.exit(0);
}

fixPendingDriver().catch((e) => {
  console.error(e);
  process.exit(1);
});
