# Contributing to BookIt

Thank you for helping more people read in their own language!

## Ways to help

- **Translate the app's menus into your language.** The menus are in `app/lib/l10n/`. Copy `hi.dart` to your language code (for example `kn.dart` for Kannada), translate the right-hand side of each line (keep `{placeholders}` as they are), then add your language to `kAppLanguages` and `_tables` in `strings.dart`. `flutter test` checks that nothing is missing. Fixes to the existing Hindi, Tamil, Bengali, Telugu and Marathi menus are very welcome too.
- **Translate a book for the community library.** See *Community library* in the README. Good first picks: popular classics, children's books and short-story collections.
- **Check translation quality.** If you read Tamil, Hindi, Bengali or any other language, open an issue with examples of good and bad translations — it helps us choose better models.
- **Report bugs** with your device (phone model / Windows version), the book, and steps to reproduce.
- **Code.** Pick an issue or an item from the roadmap.

## Development

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

- Keep `flutter analyze` clean and add tests for parsing, layout and translation logic (`app/test/`).
- The translation engine has an end-to-end test that downloads the model and compares the Dart engine with a Python reference: run the **Engine test** workflow, or locally set `NLLB_MODEL_DIR`, `NLLB_REFERENCE` and `NLLB_TOKENIZER` (see `.github/workflows/engine.yml`).
- UI text should be simple and friendly — many readers are not technical. Wrap every visible string in `tr('…')` and add it to each file in `app/lib/l10n/` (the test lists any you missed).
- Windows builds need `nuget.exe` on the PATH (used by the text-to-speech plugin).
- The **Starter editions** workflow translates public-domain classics in CI and publishes them to the community library.

## Adding an edition to the catalog

Each entry in `catalog/editions.json` looks like:

```json
{
  "id": "pg1342-tam_Taml",
  "title": "Pride and Prejudice",
  "author": "Jane Austen",
  "lang": "tam_Taml",
  "sourceLang": "eng_Latn",
  "gutenbergId": 1342,
  "engine": "nllb-200-distilled-1.3B",
  "size": 1234567,
  "url": "https://github.com/MohammedAnasAsif/BookIt/releases/download/editions/pride-and-prejudice.tam_Taml.bookit",
  "cover": "https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg"
}
```

Only public-domain books (or books whose rights holders allow sharing) can be added.
