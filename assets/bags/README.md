# Bag source catalog

These are the 15 GLB files imported from the user's `Downloads/dump/production_bags` delivery. `catalog.json` records each original relative path and its permanent model ID. The legacy Runecloth Bag (`DarkSchoolbag`) remains ID 1 and keeps its existing model and texture bytes. Production model IDs are 2 through 16.

The source GLBs are rigid, single-node meshes with no node transforms or skins. Their materials share one opaque painted atlas; the importer validates normals, UV ranges, material properties, index limits, and finite positions. New meshes are converted to the client's axes, centered at the panel against the character, and normalized to the original bag's 1.239-unit height. Relative proportions are retained. Each bag can then be scaled and positioned independently in the addon.

The original 128, 256, or 512 pixel production atlas resolution is retained. The converter creates DXT1 BLP2 textures with complete mip chains. The existing Runecloth Bag stays at its original 128 pixel output resolution. Material texture references point only to the matching packaged BLP; the client's loose-file exception is restricted to the catalog's exact model and texture paths.

Rebuild all assets and both catalogs, using Python with Pillow:

```sh
python3 tools/build_bag_catalog.py
python3 tests/test_bag_model.py
python3 tests/test_bag_catalog.py
```

Import a later complete production delivery, appending new IDs without changing existing ones:

```sh
python3 tools/build_bag_catalog.py --import-directory /path/to/production_bags
```

The import requires every previous source path to remain present. It never silently removes models or renumbers saved selections. `native/BAG-ASSETS.json` contains source, M2, and BLP checksums, bounds, mesh counts, normalization factors, and source image dimensions. `tools/package.py` verifies this manifest before including all 32 model/texture files.

The original creative assets and converted versions retain their applicable ownership and asset terms; see `../../ASSETS-LICENSE` and the addon Models license notice. The catalog and conversion code retain the repository's source-code license.
