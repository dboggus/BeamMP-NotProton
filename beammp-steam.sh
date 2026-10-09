#!/bin/sh
# beammp-steam.sh — one-click BeamMP for BeamNG.drive under NotProton (macOS Steam)
#
# Steam launch options for BeamNG.drive:
#   <NotProton's NAME=value settings> "$HOME/BeamMP/beammp-steam.sh" %command% -gfx dx11
#
# What it does when you press Play:
#   1. (optional) Runs the BeamMP launcher briefly BEFORE the game starts so it can
#      download + re-patch BeamMP.zip if a new mod version is out, then stops it.
#   2. Hands off to NotProton (%command%) to start the game normally.
#   3. In the background, waits for BeamNG to start (after NotProton's prefix reset),
#      then starts the launcher with --no-launch --no-download --no-update so the
#      in-game BeamMP mod finds it on 127.0.0.1:4444.
#
# Tunables (put them in front of the script path in Steam's launch options):
#   BEAMMP_MOD_UPDATE=0   skip step 1 (faster launch; update the mod manually)
#   BEAMMP_PORT=4444      launcher port, if you changed it in Launcher.cfg
#   BEAMMP_DEBUG=1        keep a verbose launcher log

# ---- 0. Arguments: tolerate NAME=value words that land between us and %command% ----
while [ $# -gt 0 ]; do
  case "$1" in
    [A-Za-z_]*=*)
      name=${1%%=*}
      case "$name" in *[!A-Za-z0-9_]*) break ;; esac
      export "$1"; shift ;;
    *) break ;;
  esac
done

if [ $# -eq 0 ]; then
  echo "beammp-steam.sh: put %command% after this script in Steam's launch options" >&2
  exit 1
fi

# Not running under NotProton? Just start the game.
[ -n "$STEAM_COMPAT_DATA_PATH" ] || exec "$@"

LOG="$STEAM_COMPAT_DATA_PATH/beammp-steam.log"
PORT="${BEAMMP_PORT:-4444}"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG"; }
[ "$(stat -f %z "$LOG" 2>/dev/null || echo 0)" -gt 262144 ] && : > "$LOG"
log "=== beammp-steam start (pid $$) ==="

# ---- 1. Rebuild NotProton's Wine environment (mirrors compat_run.sh / PrefixTools) ----
tool_dir=""
for a in "$@"; do
  d=$(dirname -- "$a" 2>/dev/null) || continue
  if [ -r "$d/build" ]; then tool_dir=$d; break; fi
done
np_build=""; np_flavor=""
[ -n "$tool_dir" ] && read -r np_build 2>/dev/null < "$tool_dir/build"
[ -n "$tool_dir" ] && [ -r "$tool_dir/flavor" ] && read -r np_flavor 2>/dev/null < "$tool_dir/flavor"
# Fall back to the build NotProton last ran this prefix with.
[ -n "$np_build" ] || read -r np_build 2>/dev/null < "$STEAM_COMPAT_DATA_PATH/notproton-build"
case "$np_build" in ''|*[!A-Za-z0-9.-]*)
  log "could not work out the NotProton CrossOver build; starting the game without BeamMP"
  exec "$@" ;;
esac

CX_ROOT="$HOME/Library/Application Support/notproton/runners/crossover-$np_build/CrossOver"
CX_HOME="$HOME/Library/Application Support/CrossOver"
wine_unix="$CX_ROOT/lib/wine/aarch64-unix"
WINELOADER="$wine_unix/wine.app/Contents/MacOS/wine"
WINESERVER="$CX_ROOT/bin/wineserver-arm64"
if [ "$np_flavor" = rosetta ] || [ ! -x "$WINELOADER" ] || [ ! -x "$WINESERVER" ]; then
  wine_unix="$CX_ROOT/lib/wine/x86_64-unix"
  WINELOADER="$wine_unix/wine"
  WINESERVER="$CX_ROOT/bin/wineserver"
  [ -x "$WINESERVER" ] || WINESERVER="$CX_ROOT/bin/wineserver-x86"
