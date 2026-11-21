"""Validate the shared catalog and translation references on both platforms."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
catalog = json.loads((root / 'src/Shared/translations.json').read_text())
languages = {'en', 'ko', 'ja', 'zh-Hans', 'es', 'fr', 'de', 'pt', 'ru', 'ar'}
for key, translations in catalog.items():
    assert set(translations) == languages, f'{key}: missing language'
    placeholders = set(re.findall(r'\{\d+\}', translations['en']))
    for language, text in translations.items():
        assert text.strip(), f'{key}/{language}: empty'
        assert set(re.findall(r'\{\d+\}', text)) == placeholders, f'{key}/{language}: placeholders'
        if language not in {'ko'}:
            assert not re.search('[가-힣]', text), f'{key}/{language}: Korean text leaked'
for pattern in ['src/macOS/*.swift', 'src/Windows/*.cs']:
    for source in root.glob(pattern):
        content = source.read_text()
        for key in re.findall(r'\bT\("([A-Za-z]+)"', content):
            assert key in catalog, f'{source.name}: unknown key {key}'
        # Native language names are deliberate, stable labels in the selector.
        if source.name not in {'Localization.swift', 'Localization.cs'}:
            assert not re.search('[가-힣]', content), f'{source.name}: untranslated UI text'
print(f'PASS: {len(catalog)} messages, 10 languages, placeholders, source references, no Korean UI leakage')
