# Third-Party Notices

ds-xzt distributes the following third-party components. Each component
remains under its own license. This notice identifies the major components in
the published Windows installer; `pnpm-lock.yaml` records the exact desktop
build dependency closure.

## DeepSeek Harness

- Project: DeepSeek Harness
- Version: `dsh-v0.1.0-rc.8`
- Source commit: `141eb6fef83422698aef7a981029e843e8161534`
- Upstream: <https://github.com/deepseek-ai/deepseek-harness>
- License: MIT
- Copyright: Copyright (c) 2026 DeepSeek
- License text: `licenses/DEEPSEEK-HARNESS-LICENSE.txt`

The installer bundles the official DeepSeek Harness npm packages. The generated
upstream notice is included in the installed runtime at
`resources/dsh/THIRD_PARTY_NOTICES.md` and is available from the upstream
repository.

## Runtime components

| Component | Version | License |
| --- | --- | --- |
| Node.js | 24.18.0 | Node.js license |
| Electron | 39.8.10 | MIT |

Electron's license text is in `licenses/ELECTRON-LICENSE.txt`.
Node.js's license text is in `licenses/NODEJS-LICENSE.txt` and is included
beside the bundled runtime at `resources/runtime/LICENSE.nodejs.txt`.

## Desktop build tooling

| Component | Version | License |
| --- | --- | --- |
| electron-builder | 26.15.3 | MIT |

electron-builder's license text is in
`licenses/ELECTRON-BUILDER-LICENSE.txt`.

## Dependency closure

The desktop package's direct development dependencies are Electron and
electron-builder. The complete pinned dependency closure is recorded in
`pnpm-lock.yaml`. The bundled DSH runtime carries the complete upstream
DeepSeek Harness third-party notice and package license files.
