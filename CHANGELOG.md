# Changelog

Newest first. After you update, `sha256sum install-connect-lookup.sh` should
match the checksum in README.md.

## 2026-11-22 (version 1.5.10)
- Fixed: on a node with several direct links, keying lit every direct link on the
  page whenever the panel showed "PTT Keyed", even when only one link was actually
  talking (the others were just being repeated to). Now, when a link is the one
  talking, only that link is outlined (and, with the top box ticked, the stations
  behind it). When nobody on a link is talking (the local microphone), every linked
  station is still outlined, as before.

## 2026-11-22 (version 1.5.9)
- Changed: in the node-connect panel, the red for a keyed (transmitting) station now
  matches the Connect Lookup page: the same faint maroon fill with the same thin red
  outline, in the Node Connection table.
- Changed: the number column of the panel's Favorites list (0, 1, 2 ...) now uses the
  page's reds. It still fades with activity, but between the page's faint red and a
  slightly brighter red, with the thin red outline while that favorite is transmitting
  (it used to be green and plain red).
- Changed: node numbers in the panel (Favorites list and Node Connection table) use the
  same green as the "So far" times on the page, and a linked favorite's lit Node cell
  is a dark fill of that same green (it still fades with activity).
- Changed: the red "transmitting" outline on the Connect Lookup page now shows up
  sooner. The node checks for a keyed station about five times a second instead of
  twice, the page asks and redraws more often, and when the node-connect panel is
  loaded the page follows the keyed station straight from the panel's own Node
  Connection table (a keyed link, or this node's own PTT row, hang time included),
  so both sides switch on and off at the same moment (if the panel is not loaded,
  the page uses its own check as before).
- If you already installed 1.5.8, run this installer again. Your password and your
  Full control / Read-only level are kept.

## 2026-11-21 (version 1.5.8)
- New: the page now fits a phone. On a screen narrower than about 700 pixels
  (an iPhone held upright, for example) each row of the two tables becomes a small
  card with a label in front of each item, so you only scroll down, never sideways.
  On a computer or tablet the page looks exactly as before; nothing changed there.
- If you already installed 1.5.7, run this installer again. Your password and your
  Full control / Read-only level are kept.

## 2026-11-21 (version 1.5.7)
- Fixed: some callsigns outside the US showed a dash instead of a name. For
  certain callsigns QRZ keeps the whole name in the first-name field and leaves the
  last-name field empty, and the lookup threw that answer away. It now uses whatever
  name QRZ returns, with no stray spaces.
- A callsign the lookup could not find is normally tried again after a week. Running
  this installer now clears that list, so names an earlier version missed are looked
  up again right away. To retry just one callsign without reinstalling, run
  `sudo sed -i '/^CALLSIGN /d' /var/log/asterisk/node-history/peoplemiss.txt`
  (put the callsign in place of CALLSIGN).
- If you already installed 1.5.6, run this installer again. Your password and your
  Full control / Read-only level are kept.

## 2026-11-20 (version 1.5.6)
- Fixed: the Full control / Read-only switch could change the wrong settings file.
  On a node that keeps a backup copy of the app's settings next to the real one in
  `/etc/allscan/`, the switch changed the backup, so the node-connect app kept its
  old level. The installer now uses the app's own settings file
  (`/etc/allscan/<app folder name>.db`, for example `allscan.db`) and never picks a
  backup copy. If you already installed 1.5.5, run this installer again: it points
  the switch at the right file and keeps your password.

## 2026-11-20 (version 1.5.5)
- New: a **Full control / Read-only switch** at the very top of the panel, right
  beside the word node-connect. Full control lets visitors connect, disconnect,
  monitor and use favorites; Read-only lets them only look. It changes the app's
  visitor level on the node, so it applies to everyone, not just one browser, and it
  stays as the owner left it through reboots and updates.
- New: the switch is protected by a password chosen by the node owner. The
  installer asks for it once (type it twice, hidden; press Enter to skip). Only a
  scrambled hash is saved (`panel-access.php`, readable only by root and the web
  server); the password is never stored or published. Set or change it any time:
  `sudo bash install-connect-lookup.sh --password`. Without a password the switch
  is greyed out and the panel stays on Read-only.
- New: after 5 wrong passwords in 10 minutes, further tries are held back (one
  per 5 minutes). A browser that gave the right password stays unlocked for up to 8 hours, or until
  Full control is turned OFF. Turning it OFF never asks for the password and locks
  the browser again, so turning it back ON asks for the password.
- Changed: updating no longer resets the choice. Once the switch has been set up,
  an update leaves its current Full control / Read-only setting and password alone.
  On a first install the visitor level is set to Read-only; the owner turns Full
  control on with the switch and the password.
- Changed: the "node-connect" title bar of the panel now holds the switch, and the
  Reload button sits at the right.

## 2026-11-20 (version 1.5.4)
- Changed: the node-connect panel now works right after an install or an update,
  with no login: its connect, disconnect, monitor and favorites controls are
  switched on by the installer. Nothing else in the app's own settings is changed.

## 2026-11-20 (version 1.5.3)
- Changed: in the panel's Favorites list the Name column now shows only the
  callsign (a link to its QRZ page); the words that followed it are left out.
  Other tables are unchanged.
- Changed: the red box around a transmitting station is a touch fainter. In the
  panel, the app's own reds are toned down too: the far-left number column of the
  Favorites list and the "PTT Keyed" and keyed-station rows under Node Connection.
- Changed: default favorites. A node whose favorites are only the long sample list
  that comes with the app (never edited) now gets the defaults, in a new favorites
  list; the sample file is not touched. A list that has been edited, or any
  favorites file with entries of its own, is still never touched.
- Fixed: when the node also has an old backup copy of the connect app (a folder
  whose name says bak, old, orig or backup), the installer no longer picks the
  backup for the panel.

## 2026-11-20 (version 1.5.2)
- New: an optional panel on the right of the page that shows your node's own
  connect / disconnect / monitor / favorites page, restyled to match, so all of it
  is on one page. It has its own checkbox at the top ("Show the node-connect panel
  on the right"), which starts unticked; each browser remembers its choice. The
  installer finds that web app by what it contains; if it is not installed, nothing
  is added. The panel shows EchoLink favorites with their callsigns, a note that
  EchoLink favorites need EchoLink installed on the node, the CPU temperature
  (refreshed every 10 seconds, in your local time), and callsigns in the name
  columns that open their QRZ page in a new tab (EchoLink callsigns in white). The panel fits a phone screen (below Connect Lookup, tables sized to the screen).
- New: default favorites. If the node has no favorites yet, a few defaults are
  added once. They are never put back after you change or delete them, updating
  never touches your favorites, and uninstalling leaves them alone.
- Installer: adds `panel.css`, `panel.js`, `panel-words.txt` and
  `panel-remove.txt` in the Connect Lookup folder, and `panel.txt` when the app is
  found. An existing `panel.txt` is never overwritten.

## 2026-11-20 (version 1.5.1)
- New: update notice. Once a day (a systemd timer, with a random delay of up to
  6 hours) the node reads the one-line file `VERSION` from this repository. If the
  number there is newer than the version you run, the "Version" line at the top
  of the page says which version is available, with a red "get it on GitHub" link
  that fades slowly in and out and goes to the project page (the link address is
  fixed in the page; the version file cannot change it). It is a notice only:
  nothing is downloaded or installed by it, only digits and dots are accepted from
  the file, and if GitHub cannot be reached the page simply shows the plain
  version line. Nodes running 1.5 or older do not have this check until they run
  this installer once.
- Installer: adds `checkver.sh` and the `connect-lookup-checkver` service and
  timer; the uninstall removes them again.

## 2026-11-20 (version 1.5)
Found by checking the numbers on the page against a real day of use.
- New: the version number is shown in faint letters above the page title.
- New: node numbers (AllStarLink nodes) open that node's bubble chart on the
  AllStarLink stats site. EchoLink nodes (3 plus 6 digits) and callsigns are
  unchanged. A "Network map for node ..." link sits under the checkbox line.
- Fixed: after a reboot or an Asterisk restart, stations that came back behind
  a direct link could keep the start time from before the restart. "Connected
  now" then showed them connected longer than the link they come through. A
  visit that is still open in the log from before Asterisk started is now ended
  at the moment Asterisk started, and a new visit begins when Connect Lookup
  first sees the station again. The start time of Asterisk is taken from
  Asterisk itself ("core show uptime seconds"), not from the process list,
  which can be several seconds off on a long-running machine.
- Fixed: a connect could be logged twice within a second or two (once by
  Asterisk's own connect program and once by the tracker), which showed up as an
  extra row of 0 s or 1 s in "Last 24 hours". The tracker no longer logs the
  second one, and the page keeps only the first of two connects logged within
  3 seconds for the same station, which also hides such rows already in the log.
- Known limit: Connect Lookup cannot see the exact second a station came back,
  so a new visit after a restart starts when it first notices the station, a
  few seconds later at most.

## 2026-11-19 (version 1.4.1)
- Fixed: version 1.4 joined two separate visits into one long visit when the
  log showed a connect with no disconnect before the next connect, which is what
  a restart or reboot leaves behind. Each connect now starts a new visit again,
  and the earlier one ends at that time. A doubled disconnect line still adds
  no extra row.

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
- Fixed: the page no longer makes up a "before logging began" row from a
  doubled disconnect line.

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
