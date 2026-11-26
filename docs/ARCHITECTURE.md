# Architecture

## Package boundaries

- `init.luau` is the public entry point and owns the library instance.
- `Core/` contains configuration storage, theme/localization registries, signals, janitorial cleanup, icon registry and bounded instance pooling.
- `UI/` contains the window, tab, section and control implementations.
- `examples/` contains consumers of the public API; examples do not modify the library internals.
- `tests/` contains static API contracts and a manual Studio smoke test.

## Ownership

The library owns the ScreenGui and UI instances it creates. Controls belong to their section, sections to their tab, and tabs to their window/library. Destroy the owning library when its LocalScript or UI session ends.

## Storage boundary

The default configuration adapter is in-memory. Persistent storage is injected by the host through the documented adapter interface; the library does not assume executor or filesystem APIs.

## Runtime boundary

The library uses Roblox client APIs and Luau only. It does not include game-specific remotes, external service clients, executor APIs, authentication or loaders.
