# Product images

All public images use synthetic demo accounts.

| File | View |
| --- | --- |
| `usage-dark.png`, `usage-light.png` | Usage panels with CleanShot X backgrounds |
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

The framed panels use CleanShot X's gray/pink gradient, centered alignment, 90 px padding, 24 px shadow, 14 px corners, and a 3:4 canvas. Native captures do not simulate a hardware notch.

Check for clipping and private data before committing. Raw captures and CleanShot projects are ignored.
