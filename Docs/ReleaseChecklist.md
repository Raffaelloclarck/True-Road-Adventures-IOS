## Release-checklist (iOS Rider & Driver)

### Signing & bundling
- [ ] Bundel-ID’s: `com.trueroadadventures.customer.ios`, `com.trueroadadventures.driver.ios`.
- [ ] Profielen/Certs: koppel juiste provisioning profiles per target (Debug/Release) en team.
- [ ] Swift flags: `RIDER` voor rider-target, `DRIVER` voor driver-target; check schema’s.

### Assets
- [ ] Vul `Assets.xcassets/DriverAppIcon.appiconset` en `RiderAppIcon.appiconset` met alle iOS resoluties (20–1024).
- [ ] Launch screens per target (Storyboard of SwiftUI view) + light/dark varianten.
- [ ] App privacy “nutrition label” data verzameling invullen.

### Info.plist / capabilities
- [ ] Privacy strings: NSLocationWhenInUseUsageDescription, NSLocationAlwaysAndWhenInUseUsageDescription, NSCameraUsageDescription (voor KYC), NSPhotoLibraryAddUsageDescription, NSMicrophoneUsageDescription (indien nodig), NSUserTrackingUsageDescription (indien ATT).
- [ ] Background modes: Location updates, Remote notifications (Driver app).
- [ ] Push entitlements: Remote notifications + APNS keys in App Store Connect.
- [ ] URL Schemes voor betalingsproviders (Stripe/Adyen), Google Sign-In / Apple Sign-In.

### Config & omgevingen
- [ ] Vervang placeholder API/keys in `.xcconfig` bestanden (prod/test) en koppel Info.plist build settings.
- [ ] Firebase: voeg juiste `GoogleService-Info-*.plist` per target en environment; enable Crashlytics + Analytics.
- [ ] Map keys (Google Maps/Places) actief op bundle-ID’s.

### Kwaliteit
- [ ] Run Unit/UI-tests: `RideServiceOfflineTests`, `RideRepositoryTests`, `ApiClientTests`; Xcode UI-tests voor happy/edge cases.
- [ ] Smoke op device: login, push toestemming, rit aanvragen/annuleren, driver accept → complete, offline gedrag.
- [ ] Performance: monitor main-thread hitches in heavy views; reduce network on main thread.

### Store voorbereiding
- [ ] App Store metadata: title/subtitle, keywords, description (NL/EN), privacy policy URL.
- [ ] Screenshots per device (5.5”, 6.5”, 6.7”) voor Rider & Driver flows.
- [ ] Age rating + content rights ingevuld.
- [ ] TestFlight groepen + interne testers; beta review notities (demo accounts).

### Release/rollback
- [ ] Versienummer/verhogen build; tag release.
- [ ] Opslaan changelog per target; noteer breaking changes.
- [ ] Rollback-plan: keep vorige build op TestFlight; feature flags voor risicovolle onderdelen.
