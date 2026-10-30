# Coin Vault 3D

A private first-person prototype inspired by the bunker, coin pile, and deposit loop in One Million Coins.

## Run the game

1. Open this project in Godot 4.7.2 stable.
2. Press **F5** to start.
3. On the title screen, choose **New Game** and one of three slots, or **Continue** to open the last played save. Use **WASD** to move, **Space** to jump, and the mouse to look around.
4. Hold **Shift** to sprint 70% faster.
5. Aim at the coin heap. The crosshair changes color when the heap can be collected. Hold **Left Mouse Button** to keep collecting coins, or click for a single pickup.
6. Follow the four turning stair flights around the vault wall to descend to the bottom.
7. Press **E** at the wall-mounted deposit station to bank your coins.
8. Press **Q** anywhere to open the **Coin Tree**. Spend banked coins on five connected branches: bags, tools, reach, banking, and conveyors. Drag to explore the map, zoom with the wheel, and hover an icon for its effect and price. Purchases reveal the next nearby choices.
9. Press **Q** again, **Esc**, or **Back to Vault** to close the skill tree. The skill-tree key can be rebound in Settings.

The vault starts with exactly 1,000,000 coins and a 25-coin bag. A broad, nearly flat gold surface sits just below the top rim, with thousands of instanced coin meshes and a partial second layer to keep the view filled with coins. The three visible layers use MultiMesh rendering, without individual rigid-body coins. Collecting intersects the actual tilted disc, removes the picked disc with a brief local flick, exposes the actual coin beneath it, and reduces the visible stack, and applies a small damped response to nearby coins. Neighbor movement is bounded; extraction advances through stack supports, backing layers, and deeper reserves. Five broad basins make the initial pile visibly uneven. At most 32 nearby coins settle and 12 cosmetic pickups animate at once; support and coverage updates are batched. Idle coins run no physics simulation. No replacement coins drop from above. The first-person HUD has no hand overlay. Five upgrade branches improve bag capacity, tool power, reach, deposit value, and conveyor income. Walking and sprinting use fixed base speeds.

The project uses GDScript. Codex can work directly in this project folder.

Excavated areas grow compact local reserve layers down to the deepest neighboring column. Flat packed reserve discs cover gaps and pit walls; nearby higher columns can transfer an existing coin into a narrow hole without changing the total count. Reserve geometry is built only for disturbed chunks and uses a lower-detail shared mesh.

Coin placement checks registered solid geometry. The pile extends beneath the perimeter platform to the vault walls, exposed stair coins form finite horizontal stacks on tread surfaces. Clearing a stack exposes the tread, without refilling the step or creating a replacement inside it. Stack supports, reserves, and the coverage skin are clipped against structures. Hidden coin budgets are redistributed to valid pile columns so the initial total remains 1,000,000. Coverage updates rebuild only local patches.

The outer pile tapers below the starting platform, leaving at least 0.75 m of initial air under its underside at the tested outer columns. Local settling preserves stair contact and slides along permitted boundary axes instead of crossing solid structures.

The outer edge is lowered a further half metre and filled with actual coin meshes to all four vault walls; it no longer ends at the inner railing. The solid safety floor is at the vault bottom so it does not float the player above the lowered edge.

The base pile uses broad, warped blending between rolling hills, basins, and a lower uneven perimeter. There is no hard minimum/cutoff at the old border, so the slope continues naturally into the real coin layers beneath the platform.

Vault finishes are generated in vault_details.gd: offset blockwork with mortar, worn concrete panel floors and ceilings, steel ceiling I-beams, round handrails with collars and bolted feet, and patterned metal stair treads with safety nosings. Repeated architectural geometry is combined into six MultiMesh batches plus a shared anchor-bolt batch. Four-sample antialiasing smooths rails and coin rims.

Coverage skins sit below the lowest nearby visible coin layers, rather than cutting through interpolated pile heights. The backing has no printed coin decals, and crossing reserve filler discs have been removed. Registered solid geometry occludes pickup targeting, so coins cannot be collected through stair treads or walls; open railing space remains targetable.

