class Grabit < Formula
  desc "Batch video downloader on top of yt-dlp, always at the highest quality"
  homepage "https://github.com/Canela-san/GrabIt"
  url "https://github.com/Canela-san/GrabIt/releases/download/v1.1.1/grabit.sh"
  version "1.1.1"
  sha256 "5f7344b74aac362faccd8d6f6d5c449015a03dffaef05191e13b638664fba9fa"
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
    (man1/"grabit.1").write Utils.safe_popen_read(bin/"grabit", "-L", "en", "manual")
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/grabit -L en -h")
  end
end
