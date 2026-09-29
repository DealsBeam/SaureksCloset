Refer to the README files and the Installation instructions directory for installation instructions.

Upgrading users: remember to upgrade your DLL after every update.

## Installation

### What you need

- The supported **Windows 1.12.1 client, build 5875**. This is not an addon for modern WoW Classic or Retail. Other clients may be possible to be support, open a Github issue.
- **VanillaFixes** configured to launch your game. [https://github.com/hannesmann/vanillafixes](https://github.com/hannesmann/vanillafixes)
- **VanillaHelpers.dll** installed and enabled in `dlls.txt`.
- Both parts of Saurek's Closet: the **`SaureksCloset`****&#x20;addon folder** and **`SaureksCloset.dll`** from the release download.

### Install the release

1. Download SaureksCloset-{{VERSION}}.zip

2. Fully close World of Warcraft and extract the release ZIP.

3. Copy the `SaureksCloset` folder into `Interface/AddOns/`.

4. Open the addon's installation instructions folder. Copy the included `SaureksCloset.dll` into your main game folder, beside `WoW.exe`.

5. Make sure you have [https://github.com/hannesmann/vanillafixes](https://github.com/hannesmann/vanillafixes) Vanilla Fixes installed.

6. Add `SaureksCloset.dll` to `dlls.txt`, after `VanillaHelpers.dll`. Keep any other DLL entries you already use.

7. Launch through VanillaFixes, enable **Saurek's Closet** in the AddOns list, and log in.

Your installation should contain:
```text
World of Warcraft/
├── WoW.exe
├── VanillaHelpers.dll
├── SaureksCloset.dll
├── dlls.txt
└── Interface/
    └── AddOns/
        └── SaureksCloset/
            ├── SaureksCloset.toc
            ├── Textures/
            └── ...
```

**Don't forget the DLL.** Copying only the addon folder is not a complete installation. A UI reload cannot load a new DLL; fully restart the game after replacing one.
