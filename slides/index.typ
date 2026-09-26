#import "template/slides.typ": slides
#show: slides.with(
  title: [
    The ministry of silly builds
  ],
  subtitle: [
    a Bazel 9 derivation builder
  ],
  authors: (
    (
      name: "Aleksander Gondek",
      desc: "Alex is well-known for spearheading migrations to Bazel build system at scale. He enjoys solving complex challenges in a manner that results in simple solutions. Rust, Nix and Bazel enthusiast, he attempts to bring reproducibility and correctness to any software project he works on. His mantra? 'There has to be a better way!'.",
      avatar: "AleksanderGondek.png",
      github_profile_link: "https://github.com/AleksanderGondek",
      email: "gondekaleksander@protonmail.com",
    ),
    (
      name: "Artur Stachecki",
      desc: "Artur has background in computer science and engineering, focuses on correctness, reliability, and reusability of software systems. Leading large-scale migrations, he excels in creating advanced build systems and ensuring build correctness. Artur loves engineering innovative solutions using variability modeling.",
      avatar: "r2r-dev.jpeg",
      github_profile_link: "https://github.com/r2r-dev",
      email: "contact@r2r.sh",
    ),
  ),
)

#show link: underline
#set align(horizon)

= Introduction

#align(center)[
  #image("constraints.png", height: 13em)
]

#pagebreak()

== Why running Bazel under nix is non-trival?


#align(center)[
  #text(size: 2em)[Why running Bazel under nix is non-trivial?]
]

#pagebreak()

- *Bazel* model of downloading external dependencies is skewed towards laziness (some things will be only downloaded when they are about to be used)

#pagebreak()

- *Bazel* ruleset authors have significant freedom in shaping how said external dependencies are obtained (it is possible to run arbitrary process and capture its outputs (_rctx.execute_))

#pagebreak()

- *Bazel* and its rulesets frequently do not shy away from hardcoding certain assumptions about Linux runtime

#pagebreak()

== State of art

#align(center)[
  #text(size: 2em)[State of art]
]

#pagebreak()

_buildBazelPackage_ / _bazelPackage_:
- focused on using *Bazel* to deliver binaries into _/nix/store_ ecosystem
- *Bazel* _fetch_ and/or _vendor_ outputs stored in _/nix/store_
- *Bazel* and its dependencies are patched to reference  _/nix/store_

#pagebreak()

#align(center)[
  #image("bazel-goes-into.png", height: 16em)
]

#pagebreak()

== Our usecase

#align(center)[
  #text(size: 2em)[Our usecase]
]

#pagebreak()

#align(center)[
  #image("use-case.png", height: 16em)
]

#pagebreak()

- In other words, Nix must not be visible in neither *Bazel* build system, nor output binaries.
- Also: consider _/nix/store_ capacity if each *Bazel* has separate vendored derivation.

== Goals

- Goal 1: *Bazel* and its build inputs remain untouched by _nix_ patching
- Goal 2: *Bazel* build outputs remain unaware of _nix_
- Goal 3: *Nix* derivations are granular enough to allow for artifacts sharing

== Side-note

- With Bazel 9+ usage of _bzlmod_ is mandatory. It was desgined to bring modern dependency resolution experience to Bazel.
- It has _MODULE.bazel.lock_ files!
- Surely the lockfile contains all the outputs that is registered by _module_extensions_ that can execute arbirary code
- ...

= Demo!

== Questions?

#align(center)[
  #text(size: 1em)[
    Questions?
  ]
]
