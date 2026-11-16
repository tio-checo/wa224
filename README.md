# WaveAce for macOS

A native SwiftUI application for the LeCroy WaveAce 224. Connects over Ethernet using VICP on TCP port 1861. No external libraries or VISA installation required.

## Getting started

Open `build/WaveAce.app`, enter the oscilloscope's IP address (default: `192.168.0.100`), and click **Connect** (`Připojit` in the current Czech interface). If macOS requests access to the local network, allow it and retry the connection if necessary. You can also find this permission under System Settings → Privacy & Security → Local Network → WaveAce. Connecting reads the current instrument settings; live waveform downloads also configure the transfer stride as described below. The Run, Stop, Single, timebase, channel sensitivity, and trigger controls change the instrument's settings.

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

## Communication protocol

This section documents the protocol implemented in this repository and the behavior observed on a WA224 running firmware **5.05.02.14**. It is not a complete reference for every LeCroy command or instrument. The implementation is split between [`VICP.swift`](Sources/ScopeCore/VICP.swift) (transport), [`ScopeClient.swift`](Sources/ScopeCore/ScopeClient.swift) (instrument commands), and [`Waveform.swift`](Sources/ScopeCore/Waveform.swift) (binary decoding).

### Ethernet transport and VICP framing

The application opens one persistent IPv4 TCP connection to the instrument on **port 1861**. The IP address is configurable; the port is currently fixed by the client. Commands use LeCroy's ASCII remote-control syntax inside **VICP (Versatile Instrument Control Protocol)** frames. This is neither HTTP nor a raw SCPI connection on port 5025, and it does not require VISA. USB transport is not implemented.

Every VICP frame starts with an eight-byte header:

| Byte offset | Size | Meaning in this implementation |
| --- | --- | --- |
| 0 | 1 | Operation flags. Outgoing frames use `0x81`: DATA (`0x80`) plus EOI/end of message (`0x01`). |
| 1 | 1 | Protocol version: `1`. |
| 2 | 1 | Outgoing sequence number, incremented from 1 through 255 and then wrapped to 1. |
| 3 | 1 | Reserved; outgoing value `0`. |
| 4–7 | 4 | Unsigned payload length in bytes, **big-endian**, excluding this header. |
| 8 onward | variable | Payload. Outgoing commands are ASCII followed by LF (`0x0A`); LF is included in the length. |

For example, the first `*IDN?` request is transmitted as:

```text
81 01 01 00 00 00 00 06  2A 49 44 4E 3F 0A
<---- VICP header ---->  <--- *IDN? + LF --->
```

TCP reads do not necessarily align with VICP frames. The receiver reads exactly eight header bytes, then exactly the declared payload length. It concatenates payloads until the incoming operation byte has its EOI bit set (`operation & 0x01 != 0`). A binary payload may contain LF and arbitrary byte values; those bytes do not terminate a message. The instrument was observed returning sequence number `0`, so the client does not require the response sequence to match the request.

Requests are serialized. A query sends one command and consumes its complete response before another query is issued; setting commands are sent without reading a standalone acknowledgment. The transport validates version 1, limits each complete response to 16 MiB and at most 1,024 frames, and closes the socket on transport errors. Connection establishment has a four-second timeout, as do socket send/receive operations; this is not a four-second deadline for an entire multi-frame transfer.

### Connection and polling sequence

1. Connect to TCP port 1861 and query `*IDN?`. The client requires `WA224` in the returned identity. The physical instrument returned `*IDN LECROY,WA224,LCRY2201C02097,5.05.02.14` followed by LF.
2. Query `WFSU?` and save the original waveform-transfer configuration for restoration on disconnect.
3. Read channel, timebase, and trigger settings using the queries below.
4. Before the first waveform request, or whenever the selected transfer stride changes, send `WFSU SP,<stride>,NP,0,FP,0,SN,0` and query `WFSU?` to verify the exact setting.
5. Download each enabled, locally visible channel sequentially using `C<n>:WF? ALL`. Refresh the instrument settings approximately every three seconds while live transfers are active. After each polling cycle, wait for the selected refresh delay (default 0.2 seconds).
6. On normal disconnect, attempt to send the saved `WFSU` configuration and close the connection. Restoration is best effort and cannot be guaranteed after a broken connection or abrupt termination.

The application does not stop acquisition before downloading a waveform or wait for a new trigger before every download. Records from different channels may therefore belong to different acquisitions while the instrument is running; successive downloads may also contain the same acquisition. Pausing transfers in the application sends no acquisition-control command. For a stopped event, wait for Single acquisition to complete, or use Stop, before comparing channel records.

### Commands used by the application

`<n>` is a channel number from 1 to 4. Numeric command arguments use a decimal point; timebase values are in seconds/division, sensitivity in volts/division, and trigger level in volts.

