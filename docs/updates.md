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

## One-time setup (Daniel)

1. **Generate the signing keys** (updates are EdDSA-signed so only we can ship
   them). After a local build:
   ```bash
   cd "/Users/daniel/Documents/claude aperture/OpenLens"
   SPARKLE_BIN="$(find .build -type d -name bin -path "*parkle*" | head -1)"
   "$SPARKLE_BIN/generate_keys"
   ```
   This prints a **public key** and stores the private key in your Keychain.
   Export the private key for CI:
   ```bash
   "$SPARKLE_BIN/generate_keys" -x /tmp/sparkle_private_key
   cat /tmp/sparkle_private_key   # copy this
   ```

2. **Save the keys**:
   - Put the *public* key in the repo:
     `echo "PASTE_PUBLIC_KEY" > scripts/sparkle_public_key.txt` and commit.
   - Put the *private* key in GitHub: repo **Settings ▸ Secrets and variables ▸
     Actions ▸ New repository secret**, name `SPARKLE_PRIVATE_KEY`, value =
     contents of `/tmp/sparkle_private_key`. Then `rm /tmp/sparkle_private_key`.

3. **Ship**: `git tag v0.1.0 && git push origin v0.1.0`. The Release workflow
   tests, builds, signs the zip, and attaches `appcast.xml`. From then on,
   every new tag (v0.1.1, v0.2.0…) is offered to users automatically.

Until the keys exist, everything still works — releases just publish an
unsigned appcast (Sparkle requires the signature once a public key is embedded,
so do steps 1–2 before tagging the first release users install).
