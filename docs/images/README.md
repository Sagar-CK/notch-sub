# Product images

These PNGs show the real native views rendered with synthetic demo accounts. The card framing, gradient, shadow, and rounded corners were added in **CleanShot X 5.0.1 → Add background**. They illustrate the expanded usage panel and settings, not a simulated physical notch.

| File | Appearance | Canvas |
| --- | --- | --- |
| `usage-dark.png` | Dark usage panel | 3:4 |
| `usage-light.png` | Light usage panel | 3:4 |
| `settings.png` | Placement and account controls | 4:3 |

## Recreate

```sh
swift build -c release --product SubTracker
mkdir -p docs/images/raw
.build/release/SubTracker --demo --dark --snapshot "$PWD/docs/images/raw/usage-dark.png"
.build/release/SubTracker --demo --light --snapshot "$PWD/docs/images/raw/usage-light.png"
.build/release/SubTracker --demo --dark --settings --snapshot "$PWD/docs/images/raw/settings-dark.png"
open -a 'CleanShot X' docs/images/raw/usage-dark.png
```

Use the muted gray/pink gradient (second row, second gradient), centered alignment, and no inset. Usage images use padding 90, shadow 24, corners 14, and 3:4 ratio. The settings image uses the same gradient and 4:3 ratio. Export as PNG into this directory.

Check every image for clipping and private account data before committing. `raw/` and CleanShot project files are ignored. Do not capture the normal live account view for public documentation.
