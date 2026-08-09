# True Road Adventures

A ride-hailing platform (rider + driver, Suriname / Dutch-language) consisting of:

- **iOS app** (`True Road Adventures.xcodeproj`, Swift/SwiftUI) — the primary product, with separate Rider and Driver targets. See `Docs/Targets.md`, `Docs/Structure.md`, `Docs/TestPlan.md`.
- **Firebase backend**: Cloud Functions (`functions/`, TypeScript, Node 20), Firestore rules/indexes, Storage rules.
- **Admin scripts** (`scripts/`, `functions/*.mjs`) — Node + `firebase-admin` utilities (seed admin, migrate roles, push tests).

## Cursor Cloud specific instructions

The Cloud VM is **Linux**, so the iOS app (Swift/Xcode) **cannot be built or run here** — it requires macOS + Xcode. The runnable/testable scope in this environment is the **Firebase backend** (`functions/`) and the **admin scripts** (`scripts/`).

### Tooling notes (non-obvious)

- The on-PATH `node` (`/exec-daemon/node`) differs from the nvm npm, which makes npm's default global prefix resolve to `/` (causes `EACCES` on `npm install -g`). This is already worked around: the npm global prefix is set to `~/.npm-global` (in `~/.npmrc`) and `~/.npm-global/bin` is on `PATH` via `~/.bashrc`. `firebase-tools` is installed there. New non-login shells may not have the PATH entry — run `export PATH="$HOME/.npm-global/bin:$PATH"` if `firebase` is not found.
- A harmless warning prints on most npm/node commands: `Your user's .npmrc file ... has a globalconfig and/or prefix setting, which are incompatible with nvm`. Ignore it.
- `functions/` targets Node 20 but the host runs Node 22; the emulator prints a version-mismatch warning and proceeds fine. `npm run build` (tsc) and the emulators both work on Node 22.

### Build / lint / run

- **Build + typecheck functions** (the strict `tsconfig.json` with `noUnusedLocals` doubles as the lint gate; there is no separate ESLint config): `npm --prefix functions run build`. Note `functions/lib/` is committed build output — `git checkout -- functions/lib` after building if you don't intend to commit regenerated JS.
- **Run the backend locally** with the Firebase emulator suite. Always use a `demo-` project id so it runs fully offline without GCP credentials, and pass `--only functions,firestore` (no `.firebaserc` exists in the repo):

  ```
  firebase emulators:start --only functions,firestore --project demo-trueroad
  ```

  Emulator UI on `:4000`, Functions on `:5001`, Firestore on `:8080`. Java (required by the Firestore emulator) is preinstalled.
  - `syncDriverAvailability` (a `pubsub`/scheduler function) is skipped unless the pubsub emulator is also enabled — expected.
  - FCM/messaging is **not** emulated. Trigger functions that only touch Firestore (e.g. `onReferralApplied`, `redeemDiscountCode`) run end-to-end offline; functions that call `admin.messaging()` will fail to actually deliver pushes without real credentials.

- **Exercise a function end-to-end**: write to Firestore from a small `firebase-admin` script with `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` and `projectId: "demo-trueroad"`. ESM scripts must live where `firebase-admin` is installed (e.g. inside `scripts/`) so module resolution works. Example proven flow: create a `users/{id}` doc with `referralCode`, then create another `users/{id}` with `referredBy=<code>` → `onReferralApplied` increments the referrer's `rideCredits` by 10.

- **Admin scripts** (`scripts/seed_admin.js`, `functions/migrate-roles.mjs`, `functions/test-driver-push.mjs`) talk to a **real** Firebase project and need service-account credentials (`GOOGLE_APPLICATION_CREDENTIALS`). They are not runnable against live infrastructure in the cloud VM without those secrets.
