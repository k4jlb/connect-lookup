#!/bin/bash
# ======================================================================
#  Connect Lookup - installer for AllStarLink 3 (ASL3) nodes
#
#  Adds a web page to your node that shows who is connected right now
#  and who connected during the last 24 hours (callsign, name, QRZ link,
#  how they connect, how long). Built by K4JLB.
#
#  Install:     sudo bash install-connect-lookup.sh YOURNODE
#  Check only:  sudo bash install-connect-lookup.sh YOURNODE --check
#  Remove:      sudo bash install-connect-lookup.sh --uninstall
#
#  Run it with --help for the options.
# ======================================================================
case "$(head -c 3000 "$0" 2>/dev/null)" in *$'\r'*) echo "This file was saved with Windows line endings. Fix it with:  sed -i 's/\r\$//' $0   and run it again."; exit 1;; esac # windows-line-ending guard

VERSION="1.5.8"
MARK="connect-lookup-installer-v1"
ACCESS="panel-access.php"   # the switch's settings and password hash, next to index.php (never published, never contains the plain password)
CUSTOM=/etc/asterisk/custom
LOGDIR=/var/log/asterisk/node-history
WEB=/var/www/html/connect-lookup
RPT=/etc/asterisk/rpt.conf
UNITDIR=/etc/systemd/system
BK=/var/backups/connect-lookup
STAMP=$(date +%Y%m%d-%H%M%S)

NODE=""
YES=0
QRZ=0
PWSET=0
DELHIST=0
MODE=install
CHANGED=0
RPT_DONE=0

# ----------------------------------------------------------------------
#  Small helpers
# ----------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
note() { printf '  - %s\n' "$*"; }
warn() { printf '  WARNING: %s\n' "$*"; }

die() {
  printf '\nERROR: %s\n' "$*" >&2
  if [ "$CHANGED" = 1 ] && [ "$MODE" = uninstall ]; then
    printf '\nThe removal stopped part-way. Fix the problem above and run the uninstall again:\n  sudo bash %s --uninstall\n' "$0" >&2
  elif [ "$CHANGED" = 1 ]; then
    printf '\nThe install stopped part-way. To remove what was added, run:\n  sudo bash %s --uninstall\n' "$0" >&2
  else
    printf 'Nothing on this node was changed.\n' >&2
  fi
  exit 1
}

cancelled() { say "Cancelled. Nothing was changed."; exit 0; }

