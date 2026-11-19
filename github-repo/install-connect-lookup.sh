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

VERSION="1.1"
MARK="connect-lookup-installer-v1"
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
declare -A PREV MISS WASDIR CUR
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
  /usr/sbin/asterisk -rx "rpt nodes @NODE@" 2>/dev/null | grep -v '\*' | tr ',' '\n' | tr -d ' \t' | grep -E '^[TRC][0-9A-Za-z-]+$' | cut -c2- > $D/live.tmp
  if [ ${PIPESTATUS[0]} -eq 0 ]; then mv -f $D/live.tmp $D/live.txt; fi
  now=$(date +%s)
  OLD=()
  while read -r n s; do OLD[$n]=$s; done < <(cat $D/direct.txt 2>/dev/null)
  /usr/sbin/asterisk -rx "rpt lstats @NODE@" 2>/dev/null | grep -E " (IN|OUT) " | while read -r n peer rc dir ct st; do
    IFS=: read -r h m s ms <<< "$ct"
    t=$((now - 10#$h*3600 - 10#$m*60 - 10#$s))
    o=${OLD[$n]:-0}; d=$((t-o)); if [ ${d#-} -le 3 ]; then t=$o; fi
    echo "$n $t"
  done > $D/direct.tmp
  while read -r n t; do grep -qx "$n $t" $D/direct-starts.txt 2>/dev/null || echo "$n $t" >> $D/direct-starts.txt; done < $D/direct.tmp
  mv -f $D/direct.tmp $D/direct.txt
  if [ $((now - LAST)) -ge 60 ]; then
    LAST=$now
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
    done
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
track() {
  local n ts LOG DIR
  CUR=()
  while read -r n; do [ -n "$n" ] && CUR[$n]=1; done < $D/live.txt
  [ ${#CUR[@]} -eq 0 ] && return
  DIR=" $(cut -d" " -f1 $D/direct.txt | tr "\n" " ") "
  if [ -z "$PINIT" ]; then
    PINIT=1
    for n in "${!CUR[@]}"; do PREV[$n]=1; done
  fi
  LOG=$D/$(date +%F).log
  ts="$now $(date +%F_%T)"
  for n in "${!CUR[@]}"; do
    unset "MISS[$n]"
    case "$DIR" in *" $n "*) WASDIR[$n]=1 ;; *) unset "WASDIR[$n]" ;; esac
    if [ -z "${PREV[$n]}" ]; then
      PREV[$n]=1; NEWC=1
      case "$DIR" in *" $n "*) ;; *) echo "$ts C @NODE@ $n" >> $LOG; SCANUNTIL=$((now + 300)) ;; esac
    fi
  done
  for n in "${!PREV[@]}"; do
    [ -n "${CUR[$n]}" ] && continue
    MISS[$n]=$(( ${MISS[$n]:-0} + 1 ))
    if [ ${MISS[$n]} -ge 2 ]; then
      lastd "$n" || echo "$ts D @NODE@ $n" >> $LOG
      unset "PREV[$n]" "MISS[$n]" "WASDIR[$n]"
    fi
  done
}
# true if the last logged event for node $1 (yesterday or today) is already a D
lastd() { [ "$(grep -h " [CD] @NODE@ $1\$" $D/$(date -d yesterday +%F).log $D/$(date +%F).log 2>/dev/null | tail -n1 | cut -d" " -f3)" = "D" ]; }
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
    [ -n "$l" ] && p="$f $l"
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
            $ev[] = ['t' => (int)$p[0], 'e' => $p[2], 'n' => $p[4]];
        }
        fclose($fh);
    }
    usort($ev, fn($a, $b) => $a['t'] <=> $b['t']);
    return $ev;
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
        if ($x['e'] === 'C') {
            if (isset($open[$n])) { $s = $open[$n]; $s['end'] = $x['t']; $sess[] = $s; }
            $open[$n] = ['node' => $n, 'start' => $x['t'], 'end' => null];
        } else {
            if (isset($open[$n])) { $s = $open[$n]; $s['end'] = $x['t']; $sess[] = $s; unset($open[$n]); }
            else { $sess[] = ['node' => $n, 'start' => null, 'end' => $x['t']]; }
        }
    }
    $lf = LOGDIR . '/live.txt';
    if (is_file($lf) && $now - filemtime($lf) < 20) {
        $lt = filemtime($lf);
        $live = [];
        foreach (file($lf, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $l) $live[trim($l)] = true;
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
if (isset($_GET['keyed'])) { header('Content-Type: application/json'); header('Cache-Control: no-store'); echo json_encode(add_keyed([])); exit; }
if (isset($_GET['json'])) {
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    echo json_encode(add_keyed(add_via(build())), JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
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
.live{color:#5fe08a;font-weight:600}
.empty{color:#777}
.echo td:not(.live), .echo td:not(.live) a { color: #c4e8ff; }
td{font-variant-numeric:tabular-nums}
td[data-start]{min-width:7.5em;white-space:nowrap}
tr.keyed td{background:#2a1212;box-shadow:inset 0 2px 0 #b83c3c,inset 0 -2px 0 #b83c3c}
tr.keyed td:first-child{box-shadow:inset 2px 0 0 #b83c3c,inset 0 2px 0 #b83c3c,inset 0 -2px 0 #b83c3c}
tr.keyed td:last-child{box-shadow:inset -2px 0 0 #b83c3c,inset 0 2px 0 #b83c3c,inset 0 -2px 0 #b83c3c}
tr.behind td{box-shadow:inset 0 1px 0 #6e3a3a,inset 0 -1px 0 #6e3a3a}
tr.behind td:first-child{box-shadow:inset 1px 0 0 #6e3a3a,inset 0 1px 0 #6e3a3a,inset 0 -1px 0 #6e3a3a}
tr.behind td:last-child{box-shadow:inset -1px 0 0 #6e3a3a,inset 0 1px 0 #6e3a3a,inset 0 -1px 0 #6e3a3a}
.opt{margin:10px 0 0;font-size:13px;color:#aaa}
.opt label{cursor:pointer}
.opt input{vertical-align:middle;margin-right:6px}
</style>
</head>
<body>
<h1>Connect Lookup - Node @NODE@</h1>
<div class="sub" id="status">Loading...</div>
<div class="opt"><label><input type="checkbox" id="behindBox">Outline the stations behind a link while that link is transmitting</label></div>
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
<script>
var BEHIND = false;
try { BEHIND = localStorage.getItem('cl-behind') === '1'; } catch (e) {}
var data = null;
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
      var sig = JSON.stringify(j.sessions);
      if (sig !== lastSig) { lastSig = sig; buildTables(); }
      applyKeyed();
      tick();
      $('status').textContent = 'Live - last update ' + new Date().toLocaleTimeString();
    })
    .catch(function(){ $('status').textContent = 'Update failed - retrying...'; });
}
(function(){ var b = $('behindBox'); b.checked = BEHIND; b.addEventListener('change', function(){ BEHIND = b.checked; try { localStorage.setItem('cl-behind', BEHIND ? '1' : '0'); } catch (e) {} applyKeyed(); }); })();
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
  "$fn" | sed "s/@NODE@/$NODE/g" > "$target.tmp" || die "Could not write $target"
  chmod "$mode" "$target.tmp"
  mv -f "$target.tmp" "$target" || die "Could not move $target into place"
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
  for f in "$CUSTOM/conlog.sh" "$CUSTOM/live.sh" "$CUSTOM/track.sh" "$CUSTOM/names.sh" "$CUSTOM/topology.php" \
           "$UNITDIR/connect-lookup-live.service" "$UNITDIR/connect-lookup-clean.service" \
           "$UNITDIR/connect-lookup-clean.timer" "$WEB/index.php"; do
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
  put 755 "$CUSTOM/topology.php" emit_topology
  note "$CUSTOM/conlog.sh, live.sh, track.sh, names.sh, topology.php"
  [ "$QRZ" = 1 ] && setup_qrz

  say "[3/6] Web page"
  install -d -m 755 "$WEB" || die "Could not create $WEB"
  put 644 "$WEB/index.php" emit_index
  note "$WEB/index.php"

  say "[4/6] Background service and daily cleanup"
  put 644 "$UNITDIR/connect-lookup-live.service"  emit_unit_live
  put 644 "$UNITDIR/connect-lookup-clean.service" emit_unit_clean_service
  put 644 "$UNITDIR/connect-lookup-clean.timer"   emit_unit_clean_timer
  systemctl daemon-reload || die "systemctl daemon-reload failed"
  systemctl enable connect-lookup-live.service >/dev/null 2>&1 || die "Could not enable the live service"
  systemctl restart connect-lookup-live.service || die "Could not start the live service (see: journalctl -u connect-lookup-live.service)"
  systemctl enable --now connect-lookup-clean.timer >/dev/null 2>&1 || die "Could not enable the cleanup timer"
  note "connect-lookup-live.service running, connect-lookup-clean.timer scheduled"

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
  local ip
  for ip in $(hostname -I 2>/dev/null); do
    case "$ip" in *:*) continue ;; esac
    say "    http://$ip/connect-lookup/"
  done
  if command -v tailscale >/dev/null 2>&1; then
    ip=$(tailscale ip -4 2>/dev/null | head -1)
    [ -n "$ip" ] && say "    http://$ip/connect-lookup/   (Tailscale)"
  fi
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
  say "  - Optional: at the top of the page there is a checkbox, \"Outline the stations"
  say "    behind a link while that link is transmitting\". It is off until you tick it;"
  say "    each browser remembers its own choice."
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
  systemctl disable --now connect-lookup-live.service connect-lookup-clean.timer >/dev/null 2>&1
  rm -f "$UNITDIR/connect-lookup-live.service" "$UNITDIR/connect-lookup-clean.service" "$UNITDIR/connect-lookup-clean.timer"
  systemctl daemon-reload
  note "services removed"

  # 3. scripts and page
  rm -f "$CUSTOM/conlog.sh" "$CUSTOM/live.sh" "$CUSTOM/track.sh" "$CUSTOM/names.sh" "$CUSTOM/topology.php" "$CUSTOM/qrz.conf"
  rmdir "$CUSTOM" 2>/dev/null
  if grep -q "$MARK" "$WEB/index.php" 2>/dev/null; then rm -rf "$WEB"; note "web page removed"; fi

  rm -rf "$LOGDIR/stats-cache" "$LOGDIR/topology.json" "$LOGDIR/topology.lock" "$LOGDIR/keyed.txt" "$LOGDIR/keyed.tmp" 2>/dev/null

  # 4. history is only deleted when asked
  if [ -d "$LOGDIR" ]; then
    if [ "$DELHIST" = 1 ]; then
      rm -rf "$LOGDIR"; note "history deleted"
    else
      note "history kept in $LOGDIR (to delete it too, run the uninstall again with  --delete-history )"
    fi
  fi

  say ""
  say "Connect Lookup has been removed. Other pages on this node were not touched."
  say "Check:  sudo grep -n conlog $RPT   (no output is correct)"
}

# ----------------------------------------------------------------------
#  Main
# ----------------------------------------------------------------------
for a in "$@"; do
  case "$a" in
    --yes|-y)          YES=1 ;;
    --qrz)             QRZ=1 ;;
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
say "  1. Put the web page in $WEB"
say "  2. Add five small helper scripts in $CUSTOM"
say "  3. Add a background service and a daily cleanup job (systemd)"
say "  4. Add two lines (connpgm and discpgm) to the [$NODE] section of"
say "     $RPT, after saving a backup copy, and reload app_rpt"
say "Nothing else is changed. AllScan and your other pages are left alone."
say ""
ask "Install Connect Lookup for node $NODE?" || cancelled

do_install
