# Axiom Paper Plugin — Folia port

Serverside component for [Axiom](https://modrinth.com/plugin/axiom), ported to **Folia** for **Minecraft 26.1.2** (Paper API 26.1.2.build.53-stable, Folia API merged into paper-api as of 26.x).

This is a community fork of [Moulberry/AxiomPaperPlugin](https://github.com/Moulberry/AxiomPaperPlugin) (MIT license — see `LICENSE`). The original plugin runs on Paper but not on Folia; this fork makes the necessary scheduler and threading changes so the plugin loads and runs on a Folia (or Folia-derived, e.g. [Luminol](https://github.com/LuminolMC/Luminol)) server.

## Compatibility

| | Paper | Folia | Luminol 26.1.2 |
| --- | --- | --- | --- |
| Upstream `Moulberry/AxiomPaperPlugin` | ✅ | ❌ (refuses to load) | ❌ |
| This fork (`axiom-paper-folia`) | ✅ (drop-in) | ✅ | ✅ (primary target) |

`folia-supported: true` is set in `plugin.yml`. The plugin still works on regular Paper.

## What changed for Folia

- `Bukkit.getScheduler()` → `Bukkit.getGlobalRegionScheduler().runAtFixedRate(...)` for the per-tick task in `AxiomPaper`.
- `MinecraftServer#execute(...)` from packet handlers → `Bukkit.getGlobalRegionScheduler().execute(...)`.
- `player.teleport(...)` → `player.teleportAsync(...)` (TeleportPacketListener).
- Per-entity ops (gamemode change, manipulate, delete) dispatch to the entity's `getScheduler()`.
- Spawn-entity dispatch goes to `Bukkit.getRegionScheduler()` keyed on the destination chunk.
- Blueprint upload file I/O moved to `Bukkit.getAsyncScheduler()`.
- POI updates inside `SetBlockBufferOperation` are skipped (PoiManager is per-region; POI gets refreshed naturally during chunk ticks).
- BlockEntity ops in the operation queue have `WrongThreadException` / `TickThread` fallbacks that mutate the chunk's `blockEntities` map directly.
- `playerPermissions`, `lastPlotBoundsForPlayers`, `noPhysicalTriggerPlayers`, `WorldExtension.extensions` switched to `ConcurrentHashMap` because the per-tick task and packet handlers can now run on different region threads.
- `tick()` no longer iterates `Bukkit.getOnlinePlayers()`; it only walks the active/failed Axiom-player UUID sets.

## Building

```bash
export JAVA_HOME=/path/to/jdk-25
./gradlew build
# output: build/libs/AxiomPaper-5.0.4-folia+26.1.2-all.jar
```

JDK 25 + Gradle 9.4.1 + paperweight-userdev with paper devBundle `26.1.2.build.53-stable`. The build is offline-friendly: `libs/CoreProtect-23.1.jar` is fetched at CI time (CoreProtect's `maven.playpro.com` is Cloudflare-protected and rejects automated requests).

## Repos

- Canonical: [`forgejo.ekaii.fr/exo/axiom-paper-folia`](https://forgejo.ekaii.fr/exo/axiom-paper-folia)
- Mirror: [`github.com/uncaney/axiom-paper-folia`](https://github.com/uncaney/axiom-paper-folia)

## License

MIT — same as upstream. See `LICENSE`.

---

## Original FAQ

**Axiom works in singleplayer but not when I connect to a multiplayer server running the Axiom Paper Plugin. What gives?**

First, the player must be an op on the server. If the player does not have op permissions, run `/op <playername>`. This player must then disconnect from the server and reconnect.

If you're using an alternative solution for permission management, you must give players the `axiom.default` permission.

If players continue to have issues, they can run the `/whynoaxiom` command for more information.
