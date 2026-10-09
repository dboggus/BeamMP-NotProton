# BeamMP on macOS with NotProton

Play BeamNG.drive multiplayer ([BeamMP](https://beammp.com)) on an Apple Silicon Mac by using the **native macOS Steam client** and [NotProton](https://github.com/NotProtonNot/NotProton). Once it's set up, pressing **Play** in Steam does everything: it checks the BeamMP mod for updates, starts the game, and starts the BeamMP launcher.

> **Unofficial.** BeamMP does not support macOS. This relies on a community launcher fork, NotProton, and CrossOver, and any of them can change. Expect some rough edges, such as occasional desync or odd vehicle spawns.

**Tested with:** BeamNG.drive 0.39.4 · NotProton using the CrossOver 26.3 runner (Rosetta) · [BeamMP-Launcher-macOS](https://github.com/egrm/BeamMP-Launcher-macOS) v2.8.1 · Apple Silicon

---

## What you need

- An Apple Silicon Mac with the native **Steam** app
- **CrossOver** (licensed) and **NotProton** set up according to NotProton's instructions
- **BeamNG.drive** installed from Steam, with NotProton selected as its compatibility tool
- The official **BeamMP installer** ([beammp.com](https://beammp.com))
- `BeamMP-Launcher.exe` from the [egrm/BeamMP-Launcher-macOS](https://github.com/egrm/BeamMP-Launcher-macOS/releases) releases
- [`beammp-steam.sh`](beammp-steam.sh) from this repo (step 3 downloads it for you)

## Setup

### 1. Get BeamNG running in single-player

1. In Steam, open BeamNG.drive → **Properties → Compatibility**, force the NotProton/CrossOver tool, and set:
   - **Graphics:** Automatic or D3DMetal
   - **MSync:** On
   - **High Resolution:** Off
2. In **Properties → General → Launch Options**, add `-gfx dx11` after `%command%`. For example:
   ```
   WINEMSYNC=1 %command% -gfx dx11
   ```
   > **Required.** BeamNG 0.39 uses DirectX 12 by default. Under D3DMetal, the ground doesn't render: the map shows a white haze below the horizon. Forcing DX11 fixes it.
3. Launch the game once, load a map, then quit. This creates the game's Wine prefix.

### 2. Install BeamMP into BeamNG's prefix

NotProton doesn't use CrossOver bottles. Each Steam game gets its own Wine prefix, and BeamNG's is:

```
~/Library/Application Support/Steam/steamapps/compatdata/284160/pfx
```

1. Open the **NotProton** app → **Prefixes** → select **BeamNG.drive (284160)** → **Run Program…** → choose the BeamMP installer.
2. Replace the official launcher with the Mac-patched one. Copy `BeamMP-Launcher.exe` from the egrm release over the existing file in:
   ```
   …/compatdata/284160/pfx/drive_c/users/steamuser/AppData/Roaming/BeamMP-Launcher/
   ```

### 3. Install the Play-button script

Download the script from this repo into `~/BeamMP`:

```sh
mkdir -p ~/BeamMP
curl -fsSL -o ~/BeamMP/beammp-steam.sh \
  https://raw.githubusercontent.com/dboggus/BeamMP-NotProton/main/beammp-steam.sh
chmod +x ~/BeamMP/beammp-steam.sh            # don't skip this, Steam fails silently without it
xattr -d com.apple.quarantine ~/BeamMP/beammp-steam.sh 2>/dev/null   # only if you downloaded it in a browser, see below
~/BeamMP/beammp-steam.sh echo "script runs"  # should print: script runs
```

> **About the `xattr` line:** browsers tag downloaded files with a `com.apple.quarantine` flag, which can make macOS block or prompt on files run outside Terminal. Files downloaded with `curl` don't get this flag, so if you used the command above you can skip this line. Removing the flag is a precaution, and the line does nothing if the flag isn't there. If `xattr ~/BeamMP/beammp-steam.sh` doesn't list `com.apple.quarantine`, you can also skip it.

### 4. Point Steam at the script

Set BeamNG's **Launch Options**. Keep any `NAME=value` settings NotProton has already added, and put the script directly before `%command%`:

```
WINEMSYNC=1 "$HOME/BeamMP/beammp-steam.sh" %command% -gfx dx11
```

### 5. Play

Press **Play**. The BeamMP launcher window opens shortly after the game. At the main menu it should say **Game Connected!** Open **Multiplayer** and join a server.

---

## Updating

| What | How |
|---|---|
| BeamMP mod | Automatic. The script checks for a new version each time you press Play. |
| BeamMP launcher | Download the newest `BeamMP-Launcher.exe` from the egrm fork and copy it over the old one (step 2.2). |
| `beammp-steam.sh` | Run the `curl` and `chmod` commands from step 3 again to get the latest version from this repo. |
| NotProton / CrossOver | Nothing to do. The script uses whichever runner NotProton is currently using. |

## Options

Put these in front of the script path in the Launch Options, for example `BEAMMP_MOD_UPDATE=0 "$HOME/BeamMP/beammp-steam.sh" %command% -gfx dx11`.

| Variable | Default | Effect |
|---|---|---|
| `BEAMMP_MOD_UPDATE` | `1` | Set to `0` to skip the mod update check before launch. Launch is faster, but you have to update the mod yourself. |
| `BEAMMP_PORT` | `4444` | Launcher port. Change it only if you changed it in `Launcher.cfg`. |
| `BEAMMP_DEBUG` | `0` | Set to `1` to run the launcher with `--verbose`. |

---

## Why the script is needed

Each problem below breaks a "normal" BeamMP setup under NotProton:

1. **NotProton resets the prefix when you press Play.** Its launch script runs `wineserver -k` on the game's prefix right before the game starts. This kills every Windows program in the prefix, including a BeamMP launcher you started beforehand. The script waits for the game's own process (`BeamNG.drive.x64`) and starts the launcher after the reset.
2. **The launcher can't start the game itself.** BeamMP normally launches `BeamNG.drive.exe` directly. Started that way, the game misses NotProton's Steam bridge and fails its Steam check. The script runs the launcher with `--no-launch` and lets Steam start the game.
3. **The launcher overwrites the mod while the game is using it.** The macOS fork patches `BeamMP.zip` for Wine, so the launcher's update check never matches the official version and it re-downloads the mod on every start. If the game already has the mod loaded, its multiplayer menu freezes. The script therefore runs the update before the game starts, and runs the in-game launcher with `--no-download`.
4. **The mod only looks for the launcher once.** The BeamMP mod tries to connect when the game loads. If the launcher isn't listening yet, the Multiplayer menu hangs. Starting the launcher as soon as the game process appears gets it listening in time.

The script runs the launcher with the same Wine environment NotProton uses: the same runner, prefix, and MSync setting. It logs each step to:

```
~/Library/Application Support/Steam/steamapps/compatdata/284160/beammp-steam.log
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Play starts, then stops right away, and there's no `beammp-steam.log` | The script isn't executable. Run `chmod +x ~/BeamMP/beammp-steam.sh`. |
| Ground is a white haze, in both single-player and multiplayer | `-gfx dx11` is missing from the Launch Options. |
| Multiplayer menu freezes: music still plays but clicks do nothing | The launcher isn't connected. Press **Ctrl+L** at the main menu to reload the game's Lua, then try again. Check the log for `launcher listening on 4444`. |
| Log ends with `BeamNG never started` | The game process name didn't match. Check it with `pgrep -fil beamng` while the game is running. |
| Vehicle spawns underground or doubled after joining | A known BeamMP-on-Mac issue. Open the map (**M**) and teleport, or reset the vehicle. |
| The script breaks after an update | Set the Launch Options back to `WINEMSYNC=1 %command% -gfx dx11` to play single-player, then check the log. |

### Manual fallback (no script)

1. Launch BeamNG from Steam and wait for the main menu.
2. In the NotProton app, use **Run Program…** on the 284160 prefix to start a `.bat` file containing:
   ```bat
   start "" "C:\users\steamuser\AppData\Roaming\BeamMP-Launcher\BeamMP-Launcher.exe" --no-launch --no-download --no-update
   ```
3. Press **Ctrl+L** in-game, wait for **Game Connected!**, then open Multiplayer.

To update the mod by hand, close the game and run the launcher once with only `--no-launch`, then close it.

---

## Credits

- [NotProton](https://github.com/NotProtonNot/NotProton): Steam Play for macOS
- [egrm/BeamMP-Launcher-macOS](https://github.com/egrm/BeamMP-Launcher-macOS) and [Alien4042x/BeamMP-Launcher](https://github.com/Alien4042x/BeamMP-Launcher): Wine/CrossOver fixes for the BeamMP launcher
- [BeamMP](https://beammp.com) and [BeamNG](https://beamng.com)

Not affiliated with BeamMP, BeamNG, CodeWeavers, or Valve.
