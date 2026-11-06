class Grabit < Formula
  desc "Batch video downloader on top of yt-dlp, always at the highest quality"
  homepage "https://github.com/Canela-san/GrabIt"
  url "https://github.com/Canela-san/GrabIt/releases/download/v1.0.0/grabit.sh"
  version "1.0.0"
  sha256 "cd6c8d668b7ef2af621b8aad5ce700682a1e1111a26f9ef523dd0603346cb084"
  license "MIT"

  depends_on "aria2"
  depends_on "bash"
  depends_on "ffmpeg"
  depends_on "yt-dlp"

  def install
    inreplace "grabit.sh", "#!/usr/bin/env bash", "#!#{Formula["bash"].opt_bin}/bash"
    bin.install "grabit.sh" => "grabit"
    generate_completions_from_executable(bin/"grabit", "-L", "en", "completar")
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/grabit -L en -h")
  end
end
