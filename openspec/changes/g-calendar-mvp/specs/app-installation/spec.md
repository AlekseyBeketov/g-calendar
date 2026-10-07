## ADDED Requirements

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

Packaging SHALL distinguish local ad-hoc packages from Developer ID signed and notarized distribution. Release scripts SHALL require explicit credentials and publication decisions; source push SHALL NOT implicitly publish a GitHub Release.

#### Scenario: Missing distribution credentials
- **WHEN** Developer ID or notarization credentials are unavailable
- **THEN** local installers and fixture checks remain usable but signed release acceptance remains explicitly open

#### Scenario: Signed release readiness
- **WHEN** a distribution package is reported ready
- **THEN** its final signature, notarization ticket, image contents and checksums have been verified and a downloaded build has passed a clean-machine launch
