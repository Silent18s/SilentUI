# API references

## Roblox client APIs
SilentUI uses Roblox client-side GUI, input, camera and tween APIs. Relevant references:

- [Roblox on-screen containers](https://create.roblox.com/docs/ui/on-screen-containers)
- [Roblox buttons and Activated](https://create.roblox.com/docs/ui/buttons)
- [Roblox UserInputService](https://create.roblox.com/docs/reference/engine/classes/UserInputService)
- [Roblox TweenService](https://create.roblox.com/docs/reference/engine/classes/TweenService)

## Executor-specific entry point
The optional executor loader uses \`game:HttpGet\` and \`loadstring\`, which are provided by executor environments and are not standard Roblox client APIs. Public usage references for the Delta-style loading workflow:

- [Delta Executor: advanced script execution](https://deltaexecutor.co/guides/advanced-script-execution-techniques)
- [Delta Executor: first script guide](https://deltaexecutor.games/how-to-use-delta-executor/)

These are public usage guides, not an authoritative stable API specification for every Delta release. SilentUI intentionally does not depend on executor filesystem, clipboard, environment-global or hidden-UI helpers.

## Rojo
- [Rojo project format](https://rojo.space/docs/v7/project-format/)
