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
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center">
  <a href="README.md">Português</a> · <strong>English</strong>
</p>

<p align="center">
  <img src="assets/demo.png" alt="GrabIt panel downloading several videos at once" width="860">
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

### 1. Dependencies

| Program | What for | How to install |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | the download engine | `pipx install "yt-dlp[default,curl-cffi]"` |
| [FFmpeg](https://ffmpeg.org) | merging video and audio, building the MKV, handling covers | `sudo apt install ffmpeg` · `brew install ffmpeg` |
| [Deno](https://deno.com) *(recommended)* | required by YouTube to unlock the best resolutions | see the website |
| Bash 4.4+ | running the script | ships with Linux · on macOS: `brew install bash` |

> `curl-cffi` lets GrabIt impersonate a browser when a site blocks automated downloads. It's optional, but recommended.

### 2. GrabIt

```bash
git clone https://github.com/Canela-san/GrabIt.git
cd GrabIt
chmod +x grabit.sh
```

To use the `grabit` command from any folder (and update with a simple `git pull`):

```bash
mkdir -p ~/.local/bin
ln -s "$PWD/grabit.sh" ~/.local/bin/grabit
```

GrabIt speaks Portuguese and English and follows your system's language. To pick one for good, set `IDIOMA=en` in `grabit.config` (see [Configuration](#configuration)), or use `-L en` for a single run.

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
grabit
```

Successfully downloaded links **leave the list and move to the `DOWNLOADED` section**, at the end of the same `links.txt`, exactly as you wrote them (notes included), with the date and the title of what was downloaded at the end of the line. Everything in that section is ignored: it becomes your link history, and GrabIt doesn't waste time reprocessing or listing what's already done. The ones that failed stay at the top, ready for next time.

```text
# comments and empty lines are ignored
https://vimeo.com/XXXXXXXXX          # this one failed and stays here

# ==================== DOWNLOADED ====================
# Successfully downloaded links. GrabIt ignores everything until the end of this section.
https://www.youtube.com/watch?v=XXXXXXXXXXX  # ✔ 2026-10-24 · Video title
https://www.youtube.com/playlist?list=XXXXXXXXXXXXXXXX  # ✔ 2026-10-24 · 12 videos · Lesson 1 and others
# ================ END OF DOWNLOADED ================
```

Whatever comes after the `END OF DOWNLOADED` line counts as a link to download again, so appending to the end of the file works (`echo LINK >> links.txt`); next time, GrabIt moves those links up to the list at the top.

> In Portuguese the section is called `BAIXADOS`; GrabIt recognizes both names, so switching languages doesn't mess up your list.
>
> You can edit the file while GrabIt runs: it's read again at the end, and whatever you added isn't lost. Want to download something from the section again? Move the line up and run with `-i` (see the history in [How it works](#how-it-works)).

More examples:

```bash
grabit https://youtu.be/XXXXXXXXXXX          # links straight on the command line
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
| <kbd>q</kbd> | stops after the current downloads; the remaining ones go to `links_falhos.txt`. Again: cancels right away |
| <kbd>+</kbd> / <kbd>-</kbd> | raises or lowers how many videos download at once |
| <kbd>Ctrl</kbd>+<kbd>C</kbd> | cancels right away; anything half-done starts over from scratch next time |

### Options

| Option | What it does | Default |
|---|---|---|
| `-l FILE` | file with the links (`-` = standard input) | `links.txt` |
| `-o FOLDER` | folder where videos are saved | `./Downloads` |
| `-j N` | simultaneous downloads | `2` |
| `-c N` | connections (fragments) per video | `4` |
| `-r HEIGHT` | maximum resolution (`720`, `1080`, `2160` or `4k`…) | no limit |
| `-F` | force: ignore the `grabit.config` limits for this run | — |
| `-b BROWSER` | use the browser's cookies (`firefox`, `chrome`, `brave`…) | — |
| `-p` | if the link is a video inside a playlist, download just the video | — |
| `-x` | audio only: the best track, in its original format, no re-encoding | — |
| `-d` | sort into subfolders by site and channel: `Downloads/youtube.com/Channel/` | — |
| `-f` | live queue: after the list, stays open downloading whatever you add to the link file | — |
| `-C` | capture: while GrabIt is open, every link you copy joins the queue (and is written to `links.txt`) | — |
| `-m` | lay out for Jellyfin, Plex and Kodi: `Channel/Season 2026/`, with `.nfo` and cover alongside | — |
| `-u` | on pages with several videos (previews, related…), download only the main one: the longest | — |
| `-a` | include automatic subtitles (manual ones still take priority) | — |
| `-s` | mark sponsors and intros as chapters ([SponsorBlock](https://sponsor.ajay.app)) | — |
| `-i` | ignore the download history and check file by file | — |
| `-v` | full check: decode every video end to end looking for defects | — |
| `-L pt\|en` | language of the messages: Portuguese or English | the system's |
| `-h` | show the help (`grabit -L en -h` shows it in English) | — |

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
| `ARQUIVO_LINKS` | list read when you run just `grabit` | `links.txt` |
| `PASTA_SAIDA` | where videos are saved | `./Downloads` |
| `RESOLUCAO_MAXIMA` | maximum resolution (`1080`, `2160`, `4k`…); `0` = no limit | `0` |
| `SO_AUDIO` | `1` downloads only the audio (same as `-x`) | `0` |
| `FORMATO_AUDIO` | `original` (no re-encoding) or `mp3`, `m4a`, `aac`, `opus`, `flac`, `wav`, `alac`, `vorbis` | `original` |
| `RESOLUCAO_ALERTA` | warn when the best version available is below this; `0` = never | `720` |
| `DOWNLOADS_SIMULTANEOS` | videos at the same time | `2` |
| `CONEXOES_POR_VIDEO` | connections per video | `4` |
| `TENTATIVAS` | attempts per link (`1` = don't retry) | `2` |
| `LIMITE_POR_SITE` | downloads at once from the same site (`0` = no limit) | `0` |
| `PAUSA_ENTRE_VIDEOS` | seconds of pause before each video, with random variation | `0` |
| `LIMITE_VELOCIDADE` | maximum speed per download, like `5M` or `500K` (`0` = no limit) | `0` |
| `IDIOMAS_LEGENDAS` | subtitle languages (`all` = every one) | `pt.*,en.*` |
| `LEGENDAS_AUTOMATICAS` | `1` includes automatic subtitles | `0` |
| `SPONSORBLOCK` | `1` marks sponsors and intros as chapters | `0` |
| `SEM_PLAYLIST` | `1` downloads just the video when the link also has a playlist | `0` |
| `VERIFICAR` | `1` runs the full check on every download (same as `-v`) | `0` |
| `SO_PRINCIPAL` | `1` downloads only the main video of pages with several videos (same as `-u`) | `0` |
| `COOKIES_NAVEGADOR` | browser whose login will be used | — |
| `USAR_HISTORICO` | `0` turns off the download history | `1` |
| `ARQUIVO_FALHAS` | where to save the links that failed | `links_falhos.txt` |
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

### Maximum resolution

Want to save space? With `RESOLUCAO_MAXIMA=1080` GrabIt downloads the **best version up to 1080p** of each video — still picking the best codec, frame rate and audio within the limit. The limit applies to the shorter side of the picture, so a 1080×1920 vertical video counts as 1080p. If a video has no version within the limit, it isn't downloaded: it shows up as a failure, with a notice, and goes to `links_falhos.txt`.

For an exception, use `-F` (force): it ignores the `grabit.config` limits for that run only. And `-r` sets a limit for a single run, without touching the file.

```bash
grabit -r 720                       # just this time, up to 720p
grabit -F -l links_falhos.txt       # download the ones left out, at maximum quality
```

> Videos downloaded with a limit go into the history as usual. To replace one with a bigger version later, delete the file and run with `-F -i`.

### Being nice to sites

Some sites block whoever downloads many videos in a row. For those, you can slow down:

```ini
LIMITE_POR_SITE=1        # one video at a time from each site (other sites keep going in parallel)
PAUSA_ENTRE_VIDEOS=10    # a ~10 to 15 s pause before each video
LIMITE_VELOCIDADE=5M     # at most 5 MB/s per download
```

The header shows the limits in use, and `-F` turns all of them (and the maximum resolution) off for a run.

There are also `ARQUIVO_HISTORICO` (where the download history lives) and `NO_COLOR` (turns colors off), as environment variables only.

## A summary at the end

<p align="center">
  <img src="assets/resumo.png" alt="GrabIt final summary" width="860">
</p>

| Symbol | Meaning |
|---|---|
| ✔ | downloaded now |
| ↷ | had already been downloaded (by the history or because the file was already in the folder), skipped |
| ✖ | failed, with the reason explained right below |
| ⚠ | the video is complete, but some detail failed (e.g. converting the cover) |
| ▾ | downloaded, but the best version the site offered was below `RESOLUCAO_ALERTA` (sometimes, logged in with `-b`, there's more) |

Links that failed go to `links_falhos.txt`, and GrabIt itself shows the command to retry just those. If they all succeed on the next run, the file is deleted automatically.

## How it works

- **Format:** yt-dlp's `bv*+ba/b` (best video + best audio) with **MKV** output, which accepts any codec. Nothing is re-encoded.
- **Temporary files** live in `Downloads/.parciais` only while GrabIt runs; the final, finished file goes to the folder. A download that didn't finish (<kbd>Ctrl</kbd>+<kbd>C</kbd>, error, network drop) **starts over from scratch** next time instead of resuming the pieces: resuming can leave holes in the video, and here quality comes before speed. The links that were still pending go to `links_falhos.txt`.
- **Retries:** temporary errors (network, 403, 429) go back to the end of the queue, impersonating a browser when `curl-cffi` is installed. Permanent errors (private, removed video, 404) aren't retried.
- **History:** every downloaded video is recorded in `Downloads/.grabit-historico.txt` (site + video ID). Next time it's skipped before anything else: on most sites GrabIt doesn't even need to open the page. Without the history, yt-dlp would open the page again, download the cover and rewrite the whole file just to conclude it already exists. Videos downloaded before the history existed go through that check only once and are added to it.
- **Live queue (`-f`):** after finishing the list, GrabIt stays open and checks the link file every 2 seconds: whatever you add (at the top or at the end of the file) joins the queue and starts downloading. When the queue empties, the downloaded links go to the `DOWNLOADED` section and, if the batch took a while, the completion notice arrives. Quit with <kbd>q</kbd> or <kbd>Ctrl</kbd>+<kbd>C</kbd>. It only happens with the option: without `-f`, GrabIt always closes when done.
- **Clipboard capture (`-C`):** while GrabIt is open, every link you copy (<kbd>Ctrl</kbd>+<kbd>C</kbd> in the browser) is written to the end of `links.txt` and joins the queue — it works like the live queue. Whatever was already copied before it opened and text without links are ignored. Nothing keeps running in the background: once GrabIt closes, the capture is over. It uses `wl-paste` (Wayland), `xclip` or `xsel` (X11), `pbpaste` (macOS) or PowerShell (WSL).
- **Jellyfin, Plex and Kodi (`-m`):** each channel becomes a show, with one season per year and episodes named by date (`Channel/Season 2026/Channel - 2026-10-24 - Title [id].mkv`), a format all three recognize. Next to each video go the cover and an `.nfo` with title, date and description, and in the channel folder a `tvshow.nfo`. Point a *Shows* library at the downloads folder. It only happens with the option, and it takes priority over `-d`.
- **Audio only (`-x`):** downloads the best sound track and keeps it in the format the site delivers (opus, m4a…), without re-encoding, with cover, chapters and metadata. With `FORMATO_AUDIO=mp3` (or another one), it converts at the best quality. The audio history is separate (`.grabit-historico-audio.txt`): having downloaded the video doesn't stop you from downloading the audio, and vice versa.
- **Full check (`-v`):** after downloading, ffmpeg decodes the whole video, frame by frame, with the progress on the panel. Any defect fails the file: it doesn't go into the history, it's kept with `.with-errors` in its name and the video is downloaded again from scratch. If the defect comes from the site itself and happens again, the link goes to `links_falhos.txt`. It guarantees a flawless file, at the cost of CPU and time.
- **Main video (`-u`):** when a page has several videos, GrabIt first checks each one's duration (from the site or, if it doesn't say, by reading just the video's header) and downloads only the longest — previews and related videos tend to be short. Links with a single video skip this step. Don't use it with playlists and channels: they'd also yield a single video.
- **Logs:** yt-dlp's full output for every link with a problem is kept in `Downloads/logs/<date>/`.
- **Terminal:** the panel adapts to the window width (even if you resize it midway), aligns titles with emoji and Asian characters and, if the output is redirected to a file, swaps the panel for plain lines without colors.

## Tips

- **Keep yt-dlp up to date** (`yt-dlp -U` or `pipx upgrade yt-dlp`): sites change all the time. GrabIt warns you when the installed version is old.
- **Video asks for a login or age confirmation?** Use `-b firefox` (or the browser you're logged in with).
- **Left it downloading and walked away?** With `NTFY_TOPICO=a-hard-name` in `grabit.config` and the [ntfy](https://ntfy.sh) app subscribed to the same topic, your phone tells you when the batch is done. Only the summary goes out (how many downloaded and how many failed), never links or titles.
- **Retry what failed:** `grabit -l links_falhos.txt`.
- **Deleted a video and want it again?** Run with `-i` (ignores the history) or delete its line in `Downloads/.grabit-historico.txt`.

## Disclaimer

GrabIt is just a tool. Only download content you have the right to download, and respect each site's terms of use and your country's copyright law.

## Credits

Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [FFmpeg](https://ffmpeg.org), which do the heavy lifting.

## License

Distributed under the [MIT license](LICENSE). You can use, copy, modify and redistribute GrabIt freely, including in commercial projects. The only condition is keeping the copyright notice, with credit to **Gabriel Canela ([Canela-san](https://github.com/Canela-san))**, in all copies or substantial portions of the code.

If GrabIt helped you, a link to this repository is always welcome too.
