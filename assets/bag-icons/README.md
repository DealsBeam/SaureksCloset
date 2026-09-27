# Custom bag icons

These eleven original inventory icons were generated with the built-in image
tool using the supplied bag model review images as strict subject references.
`generation.json` records each full prompt, input origin, and input/output hash.
The `references` folder retains the exact provided review images; the sibling
`BagIcon*.png` files retain the original generated artwork.

Run `python tools/build_bag_icons.py` with Pillow available to reproduce the
64×64 RGBA TGA runtime textures and their `ARTWORK.json` records. This export
only downsamples and converts the approved images; it does not generate art.
An optional `--preview /absolute/path.png` produces a 64px/32px review sheet.

Runecloth Bag uses the Dark Schoolbag Classic reference whose GLB matches the
addon’s `assets/DarkSchoolbag.glb` source. The other ten references come from
the corresponding delivered production bag folders. Colors and construction
come from the actual model references, including the four cloth pouch colors.
