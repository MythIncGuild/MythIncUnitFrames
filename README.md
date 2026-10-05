# MythInc Unit Frames

MythInc Unit Frames (MIUF) is a configurable native unit-frame addon for **World of Warcraft Retail**. No oUF is required.

**Current version: 0.10.0-beta.4** — an outside-testing beta. This is active beta testing, and you may encounter bugs.

## What's new in beta.4

- Refreshed castbar visuals, a Player latency SafeZone, and wider Player/Target castbar positioning ranges.
- Added a precision frame-positioning panel and made dispel highlights more visible.
- Party/Raid temporary status icons now show observable Soulstone buffs on living units; visible icons collapse together without gaps. Soulstone is not tracked after death.
- Added profile Export/Import and expanded the Profiles page. Import replaces the current profile's settings, keeps its tracked buffs, and reloads the UI. Tracked buffs and discovery history are excluded from sharing.
- Added manual tracked-buff entry by Spell ID. Explicitly tracked helpful buffs now display regardless of caster.
- Seen Buff discovery now includes safely identifiable player/party/raid player sources outside combat while configuring. Missing or restricted sources are skipped; manual Spell ID remains the fallback.
- Right-click Seen Buffs to dismiss unwanted entries permanently. Clear Seen History keeps dismissals; Reset Dismissed allows rediscovery. Tooltips clear when buff icons disappear or move.

Please test externally cast Power Infusion (10060), dismissal/reset, profile copy/paste and tracked-buff preservation, exact positions after reload, and castbar/Soulstone behavior in groups at your usual UI scale.

## Frames and features

Supports **Player, Target, Focus, Pet, Target of Target, Party, Boss, and Raid**.

- Configurable layouts, appearance, text, auras, and indicators.
- Native Player, Target, Focus, and Boss castbars.
- Profiles, frame and aura movers, and configuration previews.
- Bundled textures and fonts, plus click-casting compatibility through addons such as Clique.
- Reversible Blizzard-frame ownership for Party, the raid container, and the normal Player castbar. Other Blizzard unit-frame restoration is limited; see [README.txt](README.txt).

## Install

Place the `MythIncUnitFrames` folder directly in your Retail `Interface\AddOns` directory. It must directly contain `MythIncUnitFrames.toc`, with no extra nested repository folder. Keep the Lua files and `Media` folder alongside it, then enable MythInc Unit Frames in the game's AddOns list.

## Configure

Open **`/miuf`** outside combat. Configuration edits are staged:

- **Apply Changes** commits pending edits.
- **Revert Changes** discards pending edits and keeps the session open.
- **Minimize** collapses the window while preserving the active session and pending edits; **Restore** returns to that session.
- **Close (X)** discards unapplied pending edits and restores the last applied state.

Locking movers does not save edits; use Apply Changes. See [README.txt](README.txt) for detailed controls, slash commands, and current limitations.

## Beta feedback

When reporting a bug, include your **MIUF version**, **Retail version**, **steps to reproduce**, and what you expected versus what happened. Include the **complete Lua error** when applicable. Screenshots and a list of other relevant addons can also help.
