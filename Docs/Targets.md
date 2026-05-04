## Targets en schemas

- **Rider app**: `[True Road Adventures/True_Road_AdventuresApp.swift]` (#if RIDER) gebruikt `AppContainer(appMode: .customer)` en presenteert `CustomerRootView`.
- **Driver app**: `[True Road Adventures/DriverApp.swift]` (#if DRIVER) gebruikt `AppContainer(appMode: .driver)` en presenteert `DriverRootView`.
- **Gemeenschappelijke dependencies**: `AppContainer` levert `AuthService`, `PushService`, `LocationService`, `RideService`, `PaymentService`, `NavigationSessionManager`, `DirectionsClient`, `ApiClient`.
- **Environment injection**: beide targets registreren `AppDelegate` via `@UIApplicationDelegateAdaptor` voor push + Maps keys; environmentObjects worden doorgegeven vanuit container.

## Configuratiebestanden per target

- Globale configs: `[True Road Adventures/Configs/Debug.xcconfig]` en `[Release.xcconfig]` (API_BASE_URL, PAYMENT_PUBLIC_KEY, PUSH_UPLOAD_URL, MAP keys, bundle-id overrides).
- Rider-specifiek: `[True Road Adventures/Configs/Rider.Debug.xcconfig]`, `[Rider.Release.xcconfig]` (rider API/push endpoints, feature flags).
- Driver-specifiek: `[True Road Adventures/Configs/Driver.Debug.xcconfig]`, `[Driver.Release.xcconfig]` (driver API/push endpoints, feature flags).
- Firebase/Google: `GoogleService-Info-Rider.plist`, `GoogleService-Info-Driver.plist` moeten per target aan de bundle worden gekoppeld.

## Bundles en assets

- Bundle overrides vanuit xcconfig: `CUSTOMER_BUNDLE_ID = com.trueroadadventures.customer.ios`, `DRIVER_BUNDLE_ID = com.trueroadadventures.driver.ios`.
- App icon sets per target: `Assets.xcassets/DriverAppIcon.appiconset`, `Assets.xcassets/RiderAppIcon.appiconset` (nog te vullen met juiste resoluties); gedeelde `AppIcon.appiconset` bestaat maar bevat nog geen afbeeldingsbestanden.
- Launch screens: nog niet gedefinieerd; voeg per target toe (Storyboard/SwiftUI of asset catalog).

## Build settings / schemas (te controleren in Xcode)

- Activeer `DRIVER` / `RIDER` Swift compiler flags per respectieve target.
- Koppel juiste xcconfig aan Build Settings (Debug/Release per target) en verify Info.plist referenties.
- Push/Background modes: Remote notifications + Background location vereisen entitlements en capabilities per target.
- Signing: stel afzonderlijke provisioning profiles + Team in per bundle id.
