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
nomalms upgrade nomaubl          # one product, by name or by folder
nomalms upgrade                  # asks which one when several are installed
nomalms upgrade --all            # every product installed through nomalms
```

With a single product installed, `nomalms upgrade` upgrades it directly. In a script
(no terminal) with several products, name the product or pass `--all`.

This pulls the new version only: the files are replaced, the running application is not
touched. A plain `git pull` in the product folder works too.

### Upgrade the application as well (Linux)

Add `--apply` to run the product's own upgrade procedure after the pull:

```bash
nomalms upgrade nomaubl --apply --env py     # this environment (repeat --env for several)
```

For NomaUBL the environment is required: nothing is upgraded without `--env` (or the `envs`
setting below), so test and production are never upgraded together by accident.

| Product | What `--apply` runs |
|---|---|
| NomaUBL | `./nomaubl.sh upgrade <env>` for each environment named, one after the other; it stops at the first that fails |
| Liberty apps, Docker | `./liberty apps <the wheel named in LATEST>` in the liberty-next release folder |
| Liberty apps, Python | `pipx inject --force liberty-next <wheel>`, `liberty-apps install --target <target>`, `liberty-ops migrate` |

The Liberty wheel is checked against `SHA256SUMS` first.

Settings are kept per install, on this server:

```bash
nomalms set nomaubl envs py                  # the environments upgraded when no --env is given
nomalms set nomaubl apply yes                # upgrade them after every pull that brings a new version (needs envs)
nomalms set liberty mode docker              # or: python  (required for Liberty)
nomalms set liberty liberty_dir /opt/liberty-next/release      # Docker: where the ./liberty script is
nomalms set liberty target /opt/liberty/apps/config            # Python: default shown
nomalms set nomaubl                          # show the settings
```

With `apply yes`, a pull that brings nothing new upgrades nothing; `--apply` on the command
line always runs the procedure. On Windows, `nomalms upgrade` pulls only.

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
| `nomalms upgrade [product\|folder\|--all]` | `git pull` of one product; asks which when several are installed |
| `nomalms upgrade ... --apply [--env <name>]` | the same, then the product's upgrade procedure (Linux) |
| `nomalms set <product\|folder> [key value]` | settings of an install: `apply`, `envs`, `mode`, `liberty_dir`, `target` |
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
