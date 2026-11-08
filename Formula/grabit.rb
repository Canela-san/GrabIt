class Grabit < Formula
  desc "Batch video downloader on top of yt-dlp, always at the highest quality"
  homepage "https://github.com/Canela-san/GrabIt"
  url "https://github.com/Canela-san/GrabIt/releases/download/v1.1.0/grabit.sh"
  version "1.1.0"
  sha256 "b4548baaa79a837cfc063c421696c2cb35d6b75472232c1e353e92814d471a1f"
  license "MIT"

  depends_on "aria2"
  depends_on "bash"
  depends_on "ffmpeg"
  depends_on "yt-dlp"

  def install
    inreplace "grabit.sh", "#!/usr/bin/env bash", "#!#{Formula["bash"].opt_bin}/bash"
    chmod 0755, "grabit.sh"
    bin.install "grabit.sh" => "grabit"
    generate_completions_from_executable(bin/"grabit", "-L", "en", "completar")
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/grabit -L en -h")
  end
end
