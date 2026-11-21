# Connect Lookup for AllStarLink 3 (ASL3) nodes

A web page on your own node that shows, live, who is connected to your node
right now, and who connected during the last 24 hours. Built by K4JLB.

- Node, callsign (click it to open the QRZ page) and the operator's name
- "Connected through": Direct, or which node the station comes through
- Description and location, time connected, and how long
- EchoLink stations in light blue; Web Transceiver callsigns work too
- A red box around a station's row while it is transmitting (direct links)
- Node numbers open that node's bubble chart on the AllStarLink stats site (the
  link keeps the normal text color; it underlines when you point at it)
- A "Network map for node ..." link at the top, and the version number in faint
  letters above the title
- An optional checkbox at the top of the page that also outlines, faintly, the
  stations behind that link while it is transmitting (off until you tick it)
- An optional panel on the right with your node's own connect / disconnect /
  monitor / favorites page, so you can do all of it on one page (off until you tick
  its checkbox; only offered if that web app is already installed on your node)
- A count beside each heading; the page refreshes itself every few seconds
- A notice when a newer version is published here: once a day the node reads one
  line from this repository (`VERSION`), and if it is newer than the one you run,
  the "Version" line at the top of the page says so, with a red "get it on GitHub"
  link (to this page) that fades slowly in and out. It only tells you; nothing installs by itself

It installs by typing one thing: **your own node number**. It does not touch
any other page on your node, and you can remove it completely with one command.

## Install

Run these on your node (log in with SSH first). Replace `123456` with **your**
node number. Each command goes on its own line; wait for it to finish.

Download the installer (use whichever of the two works on your node):

```
wget https://raw.githubusercontent.com/k4jlb/connect-lookup/main/install-connect-lookup.sh
```

```
curl -fLO https://raw.githubusercontent.com/k4jlb/connect-lookup/main/install-connect-lookup.sh
```

Check the download is intact. It should print exactly this:
`516475221749643552f8438d38d991139bf98ce0ceb6e1fca07dc786ca09d6c4`

```
sha256sum install-connect-lookup.sh
```

Look only, changes nothing:

```
sudo bash install-connect-lookup.sh 123456 --check
```

Install:

```
sudo bash install-connect-lookup.sh 123456
```

It prints the address to open in a browser, for example
`http://192.168.1.50/connect-lookup/`. The page starts empty and fills in as
stations connect.

You can read the whole script in any text editor before running it. It
contains no passwords and nothing that belongs to anyone else's node; your
node number is the only thing that is filled in.

## The optional panel on the right

If your node already has the web app where you connect, disconnect, monitor and
keep favorites, the installer finds it (by what it contains) and adds a second
checkbox at the top of the page:

**[ ] Show the node-connect panel on the right**

- It is **off** until you tick it, and each browser remembers its own choice.
- The panel shows that app beside Connect Lookup, restyled to match, so you can
  connect, disconnect, monitor, use DTMF and add, edit or delete favorites without
  leaving the page. In the Favorites list the Name column shows just the callsign, and callsigns open their QRZ page in a new tab (EchoLink callsigns are shown in white so they are easy to tell apart). EchoLink favorites show the callsign. The CPU temperature is
  shown at the top right and refreshes every 10 seconds, in your local time.
- If that app is not installed, nothing is added and the panel stays off. Install
  it, then run this installer again.
- **Default favorites.** If the node has no favorites yet (the long sample list that
  comes with the app, if it was never edited, does not count), a few default ones
  are added once, in a new favorites list; the sample file itself is not touched.
  Change or delete them any way you like: they are never put back, and updating
  this installer never touches your favorites. Removing Connect Lookup leaves your
  favorites alone too.

## The Full control / Read-only switch

At the very top of the panel, right beside the word **node-connect**, there is a
switch: **Full control: ON** or **Full control: OFF (read-only)**.

