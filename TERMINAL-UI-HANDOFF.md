# Personal terminal UI — next-session handoff

Status: PLAN ONLY. No UI, palette adapter, dependencies or runtime changes were
implemented. The user closed the citizen-lab phase and now wants a terminal they
can personally use. They explicitly authorized reusing Signal's color values and
asked for ecosystem options before implementation. The user clarified that they
developed Signal themselves, are its sole contributor/user, and explicitly want
the palette reused. Treat that authorization as settled. Do not restart lab expansion.

## Recommendation and decision

Start with a local Phoenix endpoint plus xterm.js and a small TypeScript frontend.
Keep Erlang session ownership and the external Rust helper. Make one shell usable
in a browser first. Add Tauri only after that works if a standalone desktop window
is wanted. This is the recommended default for the next session, not a claim that
the user has selected a framework. A request to implement this handoff can accept
that default; do not scaffold several competing stacks.

Why: terminal emulation is its own subsystem. xterm.js supplies an established
terminal surface; Phoenix integrates with the BEAM processes we already have.
Rust is the stronger choice here for a fully native GUI, but a general GUI toolkit
does not by itself provide a finished terminal widget. Those are engineering
judgments about this project, not a universal ecosystem ranking.

| Option | What it supplies | Fit / tradeoff |
| --- | --- | --- |
| Phoenix + xterm.js | Local web application, channel transport, browser terminal surface | Recommended first usable version; fits existing OTP ownership; browser shortcuts and lifecycle need explicit handling |
| Tauri + xterm.js | Desktop window with Rust host and OS webview; same frontend can be reused | Recommended later desktop wrapper; package/start/stop BEAM release too, and test macOS WebKit behavior |
| Electron + xterm.js | Desktop shell with bundled Chromium/Node | Good alternative if consistent Chromium behavior outweighs a larger runtime; still connect to BEAM rather than create a second PTY owner |
| Rust Iced/egui + terminal core | Native GUI toolkits plus reusable terminal state/parser components | Strongest route of these for a Rust-native product; materially more work for glyph rendering, selection, IME, accessibility and terminal integration |
| Erlang wx | OTP binding to native wxWidgets GUI components | Real and longstanding surprise option. Good for tooling/inspectors; a terminal emulator/renderer still has to be integrated. Not the quickest route to this personal terminal |
| Elixir Scenic | BEAM client graphics framework, primarily aimed at fixed-screen devices | Interesting native experiment; less direct fit than xterm.js for a desktop terminal |

Do not treat Ratatui or another TUI toolkit as the emulator: it draws inside an
existing terminal. A custom native alternative should evaluate alacritty_terminal
for its parser/grid/selection model, while preserving our PTY ownership rather
than accidentally enabling its separate PTY event loop. No new emulator from scratch.

## Workspace and source binding

- Repo: /Users/cem/play/pty-lab; origin git@github.com:c3mb0/play.git; MIT.
- Lab baseline inspected: f7e6c11d0a0a722652b3fead8bf98a23bc27d81f.
- Read HANDOFF.md, erlang/pty_lab/API.md, protocol/README.md, RECEIPTS.md and
  OPERATOR-WISHLIST.md before changing lifecycle semantics. Check git status first.
- Signal source: /Users/cem/ins_repo/signal (not /home/ins_repo/signal).
- Signal HEAD: b8efbdf9c00cccc68b93884b7b942a64ebd369ee; clean when inspected.
- Canonical roles: signal.go, gruvbox.go, roles.go; Roles() is the export boundary.
- Signal typography: typography.go. Signal Mono / FiraCode, Nerd Fonts v3.4.0,
  ligatures disabled; fallback ui-monospace, SFMono-Regular, Menlo, Monaco,
  Consolas, monospace. Font distribution is separate from copying color values;
  if bundling font files, retain their SIL OFL terms/notices. Export theme roles;
  no whole-repository vendoring or runtime Go dependency is needed.

The source revision above is a navigation/reproducibility aid, not an ownership
check or an approval gate. Export the role values into one local theme snapshot
so the terminal builds without the Signal checkout or Go. Keep a short source
pointer with it; updates can be intentional later. No hash ceremony is required.
This handoff lists values but creates no executable theme artifact.

## Palette lifted into the plan

