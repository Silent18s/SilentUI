# Build and verification report

- Language: Luau with \`--!strict\`.
- Runtime: Roblox client UI APIs.
- Modular sources: 13 ModuleScript-oriented source modules under \`src/SilentUI\`.
- Executor bundle: \`dist/SilentUI.lua\`; all module dependencies are statically bundled, and the chunk returns an initialized SilentUI instance.
- All-in-one demo: \`dist/SilentUI-Showcase.lua\`; bundles the library and eight-tab playground.
- Executor entry point: \`examples/ExecutorShowcase.lua\`; requires executor-provided \`game:HttpGet\` and \`loadstring\`.
- Studio entry point: \`examples/Showcase.client.luau\`; consumes the instance returned by \`require(ReplicatedStorage.SilentUI)\`.
- Project mapping: optional Rojo \`default.project.json\`.
- Automated checks: static Python contract scripts and GitHub Actions.

Static checks validate packaging and selected API contracts; they are not a Luau parser, type checker, executor runtime test, GUI rendering test, or memory benchmark. Run the one-line all-in-one entry point in the target Delta build and complete the Studio/device checklist separately.
