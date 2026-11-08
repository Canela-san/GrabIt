<p align="center">
  <img src="assets/logo.png" alt="GrabIt" width="200">
</p>

<h1 align="center">GrabIt</h1>

<p align="center">
  <strong>Download videos from any site, in batches, always at maximum quality.</strong><br>
  A single Bash script on top of <a href="https://github.com/yt-dlp/yt-dlp">yt-dlp</a>, with a live panel in the terminal.
</p>

<p align="center">
  <img alt="Bash 4.4+" src="https://img.shields.io/badge/bash-4.4%2B-4EAA25?logo=gnubash&logoColor=white">
  <img alt="Engine: yt-dlp" src="https://img.shields.io/badge/engine-yt--dlp-red">
  <img alt="Linux and macOS" src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS-informational">
  <a href="https://github.com/Canela-san/GrabIt/actions/workflows/testes.yml"><img alt="Tests" src="https://github.com/Canela-san/GrabIt/actions/workflows/testes.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center">
  <a href="README.md">Português</a> · <strong>English</strong>
</p>

<p align="center">
  <img src="assets/demo-en.png" alt="GrabIt panel downloading several videos at once" width="860">
</p>

## Why GrabIt?

- **Maximum quality, always.** It grabs the best video and the best audio available (4K, 60 fps, HDR, 5.1 sound — whatever exists) and puts them together in an MKV, without re-encoding anything. And it never hands you an incomplete video: if a piece is missing, the download fails and starts over from scratch.
- **Any site.** Works with everything yt-dlp supports: thousands of sites, playlists, channels and pages with embedded video.
- **Batch and parallel.** You hand it a list of links; it downloads several videos at once, each with several connections.
- **Live panel.** Progress, speed, time left and the quality of each download, an estimate of how long the whole batch still needs, without yt-dlp's flood of text. At the end, each video shows what was *actually* saved (read from the file with `ffprobe`).
- **Everything inside the file.** Subtitles, cover, chapters and metadata are embedded in the MKV.
- **Resilient.** Temporary failures get an automatic retry, and errors come explained in plain English (or Portuguese).
- **Never downloads twice.** Every downloaded video goes into a history; next time it's skipped right away, without touching the site or the file — even if you've already moved it to another folder.

## Installation

```bash
git clone https://github.com/Canela-san/GrabIt.git
cd GrabIt
bash grabit.sh --install
```

On Debian, Ubuntu, Pop!_OS and derivatives, with `apt`:

```bash
curl -fsSL https://canela-san.github.io/GrabIt/grabit.gpg | sudo tee /usr/share/keyrings/grabit.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/grabit.gpg] https://canela-san.github.io/GrabIt stable main" | sudo tee /etc/apt/sources.list.d/grabit.list
sudo apt update
sudo apt install grabit
grabit install
```

After that, GrabIt updates along with the rest of the system: `sudo apt update && sudo apt upgrade`. `grabit install` brings the newest yt-dlp, since apt's tends to lag behind, and `grabit update` keeps taking care of it, Deno and FFmpeg.

Or, without Git, just the newest published version:

```bash
mkdir -p ~/.local/share/grabit
curl -fsSL https://github.com/Canela-san/GrabIt/releases/latest/download/grabit.sh -o ~/.local/share/grabit/grabit.sh
bash ~/.local/share/grabit/grabit.sh --install
```

On macOS, with Homebrew: `brew tap Canela-san/grabit https://github.com/Canela-san/GrabIt && brew trust canela-san/grabit && brew install grabit`. On Arch Linux, there's a `PKGBUILD` in [`packaging/aur`](packaging/README.md).

`--install` checks what's missing and shows the plan before doing anything. What's essential is FFmpeg and yt-dlp, through your system's package manager (apt, dnf, pacman, zypper, apk or Homebrew) and `pipx`, and the `grabit` command in `~/.local/bin`. What only improves what GrabIt can do is asked about, one by one:

