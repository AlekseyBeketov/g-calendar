# Third-party components

g-calendar embeds [Sparkle](https://github.com/sparkle-project/Sparkle), version **2.10.0**, for authenticated macOS updates. Its distribution archive is downloaded by `scripts/fetch-sparkle.sh` from the official GitHub release and pinned to SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`.

The original signed framework is copied into `Contents/Frameworks`. Its license and third-party notices are included in the application as `Contents/Resources/Sparkle-LICENSE.txt`. Dependency binaries remain in ignored `.build/` and `dist/` directories; they are not checked into this repository.

The Google sign-in logo comes from Google's official branding resources; provenance is recorded in [resources/GoogleSignIn/README.md](../resources/GoogleSignIn/README.md).
