# Product images

These images show real native views with synthetic demo accounts. `usage-dark.png` and `usage-light.png` use CleanShot X’s Add background feature for framing, gradient, shadow, and rounded corners. The coding-provider and current Settings images are direct native renders. `notch.jpg` is a native capture of the expanded notch panel. The images do not simulate a hardware cutout.

| File | Appearance | Canvas |
| --- | --- | --- |
| `usage-dark.png` | Dark usage panel | 3:4 |
| `usage-light.png` | Light usage panel | 3:4 |
| `notch.jpg` | Expanded notch panel | Native capture |
| `settings.png` | Placement and account controls | Native view |
| `coding-dark.png` | Copilot, Cursor, and Kimi | Native view |
| `coding-light.png` | The same accounts in light appearance | Native view |

## Recreate

```sh
swift build -c release --product SubTracker
mkdir -p docs/images/raw
.build/release/SubTracker --demo --dark --snapshot "$PWD/docs/images/raw/usage-dark.png"
.build/release/SubTracker --demo --light --snapshot "$PWD/docs/images/raw/usage-light.png"
.build/release/SubTracker --demo --coding --dark --snapshot "$PWD/docs/images/raw/coding-dark.png"
.build/release/SubTracker --demo --dark --settings --snapshot "$PWD/docs/images/raw/settings-dark.png"
open -a 'CleanShot X' docs/images/raw/usage-dark.png
```

Use the muted gray/pink gradient (second row, second gradient), centered alignment, and no inset. Usage images use padding 90, shadow 24, corners 14, and 3:4 ratio. The previous Settings image used the same gradient and 4:3 ratio. Current direct renders can be opened in the same editor when available. Export as PNG into this directory.

Check every image for clipping and private account data before committing. `raw/` and CleanShot project files are ignored. Do not capture the normal live account view for public documentation.
