# Product images

All public images use synthetic demo accounts.

| File | View |
| --- | --- |
| `usage-dark.png`, `usage-light.png` | Usage panels with gradient backgrounds |
| `coding-dark.png`, `coding-light.png` | Copilot, Cursor, and Kimi |
| `notch.jpg` | Expanded notch panel |
| `settings.png` | Placement and compact display settings |

## Recreate

```sh
./scripts/build.sh
mkdir -p docs/images/raw
"dist/Sub Tracker.app/Contents/MacOS/SubTracker" --demo --dark --snapshot "$PWD/docs/images/raw/usage.png"
"dist/Sub Tracker.app/Contents/MacOS/SubTracker" --demo --dark --settings --snapshot "$PWD/docs/images/settings.png"
```

Add `--light` instead of `--dark`, or `--coding` for the other provider set.

The framed panels use native captures on a gray/pink gradient, matching the original CleanShot presentation. The current frames were rendered in HTML: 1140 × 1520 canvas, centered 764 × 1152 capture, 56 px corners, and a soft shadow. Native captures do not simulate a hardware notch.

Check for clipping and private data before committing. Raw captures and CleanShot projects are ignored.
