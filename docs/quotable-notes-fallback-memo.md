# Quotable Notes Fallback Memo

## Intent

The quote-note dropdown in lesson questions could become empty even when users
had quote-enabled notes. A frequent pattern was that newly created notes were
found, while older notes were not.

To keep risk low, we only added a fallback on the **own notes** stream.

## What changed

- Keep existing strict own-note query (`courseId` + `lessonNumber`) as-is.
- Add a second own-note fallback query scoped by
  `courseTitle` + `lessonTitle`.
- Merge strict and fallback results by note id before rendering.
- Keep final post-time validation unchanged (strict checks still run).
- Add a loading field for quote notes so users do not see temporary "no items"
  while streams are still loading.

## Why this is safe

- Public-note query logic was not relaxed (Firestore rules there are strict).
- Posting rules and validation are unchanged, so invalid quotes are still blocked.
- Fallback only improves discoverability in the UI for legacy data shape
  differences.

## Caution for future changes

If you later migrate legacy note documents (id/scope fields), remove the title
fallback carefully and validate:

1. quote dropdown population on old and new notes
2. question post with quote
3. answer post with quote
4. teacher-only/public visibility edge cases
