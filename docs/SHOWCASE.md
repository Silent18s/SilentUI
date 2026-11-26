# Showcase

\`examples/Showcase.client.luau\` is a standalone UI playground.

## Run
1. Install Rojo and its Studio plugin.
2. Run \`rojo serve\` from the repository root.
3. Connect Studio to Rojo and start a Play session.
4. The library appears at \`ReplicatedStorage.SilentUI\`; the showcase LocalScript is placed in \`StarterPlayerScripts\`.
5. Press **RightControl** to toggle the window.

## Pages
- Overview: cards, paragraphs, tags, stats, info grids, dialogs and notifications.
- Controls: toggles, sliders, stepper, progress, dropdowns, textbox, color, keybinds and conditional bindings.
- Components: table, console, changelog, grids, media, code, loadout and rating.
- Layout: groups, multi-section columns, subtabs and declarative controls.
- Feedback: notifications, dialogs, confirmation and prompt.
- Settings: themes, scale, transparency, blur, config profiles and localization.
- Runtime: keybind list, state list, watermark and bubble.
- Diagnostics: values, snapshots, restore and reset.

The default config adapter uses memory. Media controls use empty asset IDs intentionally. Static checks do not prove Roblox runtime behavior; complete Studio and touch-device testing before production.