The graphic HUD in vault_hud.gd shows an illustrated gold balance counter, a subtle remaining-coin count, and a framed bag panel with a sack icon and animated capacity bar. Full bags use a warmer warning colour. Balances, deposits, passive income, and capacity upgrades update these controls. The HUD remains non-interactive during play and reflows for smaller windows.


## The Coin Tree

Open with Q. Drag with the left, middle, or right mouse button to move the map. A left click buys a skill; dragging across a node never purchases it. Use the mouse wheel to zoom around the cursor and Center Tree to fit the revealed map. Q, Escape, or Back to Vault closes the tree. The opening key remains rebindable.

The tree contains 140 one-time skills across five categories. Each category has eight tiers, with a core path, two smaller side upgrades per tier, and four powerful milestone hexagons. Side upgrades vary within each category, including collection rhythm, carrying capacity, deposit range, and passive income. Milestone skills offer large rewards such as +60% current bag capacity, +75% current coins per pickup, +50 percentage points of deposit value, and major conveyor income boosts.

Only learned nodes and their immediate next choices are visible. Deeper descendants are hidden. Next choices can still require more coins or a collection milestone: hover an icon to see the exact effect, price, progress requirement, and purchase status. Effects and upgrade names are displayed only in the hover panel, rather than printed across the map.

Core tier milestones: 0, 100, 750, 3,000, 12,000, 50,000, 180,000, and 450,000 physical coins collected. Major rewards require 250, 7,500, 125,000, and 900,000 collected coins, plus both side skills in that tier. Costs and core effects increase by tier. Branches do not exclude one another. All skills require banked coins to buy, and learned skills cannot be bought twice.

Collection progress never decreases when depositing or spending. Conveyors remove real vault coins and count toward collection milestones; deposit bonuses do not. Progress belongs to each saved run and resumes when that slot is loaded. Banking bonuses and passive income support the later upgrades. These are initial balance values, still subject to playtesting.

Large tool scoops process at most four visible discs per batch with a soft time budget between discs, spreading work across frames. Opening a menu or losing focus cancels unfinished pickup work. Each successful physical coin updates the bag, remaining vault count, and collection milestones exactly once.


## Save files and title screen

The game opens on the Coin Vault 3D title screen, with Continue, New Game, Settings, Help & Controls, and Quit to Desktop. Continue loads the most recently played readable save. The three slot buttons can load a different run. New Game offers three slots and asks before replacing an occupied one.

Runs are stored locally in `user://saves/vault_1.sav` through `vault_3.sav`. On Windows this normally resolves to `%APPDATA%/Godot/app_userdata/Coin Vault 3D/saves/`. Settings and key bindings remain shared in the existing preferences file, separate from run saves.

Saving includes balances, bag contents and capacity, total physical collection, all learned skills and their exact applied effects, player position and look direction, play time, and the excavated pile's remaining columns, visible layers, backing coins, short stacks, reserves, and settling state. In-flight cosmetic coins and unfinished pickup work are not resumed. Conveyors do not run while the game is closed.

A run autosaves every 30 seconds of active play. Banking coins and buying skills request an early autosave. Opening pause/focus loss saves immediately. The pause menu also offers Save Game, Save & Title Screen, and Save & Quit. Closing the game window uses the same save-before-quit path. If writing fails, an error is shown and quit/return-to-title is stopped so the player can retry.

Periodic writes use a background thread after capturing state on the main thread. Saves have a version, checksum, validation, a verified temporary file, and a previous-version `.bak`. An unreadable primary automatically falls back to its valid backup. Unreadable slots are not silently overwritten by Continue. Force-stopping the process can lose changes since the last completed save.


Conveyors collect real coins across the vault from the highest occupied horizontal layer down. They clear broad top layers with uneven priorities, leaving small mounds and dips instead of a flat top. A bounded spatial bias and changing per-coin variation spread extraction across nearby height bands. A selected coin stays within approximately 66 cm of the highest remaining column, preventing deep isolated shafts. Manual excavation updates conveyor priorities immediately. Each actual removal banks one coin, reduces the remaining vault count by one, and adds one to collection milestone progress. Bag capacity and deposit bonuses do not affect conveyor collection. Empty vaults produce no income. High rates are processed in bounded batches over frames; queued work is saved and top-layer priorities are rebuilt from the saved pile, with older saves defaulting to no queued work. Each removal advances the actual visible coin layers and uses the normal pickup flick. Pause and title screens stop conveyors; the skill tree leaves them running.


