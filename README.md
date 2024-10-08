<p align='center'>
<img width=300 src='/assets/images/logo.png'>  
</p>

# GrabIt! - Firefox Extension for Easy Video and Audio Downloads

GrabIt! is a Firefox extension designed to streamline the process of downloading videos, audio, and subtitles from a wide range of websites. It works by making a request to a web service that runs the powerful **yt-dlp** tool in the background, ensuring that you can download content in various formats and resolutions effortlessly.

## Features

- **Download Video** in multiple formats: MP4, MKV, WEBM, and more.
- **Extract Audio** as MP3, M4A, AAC, and other formats.
- **Subtitle Downloads**: Fetch and download subtitles in different languages.
- **Customizable Quality**: Download content in the best available quality, including 1080p, 4K, and even 8K.
- **Playlist and Channel Support**: Download entire playlists or channels with a single click.
- **Live Stream Support**: Grab live streams or recorded streams once the event ends.

## Supported Sites

GrabIt! supports downloading from a wide variety of websites, including but not limited to:

- **YouTube**
- **Vimeo**
- **Facebook**
- **Instagram**
- **Twitter**
- **TikTok**
- **Dailymotion**
- **Twitch**
- **SoundCloud**
- **Reddit**
- **MetaCafe**
- **Veoh**
- **NicoNico**
- **Bandcamp**
- **9GAG**
- **Flickr**
- **IMDB**
- **TED**
- **VK**
- **Rutube**
- **BBC**
- **CNN**
- **NBC**
- **Disney+**
- **HBO Max**
- **Netflix** (download limited by DRM restrictions)
- **Amazon Prime Video** (download limited by DRM restrictions)
- **Peacock TV**
- **Crunchyroll**
- **Funimation**
- **Udemy**
- **Coursera**
- **LinkedIn Learning**
- **National Geographic**
- **Comedy Central**
- **MTV**
- **Apple Podcasts**
- **Mixcloud**
- **Deezer**
- **Gaana**
- **JioSaavn**
- **Spotify** (for public content)
- **News Websites**: BBC News, The Guardian, The New York Times, and more.
- **Many more...**

## Download Options

- **Video Formats**: MP4, WEBM, MKV, FLV, AVI, MOV, and more.
- **Audio Formats**: MP3, M4A, AAC, OGG, WAV, FLAC.
- **Subtitles**: Download subtitles as `.srt` or `.vtt` files, with multi-language support.
- **Resolutions**: 144p, 360p, 480p, 720p, 1080p, 1440p (2K), 2160p (4K), and up to 4320p (8K), depending on availability.
- **Frame Rates**: Supports 24fps, 30fps, 60fps, and more.

## How It Works

1. **Install the Extension**: Add the GrabIt! extension to your Firefox browser.
2. **Visit a Supported Website**: Navigate to the video or audio content you want to download.
3. **Click the GrabIt! Icon**: When you're on a supported page, the GrabIt! icon will highlight. Click the icon to start the download process.
4. **Choose Your Format and Quality**: Select your preferred video/audio format and resolution.
5. **Download**: GrabIt! sends a request to the web service running **yt-dlp**, which handles the download and returns the file to your browser.

## Requirements

- **Firefox 60+**: GrabIt! works on all recent versions of Firefox.
- **yt-dlp Web Service**: You'll need to run a web service on your local machine or server that executes `yt-dlp`. More details on setting up the service can be found in our [Web Service Setup Guide](#web-service-setup-guide).

## Installation

To install the GrabIt! extension:

1. Clone or download the repository from GitHub.
2. Open Firefox and navigate to `about:debugging`.
3. Click on "This Firefox" and then "Load Temporary Add-on".
4. Select the `manifest.json` file in the `extension` folder.

For a persistent installation, submit the extension to the Firefox Add-ons site (AMO).

## Web Service Setup Guide

GrabIt! relies on a local or remote web service to run **yt-dlp**. Here's how to set it up:

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/grabit-web-service.git
