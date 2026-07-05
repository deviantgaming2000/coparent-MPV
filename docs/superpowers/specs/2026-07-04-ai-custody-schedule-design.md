# AI-Parsed Custody Schedule - Design

Date: 2026-07-04
Status: Approved, ready for implementation plan

## Goal

Replace the manual custody-schedule setup (pattern picker) with a natural-language flow.
The user types or dictates their schedule and its nuances, an on-device AI turns it into a structured schedule, and the app shows a preview to confirm before saving.
The saved schedule color-codes the calendar exactly as it does today.
The user can fine-tune the result by hand, and the feature degrades gracefully on devices without on-device AI.

## Context and constraints

- The app targets iOS 26.5, so Apple's on-device Foundation Models framework is available.
- The AI runs fully on device.
  No API key, no backend, no network, and no custody data leaves the phone.
  This matches the app's privacy stance ("your records stay private and secure").
- The existing `CustodySchedule` model already represents whole-day custody plus per-date overrides, so no model change is needed:
  - `anchorDate`, `caregivers: [CustodyCaregiver]`, `cycle: [String]` (one caregiver id per day of the repeating cycle), `overrides: [String: String]` (dateKey to caregiver id), `patternID`.
- `CustodyScheduleStore` persists the schedule, and the calendar already reads it to color days and mark exchanges.
  Those are reused unchanged.
- The current `CustodyScheduleView` (pattern picker, custom day painter, anchor `DatePicker`, live preview grid) is reused as the manual editor and the fallback, not discarded.
- Dictation reuses the existing `SpeechTranscriber`.
- Scope is whole-day assignments plus one-off date overrides (holidays).
  Partial-day (for example dinner visits) is out of scope.

## Components

### 1. Describe screen (`CustodyDescribeView`, new)

- A large multi-line text field with a guiding placeholder, for example "I have the kids Monday to Wednesday and every other weekend. My co-parent Jordan has them the rest. I get them Christmas."
- A mic button that toggles dictation via `SpeechTranscriber`, merging recognized text into the field.
- A primary button "Map my schedule" that runs the parser and advances to the preview.
- A small "Set it up manually instead" link that opens the manual editor directly.
- While parsing, the button shows a progress state.

### 2. Custody schedule parser (`CustodyScheduleParser.swift`, new)

- Protocol `CustodyScheduleParsing` with one async method: `parse(description: String, existingPeople: [SavedPerson], referenceDate: Date) async throws -> CustodyParseResult`.
- `CustodyParseResult` carries the mapped `CustodySchedule` plus a plain-English `summary` and a list of `holidayNotes` for the preview.
- `OnDeviceCustodyParser` (primary) uses `LanguageModelSession` with guided generation.
  It defines a `@Generable` output type so the model must return a typed structure rather than free text:
    - `cycleLengthDays: Int` (for example 7 or 14),
    - `days: [GenDay]` where each `GenDay` has a `dayIndex` and a `caregiverLabel`,
    - `caregivers: [GenCaregiver]` where each has a `label` and a `role` (you / co-parent / other),
    - `startHint: String` (for example "this week", "next Monday", or a described anchor),
    - `holidays: [GenHoliday]` where each has a `name` or explicit date phrase and a `caregiverLabel`.
  Each field carries a `@Guide` description so the model fills it correctly.
- `HeuristicCustodyParser` (fallback) recognizes a few common phrasings (week on / week off, 2-2-3, every other weekend) by keyword, for when on-device AI is unavailable but the phrase is simple.
  If it cannot parse, it signals that the manual editor should be used.

### 3. Mapping layer (in `CustodyScheduleParser.swift`)

- Converts the `@Generable` output into a `CustodySchedule`:
  - Resolves "me" / "I" / "you" to the stable `CustodyCaregiver.youID`, and maps other labels to caregivers, matching existing `SavedPerson` names where possible and assigning palette color indexes.
  - Builds `cycle` as one caregiver id per day for the cycle length.
  - Resolves the `startHint` to an `anchorDate` (defaulting to the start of the week containing `referenceDate` when the hint is vague).
  - Resolves fixed holiday names (Christmas, New Year's Day, Independence Day, Thanksgiving, and similar) to real dates for the upcoming occurrence and writes them into `overrides`.
    Holiday phrases that are not recognizable to a fixed date are surfaced in `holidayNotes` so the user can add them by editing, rather than guessed.
- The mapping is pure and independently testable, separate from the model call.

### 4. Preview screen (`CustodyPreviewView`, new)

- Header "Here's what we heard".
- A colored week (or cycle) grid using the existing custody palette, showing who has each day.
- A plain-English summary line and a list of holiday overrides (and any `holidayNotes` that need manual attention).
- A "Starts the week of [date]" control that shifts the `anchorDate` by whole weeks (and a date picker), so the repeating cycle lines up with real life.
- Buttons: "Save" (writes via `CustodyScheduleStore.save`, the calendar updates), "Edit manually" (opens the manual editor pre-filled with this schedule), and "Re-describe" (returns to the describe screen).

### 5. Manual editor and fallback (reuse `CustodyScheduleView`)

- "Edit manually" opens the existing `CustodyScheduleView`, pre-filled from the current or AI-produced schedule, so manual fine-tuning is the same familiar screen.
- On devices where `SystemLanguageModel.default.availability` is not `.available`, the Describe screen shows a short note and routes to the manual editor, so the feature always works.

### 6. Menu entry

- The menu's "Custody schedule" row opens the Describe screen when no schedule exists, or a compact current-schedule view (summary plus preview) with "Re-describe" and "Edit manually" when one exists.
- Turning the schedule off still clears it via `CustodyScheduleStore.clear()`.

## Data flow

1. The user types or dictates a description and taps "Map my schedule".
2. `OnDeviceCustodyParser` (or the heuristic fallback) returns a `CustodyParseResult` containing a mapped `CustodySchedule`, a summary, and holiday notes.
3. The preview shows the colored week, summary, holidays, and a start-week control.
4. The user adjusts the start week if needed and taps "Save", or opens the manual editor, or re-describes.
5. "Save" writes to `CustodyScheduleStore`, and the calendar reflects the colors and exchanges immediately.

## Error handling

- On-device model not available: the Describe screen notes it and routes to the manual editor.
- The model returns an empty or unusable result: show "I couldn't quite get that. Try rephrasing, or set it up manually." with the manual option.
- Ambiguity is caught by the human: nothing is saved until the user confirms the preview.
- Dictation errors reuse the existing `SpeechTranscriber` handling (a brief caption), and typing always remains available.

## Testing

- The mapping layer is unit-testable in isolation: given a fixed `@Generable`-shaped input, it produces the expected `CustodySchedule` (cycle, anchor, overrides, caregivers).
  This is the highest-value test and does not require the model.
- Foundation Models runs on device and on the simulator only when the host Mac supports Apple Intelligence; where it is unavailable, verify the fallback path (Describe routes to manual) and that the app never blocks.
- End to end on a supported device: describe a week-on / week-off schedule with a Christmas override, confirm the preview colors and the saved calendar, then edit manually and confirm the change persists.

## Out of scope for this pass

- Partial-day or time-of-day custody (for example dinner visits).
- Guessing personal dates the user did not state (for example birthdays).
- Any cloud or API-based model; a backend proxy remains a future option only for heavier features, never a key embedded in the app.
- Multi-year holiday expansion beyond the upcoming occurrence.