| Role | Value | Proposed use |
| --- | --- | --- |
| canvas | #1d2021 | terminal background |
| surface | #282828 | tab/title strip |
| surfaceRaised | #32302f | small menus/preferences |
| text | #e8e4dc | default terminal foreground/cursor |
| toolText | #adb3b8 | secondary chrome text |
| muted | #929ca5 | inactive labels |
| dim | #808a95 | quiet terminal/chrome detail |
| chromeTitle | #bbc0c5 | window/session title |
| chromeBorder | #65717c | chrome boundary |
| separator | #46515b | restrained dividers |
| positive | #8fb573 | positive status / ANSI green candidate |
| negative | #d96b63 | failure status / ANSI red candidate |
| pending | #d8bd72 | pending status / ANSI yellow candidate |
| identityBlue | #82a9cc | ANSI blue candidate |
| identityViolet | #b49be0 | ANSI magenta candidate |
| identityAqua | #78b9a2 | ANSI cyan candidate |
| identityOrange | #e09a65 | optional accent |
| copySurface | #203446 | copy feedback; selection-background candidate to review |

These values are observed Signal definitions. Their mapping to terminal ANSI
slots is a NEW proposed adapter, not an existing Signal ANSI theme. First palette:
black=canvas, red=negative, green=positive, yellow=pending, blue=identityBlue,
magenta=identityViolet, cyan=identityAqua, white=text. Start bright variants as
aliases, except brightBlack=dim, then check actual ANSI samples before accepting
that mapping. Do not invent brighter hex values merely to fill slots. Preserve
application-provided 256-color and truecolor sequences; do not recolor their bytes.

One CSS-token/JSON source snapshot should drive chrome and the xterm ITheme
adapter. Cursor accent can use canvas against text. Review selection contrast,
bold versus bright, dim text, Unicode/box drawing and screenshot legibility in the
actual terminal. Color names do not imply validated contrast on every background.

## Intended shape

    xterm.js + small TS/CSS chrome
               | Phoenix channel (local only)
    Elixir connection/session adapter
               | existing Erlang API, extended explicitly
    Erlang session worker -> Rust relay -> guardian -> interactive shell

Phoenix serves local assets and routes sessions; xterm owns the screen/grid,
escape-sequence parsing, selection and terminal input encoding. A LiveView page
may own outer controls later, but the terminal DOM is client-owned: do not send
cell grids or every keystroke through LiveView rendering/diffs. No React/Svelte
framework is required for the first terminal surface.

First product shape: one terminal pane filling the window, small title strip,
font-size controls and an exit/disconnect indication. Add tabs only after one pane
works. No lab dashboard, inspector badges, decorative telemetry or workflow UI.

## Gaps to solve before calling it a usable terminal

1. Interactive shell topology. Use ctty, fresh session and correct foreground
   process group, not the lab's slave-only comparison mode. Default to the user's
   configured executable shell, fallback /bin/zsh on this Mac; launch interactively
   and document login-shell choice. Start in an explicit user-selected cwd/default
   home. Use an explicit inherited environment snapshot appropriate to personal
   use, including TERM compatible with xterm; do not reuse the lab's tiny env or
   change the user's shell configuration. Ctrl-C/Ctrl-Z are terminal input bytes
   interpreted by line discipline/job control, not GUI-issued kill shortcuts.
2. Real lifetime policy. Current OTP sessions enforce a maximum 60000 ms deadline.
   A shell must survive normal use. Add an explicit interactive policy, e.g. a
   renewable owner lease with bounded disconnect grace, while keeping experiment
   deadline behavior unchanged. Define tab close, page refresh, browser death and
   BEAM restart. First version: no detach, no automatic shell replay; lost owner
   cancels after stated grace. Do not silently interpret caller death as cleanup.
3. Live resize. Add semantic resize(rows, cols), validate bounds, apply TIOCSWINSZ
   in Rust and return observed dimensions. Fit xterm after fonts load and on size
   changes; initialize size before launch. Test SIGWINCH and foreground job behavior
   with a controlled subject before using an editor. Initial-width evidence does
   not establish live resize behavior.
4. Flow control. Keep raw PTY bytes ordered. Decode helper hex to bytes, not to
   independently decoded text chunks; pass Uint8Array to xterm. Preserve partial
   UTF-8/escape sequences. Forward onData and, where needed, onBinary correctly.
   Bound every queue including BEAM mailboxes and browser buffers. Use output
   credits/acknowledgements tied to xterm.write completion and propagate backpressure
   upstream without blocking control/close messages. Current lab overflow-failure
   behavior alone is not adequate for a comfortable long output stream. Keep
   protocol changes semantic; do not build a generalized stream platform.
5. End versus EOF versus cleanup. Split direct-child exit from output stream
   completion when needed; a shell may exit while a descendant holds descriptors.
   Define ordinary terminal hangup and bounded close escalation. Existing public
   terminate kills only the direct child. Verify a foreground sleep/job on close;
   do not claim arbitrary descendant containment. UI state must distinguish exited,
   disconnected and cleanup incomplete. Retain remaining observations without
   making the user read harness internals during normal use.