| Optional | What for | If you just press Enter |
|---|---|---|
| Deno | YouTube requires a JavaScript runtime to unlock the best resolutions (only offered if there's none that yt-dlp accepts) | installs |
| `curl-cffi` | impersonate a browser when a site blocks automated downloads | installs |
| aria2 | download direct files over several connections | installs |
| `wl-clipboard` or `xclip` | capture copied links (`-C`) and read the copied cURL | installs |
| Firefox | sites that only work in a browser (only offered if you have no compatible one) | **doesn't install** |

To install without questions, use `grabit install -y` (or `--yes`): it installs everything. A browser only goes in if the computer has no compatible one, and then only Firefox. Any other browser, only on request: `grabit install chrome` (or `chromium`, `brave`, `edge`, `firefox`).

To put everything on the newest version in one go:

```bash
grabit update
```

It updates GrabIt, yt-dlp with its dependencies, Deno and FFmpeg (the latter through your system's package manager, asking for the password only if there's a new version) and installs whatever is missing, without asking. It just doesn't install a browser.

All commands work in English and Portuguese, with or without the dashes: `grabit update`, `grabit atualizar`, `grabit --update` and `grabit --atualizar` are the same thing. The same goes for `install`/`instalar`, `version`/`versao`, `check`/`verificar`, `list`/`lista` and `help`/`ajuda`. Only a link file named like a command needs `./` in front of it (`grabit ./update`).

GrabIt itself comes from the **newest published version**, which already passed all the tests, and the downloaded file is checked before replacing the script (SHA-256 checksum and signature). What changed in each version is in the [CHANGELOG](CHANGELOG.md). To follow everything that lands in the repository, as soon as it does, use `CANAL_ATUALIZACAO=main` in `grabit.config`.

To see the installed version, whether there's a newer one and what GrabIt is using (yt-dlp, FFmpeg, JavaScript runtime):

```bash
grabit --version
```

<details>
<summary>Manual installation</summary>

| Program | What for | How to install |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | the download engine | `pipx install "yt-dlp[default,curl-cffi]"` |
| [FFmpeg](https://ffmpeg.org) | merging video and audio, building the MKV, handling covers | `sudo apt install ffmpeg` · `brew install ffmpeg` |
| [Deno](https://deno.com) *(recommended)* | required by YouTube to unlock the best resolutions | see the website |
| Bash 4.4+ | running the script | ships with Linux · on macOS: `brew install bash` |

And, to use the `grabit` command from any folder:

```bash
mkdir -p ~/.local/bin
ln -s "$PWD/grabit.sh" ~/.local/bin/grabit
```

</details>

## Usage

Create a `links.txt` with one link per line:

```text
# comments and empty lines are ignored
https://www.youtube.com/watch?v=XXXXXXXXXXX
https://vimeo.com/XXXXXXXXX          # you can add notes at the end of a line
https://www.youtube.com/playlist?list=XXXXXXXXXXXXXXXX
```

And run it in the same folder:

```bash
grabit download
```

`grabit` on its own shows the help: the list only gets downloaded when you ask. To see all the options, use `grabit help full`.

Each link that finishes **changes section inside the same `links.txt`**: the ones downloaded successfully go to the `DOWNLOADED` section, at the end of the file, and the ones that failed go to the `FAILED` section, right above it. No other file is created: `links.txt` keeps everything. The line moves exactly as you wrote it, with your comment, and GrabIt only adds at the end a ✔ (or a ✖), the date and the video title (or the reason for the failure). `grabit download` skips both sections: it doesn't waste time on what's already done, nor does it keep insisting on what just failed. Whatever didn't even get downloaded (cancelled, postponed because the site asked to slow down, disk full) stays at the top, ready for next time.

```text
# comments and empty lines are ignored
https://vimeo.com/XXXXXXXXX          # this one hasn't been downloaded yet

# ==================== FAILED ====================
# Links that failed. GrabIt only tries again with: grabit download --retry
https://vimeo.com/YYYYYYYYY  # saturday's show  ✖ 2026-10-24 · private video
# ================ END OF FAILED ================

# ==================== DOWNLOADED ====================
# Successfully downloaded links. GrabIt ignores everything until the end of this section.
https://www.youtube.com/watch?v=XXXXXXXXXXX  # ✔ 2026-10-24 · Video title
https://www.youtube.com/playlist?list=XXXXXXXXXXXXXXXX  # ✔ 2026-10-24 · 12 videos · Lesson 1 and others
# ================ END OF DOWNLOADED ================
```

To try the failed ones again: `grabit download --retry`. It downloads the list at the top and the `FAILED` section; whatever works goes to `DOWNLOADED`, and whatever fails again stays in `FAILED`, with the new reason. The end of each run shows the right command to carry on.

Whatever comes after the last end line (`END OF DOWNLOADED`) counts as a link to download again, so appending to the end of the file works (`echo LINK >> links.txt`); next time, GrabIt moves those links up to the list at the top.

To move links between sections without digging through the file:

```bash
grabit list                    # the file by parts (to download, FAILED, DOWNLOADED), with the links numbered
grabit list back 3 5           # send links 3 and 5 back to the list to download, without the date and note
grabit list back failed        # send back everything in FAILED (or: downloaded, all)
grabit list downloaded 4       # mark as downloaded, without downloading (a LINK outside the file works too)
grabit list skip 2             # put it in FAILED: a normal download stops trying it
grabit list clear notes        # remove GrabIt's dates and notes; each link stays where it is
grabit list clear failed       # empty FAILED (asks first and keeps links.txt.bak)
grabit list clear downloaded   # empty DOWNLOADED (same)
grabit list tidy               # each part in its place, without repeated lines
grabit list edit               # open the file in your editor ($VISUAL, $EDITOR, nano or vim)
```

Moving a link between sections only touches what GrabIt wrote: the ✔ or the ✖, the date and the note. **Your comment stays as it was**, in any section, so you can keep recognizing the video by its link. For it to travel with the link, write it on the same line (`https://… # the wedding one`): a comment line on its own stays where it is. Use `-l FILE` for another link file (`grabit -l courses.txt list`). The video history doesn't change: to download again something already downloaded, run with `-i`.

> In Portuguese the sections are called `FALHARAM` and `BAIXADOS`; GrabIt recognizes both languages, so switching languages doesn't mess up your list.
>
> You can edit the file while GrabIt runs: it's read again at the end, and whatever you added isn't lost. Before rewriting it, GrabIt keeps a copy of how it was (`links.txt.grabit-bak`).

More examples:

```bash
grabit https://youtu.be/XXXXXXXXXXX          # links straight on the command line
grabit https://youtu.be/XXXXXXXXXXX -x       # options work before or after the links
grabit -l courses.txt -o ~/Videos/Courses    # another list, another folder
grabit -j 4 -c 8                             # 4 videos at a time, 8 connections each
grabit -b firefox                            # use the browser's login (restricted videos)
grabit -x -l songs.txt -o ~/Music            # audio only, at the best quality
grabit -d                                    # sort into folders: Downloads/site/channel/
grabit -C                                    # copy links in the browser and they get downloaded
cat list.txt | grabit -l -                   # read links from standard input
```

### While downloading

| Key | What it does |
|---|---|
| <kbd>p</kbd> | pauses everything (running downloads freeze) and resumes |
| <kbd>q</kbd> | stops after the current downloads; the remaining ones stay in the list to download. Again: cancels right away |
| <kbd>+</kbd> / <kbd>-</kbd> | raises or lowers how many videos download at once |
| <kbd>Ctrl</kbd>+<kbd>C</kbd> | cancels right away; large direct files pick up where they stopped next time, and the rest starts over |
| <kbd>Ctrl</kbd>+<kbd>Z</kbd> | suspends and gives the terminal back; `fg` continues where it stopped |

### Options

| Option | What it does | Default |
|---|---|---|
| `-l FILE` | file with the links (`-` = standard input) | `links.txt` |
| `-o FOLDER` | folder where videos are saved | `./Downloads` |
| `-j N` | simultaneous downloads | `4` |
| `-c N` | connections per video, regulated per site (see [Several connections](#how-it-works)) | `3` |
| `-O`, `--original` | keeps the site's format: `.mp4` stays `.mp4` | — |
| `-e FORMAT`, `--format` | saves in this format: `mkv`, `mp4`, `webm`, `mov`… | `mkv` |
| `-k CODEC`, `--codec` | re-encodes if the video comes in another one: `h264`, `hevc`, `av1`, `vp9`, `mpeg4` | — |
| `-q VALUE`, `--quality` | when re-encoding: `high`, `medium`, `low` or the CRF number (lower is better) | `high` |
| `--gpu[=NAME]`, `--placa` | when re-encoding, use the graphics card: `nvenc`, `vaapi`, `qsv`, `videotoolbox`; with no name, whichever there is | CPU |
| `-r HEIGHT` | maximum resolution (`720`, `1080`, `2160` or `4k`…) | no limit |
| `-F` | force: ignore the `grabit.config` limits and the automatic per-site pace for this run | — |
| `-y` | with `install`: install everything without asking | — |
| `-b BROWSER` | use the browser's cookies (`firefox`, `chrome`, `brave`…) | — |
| `--proxy URL` | send everything through a proxy: `http://host:8080` or `socks5://host:1080` | — |
| `--simulate` | show what would be downloaded and its size, without downloading | — |
| `--retry` | also try again the links in the `FAILED` section | — |
| `--details` | also show the tools, resources and history at the start | — |
| `--since DATE` | only videos since the date (`2026-01-31`) or the age (`7d`, `2w`, `3m`, `1y`) | — |
| `--max N` | at most N videos per link | — |
| `--max-size SIZE` | skip files larger than that (`2G`, `500M`) | — |
| `-A AGENT` | use the browser's User-Agent, along with `-b`, on sites with a check | — |
| `-p` | if the link is a video inside a playlist, download just the video | — |
| `-x` | audio only: the best track, in its original format, no re-encoding | — |
| `-d` | sort into subfolders by site and channel: `Downloads/youtube.com/Channel/` | — |
| `-f` | live queue: after the list, stays open downloading whatever you add to the link file | — |
| `-U` | upgrade: check videos already downloaded and replace those that have a better version on the site today | — |
| `-C` | capture: while GrabIt is open, every link you copy joins the queue (and is written to `links.txt`) | — |
| `-m` | lay out for Jellyfin, Plex and Kodi: `Channel/Season 2026/`, with `.nfo` and cover alongside | — |
| `-u` | on pages with several videos (previews, related…), download only the main one: the longest | — |
| `-a` | include automatic subtitles (manual ones still take priority) | — |
| `-s` | mark sponsors and intros as chapters ([SponsorBlock](https://sponsor.ajay.app)) | — |
| `-i` | ignore the download history and check file by file | — |
| `-v` | full check: decode every video end to end looking for defects | — |
| `-L pt\|en` | language of the messages: Portuguese or English | the system's |
| `-h` | show the help (`grabit -L en -h` shows it in English) | — |

### Follow channels

```bash
grabit channels add https://www.youtube.com/@channel/videos   # from today on
grabit channels add LINK --since 30d                          # or since a date; --all, the whole channel
grabit channels download -d                                   # download only what's new
grabit channels                                               # the list
grabit channels remove 2
```

By default, a channel you add only brings what comes out **from today on**, so the first time doesn't download years of videos. The search stops at the first video already in the history, or the first one older than the channel's date: hardly any requests to the site when there's nothing new. It also works for playlists and other links with several videos.

To run it on its own, with the phone notification from `NTFY_TOPICO`, use cron. The folder must be a full path:

```bash
0 8 * * * grabit channels download -d -o "$HOME/Videos/Channels"
```

### Difficult sites

If the video plays in a browser, you can download it, even on sites with an anti-bot check (like Cloudflare's) or a JavaScript player, where yt-dlp alone can't find the video. You still just run `grabit LINK`:

```bash
grabit 'site.com/player?season=7&episode=1'
```

> If the link has `&` or `?`, put it in quotes (the terminal reads those symbols differently) or use `links.txt`.

**GrabIt opens the browser by itself.** When a page only works in a browser, a window opens on it, GrabIt reads the video's request from the browser's own log, closes the window and downloads. If a check shows up, it's yours to do in the window: it's kept in a profile just for GrabIt (your regular browser doesn't change), so the next links tend to go straight through while it lasts. If the video doesn't start by itself, press play. Whatever is already installed works (Firefox, Chrome, Chromium, Brave, Edge, Vivaldi or Opera; to choose, use `PROGRAMA_NAVEGADOR`). With `USAR_NAVEGADOR=0`, the window never opens. Without any browser, you still have the two paths below.

**Use the browser's session.** Open the page, pass the check and run:

```bash
grabit -b firefox LINK
```

Sites with a check tend to accept the cookies only along with the User-Agent of the browser where you passed it (in Firefox, it's shown in `about:support`). Keep both in `grabit.config`, as `COOKIES_NAVEGADOR` and `USER_AGENT`, so you don't have to repeat them:

```bash
grabit -b firefox -A "Mozilla/5.0 (…)" LINK
```

**Copy the video's request.** It also works when yt-dlp doesn't recognize the page:

1. Open the page and press play.
2. Hit <kbd>F12</kbd>, go to the **Network** tab and filter by `m3u8` (or `mp4`). If there's more than one, choose the `master`: it points to both the video and the audio.
3. Right-click the request and choose **Copy as cURL**.
4. Run the command below, which reads the clipboard:

```bash
grabit curl
```

If you prefer, paste the copied command after `grabit` (GrabIt's options go before `curl`) or use `grabit curl FILE`:

```bash
grabit -o ~/Videos curl 'https://…/master.m3u8' -H 'Referer: https://…'
```

The copied command is only read, never executed. The file name comes from the page or, if the browser doesn't tell it, from the video's path. These links tend to expire: if it fails, copy it again. DRM-protected videos aren't downloaded.

## Configuration

Defaults live in **`grabit.config`**, next to `grabit.sh`. It's created on the first run, in your language, with every option commented out: to change one, remove the `#` at the start of the line and edit the value.

```ini
# grabit.config
IDIOMA=en
PASTA_SAIDA=~/Videos/GrabIt
DOWNLOADS_SIMULTANEOS=3
COOKIES_NAVEGADOR=firefox
```

| Key | What it does | Default |
|---|---|---|
| `IDIOMA` | language of the messages: `pt`, `en` or `auto` (follows the system) | `auto` |
| `ARQUIVO_LINKS` | the list that `grabit download` downloads | `links.txt` |
| `PASTA_SAIDA` | where videos are saved | `./Downloads` |
| `RESOLUCAO_MAXIMA` | maximum resolution (`1080`, `2160`, `4k`…); `0` = no limit | `0` |
| `SO_AUDIO` | `1` downloads only the audio (same as `-x`) | `0` |
| `FORMATO_AUDIO` | `original` (no re-encoding) or `mp3`, `m4a`, `aac`, `opus`, `flac`, `wav`, `alac`, `vorbis` | `original` |
| `RESOLUCAO_ALERTA` | warn when the best version available is below this; `0` = never | `720` |
| `DOWNLOADS_SIMULTANEOS` | videos at the same time | `4` |
| `CONEXOES_POR_VIDEO` | connections per video (each site's pace may lower it) | `3` |
| `TENTATIVAS` | attempts per link (`1` = don't retry) | `2` |
| `LIMITE_POR_SITE` | maximum downloads at once from the same site (`0` = automatic) | `0` |
| `PAUSA_ENTRE_VIDEOS` | seconds of pause before each video, with random variation | `0` |
| `LIMITE_VELOCIDADE` | maximum speed per download, like `5M` or `500K` (`0` = no limit) | `0` |
| `IDIOMAS_LEGENDAS` | subtitle languages (`all` = every one) | `pt.*,en.*` |
| `LEGENDAS_AUTOMATICAS` | `1` includes automatic subtitles | `0` |
| `SPONSORBLOCK` | `1` marks sponsors and intros as chapters | `0` |
| `SEM_PLAYLIST` | `1` downloads just the video when the link also has a playlist | `0` |
| `VERIFICAR` | `1` runs the full check on every download (same as `-v`) | `0` |
| `SO_PRINCIPAL` | `1` downloads only the main video of pages with several videos (same as `-u`) | `0` |
| `COOKIES_NAVEGADOR` | browser whose login will be used | — |
| `USER_AGENT` | that browser's User-Agent (see [Difficult sites](#difficult-sites)) | — |
| `OPCOES_YTDLP` | extra options for yt-dlp, separated by spaces (e.g. `--force-ipv4`) | — |
| `USAR_NAVEGADOR` | `1` opens a browser when a page only works in one; `0` never opens it | `1` |
| `PROCURAR_ARQUIVO` | `1` looks for a direct file better than the stream before downloading; `0` doesn't | `1` |
| `FORMATO_SAIDA` | file format: `mkv`, `mp4`, `webm`, `mov`…, or `original` (as the site delivers it) | `mkv` |
| `FILTRO_DESDE`, `FILTRO_MAX`, `FILTRO_TAMANHO` | the same as `--since`, `--max` and `--max-size` | — |
| `TEMA` | colors: `auto`, by the terminal's background; `claro` (light) or `escuro` (dark), if it gets it wrong | `auto` |
| `PROXY` | send everything through a proxy, including the direct-file search and the browser | — |
| `CANAL_ATUALIZACAO` | `estavel` (stable): published versions only; `main`: everything that lands in the repository | `estavel` |
| `CODEC_VIDEO` | re-encodes if the video comes in another codec: `h264`, `hevc`, `av1`, `vp9`, `mpeg4` | — |
| `QUALIDADE_VIDEO` | quality when re-encoding: `alta` (high), `media` (medium), `baixa` (low) or the CRF number | `alta` |
| `ACELERACAO_VIDEO` | who re-encodes: `cpu`, `auto`, `nvenc`, `vaapi`, `qsv`, `videotoolbox` | `cpu` |
| `PROGRAMA_NAVEGADOR` | which browser to open (e.g. `google-chrome`); empty = the first one found | — |
| `USAR_HISTORICO` | `0` turns off the download history | `1` |
| `NOTIFICAR` | bell and desktop notification at the end of batches of 1 min or more (`0` = silence) | `1` |
| `NTFY_TOPICO` | [ntfy](https://ntfy.sh) topic (or your own server's URL) to notify your phone | — |

The keys keep their original (Portuguese) names in both languages, so the same `grabit.config` works whichever language you use.

Priority is: **`grabit.config` < environment variable < command-line option**. That way you can change something just once without editing the file:

```bash
DOWNLOADS_SIMULTANEOS=4 grabit    # only for this run
grabit -j 4                       # same, through the option
grabit --config                   # show the values in use and where each one came from
```

The file stays out of Git (`.gitignore`), so updating GrabIt never touches your settings. To go back to the defaults, just delete it: it's recreated.

### Per-site profiles

A section named after the site, at the end of `grabit.config`, applies only to its links:

```ini
[youtube.com]
RESOLUCAO_MAXIMA=1080
COOKIES_NAVEGADOR=firefox

[cnbr.space]
CONEXOES_POR_VIDEO=1
PAUSA_ENTRE_VIDEOS=3
```

These work: `RESOLUCAO_MAXIMA`, `COOKIES_NAVEGADOR`, `USER_AGENT`, `LIMITE_VELOCIDADE`, `CONEXOES_POR_VIDEO`, `LIMITE_POR_SITE`, `PAUSA_ENTRE_VIDEOS`, `IDIOMAS_LEGENDAS` and `OPCOES_YTDLP`. An option on the command beats the profile, and `-F` ignores its limits. `grabit --config` shows the profiles in use.

### Maximum resolution

Want to save space? With `RESOLUCAO_MAXIMA=1080` GrabIt downloads the **best version up to 1080p** of each video — still picking the best codec, frame rate and audio within the limit. The limit applies to the shorter side of the picture, so a 1080×1920 vertical video counts as 1080p. If a video has no version within the limit, it isn't downloaded: it shows up as a failure, with a notice, and goes to the `FAILED` section.

For an exception, use `-F` (force): it ignores the `grabit.config` limits for that run only. And `-r` sets a limit for a single run, without touching the file.

```bash
grabit -r 720                       # just this time, up to 720p
grabit download --retry -F          # download the ones left out, at maximum quality
```

> Videos downloaded with a limit go into the history as usual. To replace them later with the best version, run `grabit -U -F`.

### Being nice to sites

Some sites block whoever downloads many videos in a row. GrabIt already takes care of this by itself: it spreads downloads across sites and adjusts each one's pace (see [How it works](#how-it-works)). To go even slower on purpose:

```ini
LIMITE_POR_SITE=1        # one video at a time from each site (other sites keep going in parallel)
PAUSA_ENTRE_VIDEOS=10    # a ~10 to 15 s pause before each video
LIMITE_VELOCIDADE=5M     # at most 5 MB/s per download
```

The header shows the limits in use, and `-F` turns all of them (and the maximum resolution) off for a run, along with the slow start and the interval of the automatic pace. A site's request to slow down (429) still counts.

There are also `ARQUIVO_HISTORICO` (where the download history lives) and `NO_COLOR` (turns colors off), as environment variables only.

### Quality: what to expect

GrabIt downloads **the best version the site delivers**, without recompressing it. That is usually the same as or better than what the player picks in the browser, which lowers the quality to fit the connection and the window size.

The file the uploader sent is almost never available to anyone: big sites recompress the video when they receive it, and that is the version everybody watches. So, compared to the original upload, the copy may be inferior; the loss happened on the site, not in the download.

A stream doesn't mean lower quality: it is video split into pieces. And a direct file (`.mp4`, `.mkv` or another) doesn't mean original: it is often a lighter version, and the address doesn't say which. That's why GrabIt measures both before choosing ([Direct file](#how-it-works)). It doesn't see what only shows up with the video playing in a browser, unless the page itself requires the browser.

### File format

With no option, everything ends up in **MKV**, which holds it all: thumbnail, subtitles of any kind, chapters and the site's data. The picture and sound are the same the site delivers. The one detail is that MKV stores each frame's time rounded to the millisecond (at 24 fps, 41 or 42 ms instead of 41.667), like the vast majority of MKV files out there, including those made with `mkvmerge`.

```bash
grabit LINK -O            # keeps the site's format: .mp4 stays .mp4, with each frame's exact time
grabit LINK -e mp4        # saves as .mp4 (also: webm, mov, avi, ts, flv…)
grabit LINK -k h264       # re-encodes to H.264 if the video comes in another codec
grabit LINK -k h264 -e mp4
```

With `-O` and `-e`, metadata goes in if the format accepts it, and the summary reports what didn't fit. `.mp4` holds title, description, date, channel, chapters, thumbnail and subtitles. Only MKV holds the site's data (`info.json`), which `grabit check` uses to find incomplete videos and offer to download them again. In other formats, a thumbnail and subtitles that don't fit are left beside the video. To make a format the default, set `FORMATO_SAIDA` in `grabit.config`.

With `-k`, GrabIt prefers the site's version already in that codec, at the highest resolution there is, and only re-encodes if there is none: after everything is downloaded, one video at a time. Combine it with `-r 1080` to avoid re-encoding a 4K video when the site has the 1080p one in the requested codec.

### Converting a downloaded video

```bash
grabit convert video.mkv -e mp4             # changes the extension, without re-encoding
grabit convert Downloads -e mp4 --replace   # the whole folder, without keeping the originals
grabit convert video.mp4 -k h264            # re-encodes: becomes video.h264.mp4
grabit convert video.mkv -k hevc -q medium       # smaller file, slightly less quality
grabit convert video.mkv -k h264 --gpu           # on the graphics card: much faster, larger file
```

**Changing the extension doesn't touch the quality**, however many times you do it: picture and sound are copied, bit by bit. What changes is what each format can hold. GrabIt keeps all that fits, removes only what is strictly necessary and reports what was left out. Going from MKV to `.mp4` or `.mov`, it also restores each frame's exact time, if the video has a constant frame rate. Some pairs don't exist without re-encoding, such as H.264 in `.webm`: it explains that, and `-k` solves it.

**Re-encoding always loses a little quality** and can take a long time, but sometimes it is the only way to play the video on a certain device. The original only goes away with `--replace`, and never before the new file is checked. A video already in the requested codec is left alone.

The **graphics card** (`--gpu`) is much faster, but for the same quality the file comes out larger. Before using it, GrabIt runs a brief test: with no card, or if it can't do that codec, it warns and carries on with the CPU. An **HDR** video re-encoded to H.264 or MPEG-4 has its colors converted to SDR, so they don't look washed out.

### Compare two videos

```bash
grabit compare video-av1.mp4 video-h264.mp4
```

It says how much two files of the same video differ to the eye, instead of just comparing bitrates: it measures 5 segments of 10 s with VMAF, if your ffmpeg has `libvmaf`, or with SSIM and PSNR. The reference is the file with more data, and the result says how far the other one is from it and how much space it saves. Since it needs both files, this measure isn't part of the automatic choice of what to download.

## A summary at the end

<p align="center">
  <img src="assets/resumo-en.png" alt="GrabIt final summary" width="860">
</p>

| Symbol | Meaning |
|---|---|
| ✔ | downloaded now |
| ↷ | had already been downloaded (by the history or because the file was already in the folder), skipped |
| ✖ | failed, with the reason explained right below |
| ⚠ | the video is complete, but some detail failed (e.g. converting the cover) |
| ▾ | downloaded, but the best version the site offered was below `RESOLUCAO_ALERTA` (sometimes, logged in with `-b`, there's more) |

Links from the list that failed go to the `FAILED` section of the link file itself, with the reason, and GrabIt shows the command to try again (`grabit download --retry`). Links passed straight on the command line have no file to stay in: they come back in the suggested command.

## How it works

- **Format:** yt-dlp's `bv*+ba/b` (best video + best audio) with **MKV** output, which accepts any codec. Nothing is re-encoded: the picture is the same the site delivers, frame by frame, with one detail: MKV stores each frame's time rounded to the millisecond ([File format](#file-format)).
- **Several connections:** for video split into pieces (HLS/DASH), yt-dlp itself opens the connections. For a single file, it only uses one, and what opens more is [aria2](https://aria2.github.io) (optional: `grabit install` offers it). With 3 connections, a real site delivered 3 times more. The number is regulated per site: files under 40 MB aren't split; downloads from the same site add up to at most twice `-c`; if the site refuses the extra connections, the download finishes on the ones left, losing nothing, and the next ones use only one; a site that asked to slow down gets only one. Since more connections aren't always faster, after a few seconds a probe compares them with a single plain connection and, if that delivers over twice as much, the download carries on without aria2. YouTube, which throttles large requests, always goes through yt-dlp. `-c 1` turns it off.
- **Direct file:** before downloading a stream (HLS/DASH), GrabIt looks for a video file in the site's offer and in the page itself, including scripts and download buttons: `.mp4`, `.mkv`, `.webm`, `.mov`, `.avi`, `.wmv`, `.flv`, `.mpg`, `.ts` and others, plus a `<video>` or download button with no extension in its address. It measures up to 4 candidates with `ffprobe`, starting with whatever the name promises to be the original or the highest resolution. It switches if it is the same video (same duration), has audio and is better in resolution or fps. With the same picture, the file wins unless it is clearly lighter (under 75% of the stream's bitrate, allowing for the difference between codecs): it may be the original the stream came from, and it is one download instead of hundreds of pieces. If the page doesn't open in yt-dlp, the search comes before opening a browser. A file mentioned only in the page comes without what only the site provides (thumbnail, subtitles, channel). On a site where nothing turns up three times in a row, the search stops until the next run. `PROCURAR_ARQUIVO=0` turns it off; `-x`, `-u`, `-m` and `grabit curl` don't search.
- **Temporary files** live in `Downloads/.parciais` only while GrabIt runs; the final, finished file goes to the folder. A direct file of 50 MiB or more that didn't finish (<kbd>Ctrl</kbd>+<kbd>C</kbd>, error, power cut) **picks up where it stopped** next time, if it is still the same on the site (GrabIt checks its size and version tag; this needs aria2c). Interrupted files stay in `Downloads/.parciais/retomar` for up to 14 days. A stream **starts over from scratch**: resuming its pieces can leave holes in the video, and here quality comes before speed. The links that were still pending stay in the list to download.
- **The list of links is rewritten all at once**, with a lock so two open GrabIts can't erase what the other just saved and a copy of how it was in `links.txt.grabit-bak`. A video passed as a list by mistake is refused: only text gets rewritten.
- **Cascade of attempts:** each link starts with the fastest way and only climbs if it has to: **1)** direct; **2)** with the `Referer`, impersonating a browser when `curl-cffi` is installed and with the adjustment for the error (IPv4 on network failures, one connection at a time on refused pieces, slower on 429); **3)** through the browser, if the page only works in one. Errors nothing can fix (private, removed video, 404) stop right away.
- **The cascade remembers:** the step that worked on each site is kept (in `~/.local/share/grabit/metodos.txt`), and the site's next links start right there. On a long list, this avoids repeating on every link a path already known to fail. The memory expires in 30 days and drops if the method stops working.
- **Spreading across sites:** GrabIt looks at the whole list and sorts the links by site. Each slot goes to the site with the fewest downloads running and, on a tie, to the one with the most links waiting. With 4 slots and 4 sites, it's one of each: a site's links don't pile up just because they came together in the list. While the browser window is busy, links from other sites go ahead.
- **Protection against blocks:** each site starts with a single download and goes up by one for each one it accepts (it's enough for the download to start arriving), with a small interval between starts. If a site asks to slow down (429), its limit is cut in half and it gets no new requests for 30 s, then 60, 120… up to 10 min, while the others carry on; the link waits along with it, without using up an attempt. After 4 requests to slow down, or 3 links in a row refused, that site's remaining links are left for later (they stay in the list to download), and the summary shows how many were postponed. The wait also applies to the next run.
- **Speed:** 4 videos at a time by default. Pieces refused several times in a row (401, 403, 404, 410) end the attempt in seconds, instead of holding the slot for minutes. When you know the site can take it, `-F` skips the slow start and the interval.
- **Progress saved:** every minute, the links that finished go to the `DOWNLOADED` section (or `FAILED`). If the power goes out in the middle of a long list, next time it picks up where it left off. Permanent errors (private, removed video, 404) aren't retried.
- **Disk full:** the header warns you when the destination folder has less than 2 GiB free. If the disk fills up midway, no new download starts (the next ones wouldn't fit either) and the links still pending stay in the list to download.
- **History:** every downloaded video is recorded in `Downloads/.grabit-historico.txt` (site + video ID). Next time it's skipped before anything else: on most sites GrabIt doesn't even need to open the page. Without the history, yt-dlp would open the page again, download the cover and rewrite the whole file just to conclude it already exists. Videos downloaded before the history existed go through that check only once and are added to it.
- **Live queue (`-f`):** after finishing the list, GrabIt stays open and checks the link file every 2 seconds: whatever you add (at the top or at the end of the file) joins the queue and starts downloading. When the queue empties, the downloaded links go to the `DOWNLOADED` section and, if the batch took a while, the completion notice arrives. Quit with <kbd>q</kbd> or <kbd>Ctrl</kbd>+<kbd>C</kbd>. It only happens with the option: without `-f`, GrabIt always closes when done.
- **Checking the collection (`grabit --check [FOLDER]`):** decodes, from start to end, every video and audio file already in the downloads folder (or the folder given) and compares its duration with the one recorded in the `info.json` GrabIt embeds in MKVs — so it finds defective files and incomplete downloads, old ones included. At the end, it offers to download the problem ones again: the current file is kept with `.with-errors` in its name, the video leaves the history and the link (kept in that same `info.json`) is downloaded again, in the same folder layout (`-d` or `-m`).
- **Upgrade (`-U`):** for each link in the list — including the ones in the `DOWNLOADED` section —, compares the best version the site offers today with the file already in the folder (found by the `[id]` in its name). It only downloads again what got better: higher resolution, or the same one with more frames per second or HDR. The old file is only deleted after the new one arrives complete; if the download fails or is cancelled, it comes back. Videos you moved out of the folder are skipped. Handy after downloading with a resolution limit, or when a site starts offering 4K.
- **Clipboard capture (`-C`):** while GrabIt is open, every link you copy (<kbd>Ctrl</kbd>+<kbd>C</kbd> in the browser) is written to the end of `links.txt` and joins the queue — it works like the live queue. Whatever was already copied before it opened and text without links are ignored. Nothing keeps running in the background: once GrabIt closes, the capture is over. It uses `wl-paste` (Wayland), `xclip` or `xsel` (X11), `pbpaste` (macOS) or PowerShell (WSL).
- **Jellyfin, Plex and Kodi (`-m`):** each channel becomes a show, with one season per year and episodes named by date (`Channel/Season 2026/Channel - 2026-10-24 - Title [id].mkv`), a format all three recognize. Next to each video go the cover and an `.nfo` with title, date and description, and in the channel folder a `tvshow.nfo`. Point a *Shows* library at the downloads folder. It only happens with the option, and it takes priority over `-d`.
- **Audio only (`-x`):** downloads the best sound track and keeps it in the format the site delivers (opus, m4a…), without re-encoding, with cover, chapters and metadata. With `FORMATO_AUDIO=mp3` (or another one), it converts at the best quality. The audio history is separate (`.grabit-historico-audio.txt`): having downloaded the video doesn't stop you from downloading the audio, and vice versa.
- **Full check (`-v`):** after downloading, ffmpeg decodes the whole video, frame by frame, with the progress on the panel. Any defect fails the file: it doesn't go into the history, it's kept with `.with-errors` in its name and the video is downloaded again from scratch. If the defect comes from the site itself and happens again, the link goes to the `FAILED` section. It guarantees a flawless file, at the cost of CPU and time.
- **Main video (`-u`):** when a page has several videos, GrabIt first checks each one's duration (from the site or, if it doesn't say, by reading just the video's header) and downloads only the longest — previews and related videos tend to be short. Links with a single video skip this step. Don't use it with playlists and channels: they'd also yield a single video.
- **Logs:** yt-dlp's full output for every link with a problem is kept in `Downloads/logs/<date>/`.
- **Terminal:** the panel adapts to the window width (even if you resize it midway), aligns titles with emoji and Asian characters and, if the output is redirected to a file, swaps the panel for plain lines without colors.

## Tips

- **Keep yt-dlp up to date** (`grabit --update`): sites change all the time. GrabIt warns you when the installed version is old.
- **Warning about the JavaScript runtime?** yt-dlp only accepts recent versions: an old Node.js is refused, and Bun can be too new. `grabit --version` shows what's in use, and the safest one is Deno, which `grabit --install` installs when no other is accepted.
- **Video asks for a login or age confirmation?** Use `-b firefox` (or the browser you're logged in with).
- **Left it downloading and walked away?** With `NTFY_TOPICO=a-hard-name` in `grabit.config` and the [ntfy](https://ntfy.sh) app subscribed to the same topic, your phone tells you when the batch is done. Only the summary goes out (how many downloaded and how many failed), never links or titles.
- **Retry what failed:** `grabit download --retry`.
- **Deleted a video and want it again?** Run with `-i` (ignores the history) or delete its line in `Downloads/.grabit-historico.txt`.

## Common problems

| What you see | What to do |
|---|---|
| `HTTP Error 403` on some links | GrabIt already tries other ways. If it goes on, use the cookies of the browser you are logged in to: `-b firefox` |
| `Sign in to confirm`, asks for login or age | `-b firefox` (or the browser you are logged in to) |
| `HTTP Error 429` or "the site asked to slow down" | The site limited the requests. GrabIt waits on its own and goes slower; on a huge list, use `LIMITE_POR_SITE=1` and `PAUSA_ENTRE_VIDEOS=5` |
| A browser window opened | The page only works in a browser. If a check shows up, you do it, in the window. To never open one: `USAR_NAVEGADOR=0` |
| It only downloads in low resolution | Look for `-r` or `RESOLUCAO_MAXIMA` in `grabit --config`. On YouTube, a JavaScript runtime is missing: `grabit install` |
| The video won't play on the TV or phone | Change the container (`grabit convert video.mkv -e mp4`) and, if that's not enough, the codec (`-k h264`) |
| `No space left on device` | Free up space and run it again: only what's missing is downloaded. Interrupted files stay in `Downloads/.parciais/retomar` |
| yt-dlp stopped working on a site | `grabit update`: sites change all the time. If it goes on, see the log in `Downloads/logs` |
| `grabit: command not found` | Open another terminal. If it goes on, add `~/.local/bin` to your `PATH` |

### Exit codes

For use in scripts:

| Code | Meaning |
|---|---|
| `0` | all good |
| `1` | some link or file failed (the ones from the list stay in the `FAILED` section) |
| `2` | wrong command or value: nothing was done |
| `130` | cancelled with <kbd>Ctrl</kbd>+<kbd>C</kbd> |

### Uninstall

```bash
grabit uninstall
```

It shows the list of what it will delete and asks for confirmation. Your videos, lists and histories stay. So do yt-dlp and FFmpeg, because other programs may use them.

## Tests

```bash
bash testes/rodar.sh            # all of them: starts a local server and downloads videos made by ffmpeg
bash testes/rodar.sh --rapido   # downloads nothing: options, configuration, translations and the flow with a fake yt-dlp
```

Nothing leaves your machine: the test videos are created on the spot and served on `127.0.0.1`. On every push, GitHub Actions runs the full tests on Ubuntu, the quick ones on macOS and Bash 4.4, the whole `apt` path and ShellCheck. Before publishing a version, macOS runs the full tests too, and it only goes out if everything passes. Sections run in parallel, and the panel tests run in a real terminal (a pseudo-terminal), with keys actually pressed.

## Disclaimer

GrabIt is just a tool. Only download content you have the right to download, and respect each site's terms of use and your country's copyright law.

## Credits

Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [FFmpeg](https://ffmpeg.org), which do the heavy lifting.

## License

Distributed under the [MIT license](LICENSE). You can use, copy, modify and redistribute GrabIt freely, including in commercial projects. The only condition is keeping the copyright notice, with credit to **Gabriel Canela ([Canela-san](https://github.com/Canela-san))**, in all copies or substantial portions of the code.

If GrabIt helped you, a link to this repository is always welcome too.
