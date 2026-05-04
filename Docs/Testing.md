## Testplan

- `xcodebuild test -scheme "True Road Adventures" -destination 'platform=iOS Simulator,name=iPhone 16'`
- Unit tests: `True Road AdventuresTests/ApiClientTests.swift` dekt API-decodering en offline-pad in `RideService`.
- Handmatig: auth (login/register/reset), push permissie, ride lifecycle (aanvragen, accept, status updates), offline gedrag (toggle vliegtuigstand), payment (test key), navigation reroute (bewegend met gesimuleerde locatie).

## QA checklijst

- Rider: nieuwe rit, geplande rit, annuleren, ETA, tariefberekening.
- Driver: online toggle, beschikbare rit accepteren, statusflow tot completion.
- Push: device token upload en ontvangst (APNs sandbox/production).
- Maps: Google vs Apple provider (config MAP_PROVIDER), route laden en off-route herberekening.
- Payments: payment sheet toont met test/life sleutel, correcte status in backend.
- Netwerk: offline foutmeldingen in RideService (beschikbare knoppen disabled door networkMonitor).
