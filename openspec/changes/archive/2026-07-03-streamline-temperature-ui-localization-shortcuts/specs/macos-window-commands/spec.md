## ADDED Requirements

### Requirement: Close Window uses the standard macOS command
The application SHALL expose Close Window in the Window menu with the `⌘W` shortcut and route it through the current key window. Closing a main or settings window SHALL hide that window without terminating monitoring or the application process.

#### Scenario: User closes the main window
- **WHEN** the main window is key and the user presses `⌘W`
- **THEN** the main window closes while menu bar monitoring continues

#### Scenario: User closes Settings
- **WHEN** the Settings window is key and the user presses `⌘W`
- **THEN** the Settings window closes and can later be reopened as the same logical settings window

### Requirement: Settings uses the standard macOS command
The application SHALL expose Settings in the application menu with the `⌘,` shortcut. Invoking the command SHALL activate and front the existing Settings window or create it when absent.

#### Scenario: User opens Settings from the keyboard
- **WHEN** MacWatch is active and the user presses `⌘,`
- **THEN** exactly one Settings window becomes key and visible

### Requirement: Quit uses the standard macOS command
The application SHALL expose Quit MacWatch in the application menu with the `⌘Q` shortcut and terminate through the normal application lifecycle.

#### Scenario: User quits from the keyboard
- **WHEN** MacWatch is active and the user presses `⌘Q`
- **THEN** the application records its normal termination lifecycle and exits

### Requirement: No additional shortcuts are introduced
This change SHALL NOT assign new keyboard shortcuts beyond `⌘W`, `⌘,`, and `⌘Q`.

#### Scenario: User inspects application commands
- **WHEN** the revised application menus are presented
- **THEN** this change contributes only the three approved shortcut assignments

