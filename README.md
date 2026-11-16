# WaveAce for macOS

A native SwiftUI application for the LeCroy WaveAce 224. Connects over Ethernet using VICP on TCP port 1861. No external libraries or VISA installation required.

## Getting started

Open `build/WaveAce.app`, enter the oscilloscope's IP address (default: `192.168.0.100`), and click **Connect** (`Připojit` in the current Czech interface). If macOS requests access to the local network, allow it and retry the connection if necessary. You can also find this permission under System Settings → Privacy & Security → Local Network → WaveAce. Connecting only reads the current settings and waveforms. The Run, Stop, Single, timebase, channel sensitivity, and trigger controls change the instrument's settings.

- Each channel's **Input** (`Vstup`) switch enables or disables that channel on the oscilloscope.
- The eye icon hides the waveform in the application and skips its transfer.
- The pause button next to the graph pauses transfers to the Mac; the oscilloscope continues acquiring data.
- The graph displays the entire transferred record or a zoomed section. Its time axis uses the WAVEDESC metadata. The transferred record's time range may differ from the range shown on the instrument's display.
- Vpp and RMS are calculated from the entire transferred record. The cursors measure the time difference within the visible section; `1/Δt` is the reciprocal of that difference.
- Under **Transfer to Mac → Samples** (`Přenos do Macu → Vzorky`), choose the full record or every 4th, 10th, or 20th sample. For an original record of 12,268 samples, these options transfer 12,268 / 3,067 / 1,226 / 613 samples per channel. This selects evenly spaced samples across the record; it may miss brief spikes and affect Vpp/RMS. Use the full record for detailed measurements. This setting does not change the oscilloscope's acquisition.
- CSV exports contain a separate pair of columns for each visible channel: time in seconds and voltage in volts. Only the samples actually transferred under the selected **Samples** setting are exported. PNG exports save the current graph.
- When transferring fewer samples, the WA224 firmware leaves the original record length and sample interval in the descriptor. The decoder accounts for the transfer stride and actual response length, adjusting the time axis accordingly. A normal disconnect restores the original transfer settings.
- Channels are downloaded sequentially. During continuous acquisition, their records may come from different acquisitions. To compare a single event, use Single and transfer the data after acquisition completes, or stop acquisition with the Stop button.

## Building and checking

Requires macOS 14+ and Xcode Command Line Tools with Swift 5.9+. Verified on Apple Silicon with macOS 26.7.2 and Xcode 27.2.

```sh
bash Tools/build-app.sh
swift test
swift run WaveAceCheck 192.168.0.100
swift run WaveAceCheck 192.168.0.100 --stride 10
```

`WaveAceCheck` reads the instrument identity, settings, and waveforms from enabled channels. It temporarily sets the transfer stride and restores the original value on successful completion. The Python tool `Tools/scope_probe.py` sends individual diagnostic queries (for example, `python3 Tools/scope_probe.py '*IDN?'`).

## Initial release scope

Ethernet connectivity, up to four channels, automatic transfers, Run/Stop/Single, timebase, channel sensitivity, trigger source/slope/level, zoom and pan, time cursors, Vpp/RMS, CSV, and PNG. Settings are periodically read back from the instrument. If the connection is lost, the last record remains visible and you can reconnect manually.

USB support is not yet implemented. Sequence, RIS, and waveforms with two data arrays are rejected to avoid displaying incorrectly interpreted data. Saving instrument setups, FFT, and advanced triggers are not included in this version. The oscilloscope's sample rate is independent of the waveform transfer refresh rate on the Mac.

## Compatibility and references

Verified on a physical instrument identifying itself as `LECROY,WA224`, with firmware **5.05.02.14**, VICP on port 1861, and `C1:WF? ALL` waveform transfers. The originally reported firmware version was correct; the EasyScope compatibility list on the manufacturer's website is not a complete list of all firmware versions for this instrument.

Validation on November 16, 2026: successful Debug and Release builds; seven automated decoder tests passed, including reduced-sample transfers and their time axes; decoding of an actual 12,268-sample record; CH1/CH2 retrieval through the native communication library; and live CH1–CH4 display in the application at approximately 1 frame/s. Exports and all combinations of settings have not yet been fully tested manually. This is an initial working version.

- [EasyScope — official support](https://www.teledynelecroy.com/support/softwaredownload/easyscope.aspx)
- [WaveAce 1000/2000 Remote Control Manual](https://cdn.teledynelecroy.com/files/manuals/wa1k2k_remote-control_manual.pdf) — a supporting reference for commands and the WAVEDESC structure, not a declaration of compatibility with the 224 model. The queries used were verified on a physical WA224.
- [WaveAce EasyScope Operator's Manual](https://cdn.teledynelecroy.com/files/manuals/es-om-e_reva.pdf)

The built application is locally ad hoc signed; it is not an Apple Developer ID-signed or notarized distribution package. All measurement data stays local.
