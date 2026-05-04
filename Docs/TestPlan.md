## Testmatrix

### Unit
- `RideService`: request/accept/status lifecycle, fare updates, offline guard (zie `RideServiceOfflineTests`).
- `RideRepository`: create/accept, streams, fare updates.
- `AppConfig`: defaults + key presence.

### Integratie (simulatie)
- Rider flow: login/register → rit aanvragen (direct/ gepland) → status updates → annuleren.
- Driver flow: login → online toggle → rit accepteren → statusprogressie → finalize.
- Locatie: Rider/Driver locatie-update weerspiegelt in actieve rit.
- Push/Permissies: Aanvragen push + remote token upload happy/failure.
- Payments: PaymentService stub draait zonder crash wanneer key aanwezig.

### UI-tests (aanpak)
- AuthFlowView: login/registratie toggles, error tonen.
- CustomerHomeView: rideForm disabled bij offline (NetworkMonitor injectie).
- DriverHomeView: accept-button disabled bij offline, statusknoppen werken.

### Niet-functioneel
- Offline: ride-acties blokkeren; UI melding.
- Background: LocationService start/stop zonder crash; app lifecycle smoke.
- Accessibility: labels hebben tekst, buttons toegankelijk (handmatige check).

### Testdata/fixtures
- Seed users: `demo-driver`, `demo-customer` met wachtwoord `password` (InMemoryAuthRepository).
- LatLng demo: Dam Square → Schiphol.
