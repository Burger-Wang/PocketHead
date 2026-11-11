# Live preview fixtures

These HEVC streams contain generated color bars and a moving marker, not camera footage.
Each stream has 12 independently decodable pictures with VPS/SPS/PPS before each picture.

- `color-bars.hevc`: 320 × 180.
- `color-bars-small.hevc`: 160 × 90, for format-change recovery tests.

Regenerate on macOS using the system VideoToolbox encoder:

```sh
swift scripts/generate-live-preview-fixture.swift Tests/PocketHeadCoreTests/Fixtures/color-bars.hevc 320 180
swift scripts/generate-live-preview-fixture.swift Tests/PocketHeadCoreTests/Fixtures/color-bars-small.hevc 160 90
```

The bitstream bytes can vary between encoder/OS versions. Tests check decoded content dimensions
and valid sample construction rather than binary hashes.
