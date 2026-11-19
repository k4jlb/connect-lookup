# Maintainer notes (for K4JLB) - how to publish an update

Do these every time `install-connect-lookup.sh` changes. Friends then just
download the new file and run it again; it updates in place.

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
6. Send your friends a message that an update is out. They run the three
   commands under "Install" in README.md again.

Never put a node number of your own, a login name, a password or a QRZ login in
any of these files. The installer only ever uses the node number its user types.
