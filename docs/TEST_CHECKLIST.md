# Test checklist

## Roblox Studio desktop
- [ ] Library ModuleScript loads from `ReplicatedStorage.SilentUI`.
- [ ] Window opens, closes, drags, resizes, and remains inside the viewport.
- [ ] RightControl toggles the window.
- [ ] Tabs, subtabs, sections, search, and floating toggle work.
- [ ] Toggle, slider, stepper, dropdown, multi-dropdown, textbox, color picker and keybind update values.
- [ ] Disabled/locked controls reject input; unlocking restores input.
- [ ] Notifications are removed after their configured duration.
- [ ] Dialog, confirmation and prompt actions execute once.
- [ ] Theme, accent, scale, transparency, blur and fullscreen controls respond.
- [ ] Config save/load/import/export works with the in-memory adapter.
- [ ] Destroying the owning LocalScript releases the UI and connections.

## Touch devices
- [ ] Window and controls fit narrow portrait and landscape viewports.
- [ ] Buttons, dropdowns, color picker and keybind controls are operable by touch.
- [ ] Scrolling remains available when controls exceed the viewport.
- [ ] Floating toggle remains reachable and does not cover critical controls.

## Resource and regression checks
- [ ] Repeatedly open/close the window and create/expire notifications.
- [ ] Repeatedly create and destroy the library; check for duplicate ScreenGuis or lingering input connections.
- [ ] Test with other Lighting effects enabled before using the optional blur feature.
- [ ] Replace empty media fields only with assets permitted by the experience.

Static Python checks do not replace Luau compilation, Studio execution, device testing, or memory profiling.
