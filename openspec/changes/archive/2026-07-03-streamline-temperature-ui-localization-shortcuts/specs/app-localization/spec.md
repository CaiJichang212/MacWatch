## ADDED Requirements

### Requirement: Application supports system, Chinese, and English language modes
The application SHALL provide language choices for Follow System, 中文, and English. The default for new and migrated installations SHALL be Follow System.

#### Scenario: New installation starts
- **WHEN** no language preference has been saved
- **THEN** the application uses Follow System mode

#### Scenario: Existing settings without language are loaded
- **WHEN** persisted settings from an earlier version do not contain a language field
- **THEN** all existing settings are preserved and language is migrated to Follow System

### Requirement: Follow System resolves to a supported localization
In Follow System mode, the application SHALL use Simplified Chinese when the effective macOS language matches the bundled Simplified Chinese localization and SHALL otherwise use English as the supported fallback.

#### Scenario: macOS prefers Simplified Chinese
- **WHEN** Follow System is selected and macOS resolves the application language to Simplified Chinese
- **THEN** the application displays its user-facing text in Simplified Chinese

#### Scenario: macOS prefers an unsupported language
- **WHEN** Follow System is selected and the effective macOS language is not bundled
- **THEN** the application displays its user-facing text in English

### Requirement: Language changes take effect immediately
Changing the language setting SHALL update all open SwiftUI surfaces, AppKit-owned window titles, Popup actions, and application menu commands without restarting the process. Surfaces opened after the change SHALL use the selected language.

#### Scenario: User switches from English to Chinese
- **WHEN** the user selects 中文 while the Dashboard, Settings, or Popup is visible
- **THEN** visible user-facing text updates to Simplified Chinese without relaunching the application

#### Scenario: User opens a window after switching language
- **WHEN** the user changes language and subsequently opens Dashboard or Settings
- **THEN** the new window uses the selected language

### Requirement: Language preference persists
The application SHALL save the selected language mode with other application settings and restore it on the next launch.

#### Scenario: User relaunches after selecting English
- **WHEN** the user selects English, quits, and relaunches MacWatch
- **THEN** the application remains in English mode

### Requirement: User-facing text is localized as a complete surface
All user-facing labels, actions, statuses, reasons, alerts, window titles, menu commands, temperature formatting labels, first-run content, compatibility content, Dashboard, Popup, Settings, and detail views SHALL have English and Simplified Chinese localizations. Internal metric identifiers, CLI JSON field names, logs, and acceptance protocol identifiers SHALL remain stable and SHALL NOT be translated.

#### Scenario: Chinese mode shows an abnormal reading
- **WHEN** 中文 is selected and a metric becomes unsupported, read-failed, or stale
- **THEN** its status and user-facing reason are displayed in Simplified Chinese while internal identifiers remain unchanged

