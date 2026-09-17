# JieJu application icon

`jieju-icon.png` is the approved black-and-white abstract mark (design v4), shared by both platforms.
It is copied unchanged from the selected image-generation concept; earlier concepts are not application assets.

On macOS, regenerate the platform containers with:

```bash
bash scripts/generate-app-icons.sh
```

- macOS: `JieJu/Resources/AppIcon.icns`, included in the app bundle and referenced by `CFBundleIconFile`.
- Windows: `Apps/Windows/JieJu.Windows/Assets/AppIcon.ico`, embedded in the executable, copied to output, and loaded by `AppWindow.SetIcon`.
- ICO sizes: 16, 24, 32, 48, 64, 128, 256 pixels. ICNS includes standard and Retina sizes through 1024 pixels.

Packaging only resizes the approved artwork; it does not re-generate or modify the logo.
Future MSIX packaging must separately declare its visual assets in the package manifest.
