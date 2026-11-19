#!/bin/bash
# uninstall-connect-lookup.sh
# Removes Connect Lookup completely from the VPS 684972 (the hand-made install).
#
#   sudo bash uninstall-connect-lookup.sh                 ask, then remove everything
#   sudo bash uninstall-connect-lookup.sh --keep-history  keep the saved connection logs
#   sudo bash uninstall-connect-lookup.sh --yes           do not ask the main question
#
# It removes: the conlog lines in rpt.conf, the live service and cleanup timer,
# the helper scripts (including the QRZ login file), the web page, the saved
# history, the temporary files in /tmp and, only if you say yes, the temporary
# public login page for your friend (Apache file, password file, fail2ban jail,
# public https opening).
# It does NOT touch AllScan, AllStar Connect, Cockpit or anything else.
# For a node set up with install-connect-lookup.sh use that installer's
# --uninstall instead.

if [ "$(id -u)" -ne 0 ]; then
  echo "Run it with sudo:  sudo bash $0"
  exit 1
fi

KEEP=0
YES=0
for a in "$@"; do
  case "$a" in
    --keep-history) KEEP=1 ;;
    --yes) YES=1 ;;
    -h|--help) sed -n 2,19p "$0"; exit 0 ;;
    *) echo "Unknown option: $a"; exit 1 ;;
  esac
done

RPT=/etc/asterisk/rpt.conf
CUSTOM=/etc/asterisk/custom
WEB=/var/www/html/connect-lookup
HIST=/var/log/asterisk/node-history

ask() {
  local r
  read -r -p "$1 [y/N]: " r
  [ "$r" = y ] || [ "$r" = Y ]
}

echo "Connect Lookup uninstall"
echo
if [ "$YES" != 1 ]; then
  echo "This will remove Connect Lookup from this node:"
  echo "  - the conlog lines in $RPT (a backup copy is saved first)"
  echo "  - the connect-lookup live service and cleanup timer"
  echo "  - the helper scripts in $CUSTOM"
  echo "  - the web page in $WEB"
  if [ "$KEEP" = 1 ]; then
    echo "  - (your saved history in $HIST will be KEPT)"
  else
    echo "  - the saved history in $HIST"
  fi
  echo
  ask "Remove Connect Lookup?" || { echo "Cancelled. Nothing was changed."; exit 0; }
fi

# Temporary public login page for the friend (only asked about if it exists)
DO_PUBLIC=0
if [ -e /etc/apache2/conf-available/connect-public.conf ] \
   || [ -e /etc/fail2ban/jail.d/apache-connect.local ] \
   || [ -e /etc/apache2/.htpasswd-connect ]; then
  echo
  echo "The temporary public login page for your friend is still installed."
  echo "Removing it cuts off his access over the internet."
  if ask "Also remove the temporary public login page?"; then DO_PUBLIC=1; fi
fi

echo
echo "[1/6] Connection logging in rpt.conf"
if grep -q 'conlog\.sh' "$RPT" 2>/dev/null; then
  BK="$RPT.bak-before-uninstall-$(date +%Y%m%d-%H%M%S)"
  cp -a "$RPT" "$BK" && echo "  - backup saved: $BK"
  sed -i '/conlog\.sh/d' "$RPT"
  asterisk -rx "module reload app_rpt.so" >/dev/null 2>&1 \
    && echo "  - lines removed, app_rpt reloaded" \
    || echo "  - lines removed (reload app_rpt yourself: asterisk -rx \"module reload app_rpt.so\")"
else
  echo "  - no conlog lines found (already removed)"
fi

echo "[2/6] Background service and cleanup timer"
systemctl disable --now connect-lookup-live.service >/dev/null 2>&1
systemctl disable --now connect-lookup-clean.timer >/dev/null 2>&1
systemctl stop connect-lookup-clean.service >/dev/null 2>&1
rm -f /etc/systemd/system/connect-lookup-live.service \
      /etc/systemd/system/connect-lookup-clean.service \
      /etc/systemd/system/connect-lookup-clean.timer
systemctl daemon-reload
systemctl reset-failed >/dev/null 2>&1
echo "  - service, timer and unit files removed"

echo "[3/6] Helper scripts"
rm -f "$CUSTOM/conlog.sh" "$CUSTOM/live.sh" "$CUSTOM/track.sh" "$CUSTOM/names.sh" \
      "$CUSTOM/topology.php" "$CUSTOM/qrz.conf"
rm -f "$CUSTOM"/*.bak* 2>/dev/null
if [ -d "$CUSTOM" ]; then
  rmdir "$CUSTOM" 2>/dev/null \
    && echo "  - scripts and the $CUSTOM folder removed" \
    || echo "  - scripts removed; $CUSTOM left in place because it holds other files"
else
  echo "  - scripts removed"
fi

echo "[4/6] Web page"
rm -rf "$WEB"
echo "  - $WEB removed"

echo "[5/6] Saved history"
if [ "$KEEP" = 1 ]; then
  echo "  - kept: $HIST"
else
  rm -rf "$HIST"
  echo "  - $HIST removed"
fi

echo "[6/6] Temporary files"
rm -f /tmp/live.sh.bak /tmp/live.sh.bak2 /tmp/index.php.bak* /tmp/track.sh.bak* \
      /tmp/addvia.php /tmp/viamap.php /tmp/el.jar
echo "  - /tmp backups removed"

if [ "$DO_PUBLIC" = 1 ]; then
  echo
  echo "Temporary public login page"
  a2disconf connect-public >/dev/null 2>&1
  rm -f /etc/apache2/conf-available/connect-public.conf /etc/apache2/.htpasswd-connect
  if apache2ctl configtest >/dev/null 2>&1; then
    systemctl reload apache2 && echo "  - Apache file and password file removed, Apache reloaded"
  else
    echo "  - WARNING: Apache config test failed, Apache NOT reloaded. Check: sudo apache2ctl configtest"
  fi
  rm -f /etc/fail2ban/jail.d/apache-connect.local /etc/fail2ban/filter.d/connect-login.conf
  fail2ban-client reload >/dev/null 2>&1 && echo "  - fail2ban jail removed" || echo "  - fail2ban jail files removed (reload fail2ban yourself)"
  firewall-cmd --zone=allstarlink --remove-service=https >/dev/null 2>&1 \
    && echo "  - public https closed in the allstarlink zone" \
    || echo "  - public https was not open (nothing to close)"
fi

echo
echo "Check:"
if grep -q 'conlog\.sh' "$RPT" 2>/dev/null; then echo "  - rpt.conf: STILL has a conlog line"; else echo "  - rpt.conf: clean"; fi
if systemctl list-unit-files 2>/dev/null | grep -q 'connect-lookup'; then echo "  - systemd: connect-lookup units STILL present"; else echo "  - systemd: clean"; fi
[ -e "$WEB" ] && echo "  - web page: STILL there" || echo "  - web page: gone"
echo
echo "Connect Lookup removed. AllScan and your other pages were not touched."
if [ "$DO_PUBLIC" != 1 ] && { [ -e /etc/apache2/conf-available/connect-public.conf ] || [ -e /etc/fail2ban/jail.d/apache-connect.local ]; }; then
  echo "Note: the temporary public login page is still installed (you chose to keep it)."
fi