ask() {
  [ "$YES" = 1 ] && return 0
  local a
  printf '\n  %s\n  Type  y  and press Enter to go ahead, or just press Enter to cancel: ' "$1"
  read -r a </dev/tty 2>/dev/null || { printf '\n'; return 1; }
  case "$a" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

usage() {
  cat <<'EOF_USAGE'
Connect Lookup installer

  Install:     sudo bash install-connect-lookup.sh YOURNODE
  Check only:  sudo bash install-connect-lookup.sh YOURNODE --check
               (looks at your node and changes nothing)
  Remove:      sudo bash install-connect-lookup.sh --uninstall

Options:
  --check            run the checks only, change nothing
  --qrz              also ask for your own free QRZ.com login, so names can be
                     found for callsigns outside the US (optional)
  --password         set or change the password for the panel's Full control /
                     Read-only switch (the switch is at the top of the panel,
                     beside the word node-connect). Needs Connect Lookup to be
                     installed already.
  --yes              do not ask for confirmation
  --uninstall        remove everything this installer added
  --delete-history   with --uninstall: also delete the saved connection history
  --help             show this text
EOF_USAGE
}

# ----------------------------------------------------------------------
#  The files this installer writes. They are stored here exactly as they
#  run on K4JLB's node; @NODE@ is replaced by your node number.
# ----------------------------------------------------------------------
emit_conlog() { cat <<'CL_EOF_CONLOG'
#!/bin/bash
# connect-lookup-installer-v1
echo "$(date +%s) $(date +%F_%T) $1 $2 $3" >> /var/log/asterisk/node-history/$(date +%F).log
CL_EOF_CONLOG
}

emit_live() { cat <<'CL_EOF_LIVE'
#!/bin/bash
# connect-lookup-installer-v1
D=/var/log/asterisk/node-history
URL=https://www.echolink.org/validation/node_lookup.jsp
declare -A OLD
LAST=0
LASTSCAN=0
IVL=120
declare -A PREV MISS WASDIR CUR BACK LE
. /etc/asterisk/custom/track.sh
LASTN=0
# keyed.txt: which directly linked stations are transmitting right now (checked twice a second; used by the page's red outline)
( while true; do
    k=$(/usr/sbin/asterisk -rx "rpt show variables @NODE@" 2>/dev/null | grep -m1 'RPT_ALINKS=')
    if [ -n "$k" ]; then
      echo "${k#*=}" | tr ',' '\n' | tail -n +2 | grep -E '[TR]K$' | sed 's/[TR]K$//' > $D/keyed.tmp
      mv -f $D/keyed.tmp $D/keyed.txt
    fi
    sleep 0.5
  done ) &
while true; do
  # OKLIVE=1 only when Asterisk really answered (the answer has its CONNECTED NODES heading, even if it says <NONE>)
  OKLIVE=0
  raw=$(/usr/sbin/asterisk -rx "rpt nodes @NODE@" 2>/dev/null); rc=$?
  if [ $rc -eq 0 ] && grep -q 'CONNECTED NODES' <<< "$raw"; then
    OKLIVE=1
    grep -v '\*' <<< "$raw" | tr ',' '\n' | tr -d ' \t' | grep -E '^[TR][0-9A-Za-z-]+$' | cut -c2- | grep -vx @NODE@ | awk '!seen[$0]++' > $D/live.tmp
    mv -f $D/live.tmp $D/live.txt
  fi
  now=$(date +%s)
  OLD=()
  while read -r n s; do OLD[$n]=$s; done < <(cat $D/direct.txt 2>/dev/null)
  LST=$(/usr/sbin/asterisk -rx "rpt lstats @NODE@" 2>/dev/null) || LST=FAIL
  : > $D/direct.tmp
  [ "$LST" != FAIL ] && grep -E " (IN|OUT) " <<< "$LST" | while read -r -a f; do
    n=${f[0]}; ct=${f[${#f[@]}-2]}
    [[ $ct =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]] || continue
    IFS=: read -r h m s ms <<< "$ct"
    t=$((now - 10#$h*3600 - 10#$m*60 - 10#$s))
    o=${OLD[$n]:-0}; d=$((t-o)); if [ ${d#-} -le 3 ]; then t=$o; fi
    echo "$n $t"
  done > $D/direct.tmp
  while read -r n t; do grep -qx "$n $t" $D/direct-starts.txt 2>/dev/null || echo "$n $t" >> $D/direct-starts.txt; done < $D/direct.tmp
  if [ "$LST" != FAIL ]; then mv -f $D/direct.tmp $D/direct.txt; else touch $D/direct.txt; OKLIVE=0; fi
  if [ $((now - LAST)) -ge 60 ]; then
    LAST=$now
    ( /usr/bin/flock -n 9 || exit 0
    for n in $(grep -E "^3[0-9]{6}$" $D/live.txt | cut -c2-); do
      q=$((10#$n))
      grep -q "^$n|" $D/elnames.txt 2>/dev/null && continue
      grep -q "^3$n|" /var/www/html/connect-lookup/names.txt 2>/dev/null && continue
      m=$(grep "^$n " $D/elmiss.txt 2>/dev/null | cut -d" " -f2)
      if [ -n "$m" ] && [ $((now - m)) -lt 3600 ]; then continue; fi
      c=$(/usr/sbin/asterisk -rx "echolink dbdump" 2>/dev/null | grep -E "^$q\|" | cut -d"|" -f2)
      if [ -z "$c" ]; then
        curl -s -m 10 -c $D/el.jar $URL > /dev/null
        c=$(curl -s -m 10 -b $D/el.jar -d "call=$q" $URL | tr -d "\r\n" | grep -oE "<td>[^<]+</td><td align=\"right\">$q</td>" | sed "s/<td>\([^<]*\)<\/td>.*/\1/")
      fi
      if [ -n "$c" ]; then
        echo "$n|$c|" >> $D/elnames.txt
      else
        sed -i "/^$n /d" $D/elmiss.txt 2>/dev/null
        echo "$n $now" >> $D/elmiss.txt
      fi
    done ) 9>$D/el.lock </dev/null >/dev/null 2>&1 &
  fi
  if [ $((now - LASTN)) -ge 60 ]; then LASTN=$now; /usr/bin/flock -n $D/names.lock /etc/asterisk/custom/names.sh >/dev/null 2>&1 & fi
  track
  if [ "${NEWC:-0}" = 1 ]; then NEWC=0; LASTSCAN=0; LAST=0; /usr/bin/flock $D/names.lock /etc/asterisk/custom/names.sh >/dev/null 2>&1 & fi
  if [ "${SCANUNTIL:-0}" -gt "$now" ]; then IVL=15; else IVL=120; fi
  if [ $((now - LASTSCAN)) -ge $IVL ]; then LASTSCAN=$now; /usr/bin/php /etc/asterisk/custom/topology.php @NODE@ >/dev/null 2>&1 & fi
  sleep 3
done
CL_EOF_LIVE
}

emit_track() { cat <<'CL_EOF_TRACK'
# connect-lookup-installer-v1
declare -A LT
# start time (epoch) of the running Asterisk, taken from Asterisk itself (the process start time shown by ps can be several seconds off), or nothing if it is not running; every link dies with the process
ast_start() {
  local u
  u=$(${CL_ASTERISK:-/usr/sbin/asterisk} -rx "core show uptime seconds" 2>/dev/null | awk '/^System uptime:/ {print $3; exit}')
  [[ $u =~ ^[0-9]+$ ]] && echo $((now - u))
}
track() {
  local n ts LOG DIR t
  # skip this round if Asterisk did not give a real answer (it may be restarting); an empty list with a real answer is fine
  [ "${OKLIVE:-1}" = 1 ] || return
  CUR=()
  while read -r n; do [ -n "$n" ] && CUR[$n]=1; done < $D/live.txt
  DIR=" $(cut -d" " -f1 $D/direct.txt | tr "\n" " ") "
  LOG=$D/$(date +%F).log
  ts="$now $(date +%F_%T)"
  # last logged event (C or D) of every node, read once per round from the newest three daily logs (the page reads the same three)
  LE=(); LT=()
  while read -r n e t; do LE[$n]=$e; LT[$n]=$t; done < <(cat $(ls $D/20??-??-??.log 2>/dev/null | tail -n 3) /dev/null 2>/dev/null | awk '$4=="@NODE@" && ($3=="C" || $3=="D") {l[$5]=$3; t[$5]=$1} END {for (k in l) print k, l[k], t[k]}')
  if [ -z "$PINIT" ]; then
    PINIT=1
    for n in "${!CUR[@]}"; do PREV[$n]=1; done
    # stations the log still shows as connected from before a restart, but that are gone now: close them
    for n in $(cat $(ls $D/20??-??-??.log 2>/dev/null | tail -n 3) /dev/null 2>/dev/null | awk '{print $5}' | sort -u); do
      [ -n "${CUR[$n]}" ] && continue
      lastd "$n" || echo "$ts D @NODE@ $n" >> $LOG
    done
  fi
  # a visit still open in the log from before Asterisk (re)started cannot be real: all links died with the old process (reboot, Asterisk restart).
  # End it when Asterisk started and open a new one now, so a station that came back without a logged D/C does not keep its old start time.
  AST=$(ast_start)
  if [[ $AST =~ ^[0-9]+$ ]]; then
    for n in "${!CUR[@]}"; do
      t=${LT[$n]}
      [ "${LE[$n]}" = C ] && [[ $t =~ ^[0-9]+$ ]] && [ $((t + 10)) -lt "$AST" ] || continue
      echo "$AST $(date -d @$AST +%F_%T) D @NODE@ $n" >> $LOG
      echo "$ts C @NODE@ $n" >> $LOG
      LE[$n]=C; LT[$n]=$now
    done
  fi
  for n in "${!CUR[@]}"; do
    unset "MISS[$n]"
    case "$DIR" in *" $n "*) WASDIR[$n]=1; unset "BACK[$n]" ;; *) unset "WASDIR[$n]"
      if [ -n "${PREV[$n]}" ] && [ "${LE[$n]}" = D ]; then BACK[$n]=$(( ${BACK[$n]:-0} + 1 ))
        [ ${BACK[$n]} -ge 2 ] && { echo "$ts C @NODE@ $n" >> $LOG; LE[$n]=C; unset "BACK[$n]"; }
      else unset "BACK[$n]"; fi ;; esac
    if [ -z "${PREV[$n]}" ]; then
      PREV[$n]=1; NEWC=1
      case "$DIR" in *" $n "*) ;; *) lastc "$n" || echo "$ts C @NODE@ $n" >> $LOG; LE[$n]=C; SCANUNTIL=$((now + 300)) ;; esac
    fi
  done
  for n in "${!PREV[@]}"; do
    [ -n "${CUR[$n]}" ] && continue
    MISS[$n]=$(( ${MISS[$n]:-0} + 1 ))
    if [ ${MISS[$n]} -ge 2 ]; then
      lastd "$n" || echo "$ts D @NODE@ $n" >> $LOG
      unset "PREV[$n]" "MISS[$n]" "WASDIR[$n]" "BACK[$n]"
    fi
  done
}
# true if the last logged event for node $1 (yesterday or today) is already a D
lastd() { [ "$(grep -h " [CD] @NODE@ $1\$" $(ls $D/20??-??-??.log 2>/dev/null | tail -n 3) /dev/null 2>/dev/null | tail -n1 | cut -d" " -f3)" = "D" ]; }
# true if the last logged event for node $1 is a C written in the last 5 seconds (the connect program of Asterisk already logged this connect)
lastc() { local l e; l=$(grep -h " [CD] @NODE@ $1\$" $(ls $D/20??-??-??.log 2>/dev/null | tail -n 3) /dev/null 2>/dev/null | tail -n1); e=$(cut -d" " -f1 <<< "$l"); [[ $e =~ ^[0-9]+$ ]] && [ "$(cut -d" " -f3 <<< "$l")" = C ] && [ $((now - e)) -le 5 ]; }
CL_EOF_TRACK
}

emit_names() { cat <<'CL_EOF_NAMES'
#!/bin/bash
# connect-lookup-installer-v1
D=/var/log/asterisk/node-history
now=$(date +%s)
for n in $( { cat $D/live.txt; cat $D/$(date +%F).log $D/$(date -d yesterday +%F).log 2>/dev/null | awk '{print $5}'; } | sort -u ); do
  c=$(grep -m1 "^$n|" /var/lib/asterisk/astdb.txt | cut -d"|" -f2)
  [ -z "$c" ] && c=$(grep -m1 "^${n#3}|" $D/elnames.txt 2>/dev/null | cut -d"|" -f2)
[ -z "$c" ] && [[ ! "$n" =~ ^[0-9]+$ ]] && c=$n
  b=$(echo "${c%%-*}" | tr a-z A-Z)
  echo "$b" | grep -qE "^[A-Z0-9]{1,3}[0-9][A-Z]{1,4}$" || continue
  grep -q "^$b|" $D/people.txt 2>/dev/null && continue
  m=$(grep "^$b " $D/peoplemiss.txt 2>/dev/null | cut -d" " -f2)
  if [ -n "$m" ] && [ $((now - m)) -lt 604800 ]; then continue; fi
  j=$(curl -s -m 10 "https://callook.info/$b/json" | tr -d "\n")
  p=""
  if echo "$j" | grep -q '"status": "VALID"'; then
    p=$(echo "$j" | grep -oE '"name": "[^"]+"' | tail -1 | cut -d'"' -f4 | sed 's/.*/\L&/; s/\b\(.\)/\u\1/g')
  fi
  if [ -z "$p" ] && [ -r /etc/asterisk/custom/qrz.conf ]; then
    . /etc/asterisk/custom/qrz.conf
    k=$(curl -s -m 10 -G --data-urlencode "username=$QU" --data-urlencode "password=$QP" --data-urlencode "agent=connectlookup" https://xmldata.qrz.com/xml/current/ | grep -oP '(?<=<Key>)[^<]+')
    x=$(curl -s -m 10 -G --data-urlencode "s=$k" --data-urlencode "callsign=$b" https://xmldata.qrz.com/xml/current/)
    f=$(echo "$x" | grep -oP '(?<=<fname>)[^<]+')
    l=$(echo "$x" | grep -oP '(?<=<name>)[^<]+')
    p=$(echo "$f $l" | sed 's/^ *//; s/ *$//')
  fi
  if [ -n "$p" ]; then
    echo "$b|$p" >> $D/people.txt
  else
    sed -i "/^$b /d" $D/peoplemiss.txt 2>/dev/null
    echo "$b $now" >> $D/peoplemiss.txt
  fi
done
CL_EOF_NAMES
}

emit_topology() { cat <<'CL_EOF_TOPO'
#!/usr/bin/php
<?php
// connect-lookup-installer-v1
// Works out which direct link each connected node comes through, using the
// public AllStarLink stats feed. Output: /var/log/asterisk/node-history/topology.json
// Usage: topology.php <your node number>
declare(strict_types=1);

$LOCAL = preg_replace('/\D/', '', $argv[1] ?? '');
$D = '/var/log/asterisk/node-history';
$OUT = "$D/topology.json";
$CACHE = "$D/stats-cache";
$BASE = getenv('CL_STATS_BASE') ?: 'https://stats.allstarlink.org/api/stats/';
$OK_TTL = 120;        // reuse a good answer this many seconds
$FAIL_TTL = 300;      // do not retry a failed lookup for this long
$MAX_FETCH = 8;       // network lookups per run (the feed allows 30 a minute)
$PAUSE_US = 2200000;  // pause between lookups
$MAX_DEPTH = 8;

if ($LOCAL === '') { fwrite(STDERR, "usage: topology.php <node>\n"); exit(1); }

$lock = @fopen("$D/topology.lock", 'c');
if ($lock === false || !flock($lock, LOCK_EX | LOCK_NB)) exit(0);
if (!is_dir($CACHE)) @mkdir($CACHE, 0755);

function lines(string $f): array {
    return is_readable($f) ? (file($f, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: []) : [];
}

$direct = [];
foreach (lines("$D/direct.txt") as $l) {
    $p = preg_split('/\s+/', trim($l));
    if (($p[0] ?? '') !== '') $direct[$p[0]] = true;
}
$wanted = [];
foreach (lines("$D/live.txt") as $l) {
    $n = trim($l);
    if ($n !== '' && $n !== $LOCAL && !isset($direct[$n])) $wanted[$n] = true;
}

// when each node first showed up (new ones get quick, uncached lookups)
$old = is_readable($OUT) ? json_decode((string)@file_get_contents($OUT), true) : null;
$seenAt = [];
foreach (array_keys($wanted) as $n) {
    $seenAt[(string)$n] = (int)(($old['seen_at'] ?? [])[(string)$n] ?? time());
}

// rows found on the previous run, kept when a lookup cannot be made right now
$prev = [];
foreach (($old['display_nodes'] ?? []) as $r) {
    if (isset($r['node'], $r['direct_node']) && isset($wanted[(string)$r['node']]) && isset($direct[(string)$r['direct_node']])) {
        $prev[(string)$r['node']] = $r;
    }
}

// a node that just appeared and is not placed yet: do not trust answers older than a few seconds
$fast = false;
foreach (array_keys($wanted) as $n) {
    if (!isset($prev[(string)$n]) && time() - $seenAt[(string)$n] < 300) { $fast = true; break; }
}
if ($fast) $OK_TTL = 8;

$fetches = 0;
function get_stats(string $node): ?array {
    global $CACHE, $BASE, $OK_TTL, $FAIL_TTL, $MAX_FETCH, $PAUSE_US, $fetches;
    $cf = "$CACHE/" . preg_replace('/[^0-9A-Za-z_-]/', '_', $node) . '.json';
    $c = is_readable($cf) ? json_decode((string)@file_get_contents($cf), true) : null;
    if (is_array($c)) {
        $age = time() - (int)($c['ts'] ?? 0);
        if (!empty($c['ok']) && $age < $OK_TTL) return $c;
        if (empty($c['ok']) && $age < $FAIL_TTL) return null;
    }
    if ($fetches >= $MAX_FETCH) return is_array($c) && !empty($c['ok']) ? $c : null;  // out of budget: use older answer if any
    if ($fetches > 0) usleep($PAUSE_US);
    $fetches++;
    $cmd = 'curl -s -m 6 -A ConnectLookup/1 -H "Accept: application/json" -w "\n%{http_code}" '
         . escapeshellarg($BASE . rawurlencode($node)) . ' 2>/dev/null';
    $raw = (string)shell_exec($cmd);
    $i = strrpos($raw, "\n");
    $code = $i === false ? 0 : (int)substr($raw, $i + 1);
    $body = $i === false ? '' : substr($raw, 0, $i);
    $j = $code === 200 ? json_decode($body, true) : null;
    $data = is_array($j) ? ($j['stats']['data'] ?? null) : null;
    if (!is_array($data)) {
        @file_put_contents($cf, json_encode(['ts' => time(), 'ok' => false]));
        return null;
    }
    $entries = [];
    foreach (($data['linkedNodes'] ?? []) as $e) {
        if (!is_array($e)) continue;
        $srv = is_array($e['server'] ?? null) ? $e['server'] : [];
        $entries[] = [
            'name' => trim((string)($e['name'] ?? '')),
            'call' => trim((string)($e['callsign'] ?? ($e['User_ID'] ?? ''))),
            'desc' => trim((string)($e['node_frequency'] ?? '')),
            'loc'  => trim((string)($srv['Location'] ?? ($srv['SiteName'] ?? ''))),
        ];
    }
    $links = [];
    foreach (($data['links'] ?? []) as $l) $links[] = trim((string)$l);
    $c = ['ts' => time(), 'ok' => true, 'entries' => $entries, 'links' => $links];
    @file_put_contents($cf, json_encode($c));
    return $c;
}

$rows = [];
$queue = [];
foreach (array_keys($direct) as $d) $queue[] = [(string)$d, (string)$d, 1];
$seen = $direct;
$seen[$LOCAL] = true;
$failed = [];
while ($queue && count($rows) < count($wanted)) {
    [$src, $dn, $depth] = array_shift($queue);
    $s = get_stats($src);
    if ($s === null) { $failed[$src] = true; continue; }
    $found = [];
    foreach ($s['entries'] as $e) { if ($e['name'] !== '') $found[$e['name']] = $e; }
    foreach ($s['links'] as $l) { if ($l !== '' && !isset($found[$l])) $found[$l] = ['name' => $l, 'call' => '', 'desc' => '', 'loc' => '']; }
    foreach ($found as $name => $e) {
        $name = (string)$name;
        if (isset($seen[$name]) || !isset($wanted[$name])) continue;
        $seen[$name] = true;
        $rows[$name] = [
            'node' => $name, 'direct_node' => $dn, 'parent_node' => $src, 'depth' => $depth,
            'callsign' => $e['call'], 'description' => $e['desc'], 'location' => $e['loc'],
        ];
        if ($depth < $MAX_DEPTH && ctype_digit($name)) $queue[] = [$name, $dn, $depth + 1];
    }
}

// keep the previous answer for anything we could not look up this time
$unresolved = [];
foreach (array_keys($wanted) as $n) {
    if (isset($rows[$n])) continue;
    if (isset($prev[$n])) { $rows[$n] = $prev[$n]; continue; }
    $unresolved[] = (string)$n;
}

$out = [
    'updated' => time(),
    'source' => 'stats.allstarlink.org',
    'direct' => array_map(fn($n) => ['node' => (string)$n], array_keys($direct)),
    'display_nodes' => array_values($rows),
    'unresolved' => $unresolved,
    'seen_at' => $seenAt,
];
$tmp = "$OUT.tmp";
if (@file_put_contents($tmp, json_encode($out, JSON_UNESCAPED_SLASHES)) !== false) {
    @chmod($tmp, 0644);
    @rename($tmp, $OUT);
}
// tidy cache files older than a day
foreach (glob("$CACHE/*.json") ?: [] as $f) { if (time() - (int)@filemtime($f) > 86400) @unlink($f); }
CL_EOF_TOPO
}

emit_checkver() { cat <<'CL_EOF_CHECKVER'
#!/bin/bash
# connect-lookup-installer-v1
# Once a day: read the newest published version number from GitHub (a one-line file)
# and save it for the page. Read-only notice: nothing is downloaded or installed.
OUT="${CL_VEROUT:-/var/log/asterisk/node-history/latest-version.txt}"
URL="${CL_VERURL:-https://raw.githubusercontent.com/k4jlb/connect-lookup/main/VERSION}"
v=$(${CL_CURL:-curl} -fsS -m 20 -A ConnectLookup-versioncheck "$URL" 2>/dev/null | head -c 64 | head -n 1 | tr -d '\r[:space:]')
if [[ $v =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
  printf '%s\n' "$v" > "$OUT.tmp" && chmod 644 "$OUT.tmp" && mv -f "$OUT.tmp" "$OUT"
  echo "Newest published version: $v"
else
  echo "Could not read a version number from GitHub; keeping the previous answer."
fi
exit 0
CL_EOF_CHECKVER
}

emit_unit_live() { cat <<'CL_EOF_UNIT1'
# connect-lookup-installer-v1
[Unit]
Description=Connect Lookup live connected-node list
After=asterisk.service

[Service]
User=asterisk
ExecStart=/etc/asterisk/custom/live.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
CL_EOF_UNIT1
}

emit_unit_clean_service() { cat <<'CL_EOF_UNIT2'
# connect-lookup-installer-v1
[Unit]
Description=Connect Lookup - delete connection logs older than 30 days

[Service]
Type=oneshot
User=asterisk
ExecStart=/usr/bin/find /var/log/asterisk/node-history -name "20??-??-??.log" -mtime +30 -delete
CL_EOF_UNIT2
}

emit_unit_clean_timer() { cat <<'CL_EOF_UNIT3'
# connect-lookup-installer-v1
[Unit]
Description=Daily cleanup of old Connect Lookup logs

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
CL_EOF_UNIT3
}

emit_unit_ver_service() { cat <<'CL_EOF_UNIT4'
# connect-lookup-installer-v1
[Unit]
Description=Connect Lookup - check for a newer published version

[Service]
Type=oneshot
User=asterisk
ExecStart=/etc/asterisk/custom/checkver.sh
CL_EOF_UNIT4
}

emit_unit_ver_timer() { cat <<'CL_EOF_UNIT5'
# connect-lookup-installer-v1
[Unit]
Description=Daily check for a newer Connect Lookup version

[Timer]
OnCalendar=daily
RandomizedDelaySec=6h
Persistent=true

[Install]
WantedBy=timers.target
CL_EOF_UNIT5
}

emit_index() { cat <<'CL_EOF_INDEX'
<?php
// connect-lookup-installer-v1
const LOGDIR = '/var/log/asterisk/node-history';
const ASTDB  = '/var/lib/asterisk/astdb.txt';
function load_events() {
    $files = glob(LOGDIR . '/20??-??-??.log');
    sort($files);
    $files = array_slice($files, -3);
    $ev = [];
    foreach ($files as $f) {
        $fh = @fopen($f, 'r');
        if (!$fh) continue;
        while (($line = fgets($fh)) !== false) {
            $p = preg_split('/\s+/', trim($line));
            if (count($p) < 5 || !ctype_digit($p[0])) continue;
            if ($p[2] !== 'C' && $p[2] !== 'D') continue;
            if ($p[4] === '@NODE@') continue;   // never list this node itself
            $ev[] = ['t' => (int)$p[0], 'e' => $p[2], 'n' => $p[4]];
        }
        fclose($fh);
    }
    usort($ev, fn($a, $b) => $a['t'] <=> $b['t']);
    // the same connect can be logged twice within a second or two (Asterisk's own connect program and the tracker): keep the first
    $last = []; $out = [];
    foreach ($ev as $x) {
        $l = $last[$x['n']] ?? null;
        if ($x['e'] === 'C' && $l && $l['e'] === 'C' && $x['t'] - $l['t'] <= 3) continue;
        $last[$x['n']] = $x; $out[] = $x;
    }
    return $out;
}
function newer_version() {
    // newest published version (saved once a day by checkver.sh); only digits and dots are accepted
    $cur = '@VERSION@';
    $f = LOGDIR . '/latest-version.txt';
    if (!is_readable($f)) return null;
    $v = trim((string)@file_get_contents($f, false, null, 0, 64));
    if (!preg_match('/^[0-9]+(\.[0-9]+){1,3}$/', $v)) return null;
    return version_compare($v, $cur, '>') ? $v : null;
}
function echolink_web($q) {
    // same public EchoLink lookup page the background job uses (needs the session cookie it hands out first)
    $url = getenv('CL_ELURL') ?: 'https://www.echolink.org/validation/node_lookup.jsp';
    $ctx = stream_context_create(['http' => ['method' => 'GET', 'timeout' => 8, 'header' => "User-Agent: ConnectLookup\r\n"]]);
    $r = @file_get_contents($url, false, $ctx);
    if ($r === false) return '';
    $ck = [];
    foreach (($http_response_header ?? []) as $h) if (stripos($h, 'Set-Cookie:') === 0) $ck[] = trim((string)strtok(substr($h, 11), ';'));
    $ctx = stream_context_create(['http' => ['method' => 'POST', 'timeout' => 8,
        'header' => "Content-Type: application/x-www-form-urlencoded\r\nUser-Agent: ConnectLookup\r\n" . ($ck ? 'Cookie: ' . implode('; ', $ck) . "\r\n" : ''),
        'content' => 'call=' . $q]]);
    $r = @file_get_contents($url, false, $ctx);
    if ($r === false) return '';
    $r = str_replace(["\r", "\n"], '', $r);
    if (preg_match('~<td>([^<]+)</td><td align="right">' . $q . '</td>~', $r, $m)) {
        $c = trim($m[1]);
        return preg_match('~^[A-Za-z0-9/*-]{3,20}$~', $c) ? $c : '';
    }
    return '';
}
function echo_lookup($csv) {
    $nodes = [];
    foreach (explode(',', substr($csv, 0, 200)) as $n) {
        $n = trim($n);
        if (preg_match('/^3[0-9]{6}$/', $n)) $nodes[$n] = 1;
        if (count($nodes) >= 12) break;
    }
    $out = [];
    if (!$nodes) return $out;
    $em = ei_map();
    $cf = sys_get_temp_dir() . '/connect-lookup-echo.json';
    $cache = is_readable($cf) ? (json_decode((string)@file_get_contents($cf), true) ?: []) : [];
    $tries = 0; $dirty = false;
    foreach (array_keys($nodes) as $n) {
        $c = trim((string)($em[$n]['callsign'] ?? ''));
        if ($c === '') {
            $k = $cache[$n] ?? null;
            if (is_array($k) && time() - (int)($k['t'] ?? 0) < ($k['c'] !== '' ? 86400 : 3600)) $c = (string)$k['c'];
            elseif ($tries < 3) { $tries++; $c = echolink_web((int)substr($n, 1)); $cache[$n] = ['c' => $c, 't' => time()]; $dirty = true; }
        }
        if ($c !== '') $out[$n] = $c;
    }
    if ($dirty) @file_put_contents($cf, json_encode($cache), LOCK_EX);
    return $out;
}
function panel_path() {
    // optional right-hand panel: panel.txt holds ONE same-site path such as /node-connect/ ; nothing is shown without that file
    $f = '/var/www/html/connect-lookup/panel.txt';
    if (!is_readable($f)) return null;
    $v = trim((string)@file_get_contents($f, false, null, 0, 200));
    $v = trim((string)strtok($v, "\r\n"));
    if (!preg_match('~^/[A-Za-z0-9._/-]{0,100}$~', $v)) return null;
    if (strpos($v, '//') !== false || strpos($v, '..') !== false) return null;
    return $v;
}
function node_info($nodes) {
    $want = array_flip($nodes);
    $out = [];
    $fh = @fopen(ASTDB, 'r');
    if (!$fh) return $out;
    while (($line = fgets($fh)) !== false && count($out) < count($want)) {
        $i = strpos($line, '|');
        if ($i === false) continue;
        $k = substr($line, 0, $i);
        if (isset($want[$k])) {
            $p = explode('|', rtrim($line), 4);
            $out[$k] = ['call' => $p[1] ?? '', 'desc' => $p[2] ?? '', 'loc' => $p[3] ?? ''];
        }
    }
    fclose($fh);
    return $out;
}
function via_map() {
    $f = '/var/log/asterisk/node-history/topology.json';
    $out = [];
    if (!is_readable($f) || time() - filemtime($f) > 21600) return $out;
    $j = json_decode(@file_get_contents($f), true);
    if (!is_array($j)) return $out;
    foreach (($j['direct'] ?? []) as $d) {
        if (isset($d['node'])) $out[(string)$d['node']] = 'Direct';
    }
    $walk = function ($a) use (&$walk, &$out) {
        if (!is_array($a)) return;
        if (isset($a['node'], $a['direct_node'])) {
            $n = (string)$a['node'];
            if (!isset($out[$n])) {
                $via = 'via ' . $a['direct_node'];
                if (isset($a['parent_node']) && (string)$a['parent_node'] !== (string)$a['direct_node']) $via .= ' > ' . $a['parent_node'];
                $out[$n] = $via;
                if (!empty($a['reported_node'])) $out[(string)$a['reported_node']] = $via;
            }
        }
        foreach ($a as $v) { if (is_array($v)) $walk($v); }
    };
    $walk($j['display_nodes'] ?? []);
    $walk($j);
    return $out;
}
function add_via($r) {
    $vm = via_map();
    $em = ei_map();
    $hs = []; $sf = LOGDIR . "/direct-starts.txt"; if (is_readable($sf)) foreach (file($sf, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $hl) { $hp = preg_split("/[[:space:]]+/", trim($hl)); if (count($hp) >= 2) $hs[$hp[0]][] = (int)$hp[1]; }
    $ds = [];
    $df = LOGDIR . '/direct.txt';
    if (is_readable($df) && time() - filemtime($df) < 20) {
        foreach (file($df, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $ln) {
            $p = preg_split('/\s+/', trim($ln));
            if ($p[0] === '') continue;
            $vm[$p[0]] = 'Direct';
            if (isset($p[1])) $ds[$p[0]] = (int)$p[1];
        }
    }
    foreach ($r['sessions'] as $k => $s) {
        $n = (string)$s['node'];
        $r['sessions'][$k]['via'] = $vm[$n] ?? '';
        if ($s['start'] === null && $s['end'] === null && isset($ds[$n])) $r['sessions'][$k]['start'] = $ds[$n];
        if ($s["start"] === null && $s["end"] !== null && !empty($hs[$n])) { $c = array_filter($hs[$n], fn($t) => $t <= $s["end"]); if ($c) $r["sessions"][$k]["start"] = max($c); }
        $e = $em[$n] ?? null;
        if ($e && $s['call'] === '') {
            $r['sessions'][$k]['call'] = $e['callsign'];
            if (($s['loc'] ?? '') === '') $r['sessions'][$k]['loc'] = $e['location'] ?? '';
        }
    }
    $pp = []; foreach ([LOGDIR . "/people.txt", "/var/www/html/connect-lookup/people.txt"] as $pf) { if (is_readable($pf)) foreach (file($pf, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $pl) { $pq = explode("|", $pl, 2); if (count($pq) == 2) $pp[strtoupper(trim($pq[0]))] = trim($pq[1]); } }
    foreach ($r["sessions"] as $k => $s) { $bc = strtoupper(preg_replace("/-.*/", "", (string)$s["call"])); $r["sessions"][$k]["name"] = rtrim($pp[$bc] ?? "", " ."); }
    usort($r['sessions'], fn($a, $b) => ($b['start'] ?? $b['end'] ?? 0) <=> ($a['start'] ?? $a['end'] ?? 0));
    return $r;
}
function add_keyed($r) { $k = []; $f = LOGDIR . '/keyed.txt'; if (is_readable($f) && time() - filemtime($f) < 10) foreach (file($f, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $l) { $l = trim($l); if ($l !== '') $k[] = $l; } $r['keyed'] = $k; return $r; }
function ei_map() { $f = "/var/log/asterisk/node-history/topology.json"; $o = []; $j = is_readable($f) ? json_decode(@file_get_contents($f), true) : null; foreach (($j["display_nodes"] ?? []) as $d) { if (($d["callsign"] ?? "") === "") continue; foreach ([$d["node"] ?? "", $d["reported_node"] ?? ""] as $k) { if ($k !== "") $o[(string)$k] = $d; } } $ef = LOGDIR . "/elnames.txt"; if (is_readable($ef)) foreach (file($ef, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $ln) { $p = explode("|", $ln); if (count($p) >= 2) $o["3" . trim($p[0])] = ["callsign" => trim($p[1]), "location" => ""]; } $nf = "/var/www/html/connect-lookup/names.txt"; if (is_readable($nf)) foreach (file($nf, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $ln) { $p = explode("|", $ln); if (count($p) >= 2) $o[trim($p[0])] = ["callsign" => trim($p[1]), "location" => trim($p[3] ?? "")]; } return $o; }
function build() {
    $now = time();
    $cut = $now - 86400;
    $open = [];
    $sess = [];
    $last = [];
    foreach (load_events() as $x) {
        $n = $x['n'];
        $last[$n] = $x['t'];
        $pe = $lastE[$n] ?? ''; $lastE[$n] = $x['e'];
        if ($x['e'] === 'C') {
            // a second C with no D in between means the link was set up again (for example after a restart): the earlier visit ended then
            if (isset($open[$n])) { $s = $open[$n]; $s['end'] = $x['t']; $sess[] = $s; }
            $open[$n] = ['node' => $n, 'start' => $x['t'], 'end' => null];
        } else {
            if (isset($open[$n])) { $s = $open[$n]; $s['end'] = $x['t']; $sess[] = $s; unset($open[$n]); }
            elseif ($pe !== 'D') { $sess[] = ['node' => $n, 'start' => null, 'end' => $x['t']]; }
        }
    }
    $lf = LOGDIR . '/live.txt';
    if (is_file($lf) && $now - filemtime($lf) < 20) {
        $lt = filemtime($lf);
        $live = [];
        foreach (file($lf, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $l) { $t = trim($l); if ($t !== '@NODE@') $live[$t] = true; }
        foreach ($open as $n => $s) {
            if (!isset($live[$n]) && ($s['start'] ?? 0) < $lt - 5) {
                $s['end'] = $lt; $sess[] = $s; unset($open[$n]);
            }
        }
        foreach ($live as $n => $_) {
            $n = (string)$n;
            if (!isset($open[$n]) && ($last[$n] ?? 0) < $lt - 5) {
                $open[$n] = ['node' => $n, 'start' => null, 'end' => null];
            }
        }
    }
    foreach ($open as $s) $sess[] = $s;
    $sess = array_values(array_filter($sess, fn($s) => $s['end'] === null || $s['end'] >= $cut));
    usort($sess, fn($a, $b) => ($b['start'] ?? $b['end'] ?? 0) <=> ($a['start'] ?? $a['end'] ?? 0));
    $info = node_info(array_values(array_unique(array_column($sess, 'node'))));
    foreach ($sess as &$s) {
        $i = $info[$s['node']] ?? null;
        $s['call'] = $i['call'] ?? (ctype_digit($s['node']) ? '' : $s['node']);
        $s['desc'] = $i['desc'] ?? '';
        if ($s["desc"] === "" && preg_match("/^3[0-9]{6}$/", (string)$s["node"])) $s["desc"] = "EchoLink node " . substr((string)$s["node"], 1);
        if ($s["desc"] === "" && !ctype_digit((string)$s["node"])) $s["desc"] = "Web Transceiver";
        $s['loc']  = $i['loc'] ?? '';
    }
    unset($s);
    return ['now' => $now, 'sessions' => $sess];
}
// ---- Full control / Read-only switch for the panel ----
// panel-access.php (written by the installer, next to this file) holds the app's settings-file path, the row and the two levels,
// and the HASH of the switch password. The password itself is never stored anywhere.
function perm_cfg() {
    static $c = false;
    if ($c === false) {
        $f = __DIR__ . '/panel-access.php';
        $c = is_readable($f) ? include $f : null;
        if (!is_array($c) || !isset($c['db'], $c['id'], $c['full'], $c['ro'])) $c = null;
    }
    return $c;
}
function perm_pdo($c) {
    $p = new PDO('sqlite:' . $c['db']);
    $p->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $p->exec('PRAGMA busy_timeout=5000');
    return $p;
}
function perm_get($c) {
    try {
        $s = perm_pdo($c)->prepare('select val from cfg where cfg_id = ?');
        $s->execute([(int)$c['id']]);
        $v = $s->fetchColumn();
        return $v === false ? null : (int)$v;
    } catch (Throwable $e) { return null; }
}
function perm_set($c, $lvl) {
    try {
        $s = perm_pdo($c)->prepare('insert or replace into cfg (cfg_id, val, updated) values (?, ?, ?)');
        $s->execute([(int)$c['id'], (string)(int)$lvl, time()]);
        return true;
    } catch (Throwable $e) { return false; }
}
function perm_token($c, $exp) { return $exp . '.' . hash_hmac('sha256', 'cl-perm|' . $exp, (string)$c['hash']); }
function perm_unlocked($c) {
    // a browser that gave the right password stays unlocked for 8 hours (signed cookie; changing the password locks every browser again)
    if ((string)($c['hash'] ?? '') === '') return false;
    $t = (string)($_COOKIE['cl_perm'] ?? '');
    $p = explode('.', $t, 2);
    if (count($p) !== 2 || !ctype_digit($p[0]) || (int)$p[0] < time()) return false;
    return hash_equals(perm_token($c, (int)$p[0]), $t);
}
function perm_fail_file() { return sys_get_temp_dir() . '/connect-lookup-auth.json'; }
function perm_wait() {
    // after 5 wrong passwords in 10 minutes, one more try is allowed only every 5 minutes
    $f = perm_fail_file();
    $a = is_readable($f) ? json_decode((string)@file_get_contents($f), true) : [];
    $now = time();
    $a = array_values(array_filter(is_array($a) ? $a : [], fn($t) => is_int($t) && $t > $now - 600));
    if (count($a) < 5) return 0;
    return max(0, max($a) + 300 - $now);
}
function perm_note($ok) {
    $fh = @fopen(perm_fail_file(), 'c+');
    if (!$fh) return;
    flock($fh, LOCK_EX);
    $a = json_decode((string)stream_get_contents($fh), true);
    $now = time();
    $a = ($ok || !is_array($a)) ? [] : array_values(array_filter($a, fn($t) => is_int($t) && $t > $now - 600));
    if (!$ok) $a[] = $now;
    ftruncate($fh, 0); rewind($fh); fwrite($fh, json_encode($a));
    flock($fh, LOCK_UN); fclose($fh);
}
if (isset($_GET['perm'])) {
    header('Content-Type: application/json'); header('Cache-Control: no-store');
    $c = perm_cfg();
    if (!$c) { echo json_encode(['enabled' => false]); exit; }
    $can = (string)($c['hash'] ?? '') !== '';
    $err = ''; $unl = false; $lock = false;
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $b = json_decode((string)file_get_contents('php://input', false, null, 0, 2000), true);
        $mode = is_array($b) ? (string)($b['mode'] ?? '') : '';
        if (($_SERVER['HTTP_X_CL_PERM'] ?? '') !== '1' || ($mode !== 'full' && $mode !== 'ro')) {
            $err = 'Bad request.';
        } elseif (!$can) {
            $err = 'No password has been set for this switch yet. On the node, run the installer with --password.';
        } else {
            $ok = ($mode === 'ro') || perm_unlocked($c);   // turning Full control OFF never asks for the password
            if (!$ok) {
                $w = perm_wait();
                if ($w > 0) {
                    $err = 'Too many wrong passwords. Try again in ' . (int)ceil($w / 60) . ' minute(s).';
                } else {
                    $pw = (is_array($b) && is_string($b['pw'] ?? null)) ? $b['pw'] : '';
                    if ($pw !== '' && password_verify($pw, (string)$c['hash'])) {
                        $ok = true; $unl = true; perm_note(true);
                        $exp = time() + 28800;
                        setcookie('cl_perm', perm_token($c, $exp), ['expires' => $exp, 'path' => rtrim(dirname($_SERVER['SCRIPT_NAME']), '/') . '/', 'secure' => !empty($_SERVER['HTTPS']), 'httponly' => true, 'samesite' => 'Strict']);
                    } else {
                        perm_note(false); usleep(700000);
                        $err = 'Wrong password.';
                    }
                }
            }
            if ($ok && !perm_set($c, $mode === 'full' ? (int)$c['full'] : (int)$c['ro'])) $err = "The change could not be saved: the web server cannot write the app's settings file.";
            if ($ok && $err === '' && $mode === 'ro') {
                // turned OFF: lock this browser again, so turning Full control back ON asks for the password
                $lock = true;
                setcookie('cl_perm', '', ['expires' => time() - 3600, 'path' => rtrim(dirname($_SERVER['SCRIPT_NAME']), '/') . '/', 'secure' => !empty($_SERVER['HTTPS']), 'httponly' => true, 'samesite' => 'Strict']);
            }
        }
    }
    $cur = perm_get($c);
    $o = ['enabled' => true, 'full' => $cur === (int)$c['full'], 'canChange' => $can, 'unlocked' => !$lock && ($unl || perm_unlocked($c))];
    if ($err !== '') $o['error'] = $err;
    echo json_encode($o); exit;
}
if (isset($_GET['echo'])) { header('Content-Type: application/json'); header('Cache-Control: no-store'); echo json_encode(echo_lookup((string)$_GET['echo']), JSON_FORCE_OBJECT); exit; }
if (isset($_GET['keyed'])) { header('Content-Type: application/json'); header('Cache-Control: no-store'); echo json_encode(add_keyed([])); exit; }
if (isset($_GET['json'])) {
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    $o = add_keyed(add_via(build())); $o['newer'] = newer_version();
    echo json_encode($o, JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}
$PANEL = panel_path();
$PCSS = ''; $PW = []; $PR = []; $PJS = '';
if ($PANEL !== null) {
    // panel.css: extra CSS applied inside the panel; panel-words.txt: lines  old|new  (or old, a TAB, then new, when old contains a | mark); plain text swaps, shown text only
    $f = '/var/www/html/connect-lookup/panel.css';
    if (is_readable($f)) $PCSS = (string)@file_get_contents($f, false, null, 0, 20000);
    $f = '/var/www/html/connect-lookup/panel-words.txt';
    if (is_readable($f)) foreach (array_slice(file($f, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [], 0, 40) as $l) {
        $l = rtrim($l, "\r");
        if ($l === '' || $l[0] === '#' || (strpos($l, '|') === false && strpos($l, "\t") === false)) continue;
        list($a, $b) = explode(strpos($l, "\t") !== false ? "\t" : '|', $l, 2);
        if ($a === '' || strlen($a) > 80 || strlen($b) > 80) continue;
        $PW[] = [$a, $b];
    }
    // panel.js: optional small script run inside the panel page as function(doc, data); doc = the panel's page, data = this page's connection data
    $f = '/var/www/html/connect-lookup/panel.js';
    if (is_readable($f)) $PJS = (string)@file_get_contents($f, false, null, 0, 20000);
    // panel-remove.txt: one CSS selector per line; matching things are taken out of the panel page
    $f = '/var/www/html/connect-lookup/panel-remove.txt';
    if (is_readable($f)) foreach (array_slice(file($f, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [], 0, 40) as $l) {
        $l = trim($l);
        if ($l === '' || $l[0] === '#' || strlen($l) > 120) continue;
        if (!preg_match('/^[A-Za-z0-9#._\[\]="\' :*,>+~-]+$/', $l)) continue;
        $PR[] = $l;
    }
}
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Connect Lookup - Node @NODE@</title>
<style>
body{font:15px system-ui,sans-serif;background:#111;color:#e6e6e6;margin:0;padding:16px}
h1{font-size:20px;margin:0 0 4px}
h2{font-size:16px;margin:24px 0 8px;color:#9ecbff}
.sub{color:#888;font-size:13px}
table{border-collapse:collapse;width:100%;max-width:1100px}
th,td{padding:6px 10px;border-bottom:1px solid #2a2a2a;text-align:left}
th{color:#999;font-weight:600;font-size:13px}
a{color:#7cc4ff;text-decoration:none}
a:hover{text-decoration:underline}
a.nl{color:inherit}
#ver a{color:#e05555;text-decoration:underline;animation:clpulse 4s ease-in-out infinite}
#ver a:hover{animation:none;opacity:1}
@keyframes clpulse{0%,100%{opacity:.35}50%{opacity:1}}
@media (prefers-reduced-motion:reduce){#ver a{animation:none}}
.live{color:#5fe08a;font-weight:600}
.empty{color:#777}
.echo td:not(.live), .echo td:not(.live) a { color: #c4e8ff; }
td{font-variant-numeric:tabular-nums}
td[data-start]{min-width:7.5em;white-space:nowrap}
tr.keyed td{background:#2a1212;box-shadow:inset 0 2px 0 #a63636,inset 0 -2px 0 #a63636}
tr.keyed td:first-child{box-shadow:inset 2px 0 0 #a63636,inset 0 2px 0 #a63636,inset 0 -2px 0 #a63636}
tr.keyed td:last-child{box-shadow:inset -2px 0 0 #a63636,inset 0 2px 0 #a63636,inset 0 -2px 0 #a63636}
tr.behind td{box-shadow:inset 0 1px 0 #6e3a3a,inset 0 -1px 0 #6e3a3a}
tr.behind td:first-child{box-shadow:inset 1px 0 0 #6e3a3a,inset 0 1px 0 #6e3a3a,inset 0 -1px 0 #6e3a3a}
tr.behind td:last-child{box-shadow:inset -1px 0 0 #6e3a3a,inset 0 1px 0 #6e3a3a,inset 0 -1px 0 #6e3a3a}
#wrap{display:block}
#main{min-width:0}
body.wp #wrap{display:grid;grid-template-columns:minmax(0,1fr) minmax(380px,44%);gap:16px;align-items:start}
body.wp #main{overflow-x:auto}
#panel{display:none}
body.wp #panel{display:flex;flex-direction:column;position:sticky;top:16px;height:calc(100vh - 32px);border:1px solid #2a2a2a;border-radius:6px;overflow:hidden;background:#161616}
html.ph body.wp #panel{display:none}
html.ph body.wp #wrap{display:block}
#panelbar{display:flex;align-items:center;flex-wrap:wrap;gap:10px;padding:6px 10px;border-bottom:1px solid #2a2a2a;font-size:13px;color:#999}
#panelbar b{color:#9ecbff;font-weight:600}
#panelbar button{background:none;border:0;padding:0;font:inherit;color:#7cc4ff;cursor:pointer}
#panelbar button:hover{text-decoration:underline}
#panelbar #panelReload{margin-left:auto}
#panelbar #permBtn{border:1px solid #2f7d4f;border-radius:11px;padding:1px 10px;color:#7be0a0}
#panelbar #permBtn.ro{border-color:#a33;color:#ff9c9c}
#panelbar #permBtn.dim{opacity:.55;cursor:help}
#panelbar #permBtn:hover{text-decoration:none;background:#1c1c1c}
#permForm{display:flex;align-items:center;gap:6px;margin:0}
#permForm[hidden]{display:none}
#permForm input{width:9em;font:inherit;background:#1c1c1c;color:#e6e6e6;border:1px solid #333;border-radius:3px;padding:2px 6px}
#permMsg{color:#e0b45f;font-size:12px}
#permMsg:empty{display:none}
#panelf{flex:1;width:100%;border:0;background:#111}
@media (max-width:1100px){body.wp #wrap{grid-template-columns:1fr}body.wp #panel{position:static;height:85vh}}
.opt{margin:10px 0 0;font-size:13px;color:#aaa}
.opt label{cursor:pointer}
.opt input{vertical-align:middle;margin-right:6px}
@media (max-width:700px){
body{padding:10px}
h1{font-size:18px}
h2{margin:18px 0 6px}
#main table,#main thead,#main tbody,#main tr,#main td{display:block;width:auto;max-width:none}
#main thead{display:none}
#main tr{position:relative;margin:0 0 8px;padding:5px 10px;background:#161616;border:1px solid #2a2a2a;border-radius:6px}
#main td{position:relative;padding:2px 0 2px 7.4em;border:0;min-width:0;overflow-wrap:anywhere}
#main td::before{position:absolute;left:0;top:2px;width:7em;color:#888;font-size:12px;font-weight:600}
#main td[data-start]{min-width:0}
#main td.empty{padding-left:0}
#nowBody td:nth-child(1)::before{content:"Node"}
#nowBody td:nth-child(2)::before{content:"Callsign"}
#nowBody td:nth-child(3)::before{content:"Name"}
#nowBody td:nth-child(4)::before{content:"Through"}
#nowBody td:nth-child(5)::before{content:"Location"}
#nowBody td:nth-child(6)::before{content:"Connected"}
#nowBody td:nth-child(7)::before{content:"So far"}
#histBody td:nth-child(1)::before{content:"Connected"}
#histBody td:nth-child(2)::before{content:"Disconnected"}
#histBody td:nth-child(3)::before{content:"Duration"}
#histBody td:nth-child(4)::before{content:"Node"}
#histBody td:nth-child(5)::before{content:"Callsign"}
#histBody td:nth-child(6)::before{content:"Name"}
#histBody td:nth-child(7)::before{content:"Location"}
#main td.empty::before{content:none}
#main tr.keyed,#main tr.behind{box-shadow:none}
#main tr.keyed td,#main tr.keyed td:first-child,#main tr.keyed td:last-child,#main tr.behind td,#main tr.behind td:first-child,#main tr.behind td:last-child{box-shadow:none;background:transparent}
#main tr.keyed{background:#2a1212;border-color:#a63636;box-shadow:inset 0 0 0 1px #a63636}
#main tr.behind{border-color:#6e3a3a}
}
</style>
</head>
<body<?php if ($PANEL !== null) echo ' class="wp"'; ?>>
<div id="wrap">
<div id="main">
<div class="sub" id="ver">Version @VERSION@</div>
<h1>Connect Lookup - Node @NODE@</h1>
<div class="sub" id="status">Loading...</div>
<div class="opt"><label><input type="checkbox" id="behindBox">Outline the stations behind a link while that link is transmitting</label></div>
<?php if ($PANEL !== null): ?>
<div class="opt"><label><input type="checkbox" id="panelBox">Show the node-connect panel on the right</label></div>
<?php endif; ?>
<div class="opt"><a href="https://stats.allstarlink.org/stats/@NODE@/networkMap" target="_blank" rel="noopener noreferrer">Network map for node @NODE@</a> (AllStarLink stats site)</div>
<h2>Connected now <span id="nowCount"></span></h2>
<table>
<thead><tr><th>Node</th><th>Callsign</th><th>Name</th><th>Connected through</th><th>Description / Location</th><th>Connected at</th><th>So far</th></tr></thead>
<tbody id="nowBody"></tbody>
</table>
<h2>Last 24 hours <span id="histCount"></span></h2>
<table>
<thead><tr><th>Connected</th><th>Disconnected</th><th>Duration</th><th>Node</th><th>Callsign</th><th>Name</th><th>Description / Location</th></tr></thead>
<tbody id="histBody"></tbody>
</table>
</div>
<?php if ($PANEL !== null): $pe = htmlspecialchars($PANEL, ENT_QUOTES); ?>
<aside id="panel">
<div id="panelbar"><b>node-connect</b><button type="button" id="permBtn" hidden></button><form id="permForm" hidden><input type="password" id="permPw" placeholder="Switch password" autocomplete="off" maxlength="200"><button type="submit">OK</button><button type="button" id="permCancel">Cancel</button></form><span id="permMsg"></span><button type="button" id="panelReload">Reload</button></div>
<iframe id="panelf" title="node-connect" src="<?php echo $pe; ?>"></iframe>
</aside>
<?php endif; ?>
</div>
<script>
try { if (localStorage.getItem('cl-panel') !== '1') document.documentElement.className = 'ph'; } catch (e) {}
var PANELCSS = <?php echo json_encode($PCSS, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_INVALID_UTF8_SUBSTITUTE); ?>;
var PANELJS = <?php echo json_encode($PJS, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_INVALID_UTF8_SUBSTITUTE); ?>;
var PANELREMOVE = <?php echo json_encode($PR, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_INVALID_UTF8_SUBSTITUTE); ?>;
var PANELWORDS = <?php echo json_encode($PW, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_INVALID_UTF8_SUBSTITUTE); ?>;
var BEHIND = false;
try { BEHIND = localStorage.getItem('cl-behind') === '1'; } catch (e) {}
var data = null;
var VER = '@VERSION@';
var REPO = 'https://github.com/k4jlb/connect-lookup';
var verShown = null;
function setVer(n){ var e = document.getElementById('ver'); if (!e) return; var ok = typeof n === 'string' && /^[0-9]+(\.[0-9]+){1,3}$/.test(n); var key = ok ? n : ''; if (key === verShown) return; verShown = key; e.textContent = 'Version ' + VER; if (!ok) { e.classList.remove('upd'); return; } e.textContent = 'Version ' + VER + ' - version ' + n + ' is available: '; var a = document.createElement('a'); a.href = REPO; a.target = '_blank'; a.rel = 'noopener noreferrer'; a.textContent = 'get it on GitHub'; e.appendChild(a); e.classList.add('upd'); }
function $(id){ return document.getElementById(id); }
function fmtTime(t){ return new Date(t*1000).toLocaleTimeString([], {hour:'numeric',minute:'2-digit',second:'2-digit'}); }
function fmtDate(t){ return new Date(t*1000).toLocaleDateString([], {month:'short',day:'numeric'}); }
function fmtBoth(t){ return fmtDate(t) + ' ' + fmtTime(t); }
function dur(s){
  s = Math.max(0, Math.floor(s));
  var h = Math.floor(s/3600), m = Math.floor((s%3600)/60), x = s%60;
  return h ? h+'h '+m+'m' : (m ? m+'m '+x+'s' : x+'s');
}
function cell(tr, content, cls){
  var td = document.createElement('td');
  if (content instanceof Node) td.appendChild(content); else td.textContent = content;
  if (cls) td.className = cls;
  tr.appendChild(td);
  return td;
}
function nodeCell(tr, s){
  var n = String(s.node);
  var td = cell(tr, n);
  var m = n.match(/^[A-Za-z0-9]+(\/[A-Za-z0-9]+)?/);
  var cs = m ? m[0] : '';
  if (cs === n && /[0-9]/.test(cs) && /[A-Za-z]/.test(cs)) {
    var a = document.createElement('a');
    a.href = 'https://www.qrz.com/db/' + encodeURIComponent(cs.toUpperCase());
    a.target = '_blank';
    a.rel = 'noopener';
    a.textContent = n;
    td.textContent = '';
    td.appendChild(a);
  } else if (/^[0-9]+$/.test(n) && !/^3[0-9]{6}$/.test(n)) {
    var b = document.createElement('a');
    b.href = 'https://stats.allstarlink.org/stats/' + encodeURIComponent(n) + '/networkMap';
    b.target = '_blank';
    b.rel = 'noopener noreferrer';
    b.className = 'nl';
    b.textContent = n;
    td.textContent = '';
    td.appendChild(b);
  }
  return td;
}
function callCell(s){
  var call = (s.call || '').trim();
  var m = call.match(/^[A-Za-z0-9]+(\/[A-Za-z0-9]+)?/);
  var cs = m ? m[0] : '';
  if (cs && /[0-9]/.test(cs) && /[A-Za-z]/.test(cs)) {
    var a = document.createElement('a');
    a.href = 'https://www.qrz.com/db/' + encodeURIComponent(cs.toUpperCase());
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    a.textContent = call;
    return a;
  }
  return document.createTextNode(call);
}
function infoText(s){
  return [s.desc, s.loc].filter(function(x){ return x; }).join(' - ');
}
var lastSig = '';
function buildTables(){
  var nowT = data.now + (Date.now() - data.fetched)/1000;
  var live = data.sessions.filter(function(s){ return s.end === null; });
  var nb = $('nowBody');
  nb.replaceChildren();
  if (!live.length) {
    var tr0 = document.createElement('tr');
    var td0 = cell(tr0, 'Nobody connected right now', 'empty');
    td0.colSpan = 7;
    nb.appendChild(tr0);
  }
  live.forEach(function(s){
    var tr = document.createElement('tr');
    if (/^3[0-9]{6}$/.test(String(s.node))) tr.className = "echo";
    nodeCell(tr, s);
    cell(tr, callCell(s));
    cell(tr, s.name || "-");
    var vv = s.via || "-"; cell(tr, vv, vv === "Direct" ? "live" : "");
    cell(tr, infoText(s));
    cell(tr, s.start ? fmtBoth(s.start) : 'before logging began');
    if (s.start) cell(tr, dur(nowT - s.start), 'live').setAttribute('data-start', s.start);
    else cell(tr, '-', 'live');
    tr.setAttribute("data-node", s.node);
    tr.setAttribute("data-via", s.via || "");
    nb.appendChild(tr);
  });
  var hb = $('histBody'); var done = data.sessions.filter(function(s){ return s.end !== null; }); $("nowCount").textContent = "(" + (data.sessions.length - done.length) + ")"; $("histCount").textContent = "(" + done.length + ")";
  done.sort(function(a, b) { return b.end - a.end; });
  hb.replaceChildren();
  if (!done.length) {
    var tr1 = document.createElement('tr');
    var td1 = cell(tr1, 'No connections in the last 24 hours', 'empty');
    td1.colSpan = 7;
    hb.appendChild(tr1);
  }
  done.forEach(function(s){
    var tr = document.createElement('tr');
    if (/^3[0-9]{6}$/.test(String(s.node))) tr.className = "echo";
    cell(tr, s.start ? fmtBoth(s.start) : 'before logging began');
    if (s.end === null) cell(tr, 'Connected now', 'live'); else cell(tr, fmtBoth(s.end));
    if (s.start && s.end !== null) cell(tr, dur(s.end - s.start));
    else if (s.start) cell(tr, dur(nowT - s.start), 'live').setAttribute('data-start', s.start);
    else cell(tr, '-');
    nodeCell(tr, s);
    cell(tr, callCell(s));
    cell(tr, s.name || "-");
    cell(tr, infoText(s));
    hb.appendChild(tr);
  });
}
function tick(){
  if (!data) return;
  var nowT = data.now + (Date.now() - data.fetched)/1000;
  var els = document.querySelectorAll('[data-start]');
  for (var i = 0; i < els.length; i++) {
    els[i].textContent = dur(nowT - Number(els[i].getAttribute('data-start')));
  }
}
var kt = {};
function noteKeyed(a){ var t = Date.now(); for (var j = 0; j < a.length; j++) kt[a[j]] = t; }
function applyKeyed(){ var t = Date.now(); var rows = document.querySelectorAll('#nowBody tr[data-node]'); for (var i = 0; i < rows.length; i++) { var s = kt[rows[i].getAttribute('data-node')]; var on = s !== undefined && t - s < 2200; rows[i].classList.toggle('keyed', on); var m = (rows[i].getAttribute('data-via') || '').match(/^via (\S+)/); var d = m ? kt[m[1]] : undefined; rows[i].classList.toggle('behind', BEHIND && !on && d !== undefined && t - d < 2200); } }
function pollKeyed(){ fetch('?keyed=1', {cache:'no-store'}).then(function(r){ return r.json(); }).then(function(j){ if (data) { data.keyed = j.keyed; } noteKeyed(j.keyed || []); applyKeyed(); }).catch(function(){}); }
function poll(){
  fetch('?json=1', {cache:'no-store'})
    .then(function(r){ return r.json(); })
    .then(function(j){
      j.fetched = Date.now();
      noteKeyed(j.keyed || []);
      data = j;
      setVer(j.newer);
      var sig = JSON.stringify(j.sessions);
      if (sig !== lastSig) { lastSig = sig; buildTables(); }
      applyKeyed();
      tick();
      $('status').textContent = 'Live - last update ' + new Date().toLocaleTimeString();
    })
    .catch(function(){ $('status').textContent = 'Update failed - retrying...'; });
}
(function(){ var b = $('behindBox'); b.checked = BEHIND; b.addEventListener('change', function(){ BEHIND = b.checked; try { localStorage.setItem('cl-behind', BEHIND ? '1' : '0'); } catch (e) {} applyKeyed(); }); })();
(function(){
  var b = $('panelBox'); if (!b) return;
  var on = false; try { on = localStorage.getItem('cl-panel') === '1'; } catch (e) {}
  b.checked = on;
  b.addEventListener('change', function(){
    document.documentElement.className = b.checked ? '' : 'ph';
    try { localStorage.setItem('cl-panel', b.checked ? '1' : '0'); } catch (e) {}
  });
  var r = $('panelReload'), f = $('panelf');
  if (r && f) r.addEventListener('click', function(){ f.src = f.getAttribute('src'); });
  if (!f) return;
  function esc(t){ return t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
  var rx = PANELWORDS.map(function(w){ return [new RegExp(esc(w[0]), 'gi'), w[1]]; });
  function swap(d){
    if (!rx.length || !d.body) return;
    var wk = d.createTreeWalker(d.body, 4, null), n, i, v;
    while ((n = wk.nextNode())) { v = n.nodeValue; for (i = 0; i < rx.length; i++) v = v.replace(rx[i][0], rx[i][1]); if (v !== n.nodeValue) n.nodeValue = v; }
    var t = d.title; for (i = 0; i < rx.length; i++) t = t.replace(rx[i][0], rx[i][1]); if (t !== d.title) d.title = t;
  }
  var pfn = null;
  if (PANELJS) { try { pfn = new Function('doc', 'data', PANELJS); } catch (e) {} }
  function extra(d){ if (pfn) { try { pfn(d, data); } catch (e) {} } }
  function strip(d){
    var i, j, el, list, at;
    for (i = 0; i < PANELREMOVE.length; i++) {
      try { list = d.querySelectorAll(PANELREMOVE[i]); } catch (e) { continue; }
      for (j = 0; j < list.length; j++) {
        el = list[j];
        if (el.tagName === 'INPUT' && el.type === 'checkbox') { el.checked = false; el.type = 'hidden'; el.setAttribute('data-cl-off', '1'); }
        else if (el.parentNode && !el.getAttribute('data-cl-off')) el.parentNode.removeChild(el);
      }
    }
    list = d.querySelectorAll('[data-cl-off]');
    for (j = 0; j < list.length; j++) {
      el = list[j]; el.checked = false;
      for (i = 0; i < el.attributes.length; i++) { at = el.attributes[i]; if (at.value === 'true') el.setAttribute(at.name, 'false'); }
    }
  }
  function dress(){
    var d; try { d = f.contentDocument; } catch (e) { return; }
    if (!d || !d.head || !d.documentElement) return;
    if (!d.getElementById('cl-panel-css') && PANELCSS) { var st = d.createElement('style'); st.id = 'cl-panel-css'; st.textContent = PANELCSS; d.head.appendChild(st); }
    if (rx.length || PANELREMOVE.length || pfn) { swap(d); strip(d); extra(d); if (!d.documentElement.getAttribute('data-cl-w')) { d.documentElement.setAttribute('data-cl-w', '1'); try { new MutationObserver(function(){ swap(d); strip(d); extra(d); }).observe(d.documentElement, {childList:true, subtree:true, characterData:true}); } catch (e) {} } }
  }
  if (PANELCSS || rx.length || PANELREMOVE.length || pfn) { setInterval(dress, 100); f.addEventListener('load', dress); }
})();
// Full control / Read-only switch (top of the panel, beside the word node-connect). Hidden unless the installer set it up on this node.
(function(){
  var btn = $('permBtn'), form = $('permForm'), pw = $('permPw'), msg = $('permMsg');
  if (!btn || !form || !pw || !msg) return;
  var st = null, timer = null;
  function say(t, keep){ msg.textContent = t || ''; clearTimeout(timer); if (t && !keep) timer = setTimeout(function(){ msg.textContent = ''; }, 6000); }
  function show(s){
    st = s;
    if (!s || !s.enabled) { btn.hidden = true; form.hidden = true; return; }
    if (form.hidden) btn.hidden = false;
    btn.className = (s.full ? '' : 'ro') + (s.canChange ? '' : ' dim');
    btn.textContent = s.full ? 'Full control: ON' : 'Full control: OFF (read-only)';
    btn.title = !s.canChange ? 'No password is set for this switch yet. On the node, run the installer with --password.'
      : (s.full ? 'Click to turn full control off (read-only). No password needed.' : 'Click to turn full control on' + (s.unlocked ? '.' : '. Asks for the switch password.'));
  }
  function call(body){
    var o = { method: body ? 'POST' : 'GET', cache: 'no-store', credentials: 'same-origin' };
    if (body) { o.headers = { 'Content-Type': 'application/json', 'X-CL-Perm': '1' }; o.body = JSON.stringify(body); }
    return fetch('?perm=1', o).then(function(r){ return r.json(); });
  }
  function load(){ call().then(show).catch(function(){}); }
  function reloadPanel(){ var f = $('panelf'); if (f) f.src = f.getAttribute('src'); }
  function send(pwd){
    if (!st) return;
    var b = { mode: st.full ? 'ro' : 'full' };
    if (pwd) b.pw = pwd;
    say('Working...', true);
    call(b).then(function(s){
      pw.value = '';
      if (s.error) {
        // a wrong password leaves the box open for another try; anything else closes it
        var again = /^Wrong password/.test(s.error);
        form.hidden = !again; show(s); say(s.error);
        if (again) pw.focus();
        return;
      }
      form.hidden = true; show(s); say('Saved.'); reloadPanel();
    }).catch(function(){ say('Could not reach the node. Try again.'); });
  }
  btn.addEventListener('click', function(){
    if (!st) return;
    if (!st.canChange) { say(btn.title); return; }
    if (st.full || st.unlocked) { send(''); return; }   // turning OFF never asks; turning ON asks unless this browser is unlocked
    say(''); btn.hidden = true; form.hidden = false; pw.value = ''; pw.focus();
  });
  form.addEventListener('submit', function(e){ e.preventDefault(); if (pw.value) send(pw.value); });
  $('permCancel').addEventListener('click', function(){ form.hidden = true; pw.value = ''; say(''); show(st); });
  load();
  setInterval(function(){ if (form.hidden) load(); }, 30000);
})();
poll();
setInterval(poll, 3000);
setInterval(tick, 1000);
setInterval(pollKeyed, 500);
setInterval(applyKeyed, 250);
</script>
</body>
</html>
CL_EOF_INDEX
}

# put MODE TARGET EMITTER : write one file (old copy is saved first)
put() {
  local mode=$1 target=$2 fn=$3
  if [ -e "$target" ]; then
    install -d -m 755 "$BK"
    cp -p "$target" "$BK/$(basename "$target").$STAMP"
  fi
  "$fn" | sed "s/@NODE@/$NODE/g; s/@VERSION@/$VERSION/g" > "$target.tmp" || die "Could not write $target"
  chmod "$mode" "$target.tmp"
  mv -f "$target.tmp" "$target" || die "Could not move $target into place"
}

emit_panel_css() { cat <<'CL_EOF_PANEL_CSS'
/* Restyles the right-hand panel to match the Connect Lookup page: black, same fonts and colors. */
html,body{background:#111 !important;color:#e6e6e6 !important;font:15px system-ui,sans-serif !important;scrollbar-color:#555 #111 !important}
a{color:#7cc4ff !important}
::-webkit-scrollbar{background:#111 !important}
::-webkit-scrollbar-thumb{background:#555 !important}
header{background:#111 !important;color:#9ecbff !important;border-bottom:1px solid #2a2a2a !important;border-radius:0 !important;font-size:0 !important}
header a,header small{font-size:15px !important;margin-right:12px !important}
/* the top line keeps only the name, version and node title: no login, logout, settings, users, touch screen or update links */
header a[href*="/user/"],header a[href*="/cfg/"],header a[href*="/simple/"],header a[href*="github.com"]{display:none !important}
h1,h2,h3{color:#9ecbff !important}
table.favs thead tr,table.grid thead tr{background:#111 !important}
table.favs th,table.grid th{color:#999 !important;font-weight:600 !important;font-size:13px !important}
table.favs td,table.grid td,table.favs th,table.grid th{border-bottom:1px solid #2a2a2a !important}
table.favs tbody tr:hover,table.grid tbody tr:hover{background:#1c1c1c !important}
table.grid tr.gColor td{background:#111 !important}
a.menu{background:#111 !important;color:#7cc4ff !important;border:1px solid #2a2a2a !important;border-radius:3px !important}
a.menu:hover{background:#1c1c1c !important;text-decoration:underline !important}
input[type=text],input[type=number],input[type=password],select,textarea{background:#1c1c1c !important;color:#e6e6e6 !important;border:1px solid #333 !important}
input[type=button],input[type=submit],button,.button1{background:#222 !important;color:#e6e6e6 !important;border:1px solid #333 !important;border-radius:3px !important}
input[type=button]:hover,input[type=submit]:hover,button:hover,.button1:hover{background:#333 !important}
pre{background:#161616 !important;color:#e6e6e6 !important;border:1px solid #2a2a2a !important}
.favEditPanel{background:#111 !important;border:1px solid #444 !important}
/* the program's own logo and its outside links are not shown in this panel */
img[src*="lscan" i],a[href*="lscan.info" i],a[href*="facebook" i],a[href*="idgsd" i]{display:none !important}
/* nothing under the favorites list: file chooser, system details, temperature, Node Stats button and outside links */
form:has(#_favsfile),#_favsfile,label[for="_favsfile"],#scanmsg,#statmsg,#cputemp,.m5,input[value="Node Stats"]{display:none !important}
/* Connection Status table, node entry box and Favorites table: same width, about 0.4 inch of space on each side */
table.grid,table.favs,#nodeForm{box-sizing:border-box !important;width:calc(100% - 0.8in) !important;max-width:none !important;margin-left:0.4in !important;margin-right:0.4in !important}
#nodeForm fieldset{box-sizing:border-box !important;width:100% !important;margin:0 !important;border:1px solid #2a2a2a !important;border-radius:3px !important}
/* bigger, easier-to-hit controls */
#nodeForm input[type=text]{font-size:18px !important;padding:8px 10px !important;width:7.5em !important;margin:4px !important}
#nodeForm input[type=button],#nodeForm input[type=submit],#nodeForm button{font-size:16px !important;padding:10px 16px !important;min-height:44px !important;margin:4px !important;cursor:pointer !important}
#nodeForm input.small{font-size:14px !important;padding:8px 12px !important;min-height:38px !important}
#nodeForm input[value="Connect"]{border-color:#2f7d4f !important}
#nodeForm input[value="Disconnect"]{border-color:#a33 !important}
#nodeForm input[type=checkbox]{transform:scale(1.4) !important;margin:0 8px 0 6px !important}
#nodeForm label{font-size:15px !important}
/* the box around the Connection Status table fills the whole width, so the table inside can too */
.twrap{display:block !important;width:100% !important;max-width:none !important;box-sizing:border-box !important;overflow-x:visible !important}
/* outlines: Add Favorite blue, Delete Favorite bright black (gray) */
#nodeForm input[value="Add Favorite"]{border-color:#3b82f6 !important}
#nodeForm input[value="Delete Favorite"]{border-color:#8a8a8a !important}
/* EchoLink numbers: the leading 3 is only the connect code, so it is not shown (the text itself is unchanged) */
td.cl-echo-num::first-letter{font-size:0 !important}
#cl-echo-note{font-size:12px;color:#9a9a9a;margin:4px 0 6px;text-align:center}
header{display:flex !important;align-items:center !important;flex-wrap:wrap !important}
#cl-temp{margin-left:auto !important;align-self:center !important;font-size:15px !important;color:#e6e6e6 !important;white-space:nowrap !important;text-align:center !important}
header small{display:none !important}
a.cl-echo-call,a.cl-echo-call:visited{color:#ffffff !important}
@media (max-width:600px){table.grid,table.favs,#nodeForm{width:100% !important;margin-left:0 !important;margin-right:0 !important}table.grid,table.favs{font-size:13px !important}.twrap{overflow-x:auto !important}}
/* the app paints keyed rows plain maroon and the favorites number column pure red: both toned down to match the page */
table.grid tr.tColor td,table.grid tr.rColor td,table.grid tr.rColor td a{background-color:#3b1616 !important}
table.favs tbody tr td:first-child{filter:saturate(.45) brightness(.8)}
CL_EOF_PANEL_CSS
}

emit_panel_js() { cat <<'CL_EOF_PANEL_JS'
// Runs inside the right-hand panel as function(doc, data).
// EchoLink stations (3 + their EchoLink number) in the Favorites list and the connection table: callsign in the name cell, and the leading 3 hidden on screen.
var lg = doc.querySelector('header a.logo'); if (lg && lg.textContent !== 'node-connect') lg.textContent = 'node-connect';
// a short note under the favorites buttons
if (!doc.getElementById('cl-echo-note')) {
  var anchor = doc.querySelector('#nodeForm input[value="DTMF"]') || doc.querySelector('#nodeForm input[value="Edit Favorite"]');
  if (anchor && anchor.parentNode) {
    var note = doc.createElement('div');
    note.id = 'cl-echo-note';
    note.textContent = 'Note: EchoLink favorites only work if EchoLink is installed on this node.';
    var after = anchor.nextElementSibling && anchor.nextElementSibling.tagName === 'BR' ? anchor.nextElementSibling : anchor;
    after.parentNode.insertBefore(note, after.nextSibling);
  }
}
var ct = doc.getElementById('cputemp'), hd = doc.querySelector('header');
if (ct && hd) { var rawt = ct.textContent; var tb = doc.getElementById('cl-temp'); if (!tb) { tb = doc.createElement('span'); tb.id = 'cl-temp'; hd.appendChild(tb); }
  if (tb.getAttribute('data-raw') !== rawt || !tb.__stamp) { tb.setAttribute('data-raw', rawt); tb.__stamp = new Date(); }
  var sd = tb.__stamp, sh = sd.getHours(), sm = sd.getMinutes(); var stime = (sh % 12 || 12) + ':' + (sm < 10 ? '0' : '') + sm + ' ' + (sh >= 12 ? 'PM' : 'AM');
  var tt = rawt.replace(/\s+/g, ' ').replace(/\s*\/\s*-?[0-9.]+\s*\u00b0?\s*C\b/, '').replace(/\s*@\s*[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?/, '').trim() + ' @ ' + stime;
  if (tb.textContent !== tt) tb.textContent = tt; }
var pw = doc.defaultView; if (pw && !pw.__clTemp && typeof pw.xhttpApiInit === 'function') { pw.__clTemp = pw.setInterval(function () { try { pw.xhttpApiInit('f=getCpuTemp'); } catch (e) {} }, 10000); }
var E = window.__clEcho;
if (!E) {
  E = window.__clEcho = { map: {}, asked: {}, busy: false };
  try { E.map = JSON.parse(localStorage.getItem('cl-echo') || '{}') || {}; } catch (e) {}
}
var known = {};
if (data && data.sessions) for (var j = 0; j < data.sessions.length; j++) { var x = data.sessions[j]; if (x.call && /^3[0-9]{6}$/.test(String(x.node))) known[String(x.node)] = String(x.call).trim(); }
// A callsign at the start of a name cell opens its QRZ page (same address Connect Lookup uses); -L / -R style endings are dropped for the address. A link the cell already had is replaced.
// In the Favorites list the Name column then shows only the callsign (the words after it are left out); other tables keep their text.
function linkCall(cell) {
  if (cell.querySelector('a.cl-qrz')) return;
  var kids = cell.children.length;
  if (kids > 1 || (kids === 1 && cell.children[0].tagName !== 'A')) return;
  var txt = cell.textContent;
  var only = !!(cell.closest && cell.closest('table.favs'));
  var m = txt.match(/^(\s*)([A-Za-z0-9]{1,3}[0-9][A-Za-z]{1,4}(?:\/[A-Za-z0-9]+)?(?:-[A-Za-z0-9]{1,3})?)(?=[\s,;:]|$)/);
  if (!m) return;
  var a = doc.createElement('a');
  a.className = 'cl-qrz';
  a.href = 'https://www.qrz.com/db/' + encodeURIComponent(m[2].split('-')[0].toUpperCase());
  a.target = '_blank';
  a.rel = 'noopener noreferrer';
  a.textContent = m[2];
  a.addEventListener('click', function (e) { e.stopPropagation(); });
  a.addEventListener('dblclick', function (e) { e.stopPropagation(); });
  var rest = txt.slice(m[0].length);
  cell.textContent = '';
  if (m[1]) cell.appendChild(doc.createTextNode(m[1]));
  cell.appendChild(a);
  if (rest && !only) cell.appendChild(doc.createTextNode(rest));
}
var need = [];
var tables = doc.querySelectorAll('table.grid, table.favs');
for (var t = 0; t < tables.length; t++) {
  var tb = tables[t];
  var isGrid = tb.classList.contains('grid');
  var hr = tb.querySelectorAll('thead tr'); hr = hr.length ? hr[hr.length - 1].cells : [];
  var col = -1;
  for (var h = 0; h < hr.length; h++) if (new RegExp(isGrid ? '^node info$' : '^name$', 'i').test((hr[h].textContent || '').trim())) col = h;
  if (col < 0) continue;
  var rows = tb.querySelectorAll('tbody tr');
  for (var i = 0; i < rows.length; i++) {
    var nc = rows[i].querySelector('td.nodeNum') || rows[i].cells[0];
    var cell = rows[i].cells[col];
    if (!cell) continue;
    try { linkCall(cell); } catch (e) {}
    if (!nc) continue;
    var m = (nc.textContent || '').match(/\b(3[0-9]{6})\b/);
    if (!m) continue;
    try { var qa = cell.querySelector('a.cl-qrz'); if (qa && !qa.classList.contains('cl-echo-call')) qa.classList.add('cl-echo-call'); } catch (e) {}
    var n = m[1], cur = (cell.textContent || '').replace(/[\s ]+/g, ' ').trim();
    // the leading 3 is only the connect code: hide it on screen (the text is unchanged, so selecting a row still fills in the full number)
    if (/^\s*3[0-9]{6}\s*$/.test(nc.textContent || '') && !nc.classList.contains('cl-echo-num')) nc.classList.add('cl-echo-num');
    var blank = cur === '' || cur === '-' || cur === n || /^EchoLink/i.test(cur);
    if (!blank) continue;
    var call = known[n] || E.map[n];
    if (call) { if (cell.textContent !== call) cell.textContent = call; }
    else if (!E.asked[n]) need.push(n);
  }
}
if (need.length && !E.busy) {
  E.busy = true;
  var ask = need.slice(0, 12);
  ask.forEach(function (n) { E.asked[n] = 1; });
  fetch('?echo=' + ask.join(','), { cache: 'no-store' })
    .then(function (r) { return r.json(); })
    .then(function (j) {
      for (var k in j) if (/^3[0-9]{6}$/.test(k) && typeof j[k] === 'string') E.map[k] = j[k];
      try { localStorage.setItem('cl-echo', JSON.stringify(E.map)); } catch (e) {}
    })
    .catch(function () { ask.forEach(function (n) { delete E.asked[n]; }); })
    .then(function () { E.busy = false; });
}
CL_EOF_PANEL_JS
}

emit_panel_words() { cat <<'CL_EOF_PANEL_WORDS'
# old|new   (shown text only, case does not matter);  a line with a TAB uses the TAB instead of | (for old text that contains a | mark)
 | 	
Connection Status|Node Connection
CL_EOF_PANEL_WORDS
}

emit_panel_remove() { cat <<'CL_EOF_PANEL_REMOVE'
# CSS selectors, one per line: these are taken out of the panel page.
# A check box is replaced by a hidden one that always stays off (the page's own script still reads it).
# (a line that starts with # is a comment, so write an id as input#name, not #name)
label[for="autodisc"]
input#autodisc
label[for="automondisc"]
input#automondisc
CL_EOF_PANEL_REMOVE
}

emit_fav_entries() { cat <<'CL_EOF_FAVS'
label[] = "K4JLB --CLOUD--, White Pine,TN 684972"
cmd[] = "rpt cmd %node% ilink 3 684972"
label[] = "K4JLB Home, White Pine,TN 684971"
cmd[] = "rpt cmd %node% ilink 3 684971"
label[] = "K4JLB Mobile , WHITE PINE, TN. 67270"
cmd[] = "rpt cmd %node% ilink 3 67270"
label[] = "KD4HZN 147.315, Rogersville Tennessee 680640"
cmd[] = "rpt cmd %node% ilink 3 680640"
label[] = "KD4HZN 224.480, Rogersville Tn. 686590"
cmd[] = "rpt cmd %node% ilink 3 686590"
label[] = "KD4HZN No Bob, Rogersville Tn. 686591"
cmd[] = "rpt cmd %node% ilink 3 686591"
label[] = "K4JOZ Zebra Water Cooler, Whitesburg,TN 675841"
cmd[] = "rpt cmd %node% ilink 3 675841"
label[] = " ,  3494563"
cmd[] = "rpt cmd %node% ilink 3 3494563"
label[] = " ,  3510366"
cmd[] = "rpt cmd %node% ilink 3 3510366"
CL_EOF_FAVS
}

# ----------------------------------------------------------------------
#  Optional right-hand panel (the node's own connect / favorites page, shown beside Connect Lookup)
# ----------------------------------------------------------------------
# Finds the web app on this node that provides it, by what it contains (not by name). Prints its web path, e.g. /something/
find_panel_app() {
  local d
  for d in /var/www/html/*/; do
    d=${d%/}
    [ "$d" = "$WEB" ] && continue
    case "$(basename "$d")" in *bak*|*.old|*-old|*_old|*.orig|*backup*|*~) continue ;; esac   # a backup copy of the app is not the app
    if [ -f "$d/api/index.php" ] && [ -f "$d/js/main.js" ] && [ -f "$d/include/viewUtils.php" ] \
       && grep -q 'getCpuTemp' "$d/api/index.php" 2>/dev/null; then
      printf '/%s/\n' "$(basename "$d")"
      return 0
    fi
  done
  return 1
}

# The app's own sample list: the file it ships (favorites-Sample.ini) with its long [general] list, never edited
# (the app leaves a before-edit copy beside the file the first time anyone edits the list through it).
is_untouched_sample() {
  local f=$1 d
  d=$(dirname "$f")
  [ "$(basename "$f")" = "favorites-Sample.ini" ] || return 1
  grep -q '=== SELECT ===' "$f" 2>/dev/null || return 1
  [ "$(grep -c '^[[:space:]]*label\[\]' "$f" 2>/dev/null)" -ge 20 ] || return 1
  [ "$(grep -c '^\[' "$f")" = 1 ] && grep -q '^\[general\]' "$f" || return 1
  ls "$d"/favorites*before-edit* >/dev/null 2>&1 && return 1
  return 0
}

# Default favorites: added once, only when the node has none yet (the app's own untouched sample list does not count as favorites,
# and that sample file is never touched: the defaults go into favorites.ini, which the app shows first). After that they belong to the person: anything they change or delete is never put back (a marker file remembers that this was done).
seed_favorites() {
  local d=$1 mk="$WEB/.favorites-seeded" f c n=0 empty="" new
  if [ -e "$mk" ]; then note "default favorites: handled by an earlier install - left alone"; return 0; fi
  for f in "$d"/favorites*.ini; do
    [ -f "$f" ] || continue
    if is_untouched_sample "$f"; then continue; fi
    c=$(grep -c '^[[:space:]]*label\[\]' "$f" 2>/dev/null || true)
    n=$(( n + ${c:-0} ))
    [ "${c:-0}" = 0 ] && [ -z "$empty" ] && empty=$f
  done
  if [ "$n" -gt 0 ]; then
    note "default favorites: this node already has favorites - left alone"
  elif [ -n "$empty" ]; then
    if [ "$(grep -c '^\[' "$empty")" = 1 ] && grep -q '^\[general\]' "$empty"; then
      emit_fav_entries >> "$empty" && note "default favorites added to $empty"
    else
      note "default favorites: $empty has an unusual layout - left alone"
    fi
  elif [ ! -e "$d/favorites.ini" ]; then
    new="$d/favorites.ini"
    { printf '; Default favorites from the Connect Lookup installer. Change or delete them freely - they are not put back.\n'
      printf '; The %%node%% template is replaced with your node number at run time.\n;\n[general]\n;\n'
      emit_fav_entries; } > "$new" && note "default favorites written to $new"
  fi
  if id www-data >/dev/null 2>&1; then
    for f in "$d"/favorites.ini; do [ -f "$f" ] && chown www-data:www-data "$f" 2>/dev/null && chmod 664 "$f"; done
  fi
  : > "$mk"
}

# The panel's connect / disconnect / monitor / favorites controls only work when the app lets visitors use them.
# The first time the switch is set up on a node (no panel-access.php yet), this sets the app's visitor level to READ-ONLY, so the panel
# only looks until the node owner turns Full control on with the switch password. Later installs and updates never touch the level again.
# The row number and the level are read from the app's own code; the app's settings file is found by what it contains and is written
# as the user who owns it (so the app can keep using it). Nothing else in that file is changed.
PA_DB=""; PA_ID=""; PA_FULL=""; PA_RO=""
# Reads what the visitor level needs from the app's own code and settings file: PA_ID (the settings row), PA_FULL and PA_RO (the
# "full" and "read only" levels) and PA_DB (the settings file). Returns 1 if the row, the full level or the file is missing
# (PA_RO may still be empty: the Full control / Read-only switch needs it, plain full access does not).
panel_access_info() {
  local d=$1 f
  PA_DB=""
  PA_ID=$(sed -n "s/^define('publicPermission', *\([0-9][0-9]*\)).*/\1/p" "$d/include/CfgModel.php" 2>/dev/null | head -n1)
  PA_FULL=$(sed -n "s/^define('PERMISSION_FULL', *\([0-9][0-9]*\)).*/\1/p" "$d/include/UserModel.php" 2>/dev/null | head -n1)
  PA_RO=$(sed -n "s/^define('PERMISSION_READ_ONLY', *\([0-9][0-9]*\)).*/\1/p" "$d/include/UserModel.php" 2>/dev/null | head -n1)
  [ -n "$PA_ID" ] && [ -n "$PA_FULL" ] || return 1
  # the app keeps its settings in /etc/allscan/<its folder name>.db (for /var/www/html/allscan that is /etc/allscan/allscan.db)
  f="/etc/allscan/$(basename "$d").db"
  if [ -f "$f" ] && grep -aq 'CREATE TABLE cfg' "$f" 2>/dev/null && grep -aq 'CREATE TABLE user' "$f" 2>/dev/null; then PA_DB=$f; return 0; fi
  # otherwise look for a settings file by what it contains, but never a backup copy
  for f in /etc/*/*.db /var/lib/*/*.db "$d"/*.db; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in *bak*|*backup*|*old*|*orig*|*copy*|*before*|*save*|*tmp*|*~) continue ;; esac
    if grep -aq 'CREATE TABLE cfg' "$f" 2>/dev/null && grep -aq 'CREATE TABLE user' "$f" 2>/dev/null; then PA_DB=$f; break; fi
  done
  [ -n "$PA_DB" ]
}

set_panel_access() {
  local d=$1 id full db owner out
  panel_access_info "$d" || { warn "could not read the panel's access setting from the app, or could not find its settings file - the panel may ask for a login"; return 0; }
  [ -n "$PA_RO" ] || { note "panel access: this version of the app has no read-only level, so its visitor level was left as it is"; return 0; }
  id=$PA_ID; full=$PA_RO; db=$PA_DB   # $full holds the level that gets written: the app's READ-ONLY level
  command -v php >/dev/null 2>&1 || { warn "php command line missing - the panel may ask for a login"; return 0; }
  owner=$(stat -c %U "$db" 2>/dev/null)
  local code='try { $p = new PDO("sqlite:" . $argv[1]); $p->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION); $p->exec("PRAGMA busy_timeout=5000");
    $s = $p->prepare("select val from cfg where cfg_id = ?"); $s->execute([(int)$argv[2]]); $cur = $s->fetchColumn();
    if ($cur !== false && (string)$cur === (string)(int)$argv[3]) { echo "same"; exit(0); }
    $u = $p->prepare("insert or replace into cfg (cfg_id, val, updated) values (?, ?, ?)"); $u->execute([(int)$argv[2], (string)(int)$argv[3], time()]); echo "set";
  } catch (Throwable $e) { echo "error"; exit(1); }'
  if [ -n "$owner" ] && [ "$owner" != "$(id -un)" ] && command -v runuser >/dev/null 2>&1; then
    out=$(runuser -u "$owner" -- php -r "$code" "$db" "$id" "$full" 2>/dev/null)
  else
    out=$(php -r "$code" "$db" "$id" "$full" 2>/dev/null)
  fi
  case "$out" in
    set|same) : ;;
    *) warn "could not change the panel's access setting - the panel may ask for a login" ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
#  Full control / Read-only switch (top of the panel, beside the word node-connect)
# ----------------------------------------------------------------------
PW_HASH=""
# Asks for the switch password twice, hidden. Sets PW_HASH to its bcrypt hash. Returns 1 if skipped or it could not be made.
ask_switch_password() {
  local p1 p2 h tries=0 re='^\$2y\$[0-9]{2}\$[./A-Za-z0-9]{53}$'
  PW_HASH=""
  say ""
  say "Panel switch password"
  say "  At the top of the panel there is a switch: Full control (visitors can connect,"
  say "  disconnect, monitor and use favorites) or Read-only (they can only look)."
  say "  Only someone who knows this password can turn Full control on. It is kept on this node only as"
  say "  a scrambled hash, never as readable text, and is never sent anywhere."
  say "  Use at least 6 characters, or just press Enter to skip. If you skip, the switch"
  say "  stays locked on Read-only (visitors can only look); you can set a password later with:"
  say "    sudo bash $0 $NODE --password"
  while [ "$tries" -lt 3 ]; do
    read -r -s -p "  Password (Enter to skip): " p1 </dev/tty || { printf '\n'; return 1; }
    printf '\n'
    [ -n "$p1" ] || return 1
    if [ "${#p1}" -lt 6 ]; then say "  That is too short - use at least 6 characters."; tries=$((tries + 1)); continue; fi
    read -r -s -p "  Type it again: " p2 </dev/tty || { printf '\n'; return 1; }
    printf '\n'
    if [ "$p1" != "$p2" ]; then say "  The two did not match."; tries=$((tries + 1)); continue; fi
    h=$(printf '%s' "$p1" | php -r 'echo password_hash(stream_get_contents(STDIN), PASSWORD_BCRYPT);' 2>/dev/null)
    if [[ "$h" =~ $re ]]; then PW_HASH=$h; return 0; fi
    warn "could not scramble the password with PHP - the switch password was not set"
    return 1
  done
  say "  Too many tries - no password set."
  return 1
}

# Writes panel-access.php next to index.php: the app's settings file, the row, the two levels and the password hash.
# $1 = a new hash, or empty to keep the hash already there. Only the hash is ever stored, never the password.
write_access_file() {
  local new=$1 f="$WEB/$ACCESS" hash="" asked=0 re='^\$2y\$[0-9]{2}\$[./A-Za-z0-9]{53}$'
  [ -n "$PA_DB" ] && [ -n "$PA_ID" ] && [ -n "$PA_FULL" ] && [ -n "$PA_RO" ] || return 1
  [[ "$PA_DB" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
  if [ -r "$f" ]; then
    hash=$(sed -n "s/^[[:space:]]*'hash'[[:space:]]*=>[[:space:]]*'\([^']*\)'.*/\1/p" "$f" | head -n1)
    grep -q "'asked'[[:space:]]*=>[[:space:]]*1" "$f" && asked=1
  fi
  [[ "$hash" =~ $re ]] || hash=""
  if [ -n "$new" ]; then hash=$new; asked=1; fi
  (
    umask 077
    {
      printf '<?php\n'
      printf '// %s - written by the Connect Lookup installer. Settings for the panel'"'"'s Full control / Read-only switch.\n' "$MARK"
      printf '// It holds a password HASH only, never the password. Do not publish or share this file.\n'
      printf 'return [\n'
      printf "  'db' => '%s',\n" "$PA_DB"
      printf "  'id' => %s,\n" "$PA_ID"
      printf "  'full' => %s,\n" "$PA_FULL"
      printf "  'ro' => %s,\n" "$PA_RO"
      printf "  'asked' => %s,\n" "$asked"
      printf "  'hash' => '%s',\n" "$hash"
      printf '];\n'
    } > "$f.tmp"
  ) || return 1
  if id www-data >/dev/null 2>&1; then chown root:www-data "$f.tmp" && chmod 640 "$f.tmp"; else chmod 644 "$f.tmp"; fi
  mv -f "$f.tmp" "$f"
}

# On install/update: writes the switch's settings and, the first time, offers to set its password.
# An existing password and the current Full/Read-only choice are never touched here.
setup_switch() {
  local f="$WEB/$ACCESS" had=0
  [ -e "$f" ] && had=1
  if [ -z "$PA_RO" ] || [ -z "$PA_DB" ]; then
    [ "$had" = 1 ] || note "Full control / Read-only switch: not available (this version of the app has no read-only level or its settings file was not found)"
    return 0
  fi
  if ! id www-data >/dev/null 2>&1; then
    note "Full control / Read-only switch: not set up (no www-data web user found)"
    return 0
  fi
  write_access_file "" || { warn "could not write the switch settings - the switch stays hidden"; return 0; }
  if [ "$had" = 1 ]; then
    note "Full control / Read-only switch: settings refreshed; your password and current choice were left as they are"
  elif [ "$YES" = 1 ] || [ ! -r /dev/tty ]; then
    note "Full control / Read-only switch: set up, locked (no password yet). Set one with:  sudo bash $0 $NODE --password"
  else
    if ask_switch_password && write_access_file "$PW_HASH"; then
      note "Full control / Read-only switch: password saved"
    else
      note "Full control / Read-only switch: set up, locked (no password yet). Set one later with:  sudo bash $0 $NODE --password"
    fi
  fi
  if ! runuser -u www-data -- test -w "$PA_DB" 2>/dev/null || ! runuser -u www-data -- test -w "$(dirname "$PA_DB")" 2>/dev/null; then
    warn "the web server cannot write the app's settings file ($PA_DB), so the switch will not be able to change anything"
  fi
}

setup_panel() {
  put 644 "$WEB/panel.css"        emit_panel_css
  put 644 "$WEB/panel.js"         emit_panel_js
  put 644 "$WEB/panel-words.txt"  emit_panel_words
  put 644 "$WEB/panel-remove.txt" emit_panel_remove
  note "$WEB/panel.css, panel.js, panel-words.txt, panel-remove.txt"
  local app
  app=$(find_panel_app) || app=""
  if [ -z "$app" ]; then
    note "the node-connect app was not found on this node - the panel stays off (run this installer again after you install it)"
    return 0
  fi
  if [ -e "$WEB/panel.txt" ]; then
    note "panel.txt already present - left alone"
  else
    printf '%s\n' "$app" > "$WEB/panel.txt" && chmod 644 "$WEB/panel.txt"
    note "panel available ($app) - tick \"Show the node-connect panel\" at the top of the page"
  fi
  local ad="/var/www/html$(printf '%s' "$app" | sed 's:/$::')"
  if [ -e "$WEB/$ACCESS" ]; then
    # the switch was set up by an earlier install: its current Full control / Read-only choice is the owner's, so it is not reset
    panel_access_info "$ad" || true
    note "panel access: left as the Full control / Read-only switch has it"
  else
    set_panel_access "$ad"
  fi
  setup_switch
  seed_favorites "$ad"
}

# --password: set or change the switch password on a node that already has Connect Lookup.
do_password() {
  [ -f "$WEB/index.php" ] && grep -q "$MARK" "$WEB/index.php" 2>/dev/null \
    || die "Connect Lookup is not installed on this node yet. Install it first:  sudo bash $0 YOURNODE"
  command -v php >/dev/null 2>&1 || die "The PHP command-line program is missing. Install it with:  sudo apt install php-cli"
  id www-data >/dev/null 2>&1 || die "No www-data web user was found, so the switch cannot be used on this node."
  local app ad
  app=$(find_panel_app) || app=""
  [ -n "$app" ] || die "The node-connect app was not found on this node, so there is no panel and no switch."
  ad="/var/www/html$(printf '%s' "$app" | sed 's:/$::')"
  panel_access_info "$ad" || die "Could not read the app's access setting or find its settings file."
  [ -n "$PA_RO" ] || die "This version of the app has no read-only level, so the switch cannot be used."
  [ -r /dev/tty ] || die "This needs a keyboard to type the password. Run it from your SSH window, not from a script."
  ask_switch_password || { say "No password was set. Nothing was changed."; exit 0; }
  write_access_file "$PW_HASH" || die "Could not save the switch settings."
  say ""
  say "Switch password saved. Browsers that had unlocked the switch with the old password"
  say "must enter the new one. Open the panel and use the switch beside the word node-connect."
}

# ----------------------------------------------------------------------
#  Checks (read-only)
# ----------------------------------------------------------------------
preflight() {
  say "Checking this node..."

  [ -x /usr/sbin/asterisk ] || die "Asterisk was not found at /usr/sbin/asterisk. This installer is for AllStarLink 3 nodes."
  id asterisk >/dev/null 2>&1 || die "There is no 'asterisk' user on this system."
  command -v systemctl >/dev/null 2>&1 || die "systemd was not found."
  /usr/sbin/asterisk -rx "core show version" >/dev/null 2>&1 || die "Asterisk is not running, or cannot be reached from here. Start it and try again."
  note "Asterisk is running"

  [ -f "$RPT" ] || die "$RPT was not found."
  grep -q "^\[$NODE\]" "$RPT" || die "Node $NODE has no [$NODE] section in $RPT. Check the node number. (If your node is set up in a different file, tell the person who gave you this installer.)"
  note "Node $NODE found in rpt.conf"

  command -v apache2ctl >/dev/null 2>&1 || die "The Apache web server was not found. Connect Lookup needs the web server your node already uses for its web pages."
  [ -d /var/www/html ] || die "/var/www/html was not found."
  apache2ctl -M 2>/dev/null | grep -Eqi 'php[0-9._]*_module|proxy_fcgi_module' \
    || die "PHP does not seem to be enabled in Apache. Install it first (for example: sudo apt install php libapache2-mod-php) and run this again. Note: that can change how Apache is set up, so only do it if nothing else on this node depends on the current setup."
  note "Apache and PHP are available"

  if ! command -v curl >/dev/null 2>&1; then
    if [ "$MODE" = check ]; then
      warn "curl is not installed; the installer will install it (a small, standard package)"
    else
      note "curl is missing - installing it"
      apt-get install -y curl >/dev/null 2>&1 || die "Could not install curl. Run: sudo apt install curl"
      CHANGED=1
    fi
  else
    note "curl is installed"
  fi

  if ! command -v php >/dev/null 2>&1; then
    if [ "$MODE" = check ]; then
      warn "the PHP command-line program is not installed; the installer will install php-cli (a small, standard package)"
    else
      note "php-cli is missing - installing it"
      apt-get install -y php-cli >/dev/null 2>&1 || die "Could not install php-cli. Run: sudo apt install php-cli"
      CHANGED=1
    fi
  else
    note "php command line is installed"
  fi
  if curl -s -m 8 -o /dev/null -w '%{http_code}' https://stats.allstarlink.org/api/stats/$NODE 2>/dev/null | grep -q '^200$'; then
    note "AllStarLink stats feed is reachable (used for the 'Connected through' column)"
  else
    warn "could not reach stats.allstarlink.org or it has no data for node $NODE; the 'Connected through' column may stay blank"
  fi

  # Never overwrite a hand-made copy or someone else's files.
  local f
  for f in "$CUSTOM/conlog.sh" "$CUSTOM/live.sh" "$CUSTOM/track.sh" "$CUSTOM/names.sh" "$CUSTOM/topology.php" "$CUSTOM/checkver.sh" \
           "$UNITDIR/connect-lookup-live.service" "$UNITDIR/connect-lookup-clean.service" \
           "$UNITDIR/connect-lookup-clean.timer" "$UNITDIR/connect-lookup-checkver.service" \
           "$UNITDIR/connect-lookup-checkver.timer" "$WEB/index.php"; do
    if [ -e "$f" ] && ! grep -q "$MARK" "$f" 2>/dev/null; then
      die "$f already exists and was not created by this installer (it looks like a hand-made Connect Lookup). I will not overwrite it."
    fi
  done
  if grep -q "$MARK" "$CUSTOM/live.sh" 2>/dev/null; then
    local prev
    prev=$(grep -o 'rpt nodes [0-9]*' "$CUSTOM/live.sh" 2>/dev/null | head -1 | awk '{print $3}')
    if [ -n "$prev" ] && [ "$prev" != "$NODE" ]; then
      die "Connect Lookup is already installed here for node $prev. It supports one node per computer. To switch, remove it first:  sudo bash $0 --uninstall"
    fi
    note "An earlier install by this installer was found - it will be updated"
  fi

  # connpgm / discpgm may already be used for something else.
  local stanza other
  stanza=$(awk -v hdr="[$NODE]" 'index($0,hdr)==1{f=1;next} f&&/^\[/{exit} f{print}' "$RPT")
  other=$(printf '%s\n' "$stanza" | grep -E '^[[:space:]]*(connpgm|discpgm)[[:space:]]*=' || true)
  RPT_DONE=0
  if [ -n "$other" ]; then
    if printf '%s\n' "$other" | grep -qv 'conlog\.sh'; then
      die "The [$NODE] section of $RPT already has its own connpgm/discpgm lines:
$other
Connect Lookup needs those two settings. Combine them by hand (or ask the person who gave you this installer), then run this again."
    fi
    RPT_DONE=1
    note "rpt.conf already has the Connect Lookup logging lines"
  fi
}

# ----------------------------------------------------------------------
#  Optional QRZ login (stored only for the asterisk user)
# ----------------------------------------------------------------------
setup_qrz() {
  local u p
  say ""
  say "QRZ login (optional). It is used only to look up names of callsigns that"
  say "the free US lookup cannot find. It is saved in $CUSTOM/qrz.conf, readable"
  say "only by the asterisk user, and goes nowhere except qrz.com."
  read -r -p "QRZ username (just press Enter to skip): " u </dev/tty || return 0
  [ -n "$u" ] || { note "QRZ skipped"; return 0; }
  read -r -s -p "QRZ password: " p </dev/tty || return 0
  echo
  [ -n "$p" ] || { note "QRZ skipped (no password)"; return 0; }
  (
    umask 077
    { printf 'QU=%q\n' "$u"; printf 'QP=%q\n' "$p"; } > "$CUSTOM/qrz.conf"
  )
  chown asterisk:asterisk "$CUSTOM/qrz.conf"
  chmod 600 "$CUSTOM/qrz.conf"
  rm -f "$LOGDIR/peoplemiss.txt"
  note "QRZ login saved"
}

# ----------------------------------------------------------------------
#  Install
# ----------------------------------------------------------------------
# Addresses to open the page at: this node's own addresses, each once (no IPv6, no container bridge 172.17.x), the Tailscale one labeled.
print_addresses() {
  local ip ts=""
  if command -v tailscale >/dev/null 2>&1; then ts=$(tailscale ip -4 2>/dev/null | head -1); fi
  for ip in $(hostname -I 2>/dev/null); do
    case "$ip" in *:*|172.17.*) continue ;; esac
    [ -n "$ts" ] && [ "$ip" = "$ts" ] && continue
    say "    http://$ip/connect-lookup/"
  done
  [ -n "$ts" ] && say "    http://$ts/connect-lookup/   (Tailscale)"
  return 0
}

do_install() {
  CHANGED=1

  say ""
  say "[1/6] Log folder"
  install -d -o asterisk -g asterisk -m 755 "$LOGDIR" || die "Could not create $LOGDIR"
  note "$LOGDIR"

  say "[2/6] Helper scripts"
  install -d -m 755 "$CUSTOM" || die "Could not create $CUSTOM"
  put 755 "$CUSTOM/conlog.sh" emit_conlog
  put 755 "$CUSTOM/live.sh"   emit_live
  put 755 "$CUSTOM/track.sh"  emit_track
  put 755 "$CUSTOM/names.sh"  emit_names
  rm -f "$LOGDIR/peoplemiss.txt"   # names an earlier version could not find are looked up again
  put 755 "$CUSTOM/topology.php" emit_topology
  put 755 "$CUSTOM/checkver.sh" emit_checkver
  note "$CUSTOM/conlog.sh, live.sh, track.sh, names.sh, topology.php, checkver.sh"
  note "names an earlier version could not find are looked up again"
  [ "$QRZ" = 1 ] && setup_qrz

  say "[3/6] Web page"
  install -d -m 755 "$WEB" || die "Could not create $WEB"
  put 644 "$WEB/index.php" emit_index
  note "$WEB/index.php"
  setup_panel

  say "[4/6] Background service, daily cleanup and daily version check"
  put 644 "$UNITDIR/connect-lookup-live.service"  emit_unit_live
  put 644 "$UNITDIR/connect-lookup-clean.service" emit_unit_clean_service
  put 644 "$UNITDIR/connect-lookup-clean.timer"   emit_unit_clean_timer
  put 644 "$UNITDIR/connect-lookup-checkver.service" emit_unit_ver_service
  put 644 "$UNITDIR/connect-lookup-checkver.timer"   emit_unit_ver_timer
  systemctl daemon-reload || die "systemctl daemon-reload failed"
  systemctl enable connect-lookup-live.service >/dev/null 2>&1 || die "Could not enable the live service"
  systemctl restart connect-lookup-live.service || die "Could not start the live service (see: journalctl -u connect-lookup-live.service)"
  systemctl enable --now connect-lookup-clean.timer >/dev/null 2>&1 || die "Could not enable the cleanup timer"
  systemctl enable --now connect-lookup-checkver.timer >/dev/null 2>&1 || die "Could not enable the version-check timer"
  note "connect-lookup-live.service running, connect-lookup-clean.timer and connect-lookup-checkver.timer scheduled"
  if runuser -u asterisk -- "$CUSTOM/checkver.sh" 2>&1 | grep -q '^Newest published version' && [ -s "$LOGDIR/latest-version.txt" ]; then
    note "newest published version: $(head -n1 "$LOGDIR/latest-version.txt")"
  else
    warn "could not read the newest version from GitHub just now (the daily check will try again); the page works without it"
  fi

  say "[5/6] Connection logging in rpt.conf (last, so nothing points at a missing script)"
  if [ "$RPT_DONE" = 1 ]; then
    note "already in place - left alone"
  else
    local new="$RPT.connect-lookup.new" back="$RPT.bak-connect-lookup-$STAMP"
    cp -p "$RPT" "$back" || die "Could not back up $RPT"
    awk -v hdr="[$NODE]" -v l1="connpgm = $CUSTOM/conlog.sh C" -v l2="discpgm = $CUSTOM/conlog.sh D" '
      { print }
      !done && index($0, hdr) == 1 { print l1; print l2; done = 1 }
    ' "$RPT" > "$new" || die "Could not prepare the new rpt.conf"
    [ "$(grep -c 'conlog\.sh' "$new")" = 2 ] || { rm -f "$new"; die "Safety check failed: the new rpt.conf does not look right. Your rpt.conf was not changed."; }
    [ "$(wc -l < "$new")" -eq $(( $(wc -l < "$RPT") + 2 )) ] || { rm -f "$new"; die "Safety check failed: unexpected line count. Your rpt.conf was not changed."; }
    cat "$new" > "$RPT" || die "Could not write $RPT"
    rm -f "$new"
    note "two lines added under [$NODE]; backup: $back"
  fi
  /usr/sbin/asterisk -rx "module reload app_rpt.so" >/dev/null 2>&1 || warn "Could not reload app_rpt. Run: sudo asterisk -rx \"module reload app_rpt.so\""

  say "[6/6] Checking that it works"
  sleep 6
  if systemctl is-active --quiet connect-lookup-live.service; then
    note "live service: running"
  else
    warn "live service is not running. See: journalctl -u connect-lookup-live.service"
  fi
  if [ -e "$LOGDIR/live.txt" ]; then note "live list: being written"; else warn "live list was not created yet"; fi
  local j
  j=$(curl -s -m 10 -L -k "http://localhost/connect-lookup/?json=1" 2>/dev/null)
  if printf '%s' "$j" | grep -q '"sessions"'; then
    note "web page: answering"
  else
    warn "the page did not answer at http://localhost/connect-lookup/ - check that Apache and PHP are working"
  fi
  if id www-data >/dev/null 2>&1 && ! runuser -u www-data -- test -r /var/lib/asterisk/astdb.txt 2>/dev/null; then
    warn "the web server cannot read /var/lib/asterisk/astdb.txt, so node callsigns will show blank"
  fi

  say ""
  say "Done. Connect Lookup is installed for node $NODE."
  say ""
  say "Open it in a browser at one of these addresses:"
  print_addresses
  say ""
  say "Good to know:"
  say "  - Anyone who can reach this node's web server can open the page, like your"
  say "    other node pages. It shows who connected, nothing private."
  say "  - It starts empty and fills in. Connections made before the install show"
  say "    'before logging began'. The 24-hour list builds up over the next day."
  say "  - Names come from callook.info (US FCC records) and EchoLink's node lookup"
  say "    page; neither needs a login. 'Connected through' comes from the public"
  say "    AllStarLink stats feed (nodes that do not report there show a dash)."
  if [ -r "$CUSTOM/qrz.conf" ]; then
    say "  - Your QRZ login is saved, so names of callsigns outside the US are looked up too."
  else
    say "  - Names of callsigns outside the US (Canada, for example) will show a dash"
    say "    until you add a free QRZ.com login:  sudo bash $0 $NODE --qrz"
  fi
  say "  - Your original rpt.conf was saved next to it (rpt.conf.bak-connect-lookup-*)."
  say "  - Optional: at the top of the page there are two checkboxes, \"Outline the stations"
  say "    behind a link while that link is transmitting\" and \"Show the node-connect panel"
  say "    on the right\". Both are off until you tick them; each browser remembers its own choice."
  say "  - If the node-connect app is installed here, the panel shows it beside this page, and a"
  say "    few default favorites are added once if you have none. Change or delete them freely;"
  say "    they are never put back, and updating this installer never touches your favorites."
  if [ -e "$WEB/$ACCESS" ]; then
    say "  - At the top of the panel, beside the word node-connect, is a Full control / Read-only"
    say "    switch. Full control lets visitors connect, disconnect, monitor and use favorites;"
    say "    Read-only lets them only look. It starts on Read-only. Turning Full control on asks for the"
    say "    switch password; turning it off does not, and locks it again."
    say "    To set or change that password:  sudo bash $0 $NODE --password"
  fi
  say "  - Once a day the node reads one line from GitHub (the newest version number). If a"
  say "    newer version than this one exists, the 'Version' line at the top of the page"
  say "    says so, with a red 'get it on GitHub' link that fades slowly in and out. It only"
  say "    tells you; nothing installs by itself."
  say "  - To remove everything later:  sudo bash $0 --uninstall"
}

# ----------------------------------------------------------------------
#  Uninstall
# ----------------------------------------------------------------------
do_uninstall() {
  say "Removing Connect Lookup..."
  [ -f "$CUSTOM/live.sh" ] && grep -q "$MARK" "$CUSTOM/live.sh" \
    || die "Connect Lookup was not installed by this installer on this node (no marker found), so I will not remove anything."
  ask "Remove Connect Lookup from this node?" || cancelled
  CHANGED=1

  # 1. stop Asterisk calling the logging script, then reload
  if grep -q 'conlog\.sh' "$RPT" 2>/dev/null; then
    cp -p "$RPT" "$RPT.bak-connect-lookup-remove-$STAMP" || die "Could not back up $RPT"
    sed -i -e '\|^[[:space:]]*connpgm[[:space:]]*=[[:space:]]*/etc/asterisk/custom/conlog\.sh C[[:space:]]*$|d' \
           -e '\|^[[:space:]]*discpgm[[:space:]]*=[[:space:]]*/etc/asterisk/custom/conlog\.sh D[[:space:]]*$|d' "$RPT"
    grep -q 'conlog\.sh' "$RPT" && warn "Some other line in $RPT still mentions conlog.sh; check it by hand"
    /usr/sbin/asterisk -rx "module reload app_rpt.so" >/dev/null 2>&1 || warn "Could not reload app_rpt"
    note "rpt.conf lines removed (backup: $RPT.bak-connect-lookup-remove-$STAMP)"
  fi

  # 2. services
  systemctl disable --now connect-lookup-live.service connect-lookup-clean.timer connect-lookup-checkver.timer >/dev/null 2>&1
  rm -f "$UNITDIR/connect-lookup-live.service" "$UNITDIR/connect-lookup-clean.service" "$UNITDIR/connect-lookup-clean.timer" \
        "$UNITDIR/connect-lookup-checkver.service" "$UNITDIR/connect-lookup-checkver.timer"
  systemctl daemon-reload
  note "services removed"

  # 3. scripts and page
  rm -f "$CUSTOM/conlog.sh" "$CUSTOM/live.sh" "$CUSTOM/track.sh" "$CUSTOM/names.sh" "$CUSTOM/topology.php" "$CUSTOM/checkver.sh" "$CUSTOM/qrz.conf"
  rmdir "$CUSTOM" 2>/dev/null
  if grep -q "$MARK" "$WEB/index.php" 2>/dev/null; then rm -rf "$WEB"; note "web page removed"; fi

  rm -rf "$LOGDIR/stats-cache" "$LOGDIR/topology.json" "$LOGDIR/topology.lock" "$LOGDIR/keyed.txt" "$LOGDIR/keyed.tmp" "$LOGDIR/latest-version.txt" "$LOGDIR/latest-version.txt.tmp" 2>/dev/null

  # 4. history is only deleted when asked
  if [ -d "$LOGDIR" ]; then
    if [ "$DELHIST" = 1 ]; then
      rm -rf "$LOGDIR"; note "history deleted"
    else
      note "history kept in $LOGDIR (to delete it too, run the uninstall again with  --delete-history )"
    fi
  fi

  say ""
  say "Connect Lookup has been removed. Other pages on this node, and your favorites, were not touched."
  say "The app's visitor level (Full control or Read-only) was left as it is; you can change it in the app's own settings."
  say "Check:  sudo grep -n conlog $RPT   (no output is correct)"
}

# ----------------------------------------------------------------------
#  Main
# ----------------------------------------------------------------------
for a in "$@"; do
  case "$a" in
    --yes|-y)          YES=1 ;;
    --qrz)             QRZ=1 ;;
    --password)        PWSET=1 ;;
    --check)           MODE=check ;;
    --uninstall)       MODE=uninstall ;;
    --delete-history)  DELHIST=1 ;;
    -h|--help)         usage; exit 0 ;;
    [0-9]*)            NODE="$a" ;;
    *)                 usage; die "Unknown option: $a" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "Please run this with sudo, for example:  sudo bash $0 123456"

if [ "$MODE" = uninstall ]; then
  do_uninstall
  exit 0
fi

if [ "$PWSET" = 1 ]; then
  do_password
  exit 0
fi

[ -n "$NODE" ] || { usage; die "Please give your node number, for example:  sudo bash $0 123456"; }
[[ "$NODE" =~ ^[0-9]{3,7}$ ]] || die "'$NODE' does not look like a node number."

say "Connect Lookup installer $VERSION - node $NODE"
say ""
preflight

if [ "$MODE" = check ]; then
  say ""
  say "All checks passed. Nothing was changed. Run again without --check to install."
  exit 0
fi

say ""
say "This will:"
say "  1. Put the web page in $WEB (with an optional panel beside it if the node-connect app is installed)"
say "  2. Add six small helper scripts in $CUSTOM"
say "  3. Add a background service, a daily cleanup job and a daily version check (systemd)"
say "  4. Add two lines (connpgm and discpgm) to the [$NODE] section of"
say "     $RPT, after saving a backup copy, and reload app_rpt"
say "  5. Add a Full control / Read-only switch at the top of the panel and offer to set its"
say "     password (press Enter to skip). On a first install the app's visitor level is set to Read-only."
say "Nothing else is changed. node-connect and your other pages are left alone."
say ""
ask "Install Connect Lookup for node $NODE?" || cancelled

do_install
