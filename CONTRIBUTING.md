# Contributing to FanCtl

Thanks for taking the time! Quick rules:

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/) so that
[semantic-release](https://github.com/semantic-release/semantic-release) can decide the
next version number and write the changelog automatically.

Format: `type(scope): subject`

| Type | Effect on the next release |
|------|----------------------------|
| `feat:` | minor bump (new feature) |
| `fix:`  | patch bump (bug fix) |
| `perf:` / `refactor:` | patch bump |
| `docs:` / `style:` / `chore:` / `test:` / `ci:` | no release |
| `feat!:` (or `BREAKING CHANGE:` in the body) | major bump |

Example: `feat(modes): add Cool curve with EMA smoothing`

## Development loop

```bash
swift test                              # unit tests
swift run fanctl-cli status             # poke SMC reads
bash Bundle/build-app.sh debug          # assemble FanCtl.app
bash Bundle/install.sh debug            # copy to /Applications + open
sudo log stream \
  --predicate 'subsystem == "com.jpdiaz.FanCtl"' \
  --style compact                       # follow helper + app logs
```

## Reporting issues

Include:

- macOS version (`sw_vers`)
- Mac model (`sysctl -n hw.model`)
- Output of `swift run fanctl-cli status`
- A snippet of `log stream --predicate 'subsystem == "com.jpdiaz.FanCtl"'`
