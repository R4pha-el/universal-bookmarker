# Security

This is a development build. Tests exercise ownership and retry rules but do not replace deployed-service review or signed-device validation.

Do not include access tokens, email codes, refresh tokens, service-role keys, signing credentials, or personal library content in issues, pull requests, screenshots, or logs. Client publishable keys identify a Supabase project; authenticated ownership and row policies enforce access. Service-role credentials belong only in the server function environment.

For a suspected vulnerability involving account access or saved content, use GitHub's **Report a vulnerability** option if private reporting is enabled. If unavailable, ask the repository owner to establish a private channel before sharing reproduction details. Do not post exploit details or private data publicly.

See [architecture](docs/architecture.md) and the [backend contract](docs/backend-contract.md) for security boundaries. Deployment operators must verify production authentication, email delivery, function secrets, storage policies, and deletion with disposable accounts before release.
