# Build and verification report

- Language: Luau with \`--!strict\`.
- Package: standalone Roblox UI library.
- Dependencies: no third-party runtime packages.
- Project mapping: Rojo \`default.project.json\`.
- Automated checks: Python static contract scripts.
- Manual check: \`tests/StudioSmokeTest.client.luau\`.

Static checks inspect source contracts and delimiter balance; they are not a Luau parser, type checker, renderer test, or memory benchmark. A Luau CLI, Rojo CLI, and Roblox Studio session are required for compile and runtime validation.
