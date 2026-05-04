## Feature-overzicht (Driver vs Rider)

### Gedekt nu
- **Rit aanvragen / accepteren**: Rider kan rit (optioneel gepland) aanmaken; Driver ziet beschikbare ritten met geplande tijd, kan accepteren; status-updates (arrived/pickedUp/completed/cancelled) werken bidirectioneel.
- **Locatie delen**: Rider en Driver kunnen locatie-updates sturen; Driver-location updates volgen ride lifecycle en tonen fouten bij offline.
- **Offline guards**: Alle ride-acties checken netwerk (via `NetworkMonitor`); UI disableert knoppen bij offline en toont statusfeedback.
- **Push/locatie permissies**: Eén plek om push- en locatiepermissies op te vragen vanuit home-schermen.
- **ETA/tarieven**: ETA en (realtime/finale) tarief tonen in actieve rit voor rider; driver kan finale status afronden.

### Openstaande gaten
- **Echte backend/Firebase**: ApiClient/Repositories zijn in-memory; vervang door echte backend/Firebase sync + auth, inclusief retries en security.
- **Kaart & turn-by-turn UI**: Geen live kaart/routevisualisatie in de UI; NavigationSessionManager berekent wel routes maar heeft geen zichtbare view.
- **Betalingen**: PaymentService heeft alleen stub; voeg Stripe/Adyen in-app PaymentSheet + opslaan betaalmethode + betaalstatus events.
- **Identity/compliance**: Geen KYC/KYB, geen rijbewijs/verzekering-upload voor drivers; geen SMS/e-mail verificatie voor riders.
- **Push en topics**: FCM-token wordt wel geregistreerd, maar er is geen topic/ride-subscriptie of in-app notificatie surface.
- **Earnings/rapportage**: Geen driver-earnings overzicht, dag/week rapporten of uitbetalingsflow.
- **Multi-language & accessibility**: Geen dynamische taalkeuze of VoiceOver-aandacht; labels zijn NL-only.
- **Error states**: UI toont basisfouten, maar geen retry-knoppen, skeletons of guidance (bijv. payment failed, driver no-show).
- **Store readiness**: Icons/launch screens ontbreken; privacy strings & App Tracking Transparency niet ingevuld; geen App Store metadata checklist.
