## ADDED Requirements

### Requirement: Authenticated updates from GitHub Releases
The application MUST embed a pinned Sparkle 2 framework and expose a user-controlled automatic-update option plus a manual update check in Settings. The stable feed MUST be the `appcast.xml` asset of the latest ordinary GitHub Release; each archive URL MUST point to a specific version tag. The feed and archive MUST be authenticated with the embedded EdDSA public key before archive extraction. Private signing material MUST remain outside the repository and bundle. Synthetic launches MUST NOT start the updater. Update checks and installation relaunch MUST respect unresolved Google mutation recovery.

#### Scenario: Publish a compatible update
- **WHEN** a newer build with a valid signed appcast and archive is published to the stable GitHub channel
- **THEN** opted-in running applications discover it during scheduled checks, download it and use Sparkle's installation/relaunch flow while retaining user data

#### Scenario: Reject modified update material
- **WHEN** the archive signature does not match its content or the signed feed is invalid
- **THEN** the update is rejected before archive extraction and the installed application remains intact

### Requirement: Versioned unsigned-preview release preparation
Release tooling MUST support an explicit unsigned-preview mode with ad-hoc app signing, EdDSA update signatures, a truthful manifest, versioned DMG/ZIP, appcast and SHA-256 checksums. It MUST require a matching Keychain signing key and a strictly increasing build number for new distributed versions. Preparing these files MUST NOT create tags, upload assets or publish releases. It MUST preserve canonical internal Sparkle framework symlinks while rejecting other links, special files and writes beneath framework aliases before extraction.

#### Scenario: Prepare a preview without publishing
- **WHEN** the maintainer invokes the update preparation helper with the current app, release notes and a fresh output directory
- **THEN** it generates and verifies local artifacts and signed appcast without a GitHub mutation
- **AND** the manifest states ad-hoc signing and no Apple notarization

### Requirement: Explicit verified macOS installation

The app SHALL provide a source installer and DMG workflow for the architecture and minimum macOS version actually built. Installation SHALL verify bundle identity before replacing an application and preserve user cache, settings, local reminders, mutation journals and Google credentials.

#### Scenario: Safe repeated installation
- **WHEN** the owner repeats installation or upgrades an existing matching bundle
- **THEN** concurrent installation is prevented, the new candidate is verified before replacement, and failure restores the previous bundle without deleting application data

#### Scenario: Unsupported or foreign destination
- **WHEN** architecture/macOS requirements are not met, a different application occupies the destination, or the application is running
- **THEN** installation stops with an actionable message and neither force-quits the application nor changes the foreign bundle

### Requirement: Pinned release download and integrity

The release installer SHALL resolve an explicit version, validate downloaded archive integrity, bundle identity, architecture, minimum OS and the expected Developer ID Team ID before installation. It SHALL reject unsafe archive paths and SHALL NOT disable Gatekeeper, silently remove quarantine or perform Google/OAuth actions.

#### Scenario: Invalid download
- **WHEN** checksum, signature, publisher identity or archive safety validation fails
- **THEN** installation fails before replacing the installed application and retains the previous application and user data

### Requirement: Honest distribution acceptance

Packaging SHALL distinguish local ad-hoc packages, unsigned-preview packages and Developer ID signed/notarized distribution. Release scripts SHALL require explicit credentials and publication decisions; source push SHALL NOT implicitly publish a GitHub Release.

#### Scenario: Missing distribution credentials
- **WHEN** Developer ID or notarization credentials are unavailable
- **THEN** local installers and fixture checks remain usable but signed release acceptance remains explicitly open

#### Scenario: Signed release readiness
- **WHEN** a Developer ID signed distribution package is reported ready
- **THEN** its final signature, notarization ticket, image contents and checksums have been verified and a downloaded build has passed a clean-machine launch

### Requirement: Approved portable Finder artwork
The DMG MUST include the approved light-blue wave background with a central transfer arrow, a real draggable app at the left, the Applications shortcut at the right and the installation document below. The background MUST be embedded at Retina resolution and its Finder alias MUST resolve inside the mounted image after compression, without paths to the author's checkout.

#### Scenario: Open the image on another mountpoint
- **WHEN** the final compressed image is mounted read-only at a different temporary mountpoint
- **THEN** the native alias resolver locates its own embedded background and the app, Applications shortcut and instructions retain their configured positions
