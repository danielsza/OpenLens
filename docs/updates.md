# Auto-updates (Sparkle)

OpenLens uses [Sparkle 2](https://sparkle-project.org) — the standard Mac
auto-updater. Each GitHub Release publishes an `appcast.xml`; the app checks
`https://github.com/danielsza/OpenLens/releases/latest/download/appcast.xml`
and offers updates in-app (**OpenLens ▸ Check for Updates…**, plus automatic
checks).

**Why this kills the Gatekeeper nag:** only files downloaded by a browser get
the quarantine attribute. Sparkle installs updates directly, so after the
one-time first install (right-click ▸ Open), updates apply with no warnings.
(A paid Apple Developer ID + notarization would remove even the first-install
warning — later, if desired.)

## Keys

The update-signing keypair was generated on 2026-07-23:

- **Public key** — committed at `scripts/sparkle_public_key.txt` and embedded
  in the app as `SUPublicEDKey` at build time.
- **Private key** — local only, at `scripts/sparkle_private_key.SECRET.txt`
  (gitignored). It must live in GitHub as the `SPARKLE_PRIVATE_KEY` Actions
  secret; the Release workflow signs each update zip with it (Ed25519 over the
  archive bytes — exactly what Sparkle verifies against `SUPublicEDKey`).

### Finishing setup (one manual step)
GitHub secrets can only be added by a repo admin:

1. Open https://github.com/danielsza/OpenLens/settings/secrets/actions
2. **New repository secret** → Name: `SPARKLE_PRIVATE_KEY`,
   Value: the single line inside `scripts/sparkle_private_key.SECRET.txt`.
3. Keep the SECRET file somewhere safe (it's your only copy — losing it means
   shipping a new public key in an update users must install manually).

## Shipping a release
```bash
git tag v0.1.0 && git push origin v0.1.0
```
The workflow tests, builds `OpenLens.app`, signs the zip, and publishes the
Release + appcast. Users on any older version get the update in-app.
