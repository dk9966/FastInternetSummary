# Fast Internet Summary <img src="docs/menubar-icon.svg" alt="" width="28" height="28" valign="middle">

A native macOS menu-bar app for the three questions you actually ask about a connection: what am I on, is it doing anything right now, and how fast can it go?

Most importantly, metrics are **streamed**, so it's **fast**.

<img src="docs/demo.gif" width="340" alt="Press Option-Command-Period to open Fast Internet Summary and run a speed test">

It lives in the menu bar. There is no Dock icon. Click the icon, or press **⌥⌘.**, and a compact panel drops down on the display the mouse is on. Close it with the X or **Escape**.

## Install

You need a Mac on **macOS 15** or later, and **Xcode** from the App Store. Open Xcode once so the license is accepted. There are no required Homebrew packages, no accounts, and no third-party Swift packages. The speed test uses macOS’s built-in `networkQuality` unless you optionally install Ookla’s CLI.

```bash
git clone https://github.com/dk9966/FastInternetSummary.git
cd FastInternetSummary
bash scripts/install.sh
```

That builds a Release app, copies it to `/Applications` (or `~/Applications` if that folder is not writable), and opens it. Look for the plug icon in the menu bar.

To put the app somewhere else:

```bash
PREFIX="$HOME/Applications" bash scripts/install.sh
```

To work on the code instead:

```bash
open FastInternetSummary.xcodeproj
```

Select the **FastInternetSummary** scheme and run it (⌘R).

## Uninstall

Quit from Settings, or Control-click / right-click the menu-bar icon and choose Quit. If Launch at Login is on, turn it off in the app first (or in System Settings → General → Login Items). Then:

```bash
rm -rf /Applications/FastInternetSummary.app ~/Applications/FastInternetSummary.app
```

Settings are local only. To drop them too:

```bash
defaults delete com.danielku.FastInternetSummary
```

## What it shows

The panel is three blocks, on purpose.

**Connection** tells you whether the Mac is on Ethernet, Wi‑Fi, or both. If both are up, it marks the one currently carrying internet traffic as **In use**. On Wi‑Fi it shows the network name when macOS will give it; on Ethernet it shows the negotiated link speed when that value is available.

**Live activity** is what is happening this second. It reads byte counters on the default-route interface about once a second. If nothing is transferring, it sits near zero even on a fast plan. That is expected. This is not a speed test.

The speed-test block is a capacity measurement. The title is the engine in use: **MacOS Network Quality** by default, or **Ookla Speedtest** if you switch in Settings. Opening the panel starts one automatically. Idle latency (the **ms** figure on the right) lands almost immediately. Download and upload then run one after the other (website-style) and update live. Ping under each speed is latency while that direction is filling the line.

While a test is running, a progress bar and a short stage line sit under the numbers: idle latency, then download, then upload. The last complete result stays on the Mac and comes back when you reopen the app, with a **Checked … ago** line under it. Starting a new test keeps those numbers visible but faded until the new samples replace them.

If you have Ookla’s official Speedtest CLI installed, Settings can switch to that — same engine as the Speedtest app. Turn on **Download and upload together** for Apple’s test if you want both directions at once; those results can differ from Speedtest. That toggle is only shown for Apple’s test. Run again to repeat it. Closing the panel cancels a test in progress.

Do not mix those last two numbers. Live activity is traffic right now. The speed test is what the line can do under load.

## Using it

| Action        | How                                                        |
| ------------- | ---------------------------------------------------------- |
| Open / toggle | Click the menu-bar icon, or **⌥⌘.**                        |
| Close         | X button, or **Escape**                                    |
| Settings      | Gear next to the title                                     |
| Quit          | Settings, or Control-click / right-click the menu-bar icon |

Settings covers launch at login, whether live rates appear in the menu bar itself, the sample interval (1s / 2s / 5s), optional Speedtest CLI, simultaneous vs sequential Apple tests, and the global shortcut.

The default shortcut is **Option-Command-Period**. It is not a system shortcut, and you can change it. On more than one display, the panel opens on the screen the mouse is on, lined up with the icon’s usual place in that menu bar.

## How the numbers are measured

Live rates come from `getifaddrs` byte counters on the active interface, sampled on a timer.

The default speed test is `/usr/bin/networkQuality`. Idle latency is Apple’s `base_rtt`: a few quiet-line probes (TCP handshake, TLS, HTTP/2) before the line is saturated. Capacity is sequential by default (`-s`: download, then upload). Settings can switch that to a simultaneous download and upload; those results can differ from Speedtest. Verbose TTY output is parsed so Mbps can update while the test is still running. Loaded ping under download and upload is Apple’s downlink/uplink responsiveness, shown in milliseconds.

If **Use Speedtest (Ookla)** is on, the app runs the official `speedtest` CLI instead (`--format=jsonl`). That is Ookla’s engine, talking to a nearby Speedtest server. A nearby server is remembered for about 30 minutes so the next test can skip the hunt. JSONL is parsed so idle ping, download, upload, and loaded ping under each speed update live. The CLI is optional; the app still works without it. Ookla CLI launches are capped so we do not trip their rate limit.

```bash
brew tap teamookla/speedtest
brew install speedtest
```

## Notes

- If Ethernet and Wi‑Fi are both connected, **In use** is the default route, not “whichever looks faster.”
- Ethernet link speed is omitted when the negotiated media rate cannot be read.
- The Wi‑Fi name comes from CoreWLAN. On some macOS versions the SSID is unavailable without Location permission. This app does not ask for that permission; it still shows connected / in-use state without a name.
- The app does not request Accessibility or Screen Recording permission. The global shortcut uses `RegisterEventHotKey`.
- Built as an agent app (`LSUIElement`), so it does not bounce in the Dock.
- On more than one display, the panel does not ride the menu-bar icon as it jumps between screens. It opens on the display the mouse is on.
- The last complete speed test is stored on the Mac and shown again the next time you open the panel.
- The app does not have an account, analytics, or its own servers. Connection names, live rates, and the last speed-test result stay on the Mac. The default speed test is Apple’s `networkQuality`, which talks to Apple. The optional Speedtest CLI talks to Ookla.

## License

MIT. See [LICENSE](LICENSE).
