# Release process

Releases are built only by the [release workflow](../.github/workflows/release.yml), never on a
developer machine.

For testing, the [build workflow](../.github/workflows/build.yml) builds installers for
Windows (x64), macOS (Apple silicon and Intel), and Linux (x64: AppImage, `.deb`, `.rpm`) on
every push to `main`, on pull requests, and on demand (**Actions → Build → Run workflow**). Each
platform's installers are kept as a workflow artifact (`installers-<platform>`) for 14 days.
Test builds are unsigned on Windows and signed ad hoc on macOS, so SmartScreen and Gatekeeper
warn; they are not for distribution.

## Cutting a release

1. Make sure `main` is green.
2. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [x.y.z] - YYYY-MM-DD`
   heading, following [Semantic Versioning](https://semver.org).
3. Bump `version` in the root `Cargo.toml` (`[workspace.package]`) and `package.json`.
4. Open a PR titled `chore(release): vx.y.z`, get it reviewed, and merge it.
5. Tag the merge commit and push the tag:
   ```sh
   git tag -s vx.y.z -m "TorrentStream vx.y.z"
   git push origin vx.y.z
   ```
6. The workflow builds and signs installers for Windows, macOS, and Linux (see
   [Code signing](#code-signing)), checks the signatures, then creates a **draft** GitHub release
   with the installers, `SHA256SUMS.txt`, a CycloneDX SBOM, and build provenance attestations.
7. Review the draft (download and smoke-test at least one installer per OS), paste the changelog
   section into the notes, and publish.

## Code signing

The release workflow signs whatever it has credentials for, then checks every signature
(`scripts/check-signatures.sh`) and lists them in the job summary. If signing is configured
and any file is not properly signed, the release fails.

| Platform | Configured                                                   | Not configured                    |
| -------- | ------------------------------------------------------------ | --------------------------------- |
| macOS    | Developer ID signature, hardened runtime, notarized, stapled | Ad hoc signature (no certificate) |
| Windows  | Authenticode, timestamped (app, FFmpeg sidecar, installers)  | Unsigned                          |
| Linux    | Not code signed: checksums and provenance attestations       | Same                              |

Store the secrets in the `release` environment (**Settings → Environments → release**) and add
yourself as a required reviewer there, so no release job can use them without approval. The
build workflow (pull requests, `main`) never gets them.

### macOS: Developer ID and notarization

Needs the [Apple Developer Program](https://developer.apple.com/programs/) (paid, yearly).

1. In Xcode (**Settings → Accounts → Manage Certificates → + → Developer ID Application**) or on
   the developer website with a certificate signing request, create a **Developer ID
   Application** certificate. Export it with its private key from Keychain Access as a `.p12`
   file with a strong password.
2. Create an app-specific password for your Apple Account at
   [account.apple.com](https://account.apple.com) (**Sign-In and Security → App-Specific
   Passwords**). Notarization uses it.
3. Add these secrets:

   | Secret                       | Value                                                                                |
   | ---------------------------- | ------------------------------------------------------------------------------------ |
   | `APPLE_CERTIFICATE`          | The `.p12` file, base64-encoded (`base64 -i cert.p12 \| pbcopy`)                     |
   | `APPLE_CERTIFICATE_PASSWORD` | The `.p12` password                                                                  |
   | `APPLE_SIGNING_IDENTITY`     | The certificate's name, such as `Developer ID Application: Name (TEAMID)`            |
   | `APPLE_ID`                   | The Apple Account's email address                                                    |
   | `APPLE_PASSWORD`             | The app-specific password                                                            |
   | `APPLE_TEAM_ID`              | The 10-character team ID ([Membership details](https://developer.apple.com/account)) |

All six are required together: a signed but not notarized app is still blocked by Gatekeeper, so
the workflow fails if only some are set.

Without them, the app is signed ad hoc. Apple silicon Macs refuse to open a downloaded app with
no signature at all ("damaged"); an ad hoc signed one opens after the user allows it once in
**System Settings → Privacy & Security → Open Anyway**.

### Windows: Artifact Signing (recommended)

Certificate authorities have issued code signing keys only on hardware tokens or cloud HSMs since
June 2023, so a new certificate usually cannot be exported to a `.pfx` file for CI. Microsoft's
[Artifact Signing](https://aka.ms/artifactsigning) (formerly Trusted Signing) keeps the
certificate in Azure and signs through `signtool`, at a monthly fee. It requires identity
validation; check Microsoft's current eligibility rules for organizations and individuals.

1. In an Azure subscription, create an **Artifact Signing account** and note its endpoint (for
   example `https://eus.codesigning.azure.net` for East US).
2. Complete **identity validation**, then create a **Public Trust** certificate profile.
3. Create an app registration (**Microsoft Entra ID → App registrations**) with a client
   secret, and give it the **Artifact Signing Certificate Profile Signer** role on the account.
4. Add these to the `release` environment:

   | Name                        | Kind     | Value                            |
   | --------------------------- | -------- | -------------------------------- |
   | `AZURE_TENANT_ID`           | secret   | The directory (tenant) ID        |
   | `AZURE_CLIENT_ID`           | secret   | The app registration's client ID |
   | `AZURE_CLIENT_SECRET`       | secret   | The client secret                |
   | `ARTIFACT_SIGNING_ENDPOINT` | variable | The account's endpoint           |
   | `ARTIFACT_SIGNING_ACCOUNT`  | variable | The account name                 |
   | `ARTIFACT_SIGNING_PROFILE`  | variable | The certificate profile name     |

The workflow downloads Microsoft's signing client (`Microsoft.ArtifactSigning.Client`, pinned by
version and SHA-256, and checked to be signed by Microsoft) and has Tauri sign each file with
`signtool` and Microsoft's timestamp server.

### Windows: exportable certificate

An older Authenticode certificate whose key can be exported still works: set
`WINDOWS_CERTIFICATE` (the `.pfx` file, base64-encoded) and `WINDOWS_CERTIFICATE_PASSWORD`. It is
timestamped with DigiCert's server. Set either this or Artifact Signing, not both.

### SmartScreen reputation

A valid signature removes the "unknown publisher" warning, but SmartScreen may still warn for a
new certificate until enough people have installed signed builds. Keep signing with the same
certificate profile so the reputation carries over.

### Releases without certificates

Until the certificates exist, releases are published unsigned (ad hoc on macOS). Their notes
must say so and explain how to open the app: on Windows, **More info → Run anyway** in the
SmartScreen prompt; on macOS, **Open Anyway** in **System Settings → Privacy & Security**.

## Verifying a download

```sh
# Check the checksum
sha256sum --check --ignore-missing SHA256SUMS.txt

# Check that the file was built by this repository's release workflow
gh attestation verify TorrentStream_x.y.z_x64-setup.exe --repo torrent-stream/torrentstream
```

Signed builds can also be checked with the operating system's tools:

```sh
# macOS: a Developer ID signature, notarized
codesign --verify --deep --strict --verbose=2 /Applications/TorrentStream.app
spctl --assess --type execute --verbose /Applications/TorrentStream.app

# Windows (PowerShell): Status should be Valid
Get-AuthenticodeSignature .\TorrentStream_x.y.z_x64-setup.exe | Format-List Status, SignerCertificate
```
