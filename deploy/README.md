# Deploying a prototype

One small Linux VPS runs both game servers and serves the web build over HTTPS.

```
browser ──https──▶ Caddy ──▶ /srv/kenney-mp/web          (static web export)
        ──wss────▶ Caddy ──▶ 127.0.0.1:9080  (2D server, kenney-mp@2d)
                         ├─▶ 127.0.0.1:9081  (3D server, kenney-mp@3d)
                         └─▶ 127.0.0.1:9082  (space server, kenney-mp@space)
```

Why this shape: an HTTPS page may only open `wss://` sockets, and the Godot server speaks plain `ws://`. Caddy gets a certificate automatically and terminates TLS for both the page and the sockets, so the game servers stay simple and bind to localhost only.

## Steps

1. **Build** (on your machine or in CI):
   ```bash
   tools/install_godot.sh --templates
   tools/export.sh all release
   SERVER_BIN=build/server/server.x86_64 tools/smoke.sh   # test the exact binary you ship
   ```
2. **Copy** to the server:
   ```bash
   rsync -av build/web/    you@host:/srv/kenney-mp/web/
   rsync -av build/server/ you@host:/srv/kenney-mp/server/
   ```
3. **Services** (once): create a `kenney` user, install `kenney-mp@.service`, `systemctl enable --now kenney-mp@2d kenney-mp@3d kenney-mp@space` (enable only the games you're hosting).
4. **Caddy** (once): put `Caddyfile` in `/etc/caddy/Caddyfile` with your domain, `systemctl reload caddy`.
5. Open `https://your-domain/?game=2d`, `?game=3d` or `?game=space`.

Firewall: only 80 and 443 need to be open. 9080/9081 stay closed because the servers bind to 127.0.0.1.

## Static hosts instead of Caddy

The web build is single-threaded, so it works on itch.io, GitHub Pages, Netlify or Cloudflare Pages without special headers. The game server still needs TLS somewhere. Point the page at it explicitly:

```
https://you.itch.io/game?game=2d&server=wss://game-server.example.com/ws/2d
```
