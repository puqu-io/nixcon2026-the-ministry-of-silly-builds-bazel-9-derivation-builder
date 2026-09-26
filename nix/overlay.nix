final: prev: {
  bazel_prebuilt = final.callPackage ./packages/bazel {
    jdk = final.jdk25_headless;
  };
  fetchrec = final.callPackage ./packages/fetchrec {
    jdk = final.jdk25_headless;
  };
  bzlmod_parser_poc = final.callPackage ./packages/bzlmod_parser_poc { };
  bazelUpdaters = final.callPackage ./builder/updaters { };
  mkBazelPackage = final.callPackage ./builder {
    bazel = final.bazel_prebuilt;
    jdk = final.jdk25_headless;
  };
}
