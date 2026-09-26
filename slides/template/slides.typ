#let to-string(content) = {
  if content.has("text") {
    content.text
  } else if content.has("children") {
    content.children.map(to-string).join("")
  } else if content.has("body") {
    to-string(content.body)
  } else if content == [ ] {
    ""
  }
}

#let slides(
  content,
  title: none,
  subtitle: none,
  date: none,
  authors: (),
) = {
  set document(
    title: title,
    author: authors.map(author => author.name),
    date: date,
  )

  set text(
    font: "Jetbrains Mono",
    size: 2em,
  )

  // Title page
  page(
    paper: "presentation-16-9",
    flipped: false,
    numbering: {},
  )[
    #set align(center)
    #v(-0.5em)
    #image("nixcon-2026-logo.svg", height: 65%)
    #v(-1em)
    #text(weight: "bold", size: 1.5em, title)
    #v(-1em)
    #text(size: 1.1em, subtitle)
    #v(-0.25em)
    #text(size: 0.75em)[#authors.map(author => [#link(author.github_profile_link)[#author.name]]).join(" | ")]
  ]

  // About authors page
  page(
    paper: "presentation-16-9",
    flipped: false,
    numbering: {},
    columns: authors.len(),
  )[
    #set align(horizon + center)
    #authors.map(author => [
      #box(
        height: 30%,
        image(author.avatar),
        radius: 80pt,
        clip: true,
      )
      #v(-0.5em)
      #text(size: 0.75em)[#author.name]
      #v(-0.25em)
      #par(justify: true)[#text(size: 0.5em)[#author.desc]]
      #v(0em)
      #grid(
        columns: (34%, 65%), 
        column-gutter: 1%,
        [#align(horizon+right)[#image("square-github-brands-solid.svg", height: 0.75em)]],
        [#align(horizon+left)[#link(author.github_profile_link)[#text(size: 0.4em)[#author.github_profile_link]]]],
      )
      #v(-2.75em)
      #grid(
        columns: (34%, 65%), 
        column-gutter: 1%,
        [#align(horizon+right)[#image("envelope-solid.svg", height: 0.7em)]],
        [#align(horizon+left)[#link("mailto:" + author.email)[#text(size: 0.4em)[#author.email]]]],
      )
    ]).join(colbreak())
  ]

  // Section slides
  show heading.where(level: 1): x => {
    set page(header:none,footer:none, margin: auto)
    set align(horizon + center)
    text(weight: "bold", size: 1.5em, x)
  }

  show heading.where(level: 2): pagebreak(weak: true)

  // Codeblocks
  show raw: it => block(
    fill: rgb("#effdff"),
    inset: 0.75em,
    radius: 25pt,
    it
  )

  set page(
    paper: "presentation-16-9",
    margin: (top: 4em),
    flipped: false,
    header-ascent: 50%,
    header: [
      #context {
        let main-title = lower(to-string(title).replace(regex("\s+"), "-"))
        let current-header = query(selector(heading.where(level: 1))).rev().find(x => x.location().page() <= here().page())
        let current-header = if current-header != none { lower(to-string(current-header).replace(regex("\s+"),"-")) } else { "" }
        let current-subheader = query(selector(heading.where(level: 2))).rev().find(x => x.location().page() <= here().page())
        let current-subheader = if current-subheader != none { lower(to-string(current-subheader).replace(regex("\s+"),"-")) } else { "" }
        set text(size: 0.5em)
        [
          *\[nixcon\@krakow:\~\]\$*./#main-title/#current-header/#current-subheader
        ]
      }
    ],
    footer: [
      #align(right)[
        #text(size: 0.5em)[#authors.map(author => [#link(author.github_profile_link)[#author.name]]).join(" | ")]
      ]
    ]
  )

  content
}
