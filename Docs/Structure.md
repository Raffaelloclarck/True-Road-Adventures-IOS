## Projectstructuur (georganiseerd)

- `Features/Driver/` – driver flows (`DriverRootView`, `DriverHomeView`).
- `Features/Rider/` – rider flows (`CustomerRootView`, `CustomerHomeView`).
- `Features/Common/Auth/` – gedeelde auth flow (`AuthFlowView`).
- `Features/Common/Home/` – gedeelde demo/home entry (`HomeView`).
- `Services/` – API, Auth, Location, Navigation, Payments, Push, Rides, Network monitor, Analytics.
- `DesignSystem/` – kleuren/typografie tokens.
- `Models/` – domeinmodellen (Ride, User, etc.).
- `Storage/` – Keychain/userdefaults abstraction.
- `Configs/` – xcconfig per target (Rider/Driver, Debug/Release).
- `Docs/` – checklist, feature-gaps, targets, tests, structuur.
