{
  lib,
  linkFarm,
  emptyFile,
  lock,
}:

let
  inherit (lib) concatMapStringsSep;

  # gets a writable symlink skeleton under $TMPDIR
  writableCopy = dir: storePath: ''
    mkdir -p "${dir}"
    cp -rs ${storePath}/. "${dir}/"
    chmod -R u+w "${dir}"
  '';

  # mount keeps the directorys setup hook and its bazel flag together
  mkMount =
    dirName: mkFlag: storePath:
    let
      dir = "$TMPDIR/${dirName}";
    in
    {
      inherit dir storePath;
      setup = writableCopy dir storePath;
      flag = mkFlag dir;
    };
in
{
  repoCacheMount = mkMount "repo-cache" (dir: ''--repository_cache="${dir}"'');
  vendorMount = mkMount "vendor" (dir: ''--vendor_dir="${dir}"'');

  # shell snippet preparing every mount in the list
  #TODO add another one for rendering build flags
  setup = mounts: lib.concatMapStrings (m: m.setup) mounts;

  # --repository_cache:
  #
  #  <dir>/content_addressable/sha256/<hex>/file
  #  <dir>/content_addressable/sha256/<hex>/id-<sha256(canonId)>
  #
  # DownloadManager checks the repository cache for both downloadInExecutor (archive)
  # and downloadAndReadOneUrlForBzlmod (registry), keyed by the declared checksum.
  # Registry files get their checksums from MODULE.bazel.lock
  mkRepoCache =
    {
      lockFile,
      name ? "bazel-repo-cache",
    }:
    let
      entries = lock.readLock lockFile;
      missing = lock.missingChecksums entries;

      blob = a: {
        name = "content_addressable/sha256/${a.sha256}/file";
        path = lock.fetchArtifact a;
      };

      # A canonical id restricts cache hits to entries carrying its marker:
      # DownloadCache.hasCanonicalId hashes the id and looks for "id-<hash>"
      # beside the file. Without these, every rule that sets one misses and
      # falls through to a disabled download
      idMarkers =
        a:
        map (idMarker: {
          name = "content_addressable/sha256/${a.sha256}/${idMarker}";
          path = emptyFile;
        }) a.idMarkers;
    in
    if missing != [ ] then
      throw ''
        ${toString lockFile}: ${toString (builtins.length missing)} download(s) have no declared
        sha256, so Bazel cannot find them in the repository cache offline:
        ${concatMapStringsSep "\n" (url: "  ${url}") missing}
        Add a sha256/integrity to the rule, re-record with an up-to-date MODULE.bazel.lock''
    else
      linkFarm name (
        lib.concatMap (a: [ (blob a) ] ++ idMarkers a) (lock.artifactsOf entries)
      );
}
