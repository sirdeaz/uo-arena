# Fonts

## UncialAntiqua-Regular.ttf

The face the mantras are spoken in. A caster saying `Kal Vas Flam` is a character
speaking, not a label, and an uncial says so at a glance — which matters, because the
mantra is the opponent's only read on what is coming and the whole basis of the
fizzle-feint.

The cast bar caption deliberately does **not** use it. That is chrome, and chrome should
look like the interface it is.

- **Source:** [Uncial Antiqua](https://fonts.google.com/specimen/Uncial+Antiqua) by
  Tomás García Ferrari and Carolina Giovagnoli, from
  `google/fonts@main:ofl/uncialantiqua/UncialAntiqua-Regular.ttf`.
- **Licence:** SIL Open Font License 1.1 — see `OFL.txt`. Redistributable inside the
  game builds, which is why it can ship in the browser and Windows downloads.
- **Subset to Basic Latin** (`U+0020`–`U+007E`), which takes it from 62 KB to 15 KB.
  The mantras themselves need barely two dozen glyphs, but keeping all of printable
  ASCII costs a couple of kilobytes and means a new spell cannot ship with missing
  characters.

Regenerate the subset with:

```sh
pip install fonttools
curl -fsSLO https://raw.githubusercontent.com/google/fonts/main/ofl/uncialantiqua/UncialAntiqua-Regular.ttf
python -m fontTools.subset UncialAntiqua-Regular.ttf \
    --unicodes="U+0020-007E" --layout-features='' --no-hinting --desubroutinize \
    --output-file=client/fonts/UncialAntiqua-Regular.ttf
```

Every byte here is download weight for every browser player, so measure `build/web`
before and after if you change it.
