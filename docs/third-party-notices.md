# Third-party notices

The root MIT License covers TypeSwitch's original source code. It does not replace the terms of the bundled dictionary data. Full copied upstream notices are in [LICENSES](../LICENSES/); retrieval URLs, dates, and notice-file hashes are recorded in [sources.json](../LICENSES/sources.json).

## Dictionary sources

`scripts/update-frequency-dictionaries.py` transforms these public datasets:

| Source | Material used | Upstream terms / copied notice |
| --- | --- | --- |
| [FrequencyWords](https://github.com/hermitdave/FrequencyWords), Hermit Dave; OpenSubtitles 2018 | English, Russian, and Ukrainian word-frequency lists | Content: [CC BY-SA 4.0](../LICENSES/CC-BY-SA-4.0.txt). Upstream generator code: [MIT](../LICENSES/FrequencyWords-MIT.txt). |
| [English Hunspell / SCOWL / Ispell](https://github.com/wooorm/dictionaries/tree/main/dictionaries/en) | Normalized English dictionary entries | [Complete copyright and permission notices](../LICENSES/hunspell-en.txt), including Kevin Atkinson and the upstream contributors. |
| [Russian Hunspell](https://github.com/wooorm/dictionaries/tree/main/dictionaries/ru), Alexander I. Lebedev | Normalized Russian dictionary entries | [Complete copyright, redistribution conditions, and disclaimer](../LICENSES/hunspell-ru.txt). |
| [Ukrainian Hunspell](https://github.com/wooorm/dictionaries/tree/main/dictionaries/uk), derived from [brown-uk/dict_uk](https://github.com/brown-uk/dict_uk) | Normalized Ukrainian dictionary entries | [GPL version 3](../LICENSES/GPL-3.0.txt). |

FrequencyWords identifies its content license in its [upstream README](https://github.com/hermitdave/FrequencyWords#license). The dictionary-uk package identifies its dictionary/affix files as GPL-3.0 in its [upstream README](https://github.com/wooorm/dictionaries/tree/main/dictionaries/uk#license); its package wrapper's MIT license does not relicense the dictionary.

## Transformations and resulting resources

These are modified resources, not verbatim upstream dictionaries. The generator strips frequency columns and Hunspell flags, removes uppercase/proper-name entries from Hunspell inputs, applies language/length filters, merges and sorts unique words, and removes explicitly listed generated noise. Russian/Ukrainian marker lists use a minimum frequency and an 8:1 cross-language frequency ratio. Source code and the generated text are both included; the app does not download them at runtime.

`english.txt` and `russian.txt` combine CC BY-SA 4.0 frequency content with the attributed permissive Hunspell sources. Their adaptations are distributed under CC BY-SA 4.0 while retaining the copied upstream notices. `russian-markers.txt` and `ukrainian-markers.txt` derive from FrequencyWords and remain under CC BY-SA 4.0.

`ukrainian.txt` combines CC BY-SA 4.0 frequency content with GPL-3.0 Ukrainian Hunspell data. This combined resource is distributed under GPL version 3, with FrequencyWords attribution and the upstream GPL terms retained. Creative Commons lists GPLv3 as a [one-way compatible adapter license for BY-SA 4.0](https://creativecommons.org/compatible-licenses/). Do not describe this resource as MIT-licensed or as solely CC BY-SA.

The source URLs used by the existing generator are listed in that script. The original private generation did not record upstream commit IDs, so the notice retrieval record is not presented as proof of the exact original dictionary revision. Future resource refreshes should record and pin source revisions.