| Purpose | Query | Setting command sent by the UI |
| --- | --- | --- |
| Instrument identity | `*IDN?` | — |
| Waveform transfer setup | `WFSU?` | `WFSU SP,<stride>,NP,0,FP,0,SN,0` |
| Waveform, including descriptor | `C<n>:WF? ALL` | — |
| Channel acquisition/display enabled | `C<n>:TRA?` | `C<n>:TRA ON` or `C<n>:TRA OFF` |
| Channel sensitivity | `C<n>:VDIV?` | `C<n>:VDIV <value>` |
| Channel vertical offset | `C<n>:OFST?` | — |
| Input coupling | `C<n>:CPL?` | — |
| Timebase | `TDIV?` | `TDIV <value>` |
| Acquisition/trigger mode | `TRMD?` | `TRMD AUTO`, `TRMD STOP`, or `TRMD SINGLE` |
| Trigger selection/source | `TRSE?` | `TRSE <selection>`; preserve the returned comma-separated selection and replace only its `SR` source token with `C<n>` |
| Trigger level, for a channel source | `C<n>:TRLV?` | `C<n>:TRLV <value>` |
| Trigger slope, for a channel source | `C<n>:TRSL?` | `C<n>:TRSL POS` or `C<n>:TRSL NEG` |

Text responses can include an echoed command header, for example `C1:VDIV 1.00E+00V`. The client removes the first space-separated header, parses the leading numeric value where appropriate, and trims surrounding whitespace. After a UI setting command, it reads the settings back from the instrument. An external trigger source is not silently changed to channel 1.

### Waveform response and WAVEDESC

After VICP reassembly, `C1:WF? ALL` returns an ASCII prefix followed by an IEEE 488.2 definite-length binary block. An observed full-record response starts as follows:

```text
C1:WF ALL,#9000012614<WAVEDESC and waveform bytes><trailing line endings>
```

The block format is `#<d><length><binary data>`: `<d>` is one ASCII digit giving the number of decimal digits in `<length>`. In this example, `d = 9`, the nine-digit length is `000012614`, and the binary block contains 12,614 bytes: a 346-byte descriptor plus 12,268 signed byte samples. The length excludes the ASCII prefix, the `#` length header, trailing line endings, and VICP headers. The decoder searches for `#` within the first 256 response bytes, accepts length fields with 1–9 digits, and requires the declared block to be present in full.

Offsets in the following table are **zero-based from the first `W` of `WAVEDESC`**, not from the beginning of the network response. Descriptor integers and floating-point values follow `COMM_ORDER`; this is independent of the VICP header's always-big-endian length.

| Offset | Field | Type / use |
| --- | --- | --- |
| 0 | `DESCRIPTOR_NAME` | Starts with ASCII `WAVEDESC`. |
| 16 | `TEMPLATE_NAME` | 16-byte string; `WAVEACE` identifies the tested reduced-transfer format. |
| 32 | `COMM_TYPE` | 16-bit integer: `0` = signed 8-bit samples, `1` = signed 16-bit samples. |
| 34 | `COMM_ORDER` | 16-bit integer: `0` = big-endian, `1` = little-endian. The tested instrument sends little-endian. |
| 36 | `WAVE_DESCRIPTOR` | 32-bit descriptor length in bytes; at least 346. |
| 40, 44, 48, 52, 56 | `USER_TEXT`, `RES_DESC1`, `TRIGTIME_ARRAY`, `RIS_TIME_ARRAY`, `RES_ARRAY1` | 32-bit lengths of blocks between the descriptor and the first sample array. |
| 60, 64 | `WAVE_ARRAY_1`, `WAVE_ARRAY_2` | 32-bit sample-array byte lengths; a second array is unsupported. |
| 76 | `INSTRUMENT_NAME` | 16-byte string; `WA224` for the tested reduced-transfer format. |
| 116 | `WAVE_ARRAY_COUNT` | 32-bit sample count. |
| 124, 128 | `FIRST_VALID_PNT`, `LAST_VALID_PNT` | 32-bit inclusive valid sample range. |
| 132 | `FIRST_POINT` | 32-bit first-point index; required to be zero for the supported reduced-transfer format. |
| 136 | `SPARSING_FACTOR` | 32-bit transfer stride. |
| 144 | `SUBARRAY_COUNT` | 32-bit subarray count; multiple subarrays are unsupported. |
| 156, 160 | `VERTICAL_GAIN`, `VERTICAL_OFFSET` | IEEE 754 32-bit floats used to convert signed raw samples to volts. |
| 176 | `HORIZ_INTERVAL` | IEEE 754 32-bit float, original sample interval in seconds. |
| 180 | `HORIZ_OFFSET` | IEEE 754 64-bit float, time of the first point in seconds. |

