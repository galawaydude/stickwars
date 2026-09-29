# STICKTOP

Press ⌥⇧F on any app. The screen freezes into a level: every word, icon, button and title bar is solid.
Fight stick figures on it, shoot letters out one at a time, blow craters that reveal a pixel city behind
the screen, and watch the pieces pile up. Esc or ⌥⇧F gives you your desktop back, untouched.

Native Swift + SpriteKit, no assets and no dependencies. macOS 14+, Apple Silicon, primary display.

## Build and run

```sh
./build.sh                 # swift build -c release, assembles and ad hoc signs STICKTOP.app
open STICKTOP.app          # menu-bar icon (figure.boxing)
```

`build.sh` signs with a pinned designated requirement (`identifier "com.galawaydude.sticktop"`), so the
Screen Recording and Accessibility grants survive rebuilds.

On first launch macOS asks for:

- **Screen Recording** (required). The grant only applies after STICKTOP is quit and reopened.
- **Accessibility** (optional, recommended). Used only to read element frames for exact rectangles.
  Without it, elements come from pixel detection alone.

## Controls

| Key | Action |
| --- | --- |
| A / D | move |
| W / Space | jump (double jump, wall jump) |
| S | drop through a ledge, fast fall |
| Shift | jetpack |
| Mouse, left click | aim, fire (hold for automatic weapons, hold and release to charge the blaster) |
| Right click | grenade (3, recharging) |
| 1–7, scroll | pistol, SMG, shotgun, rocket, plasma, blaster, laser |
| R | reload |
| F3 | debug overlay (FPS, update ms, elements, bodies, particles, dirty tiles) |
| Esc, ⌥⇧F | pause and hide |

The menu has Play/Pause, New Match, Bots (0–5), Difficulty and Mute.

## Dev harness (headless, never shows the window)

```sh
./dev.sh start                                   # runs STICKTOP.app --dev (no menu icon, no prompts)
./dev.sh fake play "step 600" state "snap lines" # synthetic page, simulate 5 s, dump state, PNG with ledges
./dev.sh "give rocket" "shoot 100 500 400 300" "blast 700 300 70" "perfblast 600" bots
./dev.sh stop
STICKTOP.app/Contents/MacOS/STICKTOP --selfcheck # extraction, one-way collision, fracture
```

Commands: `fake`, `play`, `pause`, `step N`, `perf N`, `perfblast N`, `snap [lines] [crop x y w h] [/path.png]`,
`state`, `key CODE down|up`, `mouse X Y`, `click down|up`, `tp X Y`, `give N|NAME`, `shoot X1 Y1 X2 Y2`,
`blast X Y R`, `grenade X Y VX VY`, `elements`, `bots`, `synth`. Results go to `/tmp/sticktop-out.txt`.
Stepping drives `scene.update` and SpriteKit physics through `SKRenderer`, so it works with the display asleep.

## Layout

| Folder | What |
| --- | --- |
| App | menu, hotkey, permissions, window, play/pause |
| Capture | ScreenCaptureKit snapshot, CGWindowList |
| Elements | pixel detector, AX scanner, merge into elements |
| Level | elements + spatial hash, raycast |
| Canvas | tiled editable snapshot with dirty-tile uploads |
| Destruction | letter knock-out, carving, crumbling, explosions, radial fracture |
| Physics | debris rigid bodies (freeze/wake), static element bodies |
| Fighter | platformer controller, procedural rig |
| Weapons | weapon table, firing, hitscan, projectiles, damage |
| AI | ledge nav graph + A*, bot brain |
| Game | scene loop, match flow, dev hooks |
| FX, HUD, Art, Audio, Dev | particles, HUD, procedural textures and font, synthesized sound, harness |
