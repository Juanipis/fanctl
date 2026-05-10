## [1.5.0](https://github.com/Juanipis/fanctl/compare/v1.4.0...v1.5.0) (2026-05-10)

### Features

* **updater:** add in-app auto-updates via Sparkle ([66a9ca1](https://github.com/Juanipis/fanctl/commit/66a9ca14245873962f09686de448cf68ac3e9258))

### Bug Fixes

* **updater:** make canCheck publicly settable so the proxy can flip it ([5fa8aaa](https://github.com/Juanipis/fanctl/commit/5fa8aaae820335604fbb7dfa2d4038530a717a41))
* **updater:** use bash loop instead of awk for appcast item insertion ([5534a75](https://github.com/Juanipis/fanctl/commit/5534a7523a08cee407fe3354cc51cb12e11c4382))

## [1.4.0](https://github.com/Juanipis/fanctl/compare/v1.3.0...v1.4.0) (2026-05-10)

### ⚠ BREAKING CHANGES

* existing v1.x installs need to be uninstalled before
v2.0.0 can run, because the helper bundle ID changed and SMAppService
treats it as a new daemon. Users should either:

  brew uninstall --cask fanctl && brew install --cask Juanipis/tap/fanctl

or run Bundle/uninstall.sh from the v1.x source tree, then reinstall.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>

### Features

* rename bundle ID from com.jpdiaz to com.juanipis ([e468e48](https://github.com/Juanipis/fanctl/commit/e468e48e703a08f51fdaad3b7ac80ff2b1fa047f))

## [1.3.0](https://github.com/Juanipis/fanctl/compare/v1.2.0...v1.3.0) (2026-05-10)

### Features

* **install:** publish Homebrew Cask in Juanipis/tap ([601d8c8](https://github.com/Juanipis/fanctl/commit/601d8c88f70200ee97a085cb5cfbc1f8b6726293))

## [1.2.0](https://github.com/Juanipis/fanctl/compare/v1.1.0...v1.2.0) (2026-05-10)

### Features

* **install:** add curl-pipeable remote installer ([c75c403](https://github.com/Juanipis/fanctl/commit/c75c4036f92901d6d81f95efb52d6367c3fb42d8))

## [1.1.0](https://github.com/Juanipis/fanctl/compare/v1.0.0...v1.1.0) (2026-05-10)

### Features

* **app:** generate AppIcon.icns from code ([7206da4](https://github.com/Juanipis/fanctl/commit/7206da49eb1ae7bd19a4e6e8a1372186c90a1f0d))

## 1.0.0 (2026-05-09)

### Features

* initial FanCtl release ([51ba557](https://github.com/Juanipis/fanctl/commit/51ba557154efc515d08d3f4a8fb344783b8c85a8))

### Bug Fixes

* **app:** pin FanCtlApp target to Swift 5 language mode ([7fdf8cb](https://github.com/Juanipis/fanctl/commit/7fdf8cb132418646d9407a4dfb52a7352c98f38a))

# Changelog

All notable changes to this project are documented here.
Generated automatically by [semantic-release](https://github.com/semantic-release/semantic-release) from
[Conventional Commits](https://www.conventionalcommits.org/) on every push to `main`.
