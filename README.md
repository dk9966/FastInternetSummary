# Fast Internet Summary <img src="docs/menubar-icon.svg" alt="" width="28" height="28" valign="middle">

A native macOS menu-bar app for the three questions you actually ask about a connection: what am I on, is it doing anything right now, and how fast can it go?

Most importantly, metrics are **streamed**, so it's **fast**.

<img src="docs/demo.gif" width="340" alt="Press Option-Command-Period to open Fast Internet Summary and run a speed test">

It lives in the menu bar. There is no Dock icon. Click the network icon, or press **⌥⌘.**, and a compact panel drops down. Close it with the X or **Escape**.

## Install

You need a Mac on **macOS 15** or later, and **Xcode** from the App Store. Open Xcode once so the license is accepted. There are no Homebrew packages, no Ookla CLI, no accounts, and no third-party Swift packages.

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

**Last speed test** is a capacity measurement using macOS’s built-in `networkQuality` tool. Opening the panel starts one automatically. Idle latency (the **ms** figure) lands almost immediately. Download and upload then run at the same time and update live while the test is still going. Turn on **Sequential speed test** in Settings if you want the website-style order: latency, then download, then upload. Run again to repeat it. Closing the panel cancels a test in progress.

Do not mix those last two numbers. Live activity is traffic right now. The speed test is what the line can do under load.

## Using it

| Action        | How                                                        |
| ------------- | ---------------------------------------------------------- |
| Open / toggle | Click the menu-bar icon, or **⌥⌘.**                        |
| Close         | X button, or **Escape**                                    |
| Settings      | Gear next to the title                                     |
| Quit          | Settings, or Control-click / right-click the menu-bar icon |

Settings covers launch at login, whether live rates appear in the menu bar itself, the sample interval (1s / 2s / 5s), sequential vs parallel speed test, and the global shortcut.

The default shortcut is **Option-Command-Period**. It is not a system shortcut, and you can change it.

## How the numbers are measured

Live rates come from `getifaddrs` byte counters on the active interface, sampled on a timer.

The speed test is `/usr/bin/networkQuality`. Idle latency is Apple’s `base_rtt`: a few quiet-line probes (TCP handshake, TLS, HTTP/2) before the line is saturated. Capacity is a parallel download and upload by default; Settings can switch that to `-s`, which runs download and then upload. Verbose TTY output is parsed so Mbps can update while the test is still running. Loaded responsiveness (RPM under saturation) is a different measurement and is not shown as ms.

## Notes

- If Ethernet and Wi‑Fi are both connected, **In use** is the default route, not “whichever looks faster.”
- Ethernet link speed is omitted when the negotiated media rate cannot be read.
- The Wi‑Fi name comes from CoreWLAN. On some macOS versions the SSID is unavailable without Location permission. This app does not ask for that permission; it still shows connected / in-use state without a name.
- The app does not request Accessibility or Screen Recording permission. The global shortcut uses `RegisterEventHotKey`.
- Built as an agent app (`LSUIElement`), so it does not bounce in the Dock.
- The app does not have an account, analytics, or its own servers. Connection names and live rates stay on the Mac. The speed test is Apple’s `networkQuality`, which talks to Apple.

## License

MIT. See [LICENSE](LICENSE).
