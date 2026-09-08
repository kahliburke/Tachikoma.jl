# tachi

Command-line renderer for `.tach` recordings — see
[docs/src/recording.md](../../docs/src/recording.md) for installation and usage.

## Working on tachi from a checkout

This project resolves `Tachikoma` from the registry so that it can be installed
as an app straight from the repository URL. To run it against your checkout
instead, dev the parent once; the resulting `Manifest.toml` is untracked and
persists:

```julia
using Pkg                       # from the repository root
Pkg.activate("tools/tachi")
Pkg.develop(path=pwd())
```

Then run it with `julia --project=tools/tachi -m Tachi <args>`.
