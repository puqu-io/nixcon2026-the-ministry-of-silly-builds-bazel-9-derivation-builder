{
  lib,
  stdenv,
  writeShellApplication,
}:

{
  pname,
  ...
}@args:
writeShellApplication {
  name = "update-${pname}-lock";
  text = ''
    set -euo pipefail
    cat << 'EOF' > fetches.jsonl
    ${builtins.toJSON {
      canonical_id_marker = null;
      context = "repository @@gcc_toolchain++gcc_toolchains+gcc_toolchain_x86_64_16_2_0";
      kind = "archive";
      sha256 = "54af34c821e59b03ded8f82d3a1104426ec4baaf3b226233e1fd76ad5dcb78cf";
      urls = [
        "https://github.com/f0rmiga/gcc-builds/releases/download/10082026/gcc-toolchain-16.2.0-x86_64.tar.xz"
      ];
    }}
    ${
      builtins.toJSON {
        canonical_id_marker = "id-19f55677f1b197271c809b82cc73ffc594898124cb6ee3327db9ae510fdd3b53";
        context = "repository @@rules_java++toolchains+remotejdk25_linux";
        kind = "archive";
        sha256 = "e476f5c98952cb365ca77a814dbe3c74341e71ae76d1a87d1c0a69c7d2b1b2d0";
        urls = [
          "https://cdn.azul.com/zulu/bin/zulu25.36.15-ca-jdk25.0.4-linux_x64.tar.gz"
          "https://mirror.bazel.build/cdn.azul.com/zulu/bin/zulu25.36.15-ca-jdk25.0.4-linux_x64.tar.gz"
        ];
      }
    } 
    ${builtins.toJSON {
      canonical_id_marker = null;
      context = null;
      kind = "registry";
      sha256 = "4a3d4f3606d3b3190be495dbc497acca552807d1d5540661ef0d1658472882e3";
      urls = [ "https://bcr.bazel.build/modules/rules_cc/0.2.25/MODULE.bazel" ];
    }}
    EOF
  '';
}
