MythInc Unit Frames 0.10.0-beta.4

Native unit frames for World of Warcraft Retail, targeting interface 120100
(12.1). Uses Blizzard's secure frames and aura containers. No oUF is required.

What's new in beta.4
-------------------
- Refreshed castbar visuals, Player latency SafeZone, and wider Player/Target
  castbar positioning ranges.
- Precision frame-positioning panel and more visible dispel highlights.
- Living Party/Raid units show observable Soulstone buffs. Visible temporary
  status icons collapse together without gaps; Soulstone is not tracked after death.
- Profile Export/Import and a larger, reorganized Profiles page. Import replaces
  current settings, preserves tracked buffs, and reloads. Sharing excludes
  tracked buffs and discovery history.
- Manual tracking by Spell ID; explicitly tracked helpful buffs display
  regardless of caster.
- Configuration-only Seen Buff discovery accepts safely identified self, party,
  and raid player sources. Missing/restricted sources are skipped.
- Right-click dismissal, persistent dismissed history, Reset Dismissed, and
  tooltip cleanup when buff icons disappear or move.

Please test external Power Infusion (10060), dismissal/reset, profile copy/paste
and tracked-buff preservation, positions after reload, and castbar/Soulstone
behavior in groups at your usual UI scale. Manual Spell ID remains the fallback
when automatic discovery misses a buff.

Installation
------------
Place MythIncUnitFrames in your Retail Interface\AddOns directory. The folder
must directly contain MythIncUnitFrames.toc, the Lua files, and the Media folder,
with artwork under Media\Artwork and no extra nested repository folder.
Enable MythInc Unit Frames in the AddOns list. Settings are stored in
MythIncUnitFramesDB.

Supported frames
----------------
Player, Target, Focus, Pet, Target of Target, Party, Boss (up to five), and Raid.
All except Raid are enabled by default. Party can optionally include the player
and is hidden in raids. Party/Boss support horizontal or vertical layouts,
growth direction, and spacing. Raid uses six groups of five, or eight groups
with Legacy 40-player groups enabled, with horizontal/vertical arrangements
and touching members and subgroups.

Configuration and movement
--------------------------
Open /miuf, select Frames and a unit type, then Layout, Text, Appearance,
Indicators, or Auras. Unsupported controls are hidden. The window is draggable
and scales down to fit the screen. Myth Inc artwork appears in the header and
addon-list icon.

GUI edits and mover position/size changes are staged. Apply Changes commits
pending edits. Revert Changes discards pending edits and restores the last
applied settings while keeping the session open. Minimize collapses the window
and preserves the session, pending edits, selected context, and active previews;
Restore returns to that same session. Close (X) discards all unapplied pending
edits, clears previews, stops and locks movers, restores the last applied state,
and ends the session. Protected restoration waits until combat ends if needed.
Frame, aura, and Reset All buttons stage resets. Raid also has Revert Raid Changes.

Unlock Frames enables global frame movers and resize handles.
Party, Boss, and Raid have group previews for layout work. In Auras, Preview
Position toggles a focused mover for the selected aura type; multiple aura-type
previews can stay active within the same frame type. Switching frame types
clears these previews. Movers position aura groups relative to their frames.
Party/Raid use a visible live member when available, or an existing visible
configuration group preview when no live member is available. These fallback
movers show placement, not simulated aura icons. Unlock Frames to show group
previews as needed. Aura movers retain a separate lock state; unlocking it
alone does not display every aura mover.
The floating Lock Movers button locks both kinds. Locking does not commit
edits: use Apply Changes to save. Configure and move frames outside combat.

Appearance and text
-------------------
Per-type controls cover width, height, power-bar height, bar texture, health
and power color presets, and background/border opacity. Optional portraits
support left/right placement and proportional width; Raid has no portraits.
Text controls provide built-in and bundled fonts, font size, name/health-text
visibility, and separate X/Y offsets. Health text shows a percentage or available Offline,
Ghost, Dead, or AFK status. Party/Raid members have automatic range fading.

Auras
-----
Buffs and debuffs: Player, Target, Focus, Target of Target, and Party.
Defensives: Player and Party, using Blizzard's big/external defensive filters.
Raid: debuffs only. Pet and Boss: no aura display or aura controls.

Supported aura types have enable, cooldown-text, icon-size, maximum-count,
spacing, top/bottom anchor, left/right growth, and X/Y offset controls.
Enable Buff Filtering is per frame type: on shows helpful buffs from the
profile-wide tracked list; off shows all helpful buffs. It defaults off for
Target and on for other supported buff frames. An empty tracked list shows
no normal buffs while filtering is enabled.

Manage Tracked Buffs adds observed buffs or known Spell IDs, or removes tracked
buffs. Tracked buffs match regardless of caster. Discovery scans up to 40 helpful
auras on selected units outside combat while configuring, accepting only safely
identified self/party/raid player sources. Unknown or restricted sources and
non-player sources are skipped. Tracking edits are staged and require Apply.
Right-click a Seen Buff to dismiss it immediately across profiles and prevent
rediscovery. Clear Seen History clears history but keeps dismissals; Reset
Dismissed allows discovery again. Neither history action requires Apply.
Player, Party, Target of Target, and Raid debuffs use built-in exclusions and
omit player/player-pet debuffs; Target/Focus use the general harmful filter.
Player, Party, Focus, and Raid have dispel highlighting. Party defensive
displays are hidden when the member is not visible to the client.

