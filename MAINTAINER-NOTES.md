# Maintainer notes (for K4JLB) - how to publish an update

Do these every time `install-connect-lookup.sh` changes. Friends then just
download the new file and run it again; it updates in place. Since version 1.5.1
their page also tells them when an update is out (see step 7).

1. Get the new installer from Claude and check it first on your test node:
   `sha256sum install-connect-lookup.sh`, then
   `sudo bash install-connect-lookup.sh YOURNODE --check`, then install it.
2. On GitHub, open the repo, open `install-connect-lookup.sh`, click the pencil
   (or **Add file > Upload files**) and replace it with the new file. Write a
   short note in the "Commit message" box, for example "Fix old EchoLink nodes".
3. Open `README.md` and replace the checksum line with the new one
   (`sha256sum` of the new installer).
4. Open `docs/STEP-BY-STEP-GUIDE.txt` and replace the checksum near the bottom
   the same way.
5. Open `CHANGELOG.md` and add a dated line at the top saying what changed.
6. LAST: open `VERSION` and change the number to the new version (digits and
   dots only, one line, for example `1.5.2`; use 1.5.2, not 1.52, because the
   page compares the parts between the dots). Do this only after the new
   installer is on GitHub, so nobody is told about a version they cannot
   download yet.
7. Nothing else to send. Once a day each node on 1.5.1 or newer reads `VERSION`.
   If the number is newer than the one it runs, the "Version" line at the top of
   its page says so, with a red "get it on GitHub" link. Friends then run the
   three commands under "Install" in README.md again. Nodes on 1.5 or older do
   not have the notice until they update once.

To see it work on a node right away instead of waiting for the daily check, run
this on that node: `sudo -u asterisk /etc/asterisk/custom/checkver.sh` (it
should print `Newest published version: ...`), then reload the page with Ctrl+F5.

Never put a node number of your own, a login name, a password or a QRZ login in
any of these files. The installer only ever uses the node number its user types.
