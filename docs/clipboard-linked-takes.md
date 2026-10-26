# clipboard history: linked takes

How a take with a collage and words becomes one clipboard history row, and how it pastes.


- **Model.** No schema change. The row is kind `.text`, source `.transcript`, with the collage in `imageFileName` (`ClipboardItem.isLinkedSession`). Fingerprint is `linked:<textHash>:<imageHash>`. Older builds read it as a mixed copy.
- **Migration.** On load, `ClipboardSessionLinkMigration` merges legacy pairs. A pair is a transcript row with no image and a screenshot row whose `firstCopiedAt` is within 1.5s (nearest, one to one). The words row keeps its id and gains the collage. Pinned is ORed. A conflicting `pinKey` leaves the pair alone. The index is rewritten once; a second load is a no-op. No image file is deleted.
- **Pin and delete** act on the one row, so on both parts. Delete removes the collage file.
- **Row.** 44pt tall. A 60x36 collage thumbnail in a 1pt Ink frame beside up to two lines of the words. The preview says "Contents: collage + words" and "Paste: picture, then words".
- **Pasteboard (copy, ⌥Enter, manual ⌘V).** Two `NSPasteboardItem`s. Item 1 has PNG, TIFF and an image-only RTFD (PNG bytes wrapped, no re-encode). Item 2 has the plain string. No HTML and no RTF of the words, because Chrome then prefers the HTML and drops the picture. Measured on macOS 26: a rich NSTextView pastes picture, newline, words. A plain text field pastes the words. Chrome exposes text/plain plus a PNG file; a default contenteditable keeps only the picture and a textarea gets the words.
- **Our paste (auto-paste on stop, Enter/click/⌘digit, ⌃⌥V).** Always sequential, because a target may read only one item. Write the picture alone, ⌘V, wait 0.35s, write "\n" + words, ⌘V, then after 1.0s rewrite the two-item board so a later manual ⌘V still has both. The restore is skipped if anything else changed the pasteboard in between.
- **Held paste.** The stop path stages the two-item board once. A later ⌘V gets the board as is; the ⌘V follow-up is not armed for linked boards, since apps that read both items would get the words twice.
- **Plain text only** does not strip item 1. It holds only the picture.