If you become stuck, open the pause menu and choose **Unstuck / Return to Top**. This returns you to the starting platform, clears movement and unfinished manual pickup work, saves the new position, and resumes play. Your coins, skills, and excavation progress are kept.


## Feedback, conveyor machinery, and graphics presets

Manual scoops show the actual collected total near the crosshair, with a short coin sound and a subtle pulse on higher effects settings. Full bags get a return-to-deposit hint. Deposits show the exact credited bank amount and play a different chime; learned skills have a confirmation sound. Sounds are generated locally without external audio assets. Sound effects and volume are adjustable under Settings > Mouse & Controls, then Apply.

A visible conveyor beside the deposit station carries cosmetic coins toward the bank when automation is working. Its display shows the conveyor collection rate, an offline message before conveyors are learned, and an empty-vault message when collection is finished. The existing real-disc extraction, top-down uneven surface, coin conservation, and milestone accounting remain the source of actual progress.

The skill tree now shows current bag capacity, scoop amount, reach, collection timing, deposit bonus, deposit reach, and conveyor rate. Hovering a learnable icon also shows exact before-and-after values, including multiplicative upgrades and timing minimums. Map framing adapts to the new header and window size.

Settings > Display offers Low, Balanced, High, and automatic Custom detection. Low uses simple coin meshes, reduced material grain, four pickup visuals, 12 settling coins, and four belt coins animated at 15 Hz. Balanced uses medium coin meshes, 2x MSAA, eight pickup visuals, 24 settling coins, and eight belt coins at 30 Hz. High uses full coin meshes, 4x MSAA, 12 pickup visuals, 32 settling coins, and 12 belt coins at 60 Hz. Actual collection rates and save data are unaffected by graphics quality. Fresh settings default to Low; existing saved detail/MSAA preferences are retained. Apply commits changes; window changes retain the existing confirmation/revert flow.

The FPS overlay includes median frame time and a rolling 95th-percentile frame time so slow frames are visible. 60 FPS corresponds to about 16.7 ms per frame. Performance results depend on hardware, resolution, and excavation state; presets are not a universal FPS guarantee.

Excavation performance: unchanged reserve columns reuse cached geometry, and active pile-coverage rebuilds are spread across frames. Startup and loading still reconstruct the full surface. These are visual scheduling optimizations; real coin removals and collection totals remain immediate and exact.


The skill tree uses tighter branch spacing and a smaller central hub. Affordable upgrades have green outlines, a plus badge, and their bank price below the icon. Learned nodes are subdued with a check; a coin badge means more banked coins are needed, and a lock marks an unmet collection milestone. The header counts each state. Next Buy centers and highlights affordable choices, cheapest first, without purchasing. Fit Tree frames the revealed map; Stats toggles the current-stat summary to keep the map compact. Effects and before/after comparisons remain hover-only. Upgrade IDs, effects, costs, requirements, and existing save progress are unchanged.

The pile uses finite coin columns that extend to the vault floor. Each column has a fixed initial capacity and floor; each successful pickup lowers its visible surface until the final coin is removed. Solid structures are skipped without deleting or transferring the remaining column budget. Empty columns end at the floor. The old brown coverage surface and side walls are retired; only actual coin meshes represent remaining coins. Exposed reserves fill down to nearby excavation depths, with hidden interiors omitted for performance. Finite capacities and ceilings are saved alongside exact per-column progress.

Loading a pre-finite save redistributes stranded reserve outliers across collectible floor columns while preserving its remaining total, collected total, balances, bag contents, skills, and applied effects. The legacy pile shape changes during this one-time repair. Later saves restore the exact finite pile. Changes lost before the last successful save cannot be recovered from that file.