- **Read-only:** visitors can only look. This is how a first install starts.
- **Full control:** visitors can connect, disconnect, monitor and use favorites.
  Only the node owner can turn it on, with the switch password. The switch changes
  the app's visitor level on the node, so it applies to everyone who opens the page,
  and it stays that way, through reboots and updates, until the owner turns it off.
- **The node owner's password.** The installer asks once: *Panel switch password*
  (type it twice; it is not shown; press Enter to skip). Only someone who knows it
  can flip the switch; the box asks for it when you click. A browser that gave the
  right password stays unlocked for up to 8 hours, or until you turn Full control OFF.
  Turning it OFF never asks for the password and locks the browser again, so turning
  it back ON asks for the password. After 5 wrong tries in 10 minutes,
  further tries are held back (one per 5 minutes).
- **Skipped it?** The switch is greyed out and the panel stays on Read-only.
  Set a password later (or change it):

  ```
  sudo bash install-connect-lookup.sh --password
  ```

- Only a scrambled hash of the password is stored on your node (in
  `/var/www/html/connect-lookup/panel-access.php`, readable only by root and the web
  server). The password itself is never saved, shown or sent anywhere, and it is not
  part of this repository. Forgot it? Run the command above again to choose a new one.
- Updating the installer keeps your password and the current Full control /
  Read-only setting.

## The optional outline checkbox

There is nothing to choose when you install. At the top of the page there are two
checkboxes (both start unticked). The first one:

**[ ] Outline the stations behind a link while that link is transmitting**

- **Unticked (the normal setting):** the station you are linked to directly gets
  a red box while it transmits.
- **Ticked:** that station still gets the red box, and the stations that come
  through that link also get a faint outline while it transmits. Handy to see who
  is behind the station that is talking, but on a busy node many rows can be
  outlined at once.

Tick it or untick it any time; the page changes right away. Each person's
browser remembers its own choice, so it does not change the page for anyone else.

## Update

Run the same download and install commands again with the new file. It finds
your existing install, updates it in place, and keeps your saved history.
Check [CHANGELOG.md](CHANGELOG.md) to see what changed. If the checksum above
does not match your download, get the file again.

## Remove

```
sudo bash install-connect-lookup.sh --uninstall
```

It puts `rpt.conf` back the way it was and keeps your saved history. Add
`--delete-history` to delete that too.

## What it changes on your node (and nothing else)

- Adds the page in `/var/www/html/connect-lookup/`
- Adds six small scripts in `/etc/asterisk/custom/`
- Adds a background service, a daily cleanup job (deletes logs over 30 days old) and
  a daily version check (reads the one-line `VERSION` file from this repository;
  nothing about your node is sent, and nothing is installed by it)
- Adds two lines (`connpgm` and `discpgm`) to your node's section of
  `/etc/asterisk/rpt.conf`, after saving a backup copy next to it
- If the node-connect panel is available: on a first install it sets the app's visitor
  level to Read-only, and it adds `panel-access.php` (the switch's settings and
  the password hash) in the same page folder
- Installs two small standard packages (`curl`, `php-cli`) only if missing

It refuses to continue if your node already uses `connpgm`/`discpgm` for
something else, or if it finds a hand-made Connect Lookup it did not install.

## Requirements

An ASL3 node with Asterisk running, the Apache web server with PHP (the one your
node's other web pages already use), `sudo`, and internet access from the node
("Connected through" uses AllStarLink's public stats feed).

Names come from callook.info (free US FCC records) and EchoLink's public node
lookup page; no login is needed. For names of callsigns outside the US you can
optionally add your own free QRZ.com login with `--qrz`; it is stored readable
only by the asterisk user.

## Good to know

- Anyone who can reach your node's web server can open the page, like your other
  node pages. It shows who connected, nothing private. Limit access with your
  firewall or router if your node is open to the internet.
- One node per computer.
- Step-by-step instructions for beginners (copying the file from a PC, what each
  prompt means, troubleshooting) are in
  [docs/STEP-BY-STEP-GUIDE.txt](docs/STEP-BY-STEP-GUIDE.txt).
