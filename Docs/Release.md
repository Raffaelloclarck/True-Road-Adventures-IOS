## Release checklist (Driver & Rider)

1) **Config & keys**
- Vul `True Road Adventures/Configs/*.xcconfig` met echte API/push/payment keys.
- Zet `MAP_PROVIDER` (google/apple) en bundle IDs per target.
- Voeg `GoogleService-Info-Driver.plist` en `GoogleService-Info-Rider.plist` productievarianten toe.

2) **Signing**
- Zorg dat `DEVELOPMENT_TEAM` in projectinstellingen klopt.
- Voor productieprofielen: stel `PROVISIONING_PROFILE_SPECIFIER` per target (Rider, Driver).
- Bump versies: `MARKETING_VERSION` (semver) en `CURRENT_PROJECT_VERSION` (build).

3) **Build & test**
- `xcodebuild -scheme "True Road Adventures" -configuration Release -destination 'generic/platform=iOS' clean build`
- `xcodebuild test -scheme "True Road Adventures" -destination 'platform=iOS Simulator,name=iPhone 16'`

4) **App Store / TestFlight**
- Archive per target (Rider en Driver) en upload met Organizer/`xcodebuild -exportArchive`.
- Voeg App Store metadata en screenshots toe; iconen staan in `Assets.xcassets/DriverAppIcon.appiconset` en `Assets.xcassets/RiderAppIcon.appiconset`.

5) **Observability**
- Backend moet push token endpoint (`PUSH_UPLOAD_URL`) accepteren met Bearer token (PushService).
- Controleer analytics events in `RideService` (ride lifecycle) en payment status.

6) **Smoke tijdens review**
- Rider: login, rit aanvragen, annuleren, geplande rit, payment sheet tonen.
- Driver: online toggle, rit accepteren, statusflow, ETA updates, off-route reroute.
