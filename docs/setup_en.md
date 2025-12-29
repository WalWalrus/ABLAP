# Instructions:
[Click Here](https://github.com/ArsonAssassin/Archipelago.Core/wiki/How-to-start-playing-a-game-using-this-library) for general instructions.

## Playing a Game with A Bug's Life

### Required Software
Important: As the client runs only on Windows, no other systems are supported yet.

- BizHawk
- Archipelago version 0.6.1 or later.
- The [A Bug's Life Client, BizHawk Lua Script and .apworld](https://github.com/WalWalrus/ABLAP/releases)
- A legal PS1 A Bug's Life NTSC-U (US version) ROM. We cannot help with this step.

### Create a Config (.yaml) File

#### What is a config file and why do I need one?

See the guide on setting up a basic YAML at the Archipelago setup guide: [Basic Multiworld Setup Guide](https://archipelago.gg/tutorial/Archipelago/setup_en)

This also includes instructions on generating and hosting the file.  The "On your local installation" instructions
are particularly important.

#### Where do I get a config file?

Run `ArchipelagoLauncher.exe` and generate template files.  Copy `A Bug's Life.yaml`, fill it out, and place
it in the `players` folder.

### Generate and host your world

Run `ArchipelagoGenerate.exe` to build a world from the YAML files in your `players` folder.  This places
a `.zip` file in the `output` folder.

You may upload this to [the Archipelago website](https://archipelago.gg/uploads) or host the game locally with
`ArchipelagoHost.exe`.

### Setting Up A Bug's Life for Archipelago

1. Download the A_Bug's_Life_AP_Client.zip, abugslife.apworld and abugslife.lua from the GitHub page linked above.
2. Double click the apworld to install to your Archipelago installation.
3. Extract the A_Bugs_Life_AP_Client.zip and note where ABugsLife_Client.exe is located.
4. Host or join an Archipelago lobby either locally or via the Archipelago website.
5. Open the ABugsLife_Client.exe file. (You may want to do this as an administrator)
6. Enter your host, slot and optionally your password.
7. Open BizHawk and load into A Bug's Life.
8. Select Tools > Lua Console and open a script.
9. Select the ABL.lua file and open it.
10. It will need a few seconds to load, it should return a "ABL: load successful" message if it has loaded correctly.
11. Start playing!