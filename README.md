Snake Arena - Godot 4.3+ (GL Compatibility renderer, landscape)

LOCAL: Menu > PLAY (2-4 players on one device, four on-screen direction buttons per player).
ONLINE: Menu > ONLINE. One device taps HOST GAME and reads the IP shown in the lobby.
        Others type that IP and tap JOIN. Host taps START when everyone is in (2-4 players, port 7777 UDP).
        The host runs the game; speed / rounds / wrap come from the host's Settings.

Touch controls: four on-screen direction buttons (up/down/left/right) for each local player.
Desktop test keys: P1 WASD, P2 arrows, P3 IJKL, P4 numpad 8/4/5/6 (online: WASD or arrows).

Android export: Editor > Editor Settings > Export > Android (JDK + SDK + debug keystore),
Project > Export > Add > Android, and tick Permissions > Internet in the preset. Then Export Project.