The sample data starts at `WAVE_DESCRIPTOR + USER_TEXT + RES_DESC1 + TRIGTIME_ARRAY + RIS_TIME_ARRAY + RES_ARRAY1`. For a full transfer, valid sample index `i` is converted with:

```text
voltage[i] = signed_raw[i] * VERTICAL_GAIN - VERTICAL_OFFSET
time[i]    = HORIZ_OFFSET + i * HORIZ_INTERVAL
```

The decoder keeps the inclusive valid range. It uses descriptor calibration directly; it does not apply a second probe multiplier or derive voltage/time from the GUI division settings. It rejects invalid lengths/ranges, non-finite calibration, unsupported sample types, sequence records, RIS data, and second sample arrays. The graph and CSV use these calibrated values and times.

### Reduced-sample transfers: WA224 firmware behavior

The supported strides are `1`, `4`, `10`, and `20`. For the tested firmware, `WFSU SP,<stride>,NP,0,FP,0,SN,0` selects every `<stride>`th sample across the record, with zero values selecting the default/full extent for the other transfer parameters. This configures waveform readout rather than acquisition. A typical readback is `WFSU SP,10,NP,0,FP,0,SN,0`.

**Firmware 5.05.02.14 leaves several descriptor fields describing the original full record even when the binary block contains fewer samples.** In particular, the sample count, array byte length, valid range, and horizontal interval retain their full-record values; the sparsing factor changes and the binary block length reflects the actual transmitted bytes. The decoder handles this observed format as follows:

```text
received_count = floor(WAVE_ARRAY_COUNT / SPARSING_FACTOR)
received_dt    = HORIZ_INTERVAL * SPARSING_FACTOR
voltage[j]     = signed_received_raw[j] * VERTICAL_GAIN - VERTICAL_OFFSET
time[j]        = HORIZ_OFFSET + j * received_dt
```

| Stride | Samples received from an original 12,268-point record | Binary block bytes (346-byte descriptor + byte samples) |
| --- | ---: | ---: |
| 1 | 12,268 | 12,614 |
| 4 | 3,067 | 3,413 |
| 10 | 1,226 | 1,572 |
| 20 | 613 | 959 |

The workaround is restricted to descriptors identifying template `WAVEACE` and instrument `WA224`, with first point zero, the full original valid range, and a consistent original array byte length. The actual sample payload must match the reduced count exactly, so a truncated response is not accepted as a reduced record. Other sparse descriptor layouts are rejected. Reduced transfers do not average or preserve peaks and can miss short events; a smaller payload also does not imply a proportional increase in refresh rate.

### Reproducing a read-only exchange

The diagnostic tool prints query timing, response length, and a preview. `--output` saves the final reassembled response, including its ASCII prefix and binary block but excluding VICP headers. It does not change `WFSU`, so the current instrument transfer setting applies.

```sh
python3 Tools/scope_probe.py --host 192.168.0.100 '*IDN?' 'WFSU?'
python3 Tools/scope_probe.py --host 192.168.0.100 'C1:WF? ALL' --output /tmp/wa224-c1.bin
swift run WaveAceCheck --decode /tmp/wa224-c1.bin
```

Unlike the query-only Python probe, `WaveAceCheck <IP> --stride <n>` temporarily writes the transfer setup and restores it on successful completion.

## Compatibility and references

Verified on a physical instrument identifying itself as `LECROY,WA224`, with firmware **5.05.02.14**, VICP on port 1861, and `C1:WF? ALL` waveform transfers. The originally reported firmware version was correct; the EasyScope compatibility list on the manufacturer's website is not a complete list of all firmware versions for this instrument.

Validation on November 16, 2026: successful Debug and Release builds; seven automated decoder tests passed, including reduced-sample transfers and their time axes; decoding of an actual 12,268-sample record; CH1/CH2 retrieval through the native communication library; and live CH1–CH4 display in the application at approximately 1 frame/s. Exports and all combinations of settings have not yet been fully tested manually. This is an initial working version.

- [EasyScope — official support](https://www.teledynelecroy.com/support/softwaredownload/easyscope.aspx)
- [WaveAce 1000/2000 Remote Control Manual](https://cdn.teledynelecroy.com/files/manuals/wa1k2k_remote-control_manual.pdf) — a supporting reference for commands and the WAVEDESC structure, not a declaration of compatibility with the 224 model. The queries used were verified on a physical WA224.
- [WaveAce EasyScope Operator's Manual](https://cdn.teledynelecroy.com/files/manuals/es-om-e_reva.pdf)

The built application is locally ad hoc signed; it is not an Apple Developer ID-signed or notarized distribution package. All measurement data stays local.
