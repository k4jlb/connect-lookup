# Changelog

Newest first. After you update, `sha256sum install-connect-lookup.sh` should
match the checksum in README.md.

## 2026-11-19 (version 1.2)
- Fixed: a station connected straight to your node could show a dash under
  "Connected through" instead of "Direct". If one direct link (an EchoLink
  station, for example) had an empty address column in the node's link list,
  the page stopped reading the list at that line and lost every link after it.
  The list is now read from the right-hand end of each line, and a line it
  cannot read is skipped instead of stopping the rest.

## 2026-11-19
- New: a checkbox at the top of the page, "Outline the stations behind a link
  while that link is transmitting". It is off until you tick it, and your
  browser remembers your choice. The red box on the link itself is unchanged.
  Nothing to choose when installing.
- Fixed: old short EchoLink nodes (for example 3222 or 49196, shown by ASL
  zero-padded as 3003222 and 3049196) never got a callsign. The lookup now strips
  the leading zeros before asking EchoLink.

## 2026-11-18
- Fixed: a station whose disconnect was never logged could show a disconnect
  time in "Last 24 hours" that kept changing. The tracker now writes the missing
  disconnect itself.

## 2026-11-16
- "Connected through" no longer depends on AllStar Connect; the page has its own
  scanner that uses AllStarLink's public stats feed.
- Added a red box around a station's row while it is transmitting (stations
  linked directly to your node).

## 2026-11-15
- First version: live "Connected now" table, 24-hour history, QRZ links, names
  (Callook, optional QRZ), EchoLink stations in light blue, installer that takes
  only your node number.
