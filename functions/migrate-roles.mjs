/**
 * Eenmalig migratiescript: voegt isDriver en isCustomer boolean velden toe
 * aan alle bestaande gebruikersdocumenten in Firestore.
 *
 * Uitvoeren vanuit de functions/ map:
 *   node migrate-roles.mjs
 *
 * Vereiste omgevingsvariabelen:
 *   GOOGLE_APPLICATION_CREDENTIALS  – pad naar je Firebase service account JSON
 * Of: gebruik `firebase login` + Application Default Credentials.
 */

import { initializeApp, cert, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

async function migrateRoles() {
  const snapshot = await db.collection("users").get();

  if (snapshot.empty) {
    console.log("Geen gebruikers gevonden.");
    return;
  }

  const BATCH_SIZE = 400;
  let batch = db.batch();
  let count = 0;
  let skipped = 0;
  let total = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();

    // Sla over als de velden al bestaan (idempotent)
    if (data.isDriver !== undefined && data.isCustomer !== undefined) {
      skipped++;
      continue;
    }

    const roleStr = (data.role ?? "").toUpperCase();
    let isDriver = false;
    let isCustomer = false;

    if (roleStr === "DRIVER") {
      isDriver = true;
      isCustomer = false;
    } else if (roleStr === "CUSTOMER") {
      isDriver = false;
      isCustomer = true;
    } else if (roleStr === "ADMIN") {
      isDriver = false;
      isCustomer = false;
    } else {
      // Onbekende of lege role: behandel als customer (veiligste default)
      isDriver = false;
      isCustomer = true;
    }

    batch.update(doc.ref, { isDriver, isCustomer });
    count++;
    total++;

    // Commit per 400 schrijfoperaties (Firestore batch max = 500)
    if (count === BATCH_SIZE) {
      await batch.commit();
      console.log(`  Batch gecommit: ${total} gebruikers bijgewerkt...`);
      batch = db.batch();
      count = 0;
    }
  }

  // Commit resterende schrijfoperaties
  if (count > 0) {
    await batch.commit();
  }

  console.log(`\nMigratie voltooid:`);
  console.log(`  Bijgewerkt : ${total}`);
  console.log(`  Overgeslagen: ${skipped} (velden bestonden al)`);
}

migrateRoles().catch((err) => {
  console.error("Migratie mislukt:", err);
  process.exit(1);
});
