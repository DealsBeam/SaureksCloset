# Release workflow

- Fetch and merge upstream changes before publishing. Preserve the user's README
  and screenshots; do not edit README wording, formatting, links or version text.
- Copy the upstream README and screenshot files byte-for-byte into the packaged
  addon so the download contains the same editorial content.
- Use `RELEASE_MESSAGE.md` for every GitHub release. Keep its wording and formatting
  verbatim, replacing only `{{VERSION}}` with the release version in the ZIP filename.
  Do not generate or substitute different release notes unless the user requests it.
- Increment current addon/DLL versions, update manifests and installation/build
  documentation together. README is exempt. Preserve historical version references
  and minimum-compatible-renderer thresholds.
- Build and run the release/package checks before pushing and publishing.
