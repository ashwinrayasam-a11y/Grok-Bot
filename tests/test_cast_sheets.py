"""The bundled iOS sheets are the personas — keep them full and in lockstep.

Vesper's Home leg builds her prompt on the Mac from BASE_PERSONA while her
Away leg builds it on the phone from the bundled vesper.sheet.md; those two
must stay byte-identical or switching legs changes who she is.
"""

from pathlib import Path

from companion.personality import BASE_PERSONA

REPO = Path(__file__).resolve().parent.parent
SHEETS = REPO / "ios" / "Vesper" / "Vesper" / "Sheets"


def test_all_three_sheets_exist_and_are_full():
    # Minimum sizes catch a sheet regressing into a one-line stub.
    for name, minimum in (("vesper", 2000), ("mika", 1000), ("chat", 100)):
        path = SHEETS / f"{name}.sheet.md"
        assert path.is_file(), f"{path} is missing"
        text = path.read_text(encoding="utf-8").strip()
        assert len(text) >= minimum, f"{name}.sheet.md looks like a stub"


def test_vesper_sheet_matches_mac_base_persona():
    sheet = (SHEETS / "vesper.sheet.md").read_text(encoding="utf-8").strip()
    assert sheet == BASE_PERSONA.strip()


def test_mika_sheet_names_tigger():
    sheet = (SHEETS / "mika.sheet.md").read_text(encoding="utf-8")
    assert "Tigger" in sheet


def test_pbxproj_pins_all_sheets_into_bundle_resources():
    pbxproj = (
        REPO / "ios" / "Vesper" / "Vesper.xcodeproj" / "project.pbxproj"
    ).read_text(encoding="utf-8")
    for name in ("vesper", "mika", "chat"):
        assert f"Sheets/{name}.sheet.md" in pbxproj, (
            f"{name}.sheet.md is not pinned into Copy Bundle Resources"
        )
