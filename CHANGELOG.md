# Changelog

Newest first. After you update, `sha256sum install-connect-lookup.sh` should
match the checksum in README.md.

## 2026-11-19 (version 1.4)
Found by an independent review of version 1.3. Each item was reproduced with a
failing test first and passes now.
- Fixed: a link that is still connecting (an outgoing link that has not come
  up yet, or never does) was logged as if a station had connected. It now shows
  up only once the link is really connected.
- Fixed: a station that came back while Connect Lookup was stopped, or that
  stayed on through another link after its direct link dropped, was missing
  from "Last 24 hours" (shown as "before logging began"). Its return is now
  logged.
- Fixed: the disconnect time of a station could keep changing if the node had
  been switched off for more than two days. The tracker now looks at the same
  three daily logs as the page.
- Fixed: a slow or hanging EchoLink name lookup could stall the whole update
  loop and empty "Connected now". The lookup now runs in the background.
- Fixed: if "rpt lstats" failed once, the list of direct links was emptied for
  one round, which could split one visit in two. That round is now skipped.
- Fixed: the page no longer makes up a session or a "before logging began" row
  from doubled connect/disconnect lines.

## 2026-11-19 (version 1.3)
- Fixed: a station could sit in "Connected now" and then in "Last 24 hours"
  with a disconnect time that kept changing. The disconnect was never logged if
  the very last station left (the list was empty), or if the station left while
  Connect Lookup was not running (a reboot, for example). Both are now closed
  out properly. A station that leaves is logged within a few seconds.
- Fixed: your own node could appear in "Connected now" with a dash under
  "Connected through". When another node's link list includes yours, Asterisk
  reports your own node back as connected. Your own node number is now left out
  of the list, and the page ignores it too.
- Hardened: a node listed twice in Asterisk's answer now appears once, and a
  failed or empty answer from Asterisk (during a restart, for example) no longer
  records anyone as having left.

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
