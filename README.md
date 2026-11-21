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
`ad0098f5d1ae1a87c1c11c393d1fae6c87e5dd5890d2aadb9dee12bdf88b2599`

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
  leaving the page. Callsigns in the name columns open their QRZ page in a new tab (EchoLink callsigns are shown in white so they are easy to tell apart). EchoLink favorites show the callsign. The CPU temperature is
  shown at the top right and refreshes every 10 seconds, in your local time.
- If that app is not installed, nothing is added and the panel stays off. Install
  it, then run this installer again.
- **Default favorites.** If the node has no favorites yet, a few default ones are
  added once. Change or delete them any way you like: they are never put back, and
  updating this installer never touches your favorites. Removing Connect Lookup
  leaves your favorites alone too.

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
