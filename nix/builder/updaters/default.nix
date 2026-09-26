{ callPackage }:

{
  fetchrec = callPackage ./fetchrec.nix { };
  bzlmodParser = callPackage ./bzlmod-parser.nix { };
}
