# Internet Info <img src="docs/menubar-icon.png" alt="" width="28" height="28" valign="middle">

A native macOS menu-bar app for the three questions you actually ask about a connection: what am I on, is it doing anything right now, and how fast can it go?

Most importantly, metrics are **streamed**, so it's **fast**.

<img src="docs/demo.gif" width="340" alt="Press Option-Command-Period to open Internet Info and run a speed test">

It lives in the menu bar. There is no Dock icon. Click the network icon, or press **⌥⌘.**, and a compact panel drops down. Close it with the X or **Escape**.

## What it shows

The panel is three blocks, on purpose.

**Connection** tells you whether the Mac is on Ethernet, Wi‑Fi, or both. If both are up, it marks the one currently carrying internet traffic as **In use**. On Wi‑Fi it shows the network name when macOS will give it; on Ethernet it shows the negotiated link speed when that value is available.

**Live activity** is what is happening this second. It reads byte counters on the default-route interface about once a second. If nothing is transferring, it sits near zero even on a fast plan. That is expected. This is not a speed test.

**Last speed test** is a capacity measurement using macOS’s built-in `networkQuality` tool. Opening the panel starts one automatically. Idle latency (the **ms** figure) lands almost immediately. Download and upload then run at the same time and update live while the test is still going. Run again to repeat it. Closing the panel cancels a test in progress.

Do not mix those last two numbers. Live activity is traffic right now. The speed test is what the line can do under load.

## Using it

| Action        | How                                                        |
| ------------- | ---------------------------------------------------------- |
| Open / toggle | Click the menu-bar icon, or **⌥⌘.**                        |
| Close         | X button, or **Escape**                                    |
| Settings      | Gear next to the title                                     |
| Quit          | Settings, or Control-click / right-click the menu-bar icon |

Settings covers launch at login, whether live rates appear in the menu bar itself, the sample interval (1s / 2s / 5s), and the global shortcut.

The default shortcut is **Option-Command-Period**. It is not a system shortcut, and you can change it.

## Build

Requires macOS 15 or later and Xcode 26. There are no Homebrew packages, no Ookla CLI, and no third-party Swift packages.

```bash
open InternetInfo.xcodeproj
```

Select the **InternetInfo** scheme and run it (⌘R). The app appears in the menu bar.

From the command line:

```bash
xcodebuild -project InternetInfo.xcodeproj -scheme InternetInfo -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/InternetInfo-*/Build/Products/Debug/InternetInfo.app
```

## How the numbers are measured

Live rates come from `getifaddrs` byte counters on the active interface, sampled on a timer.

The speed test is `/usr/bin/networkQuality`. Idle latency is Apple’s `base_rtt`: a few quiet-line probes (TCP handshake, TLS, HTTP/2) before the line is saturated. Capacity is a parallel download and upload; verbose TTY output is parsed so Mbps can update while the test is still running. Loaded responsiveness (RPM under saturation) is a different measurement and is not shown as ms.

## Notes

- If Ethernet and Wi‑Fi are both connected, **In use** is the default route, not “whichever looks faster.”
- Ethernet link speed is omitted when the negotiated media rate cannot be read.
- The Wi‑Fi name comes from CoreWLAN. On some macOS versions the SSID is unavailable without Location permission. This app does not ask for that permission; it still shows connected / in-use state without a name.
- The app does not request Accessibility or Screen Recording permission. The global shortcut uses `RegisterEventHotKey`.
- Built as an agent app (`LSUIElement`), so it does not bounce in the Dock.
