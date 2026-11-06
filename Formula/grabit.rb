class Grabit < Formula
  desc "Batch video downloader on top of yt-dlp, always at the highest quality"
  homepage "https://github.com/Canela-san/GrabIt"
  url "https://github.com/Canela-san/GrabIt/releases/download/v1.0.0/grabit.sh"
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on "aria2"
  depends_on "bash"
  depends_on "ffmpeg"
  depends_on "yt-dlp"

  def install
    inreplace "grabit.sh", "#!/usr/bin/env bash", "#!#{Formula["bash"].opt_bin}/bash"
    bin.install "grabit.sh" => "grabit"
    generate_completions_from_executable(bin/"grabit", "completar")
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/grabit -L en -h")
  end
end
