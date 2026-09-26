{
  lib,
  fetchurl,
}:

let
  inherit (lib) substring;
in
rec {
  #  {"kind":"archive","urls":["https://..."],"sha256":"a1b2...","canonical_id_marker":null,"context":"repository @@rules_cc+"}
  #  {"kind":"registry","urls":["https://..."],"sha256":"b2c3...","canonical_id_marker":"id-c3d4...","context":null}
  readLock =
    lockFile:
    let
      lines = builtins.filter (line: line != "") (
        lib.splitString "\n" (builtins.readFile lockFile)
      );
    in
    map builtins.fromJSON lines;

  missingChecksums =
    entries:
    lib.unique (
      lib.concatMap (e: e.urls) (builtins.filter (e: e.sha256 == null) entries)
    );

  # The same bytes are usually recorded many times: once per Bazel command under mirror urls,
  # or by several repos. Merge them into one artifact per sha256
  #
  # [
  #   {
  #     sha256 = "283fa1cd...";
  #     urls = [ "https://github.com/.../rules_bar-0.9.9.tar.gz" "https://mirror.example/rules_bar-0.9.9.tar.gz" ];
  #     idMarkers = [ "id-569116ae..." "id-93e8304d..." ];
  #     kinds = [ "archive" ];
  #   }
  # ]
  artifactsOf =
    entries:
    lib.mapAttrsToList (sha256: group: {
      inherit sha256;
      urls = lib.unique (lib.concatMap (e: e.urls) group);
      idMarkers = lib.unique (
        builtins.filter (idMarker: idMarker != null) (
          map (e: e.canonical_id_marker) group
        )
      );
      kinds = lib.unique (map (e: e.kind) group);
    }) (lib.groupBy (e: e.sha256) (builtins.filter (e: e.sha256 != null) entries));

  fetchArtifact =
    a:
    fetchurl {
      inherit (a) urls sha256;
      name = a.name or "bazel-blob-${substring 0 12 a.sha256}";
    };

  # artifacts in the lock file as a list of store paths
  artifacts = lockFile: map fetchArtifact (artifactsOf (readLock lockFile));
}
