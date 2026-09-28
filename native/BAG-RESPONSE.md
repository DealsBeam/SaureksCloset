# Placement-driven bag deformation prototype

All catalog bags use a shared 3 × 4 × 5 volume lattice (60 control bones plus a root). Four tetrahedral skin weights bind each vertex. The upper rim and rear panel stay fixed; lower/front fabric has a nonlinear, spatially varying response. The flap and body sample the same field, rather than playing independent clips. This is a reduced deformation model, not simulated loose contents or full cloth contact.

The native renderer caches spring coefficients and control weights after a fit stops changing. Each instance measures its fitted mounting point; material changes, placement changes and body recreation invalidate its cache. Cloth gives more than canvas or leather. Dragging pauses the selected bag until release. Motion has continuous state and bounded acceleration; it does not dispatch Run, Jump or Fall clips, and runs alongside the restored original rigid bounce and upward/outward jump lift.

The placement window reuses the wardrobe's independent preview models. Left drag moves the bag around a body guide, right drag turns the view, and the numeric tuner remains available afterward. The guide is an ellipse per body, not a hit test against equipped armor. Fits remain drafts until Save Fit.

Weapon children expose transforms and rest bounds, which could support conservative collision proxies in a later change. Live cape surface geometry is not exposed by the current bridge. Equipment collision avoidance is not implemented or guaranteed here.

Build: `python tools/build_bag_catalog.py`, then `tools/build_native.sh` with the existing toolchain. Run `python tools/check_release.py`. Archived offline bake files do not affect the shipped models.

Native update routing covers recursive child updates (return `0x718761`) and lazy child updates (`0x71415D`/`0x714183`). Each can replace the complete instance bone palette, so local controls are applied after all owned-bag routes. In build 5875, drawing constructs its renderer on the stack at `0x708942`; constructor `0x70B0E0` clears the previous-model cache (`+0x3314`). The GPU palette path reads instance `+0x94` at `0x70CC30`, and the CPU skinning path reads it at `0x719DF2`. These consumers run after updates and are not gated on animation key tracks. Regression tests emulate native palette replacement before skinning weighted vertices through each update route. They verify data flow and motion bounds, not live client appearance.