fi
WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
WINEDLLPATH="$CX_ROOT/lib/wine/x86_64-windows:$wine_unix"
LAUNCHER_DIR="$WINEPREFIX/drive_c/users/steamuser/AppData/Roaming/BeamMP-Launcher"
LAUNCHER_EXE="$LAUNCHER_DIR/BeamMP-Launcher.exe"
log "build=$np_build flavor=${np_flavor:-?} loader=$WINELOADER"

if [ ! -x "$WINELOADER" ] || [ ! -f "$LAUNCHER_EXE" ]; then
  log "missing wine loader or $LAUNCHER_EXE; starting the game without BeamMP"
  exec "$@"
fi

msync() {
  v=$(tr -d ' \t\n' < "$STEAM_COMPAT_DATA_PATH/notproton-msync" 2>/dev/null)
  printf '%s' "${WINEMSYNC:-${v:-0}}"
}

# Run a Wine command in the game's prefix with NotProton's runner, detached from Steam.
wine_run() {
  ( cd "$LAUNCHER_DIR" || exit 1
    env CX_ROOT="$CX_ROOT" CX_HOME="$CX_HOME" \
        WINELOADER="$WINELOADER" WINESERVER="$WINESERVER" \
        WINEDLLPATH="$WINEDLLPATH" WINEPREFIX="$WINEPREFIX" \
        WINEMSYNC="$(msync)" WINEDEBUG=-all \
        PATH="$CX_ROOT/bin:$PATH" \
        "$WINELOADER" "$@" ) </dev/null >> "$LOG" 2>&1 8>&- 9>&- &
}

port_open() { /usr/bin/nc -z -G 1 127.0.0.1 "$PORT" >/dev/null 2>&1; }
verbose=""; [ "${BEAMMP_DEBUG:-0}" = 1 ] && verbose="--verbose"

# ---- 2. Pre-game: let the launcher update + patch BeamMP.zip, then stop it ----
if [ "${BEAMMP_MOD_UPDATE:-1}" = 1 ]; then
  log "checking for a BeamMP mod update"
  wine_run "$LAUNCHER_EXE" --no-launch --no-update $verbose
  # The launcher only opens its port after the mod download/patch step has finished.
  i=0
  while [ $i -lt 90 ] && ! port_open; do sleep 1; i=$((i + 1)); done
  if port_open; then log "mod check done after ${i}s"; else log "mod check timed out after ${i}s"; fi
  env WINEPREFIX="$WINEPREFIX" "$WINESERVER" -k >/dev/null 2>&1
  env WINEPREFIX="$WINEPREFIX" "$WINESERVER" -w >/dev/null 2>&1
  i=0; while [ $i -lt 10 ] && port_open; do sleep 1; i=$((i + 1)); done
fi

# ---- 3. Background watcher: start the launcher once the game is up ----
(
  # NotProton resets the prefix (wineserver -k) before the game starts, so wait for
  # the real game process (Bin64\BeamNG.drive.x64.exe). Don't match BeamNG.drive.exe:
  # that name is in this script's own arguments.
  i=0
  until /usr/bin/pgrep -fi 'BeamNG\.drive\.x64' >/dev/null 2>&1; do
    sleep 1; i=$((i + 1))
    if [ $i -ge 300 ]; then log "BeamNG never started; watcher giving up"; exit 0; fi
  done
  log "BeamNG process seen after ${i}s; starting the launcher"
  sleep 2
  wine_run "$LAUNCHER_EXE" --no-launch --no-download --no-update $verbose
  i=0
  while [ $i -lt 60 ] && ! port_open; do sleep 1; i=$((i + 1)); done
  if port_open; then log "launcher listening on $PORT"; else log "launcher did not open port $PORT"; fi
) </dev/null >> "$LOG" 2>&1 &

# ---- 4. Hand off to NotProton ----
log "handing off to NotProton: $*"
exec "$@"
