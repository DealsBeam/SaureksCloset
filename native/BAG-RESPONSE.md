# Placement-driven bag deformation prototype

Current behavior policy: only Mageweave pouch IDs 12–16 (including the retired
Olive variant) may use the deformation field below. Every other catalog model
is rigid, including Runecloth ID 1 despite its historical `cloth` material tag.
Rigid bags bypass spring deformation and receive an identical final matrix in
every skinning control, even if stale soft state survives a model switch. Their
1.75x running bob is whole-object vertical travel; rotations and jump lift remain
rigid. The menu and picker show matching Soft body / Rigid body labels.

All catalog bags use a shared 3 × 4 × 5 volume lattice (60 control bones plus a root). Four tetrahedral skin weights bind each vertex. The upper rim and rear panel stay fixed; lower/front fabric has a nonlinear, spatially varying response. The flap and body sample the same field, rather than playing independent clips. This is a reduced deformation model, not simulated loose contents or full cloth contact.

The native renderer caches spring coefficients and control weights after a fit stops changing. Each instance measures its fitted mounting point; material changes, placement changes and body recreation invalidate its cache. Cloth gives more than canvas or leather. Dragging pauses the selected bag until release. Motion has continuous state and bounded acceleration; it does not dispatch Run, Jump or Fall clips, and runs alongside the restored original rigid bounce and upward/outward jump lift.

Saved bag identities stagger emitted local sway, spring give, local deformation and airborne response with short, fixed delays. Angular sway includes the inherited torso cycle. Vertical timing delays only the smooth spring offset: delaying absolute hip-bone height and clipping it to a small bag's bounds caused sharp catch-up motion. World travel and the live mount stay current. The legacy fallback bounds vertical give to 4% of bag height, with a further reduction below the standard 85% fit; anatomically bound bags keep their contact fixed in all axes. Smaller bags have reduced spring impulses and dynamic fabric loads, using the same settling rates. Size controls amplitude before recording motion; the delayed final orientation is never blended back toward the current body pose by size. This keeps the first two identities 80ms apart even at a 25–35% fit. Normal angular separation is bounded to 12 degrees, expanding only during the strong limb rocking described below; larger physical size supplies greater travel. The original jump-lift curve and full extension are retained with separate start/settling times per bag. Model/color changes and removing another bag cannot renumber timing. Stationary players do not generate artificial jiggle. Histories reset with placement/model changes and discontinuities, and retain enough time at high frame rates.

The placement window reuses the wardrobe's independent preview models. Left drag moves the bag around a body guide, right drag turns the view, and the numeric tuner remains available afterward. The guide is an ellipse per body, not a hit test against equipped armor. Fits remain drafts until Save Fit.

Each bag now binds its neutral upper rear contact to the nearest base-body vertex's four global skin weights. Hair, cape and clothing geosets are excluded. The current bone palette transforms that exact contact every frame; its orientation is orthonormalized before composing the bag fit, so blended joints cannot shrink or shear the bag. Saved fit coordinates are unchanged. Selection is cached and re-evaluated after a changed fit is stable for 150ms, with immediate updates to the chosen contact while dragging. Unsupported or temporarily unavailable mesh data falls back to native attachments. Preview clones keep independent caches.

Bound bags rotate around the same contact for phased sway and upward/outward jump lift, with no additional rigid vertical translation at the pin. Local lower fabric still deforms. The jump direction follows the bag's fitted outward normal rather than the original back/hip preset. Actual limb angular speed above 2.5rad/s eases in a softer rocking spring, bounded at 20 degrees (reduced for small bags); phase correction can expand from 12 to 30 degrees during those strong swings. No free-running oscillation is introduced. Stopping restores critical damping without snapping the large offset to the idle limit. Tests cover foot/hip binding, joint blends, contact preservation through jump, clone routing, small sizes, frame rates and idle settling; these are numerical checks, not a live visual review.

Native locomotion flags gate dynamic impulses. On stopping, stored spring velocities are cleared once and offsets return with damping; delayed angular sway fades out quickly, and idle breathing cannot add new spring or cloth impulses. Static cloth sag and the original landing-lift response remain. Walking, swimming and airborne movement stay active independently of the run-intensity flag.

Bound bags emit the original phase-adjusted vertical spring through the local rig. Previously `pinContact` discarded that output, removing the visible run bob. All controls below the upper attachment row now receive the same gravity-relative displacement; skin interpolation confines the give to the upper quarter while the lower body translates together. The top remains pinned. This preserves the old size-scaled amplitude and timing without a whole-bag scale, independent flap motion or idle oscillator. Combined control displacement remains within the existing culling margin. The running-bob regression compares emitted palettes against the original unpinned spring, including rear controls, multiple sizes, phases, frame rates and idle settling.

Weapon children expose transforms and rest bounds, which could support conservative collision proxies in a later change. Live cape surface geometry is not exposed by the current bridge. Equipment collision avoidance is not implemented or guaranteed here.

Running now eases the emitted bob amplitude to 1.75 times the original spring output, using the existing run-weight envelope. Walking retains its baseline amplitude. The spring frequency, per-bag phase, size gain, fixed attachment and idle damping are unchanged; combined control displacement still respects the culling margin.

Skin-bound bags also lift outward in response to the positive half of the same
vertical spring sample, then return to rest rather than swinging through the
body. The hinge comes from the fitted outward normal crossed with gravity;
there is no mount-preset condition or independent cycle. Angular response gains
sqrt(85 / fitted-size-percent), clamped to 1–2, to compensate for small bags'
short lever arm. A smooth 10-degree bound and a per-instance 45ms filter prevent
sharp reversals. Duplicate draws do not advance the filter. The top contact is
preserved before rigid bob translation; the 1.75x running translation is unchanged. It operates on a rigid rotation, so non-Mageweave geometry never
stretches. Regression checks compare all three presets at the same final pose,
quiet/moving attachment points, both side orientations, 25–85% sizes, duplicate
draws, idle settling and multiple frame rates.

Build: `python tools/build_bag_catalog.py`, then `tools/build_native.sh` with the existing toolchain. Run `python tools/check_release.py`. Archived offline bake files do not affect the shipped models.

Native update routing covers recursive child updates (return `0x718761`) and lazy child updates (`0x71415D`/`0x714183`). Each can replace the complete instance bone palette, so local controls are applied after all owned-bag routes. In build 5875, drawing constructs its renderer on the stack at `0x708942`; constructor `0x70B0E0` clears the previous-model cache (`+0x3314`). The GPU palette path reads instance `+0x94` at `0x70CC30`, and the CPU skinning path reads it at `0x719DF2`. These consumers run after updates and are not gated on animation key tracks. Regression tests emulate native palette replacement before skinning weighted vertices through each update route. They verify data flow and motion bounds, not live client appearance.

Vertical size correction: spring input limits use at least the standard 85%
reference height, spring force scales once by fitted size, and travel is capped
at 4% of actual bag height before the 1.75x running gain. Previously both input
limits and force shrank with size and the travel cap also multiplied height by
size gain, suppressing small bags quadratically. Flop normalization uses the
same single height scale. Emitted soft-rig and rigid-object tests require
25/35/56% bags to retain the same relative bounce as 85%, with smaller absolute
travel and unchanged phase/rate.
