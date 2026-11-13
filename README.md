# nomalms

Installs and upgrades Nomana products (NomaUBL, Liberty apps) on your server.

Your server is enrolled once with a code from the NomaLMS portal. After that, each
`git clone` or `git pull` of a product gets a one-hour, read-only GitHub token from
NomaLMS, as long as your licence for that product is valid. There is no token to
store or renew.

This repository is public and holds no secret.

## What you need

- `git` and `curl` (Linux, macOS), or Git for Windows and PowerShell 5.1+ (Windows)
- Outbound HTTPS from the server to `nomalms.nomana-it.fr` and to `github.com`

If your server cannot reach `nomalms.nomana-it.fr`, see [Without access to NomaLMS](#without-access-to-nomalms).

## Install the tool

Linux / macOS, as the user that runs the products:

```bash
git clone https://github.com/fblettner/nomalms-dist.git ~/nomalms-dist
sudo ln -s ~/nomalms-dist/nomalms /usr/local/bin/nomalms     # or add ~/nomalms-dist to your PATH
```

Windows (PowerShell):

```powershell
git clone https://github.com/fblettner/nomalms-dist.git C:\nomalms-dist
# then add C:\nomalms-dist to the PATH, or call C:\nomalms-dist\nomalms.cmd
```

## Enrol the server (once)

1. In the portal: **Repository access › Add a server**. Give it a name; you get a
   one-time code, valid 24 hours.
2. On the server:

   ```bash
   nomalms enroll XXXXX-XXXXX-XXXXX-XXXXX
   nomalms status
   ```

`status` lists your products, whether each licence is valid, and what is installed
on this server.

## Install a product

```bash
nomalms install nomaubl /app/nomaubl
nomalms license nomaubl          # the licence key to enter in the product
```

Then follow the product's own README for its first start.

## Upgrade

```bash
nomalms upgrade                  # every product installed through nomalms
nomalms upgrade nomaubl          # or one of them
```

This pulls the new version, then prints the product's own next step (for NomaUBL:
`./nomaubl.sh upgrade <env>`). A plain `git pull` in the product folder works too.

## Switch an existing install

A product cloned earlier with a token or an SSH deploy key can be switched without
cloning again:

```bash
nomalms adopt /app/nomaubl
```

It points the clone at `https://github.com/...`, checks that a fetch works, and
only then keeps the change. If the fetch fails, the clone is left exactly as it was.
The old token (`~/.git-credentials`) or deploy key is then no longer needed.

## Without access to NomaLMS

Nothing changes for you: keep using the token or deploy key recorded for you in the
portal (**Repository access › Tokens and deploy keys**), with a plain `git pull`.

## Commands

| Command | What it does |
|---|---|
| `nomalms enroll <code> [--url URL]` | Register this server |
| `nomalms status` | Products, licences, what is installed here |
| `nomalms install <product> [folder]` | Clone a product |
| `nomalms adopt <folder>` | Switch an existing clone to nomalms |
| `nomalms upgrade [product\|folder]` | `git pull` |
| `nomalms license <product>` | Print the licence key |
| `nomalms self-update` | Update this tool |
| `nomalms version` | The tool's version |

## Where things are kept

| | Linux / macOS | Windows |
|---|---|---|
| Server token | `~/.config/nomalms/config` (mode 600) | `%APPDATA%\nomalms\config` (encrypted for the Windows user) |
| List of installs | `~/.config/nomalms/installs` | `%APPDATA%\nomalms\installs` |

The token only identifies the server. To cut a server, revoke it in the portal:
its next pull is refused. To move the tool to another user or server, enrol again
with a new code.

## Troubleshooting

| Message | Meaning |
|---|---|
| `this server is not enrolled` | Run `nomalms enroll <code>` as the same user that runs `git` |
| `This enrolment code is not valid or has expired` | Codes work once, for 24 hours: create a new one in the portal |
| `This server has been revoked in the portal` | Add the server again in the portal and enrol with the new code |
| `The licence for … has expired or been revoked` | Renew the licence; pulls work again at once |
| `cannot reach https://nomalms…` | The server has no outbound HTTPS to NomaLMS: open it, or use a recorded token |