Indicators
----------
Raid markers are configurable on all frame types. Role icons are available
for Player, Party, and Raid. Party/Raid leader icons have visibility, size,
and offset controls; Party defaults on and Raid off. When Party excludes the
player, its leader icon can appear on the separate Player frame. Player also
has a configurable resting indicator.

Ready-check, incoming-summon, and incoming-resurrection indicators are automatic
on Player, Target, Focus, Target of Target, Party, and Raid. Shared size/offset
controls are available, but no individual enable switches. Preview temporarily
shows a ready-check icon on an available live frame or group preview; it is not
saved and clears on leaving that view.
Party/Raid also show Soulstone when its buff is safely observable on a living
unit. It disappears with the aura; unused self-resurrection is not tracked after
death. Visible status icons use Ready Check, Summon, Resurrection, Soulstone order
without gaps for hidden icons.

Castbars and click-casting
-------------------------
Player, Target, Focus, and Boss have native attached castbars for casts,
channels, and empowered channels. Presentation includes spell text and icon,
remaining-time text, a spark, an interruptibility shield for uninterruptible
casts, terminal Interrupted/Failed displays, and empowered-stage separators
where applicable and available from Retail's APIs.

Under Frames > Layout > Cast Bar, Player and Target have enablement, width,
height, X/Y offsets, and Preview Cast Bar controls. Changes are staged with
the rest of the configuration. Focus and Boss have enablement only and keep
their original frame-relative geometry (frame width, 18 high, 3 below the
frame). All Boss frames share the same castbar enablement setting.
Player/Target castbar offsets support -1000 to +1000. Player has a latency
SafeZone. The precision positioning panel supports exact frame placement.

Frames register with ClickCastFrames for compatible addons such as Clique.
Configure bindings in that addon; MIUF has no built-in binding editor.

Profiles
--------
Profiles are shared in the addon database; each character remembers its choice.
Create New starts from defaults. Copy Current copies saved settings: apply
pending edits first if they should be included. Rename Selected and Delete
Selected manage profiles. Default cannot be renamed/deleted; the active profile
cannot be deleted. Characters using a deleted profile fall back to Default.
Use Selected Profile requires no pending edits and reloads the UI. Profile operations
are unavailable in combat. Seen-buff history is shared; tracked buffs,
appearance, layouts, positions, and enable states belong to each profile.
Export shares the saved active profile; Apply or Revert pending edits first.
Import requires a clean session outside combat, confirms replacement of the
current profile, keeps its tracked buffs, and reloads. Tracked buffs, seen and
dismissed history, character profile choices, and other profiles are not shared.

Limitations and reloads
----------------------
- Most Apply Changes operations update live outside combat. Changing Raid's
  Legacy 40-player capacity or switching profiles reloads the UI. Apply also
  reloads if live application fails or cannot complete.
- Protected layout/visibility work may wait until combat ends. Apply and Revert
  are unavailable during combat; Blizzard controls restricted aura data.
- The profile picker displays thirteen entries. The buff manager displays up to 24
  seen and 24 tracked buffs. These lists currently have no pagination.
- Blizzard Party and the raid container are reversibly hidden while the
  corresponding MIUF frame type is enabled in applied settings. Applying a
  disabled state restores their original parents, leaving visibility to
  Blizzard's settings and group state. The Blizzard raid manager is retained.
- The normal Blizzard Player castbar is reversibly hidden only while both
  MIUF Player and its native castbar are enabled in applied settings. Disabling
  either restores its original parent. Ownership changes wait until combat
  ends when necessary; staged previews and Revert do not transfer ownership.
- Blizzard's Player, Pet, Target, Focus, and Boss unit frames remain suppressed
  independently of MIUF's enable switches. Disabling those MIUF frame types
  does not restore their Blizzard unit-frame counterparts.
- This is an outside-testing beta. Bugs may occur; combat, vehicles,
  group changes, artwork, UI scaling, and raid layouts warrant testing in game.

Beta feedback
-------------
Include the MIUF version, Retail version, reproduction steps, expected and
actual behavior, and the complete Lua error when applicable. Screenshots and
other relevant addons can help explain layout or compatibility issues.

Slash commands
--------------
/miuf                    Toggle configuration (also: config or options)
/miuf help               Print command help
/miuf version            Print installed addon version
/miuf unlock             Unlock frame movers
/miuf lock               Lock frame movers; review pending edits in the GUI
/miuf auraunlock         Unlock aura-mover state; use Preview Position in Auras
/miuf auralock           Lock aura movers
/miuf size <type> <w> <h> Immediately save/apply a frame type's size
/miuf reset              Immediately reset the current profile and seen history

Size types: player, target, focus, pet, targettarget, party, boss, raid.
Example: /miuf size player 250 54
The command accepts integer widths 100-600 and heights 24-150; the Raid GUI
allows smaller frames (50 wide, 18 high). Size and reset are blocked in combat.
Unlike GUI edits, these commands do not wait for Apply Changes. Prefer the GUI
for a reset you can review or revert before applying.
