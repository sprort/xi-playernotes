# PlayerNotes

**PlayerNotes** is an Ashita addon for Final Fantasy XI that lets you record and view notes, star ratings, and linkshell details for other players. Target someone and their saved information appears automatically, helping you remember interactions, impressions, and who's worth grouping with again.

Originally created by **Fyayu**; substantially extended and maintained by **Sprort**.

## Features
- **Two note types**: A short **quick note** shown on the targeting overlay, plus **detailed notes** kept in the config window for deeper info.
- **Master/detail config window**: A selectable player list (name, rating, linkshell, last seen, note updated) on the left; the selected player's full notes and editor on the right.
- **Record Notes**: Save custom notes for each player.
- **Player Ratings**: Rate players on a 5-star scale, with color-coded feedback.
- **Linkshell Tracking**: Track players' linkshell affiliations for easy reference.
- **Quick Edit**: Rate and note your current target directly from the overlay — no need to open the advanced window or retype names.
- **Search & Sort**: Filter the player list by name, note, or linkshell text, and sort by name, rating, linkshell, or last-seen.
- **Timestamps**: Automatically records when each note was created/updated and when you last targeted that player.
- **Delete Confirmation**: A confirm prompt guards against accidentally wiping a player's data.
- **Configurable UI**: Resizable advanced window for viewing and managing all recorded players, with adjustable transparency for both the overlay and the config window.

## Installation

1. **Download the repository** — clone into a folder named `playernotes`. Ashita
requires the addon folder name to match the Lua file (`playernotes/playernotes.lua`),
so the target folder is given explicitly here since the repository has a different name:
```
git clone https://github.com/sprort/xi-playernotes.git playernotes
```

2. **Place the Addon in the Ashita Addons Folder**:  
Move the `playernotes` folder into your Ashita `addons` directory:  
`Ashita\addons\playernotes`

3. **Load the Addon**:  
Launch Ashita and load the addon using:  
`/addon load playernotes`

## Usage

- **Viewing Notes**: Target any player to see their saved notes, rating, and linkshell information in an ImGui overlay.
- **Adding Notes**: Click on the "Config" button to open the advanced window where you can add new players or edit existing notes and ratings.
- **Editing Notes**: Use the "Edit" button next to each player’s name in the advanced window to update notes, ratings, or linkshell information.

### Commands

- `/pnotes` — toggle the overlay on/off
- `/pnotes on` | `/pnotes off` — force the overlay on or off
- `/pnotes config` — toggle the advanced management window
- `/pnotes help` — list the commands

Overlay visibility is saved between sessions. The advanced window also has a **"Hide overlay when no player is targeted"** option if you only want notes to appear while you have a player targeted.

## Configuration

PlayerNotes uses a JSON-based configuration that automatically saves your data, so notes, ratings, and linkshell details are persistent across sessions.

## Screenshots

_Screenshots are being refreshed for the current interface._

## Contributing

Contributions are welcome! Please open an issue or submit a pull request if you have suggestions for improvements.

## Credits

- **Fyayu** — original author of PlayerNotes.
- **Sprort** — ongoing development: two-tier notes, the master/detail config window, star ratings, chat commands, transparency and layout options, and assorted fixes.

## License

This project is licensed under the MIT License, as was the original. See the [LICENSE](LICENSE) file for details.
