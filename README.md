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
- A count beside each heading; the page refreshes itself every few seconds

It installs by typing one thing: **your own node number**. It does not touch
AllScan, Supermon, Allmon or any other page, and you can remove it completely
with one command.

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
`862171a8ff606d37b369f20c2956bb085aa0d4e7d6ccfc090fc13d872594b9e1`

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

## The optional outline checkbox

There is nothing to choose when you install. At the top of the page there is a
checkbox:

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
- Adds five small scripts in `/etc/asterisk/custom/`
- Adds a background service and a daily cleanup job (deletes logs over 30 days old)
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