6. Recording policy. Lab receipts synchronously retain full input/output. Personal
   terminals handle passwords and private command text. Default personal-session
   transcript recording OFF; keep bounded in-memory scrollback and minimal lifecycle
   events. Explicit opt-in recording/export can come later. Do not infer sensitive
   input solely from ECHO state. Preserve lab receipt behavior and old artifacts.

For the local-browser route, bind loopback, validate origin and require a startup
capability/token for shell control. Load only local app assets. PTY output is
terminal data, never injected HTML or backend commands. Give clipboard escape
requests and clickable links explicit handling. This is a local personal app,
not a remotely accessible shell service or multi-tenant product.

## Implementation order for the next session

A. Bind checkout/source revisions, read relevant AGENTS instructions, choose the
   recommended browser route unless the user specifies desktop-first. Keep the
   completed lab stable. Create a small terminal-app sibling under elixir/ (name
   such as play_terminal), depending on pty_lab; web assets live with that app.
   Do not repurpose experiment_runner as the personal terminal's session manager.
B. Export the pinned Signal role snapshot and make the xterm theme/ANSI adapter.
   Render a static terminal specimen with local fonts/fallback, ANSI/Unicode and
   selection. No new PTY owner or emulator. Pin package versions and lockfiles.
C. Wire one interactive controlling-PTY shell through the existing ownership chain.
   Add the explicit personal lifetime/recording policies and ordered byte bridge.
   Keep start/close/error behavior visible and make a one-command local launcher.
D. Implement resize and output flow control; verify editor alternate-screen,
   keyboard, paste, Unicode, job control and close behavior. Only then add tabs,
   search, font zoom and a small preferences surface as needed for actual use.
E. If desired, wrap these same assets in Tauri. Package a BEAM release and helper,
   define process startup/shutdown, keep BEAM as sole session owner, and test the
   macOS webview directly. Do not add a parallel Rust PTY stack inside Tauri.
   Bundling a BEAM runtime has its own size/startup cost even with Tauri's small
   host. Do not do desktop packaging before a useful shell exists.

## First useful acceptance, not another lab campaign

- Start from one documented command; type and edit commands in the user's shell.
- Shell survives past 60 seconds. A controlled test proves lease expiry/owner loss.
- Backspace, arrows, history, Ctrl-C, Ctrl-Z, fg, Ctrl-D, Option/Alt and Cmd-C/V work
  as specified; application copy does not swallow Ctrl-C interrupt. Bracketed paste,
  IME, Unicode/wide characters, selection and line wrapping are checked on macOS.
- less or an installed editor enters/exits alternate screen cleanly; repeated
  window resize updates stty size and redraws without changing shell session.
- A bounded high-output command completes without dropped bytes or unbounded memory;
  UI stays usable. Test split UTF-8/escape chunks and input during output pressure.
- Tab/window disconnect and helper failure leave a truthful UI and bounded cleanup
  for the documented process scope. No surprise session resurrection.
- Default recording produces no on-disk keystroke/output transcript. Lab recording
  remains unchanged. Palette comes from the pinned role export, not scattered literals.
- Run the existing checks appropriate to changed Rust/OTP/protocol code once; keep
  any failures and report scope honestly. Stop when a single-pane terminal is useful.

No implementation was performed while preparing this handoff. Source code and
fonts from Signal were inspected only. Only this Markdown plan was created.

## Primary references checked for this plan

- xterm.js project and existing consumers: https://github.com/xtermjs/xterm.js
- xterm theme API: https://xtermjs.org/docs/api/terminal/interfaces/itheme/
- xterm output flow control: https://xtermjs.org/docs/guides/flowcontrol/
- Phoenix channels: https://hexdocs.pm/phoenix/channels.html
- Tauri architecture: https://v2.tauri.app/concept/architecture/
- Tauri external binaries: https://v2.tauri.app/develop/sidecar/
- Electron process model: https://www.electronjs.org/docs/latest/tutorial/process-model
- Iced: https://iced.rs/
- egui: https://github.com/emilk/egui
- alacritty_terminal API: https://docs.rs/alacritty_terminal/latest/alacritty_terminal/
- Erlang wx: https://www.erlang.org/doc/apps/wx/chapter.html
- OTP Observer: https://www.erlang.org/doc/apps/observer/observer_ug.html
- Scenic scope: https://hexdocs.pm/scenic/overview_general.html

These establish available capabilities; no GUI stack was installed, benchmarked
or runtime-tested in this planning session. Version selection belongs to the
implementation session's lockfiles and platform checks.
