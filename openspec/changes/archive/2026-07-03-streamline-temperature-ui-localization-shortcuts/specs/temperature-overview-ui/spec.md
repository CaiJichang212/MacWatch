## ADDED Requirements

### Requirement: Popup prioritizes current hardware temperatures
The Popup SHALL present the current hottest temperature and one compact row for each tracked hardware domain. A normal row SHALL show the hardware name, primary temperature, and CPU/GPU average temperature when available, but SHALL NOT show a normal-status label, data source, or row-specific update time.

#### Scenario: All Popup readings are normal
- **WHEN** all tracked domains have current valid readings
- **THEN** the Popup shows the hottest value and compact hardware temperature rows without `Valid`, source, or per-row timestamp text

#### Scenario: CPU or GPU has an average reading
- **WHEN** a CPU or GPU primary and average temperature are both available
- **THEN** the Popup shows the primary temperature and the average temperature in the same hardware row

### Requirement: Popup reports freshness once
The Popup SHALL show one overall last-updated time derived from the overview snapshot and SHALL NOT repeat update times for individual normal rows.

#### Scenario: Popup has recently sampled data
- **WHEN** the Popup renders an overview containing sampled readings
- **THEN** exactly one overview update time is visible

### Requirement: Dashboard prioritizes temperature values
The Dashboard SHALL show the current hottest temperature and one selectable card per tracked hardware domain. A normal card SHALL show the hardware name, primary temperature, and CPU/GPU average temperature when available, but SHALL NOT show a normal-status label, source, or card-specific update time.

#### Scenario: Dashboard readings are normal
- **WHEN** the Dashboard renders valid readings for all tracked domains
- **THEN** each card contains temperature-focused content without `Valid`, source, or per-card timestamp text

### Requirement: Dashboard reports freshness once
The Dashboard SHALL show one overview-level update time near the hottest-temperature summary and SHALL NOT repeat update times on normal metric cards.

#### Scenario: Dashboard has recently sampled data
- **WHEN** the Dashboard renders an overview containing sampled readings
- **THEN** exactly one overview update time is visible above the hardware cards

### Requirement: Abnormal readings remain explicit
Popup and Dashboard SHALL distinguish `unsupported`, `readFailed`, and `stale` readings from valid temperatures. An abnormal row or card SHALL show a localized user-facing status and necessary reason, SHALL NOT show a misleading valid value, and SHALL NOT show the normal-status label when the reading recovers.

#### Scenario: Hardware metric is unsupported
- **WHEN** a tracked metric is unsupported on the current Mac
- **THEN** its row or card shows the localized unsupported state and reason instead of a temperature value

#### Scenario: Hardware read fails
- **WHEN** the latest read for a tracked metric fails
- **THEN** its row or card shows the localized read-failed state and reason without affecting other metrics

#### Scenario: Hardware reading is stale
- **WHEN** a tracked metric exceeds the freshness threshold
- **THEN** its row or card is visibly de-emphasized and shows the localized stale state rather than presenting the last value as current

### Requirement: Overview layouts use compact adaptive spacing
The Popup and Dashboard SHALL reduce unused space while preserving readable grouping, pointer targets, and temperature hierarchy. The Dashboard SHALL adapt its grid column count to the available width, and the main window SHALL remain resizable above a minimum size that does not clip primary content.

#### Scenario: Popup displays all tracked domains
- **WHEN** all tracked domains are present
- **THEN** the Popup fits its summary, rows, and actions without large metadata-driven gaps

#### Scenario: Main window is resized
- **WHEN** the user resizes the Dashboard within its supported bounds
- **THEN** hardware cards reflow without clipping their names, temperatures, or abnormal states

### Requirement: Detail pages retain diagnostic context
Each hardware detail page SHALL continue to expose current value, trend, statistics, data source, sampling information, last read state, and relevant timestamps. Detail-page visual changes SHALL be limited to alignment, spacing, and localized wording consistent with the revised overview.

#### Scenario: User opens a hardware detail page
- **WHEN** the user selects a hardware card or sidebar metric
- **THEN** the detail page provides the richer diagnostic and trend information omitted from Popup and Dashboard

