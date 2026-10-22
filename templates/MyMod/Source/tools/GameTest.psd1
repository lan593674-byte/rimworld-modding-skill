# Settings of this mod's test scripts. Every script in this folder reads this file through GameRuntime.ps1;
# nothing else in Source\tools names the mod, so the scripts can be copied unchanged to another mod.
# Paths that are not set here follow the folder convention of the skill:
#   <dev root>\<ModName>\repo              this repository (the dev root is two folders up from it)
#   <dev root>\<ModName>\dev               working notes, not in the repository
#   <dev root>\<ModName>\test              test profiles, logs, screenshots
#   <dev root>\_shared\ModLists           saved mod lists for the full profile, shared by all mods
#   <dev root>\_shared\GameRefs           1.7 reference assemblies, shared by all mods (save-game-refs.ps1)
#   <dev root>\_shared\player-log-backup  the player's 1.7 Player.log while a test runs, shared by all mods
# Keep this file ASCII, or save it as UTF-8: GameRuntime.ps1 reads it as UTF-8 either way.
@{
    # Folder name in the game's Mods folder, dll name (<ModName>.dll), test folder (<dev root>\<ModName>\test).
    ModName       = 'MyMod'
    PackageId     = 'yourname.mymod'
    # Every log line of the mod starts with this (ModLog.cs uses the same text).
    LogPrefix     = '[MyMod]'
    # Command-line switches of the mod's self-test: -mymod-selftest, -mymod-smoke, -mymod-capture, ...
    ArgPrefix     = 'mymod'
    # Root namespace of the mod's code and the prefix of its defNames: the save-safety check looks for them in
    # saves made after the mod was removed, and judges the errors of loading a save without the mod.
    CodeNamespace = 'MyMod'
    DefPrefix     = 'MyMod_'

    # Game versions the mod supports; each has its own folder (<version>\Assemblies\<ModName>.dll).
    GameVersions  = @('1.6', '1.7')
    # Release content mirrored to the game's Mods\<ModName> folder (missing ones are skipped and removed there).
    ReleaseDirs   = @('About', 'Defs', 'Patches', 'Languages', 'Sounds', 'Textures')
    ReleaseFiles  = @('LoadFolders.xml')
    # Folders the mod itself writes into Mods\<ModName> at runtime (downloads, caches): the sync leaves them alone,
    # and they must be moved out before a Workshop upload.
    RuntimeDataDirs = @()

    # Mods the mod needs, loaded right after Harmony, Core and the DLCs in every test profile; they must be
    # installed (game Mods folder or Workshop). Leave Harmony out if the mod does not use it.
    Dependencies  = @('brrainz.harmony')
    # DLC packageIds the mod requires; the core profile enables only these.
    RequiredDlcs  = @()
    # packageIds that are never loaded together with the mod (also declare them in About.xml incompatibleWith).
    IncompatibleMods = @()

    # Screenshots smaller than this are judged broken (a black or empty capture).
    MinShotBytes  = 20480

    # Extra regular expressions for errors that are expected when a save with the mod is loaded without it,
    # on top of the generic ones in run-savesafety.ps1 (missing classes in CodeNamespace, missing defs with
    # DefPrefix, the fallout of a missing building).
    AllowedUninstallErrors = @()

    # Game folder; empty means the RIMWORLD_GAME_ROOT environment variable, else the Steam library that has
    # RimWorld (found through the registry and libraryfolders.vdf).
    GameRoot      = ''
}
