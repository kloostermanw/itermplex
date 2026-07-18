# Releasing

Releases are driven by [`git-release`](https://github.com/kloostermanw/git-release),
configured in `.gitrelease`. Run it from a clean `develop` branch:

```sh
git-release
```

It prompts for the new tag. It auto-suggests a patch bump of the last tag; type
the tag you actually want (the version scheme is `vMAJOR.MINOR.PATCH`).

## What happens automatically

1. `git-release` creates a `release/<tag>` branch off `develop`.
2. **cmd1** runs `scripts/set-version.sh --release <tag>`, which rewrites
   `MARKETING_VERSION` in `project.yml` to the tag (with the leading `v`
   stripped). `git-release` commits `project.yml` on the release branch, so the
   version is baked into the tagged commit.
3. `git-release` merges the release branch into `main`, creates the annotated
   tag, and pushes `main` (with tags) to origin. It merges `main` back into
   `develop` and pushes that too.
4. **cmd3** runs `scripts/publish-release.sh --release <tag>`, which:
   - creates the GitHub release for the pushed tag (`--generate-notes` fills in
     the release body, which the in-app updater shows),
   - runs `scripts/make-dmg.sh` to build a Release `.dmg`,
   - uploads it as `itermplex.<tag>.dmg`.

## Version syncing and the in-app updater

`MARKETING_VERSION` is the app's `CFBundleShortVersionString`, which
`AppVersion.current` reads. The in-app update check (`UpdateService`) compares a
release's tag against that value, so keeping them in sync (step 2) is what makes
"a newer version is available" correct for the next release.

## Re-running after a failure

If cmd3 fails after the tag is already pushed (for example a build error),
re-run the publish step by hand once fixed. It is idempotent: it reuses an
existing GitHub release and re-uploads the asset with `--clobber`.

```sh
scripts/publish-release.sh --release <tag>
```
