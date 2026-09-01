#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import re
import struct
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "safe-dial" / "SafeDial.docc"
TUTORIALS = CATALOG / "Tutorials"
IMAGES = CATALOG / "Resources" / "Images"
MAX_FILE_BYTES = 50 * 1024 * 1024
HERO_SIZE = (1600, 900)
SECTION_SIZE = (1400, 1400)
PROJECT_FILES_NAME = "SafeDial-Tutorial-007o.zip"
PROJECT_FILES_PATH = CATALOG / "Resources" / "Downloads" / PROJECT_FILES_NAME
PROJECT_FILES_SHA256 = (
    "502fbeee09df89d273e7425e1f845ae08fc66e12d1db1e3f297d21a31ef42b2e"
)
XCODE_TITLE = "Xcode 26.4 or later"
XCODE_DESTINATION = "https://developer.apple.com/download/"

EXPECTED_SECTION_MEDIA = {
    "01-Sound.tutorial": (
        "tutorial-section-audio-preparation",
        "tutorial-section-audio-routing",
    ),
    "02-Haptics.tutorial": (
        "tutorial-section-ahap-timeline",
        "tutorial-section-feedback-curves",
    ),
    "03-DepthAxis.tutorial": (
        "tutorial-section-fixed-depth-axis",
        "tutorial-section-depth-hysteresis",
        "tutorial-section-arrival-deduplication",
    ),
    "04-Integration.tutorial": (
        "tutorial-section-fourth-lock-extension",
    ),
}

EXPECTED_TUTORIAL_TIMES = {
    "01-Sound.tutorial": 25,
    "02-Haptics.tutorial": 25,
    "03-DepthAxis.tutorial": 40,
    "04-Integration.tutorial": 15,
}

EXPECTED_HERO_MEDIA = {
    "SafeDial.tutorial": "tutorial-overview-hero",
    "01-Sound.tutorial": "tutorial-chapter-sound",
    "02-Haptics.tutorial": "tutorial-chapter-haptics",
    "03-DepthAxis.tutorial": "tutorial-chapter-depth-axis",
    "04-Integration.tutorial": "tutorial-chapter-integration",
}


def fail(message: str) -> None:
    raise SystemExit(message)


def matching_delimiter(text: str, start: int, opening: str, closing: str) -> int:
    depth = 0
    in_string = False
    escaped = False

    for index in range(start, len(text)):
        character = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue

        if character == '"':
            in_string = True
        elif character == opening:
            depth += 1
        elif character == closing:
            depth -= 1
            if depth == 0:
                return index

    fail(f"Unclosed {opening}{closing} block in tutorial source")


def directive_blocks(text: str, directive: str) -> list[str]:
    token = f"@{directive}"
    blocks: list[str] = []
    cursor = 0

    while True:
        directive_start = text.find(token, cursor)
        if directive_start == -1:
            return blocks
        brace_start = text.find("{", directive_start + len(token))
        if brace_start == -1:
            fail(f"{token} has no opening brace")
        brace_end = matching_delimiter(text, brace_start, "{", "}")
        blocks.append(text[brace_start + 1 : brace_end])
        cursor = brace_end + 1


def image_sources(text: str) -> list[str]:
    sources: list[str] = []
    cursor = 0
    image_pattern = re.compile(r"@Image\s*\(")

    while match := image_pattern.search(text, cursor):
        paren_start = text.find("(", match.start())
        paren_end = matching_delimiter(text, paren_start, "(", ")")
        directive = text[paren_start + 1 : paren_end]
        source = re.search(r'\bsource\s*:\s*"([^"]+)"', directive)
        if source is None:
            fail("An @Image directive is missing its source argument")
        sources.append(source.group(1))
        cursor = paren_end + 1

    return sources


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as image:
        header = image.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"Not a PNG file: {path.relative_to(ROOT)}")
    if header[12:16] != b"IHDR":
        fail(f"PNG has no leading IHDR chunk: {path.relative_to(ROOT)}")
    return struct.unpack(">II", header[16:24])


def validate_tutorial_references() -> list[str]:
    actual_tutorials = {path.name for path in TUTORIALS.glob("*.tutorial")}
    expected_tutorials = set(EXPECTED_SECTION_MEDIA)
    if actual_tutorials != expected_tutorials:
        fail(
            "Unexpected tutorial sources: "
            f"expected {sorted(expected_tutorials)}, found {sorted(actual_tutorials)}"
        )

    section_sources: list[str] = []
    content_and_media_count = 0
    for tutorial_name, expected_bases in EXPECTED_SECTION_MEDIA.items():
        tutorial = TUTORIALS / tutorial_name
        text = tutorial.read_text(encoding="utf-8")
        blocks = directive_blocks(text, "ContentAndMedia")
        content_and_media_count += len(blocks)
        if len(blocks) != len(expected_bases):
            fail(
                f"{tutorial_name}: expected {len(expected_bases)} "
                f"@ContentAndMedia blocks, found {len(blocks)}"
            )

        actual_sources: list[str] = []
        for section_number, block in enumerate(blocks, start=1):
            sources = image_sources(block)
            if len(sources) != 1:
                fail(
                    f"{tutorial_name} section {section_number}: expected exactly one "
                    f"@ContentAndMedia image, found {len(sources)}"
                )
            actual_sources.extend(sources)

        expected_sources = [f"{base}.png" for base in expected_bases]
        if actual_sources != expected_sources:
            fail(
                f"{tutorial_name}: expected section media {expected_sources}, "
                f"found {actual_sources}"
            )
        section_sources.extend(actual_sources)

    if content_and_media_count != 8 or len(section_sources) != 8:
        fail(
            "Expected exactly 8 @ContentAndMedia blocks and 8 section images, "
            f"found {content_and_media_count} blocks and {len(section_sources)} images"
        )
    if len(set(section_sources)) != len(section_sources):
        fail("Every @ContentAndMedia image source must be unique")

    return [source.removesuffix(".png") for source in section_sources]


def validate_hero_references() -> list[str]:
    bases: list[str] = []
    for source_name, expected_base in EXPECTED_HERO_MEDIA.items():
        source_path = CATALOG / source_name
        if not source_path.is_file():
            source_path = TUTORIALS / source_name
        if not source_path.is_file():
            fail(f"Missing tutorial source for hero validation: {source_name}")
        sources = image_sources(source_path.read_text(encoding="utf-8"))
        expected_source = f"{expected_base}.png"
        if expected_source not in sources:
            fail(f"{source_name}: missing expected hero reference {expected_source}")
        bases.append(expected_base)
    return bases


def validate_tutorial_header_contract() -> None:
    xcode_requirement = re.compile(
        rf"@XcodeRequirement\(\s*"
        rf'title:\s*"{re.escape(XCODE_TITLE)}",\s*'
        rf'destination:\s*"{re.escape(XCODE_DESTINATION)}"\s*'
        rf"\)",
        re.MULTILINE,
    )
    for tutorial_name, expected_time in EXPECTED_TUTORIAL_TIMES.items():
        text = (TUTORIALS / tutorial_name).read_text(encoding="utf-8")
        expected_header = (
            f'@Tutorial(time: {expected_time}, projectFiles: "{PROJECT_FILES_NAME}") {{'
        )
        if not text.startswith(expected_header):
            fail(f"{tutorial_name}: expected header {expected_header}")
        if len(xcode_requirement.findall(text)) != 1:
            fail(
                f"{tutorial_name}: expected one {XCODE_TITLE} @XcodeRequirement "
                f"with destination {XCODE_DESTINATION}"
            )

    catalog_source = (CATALOG / "SafeDial.tutorial").read_text(encoding="utf-8")
    if "SafeDial-Tutorial-007n.zip" in catalog_source:
        fail("The current 007o catalog must not link to the historical 007n ZIP")
    if "**Project files**" not in catalog_source:
        fail("The catalog intro must direct learners to the Project files header")


def validate_project_files_archive() -> None:
    archives = {
        path.relative_to(ROOT)
        for path in ROOT.rglob("*.zip")
        if path.is_file() and ".git" not in path.parts
    }
    expected_archive = PROJECT_FILES_PATH.relative_to(ROOT)
    if archives != {expected_archive}:
        fail(
            f"Expected only the authored DocC projectFiles ZIP {expected_archive}, "
            f"found {sorted(str(path) for path in archives)}"
        )
    if not zipfile.is_zipfile(PROJECT_FILES_PATH):
        fail(f"Invalid projectFiles ZIP: {expected_archive}")
    digest = hashlib.sha256(PROJECT_FILES_PATH.read_bytes()).hexdigest()
    if digest != PROJECT_FILES_SHA256:
        fail(
            f"projectFiles ZIP SHA-256 differs: expected {PROJECT_FILES_SHA256}, "
            f"found {digest}"
        )

    with zipfile.ZipFile(PROJECT_FILES_PATH) as archive:
        corrupt_member = archive.testzip()
        if corrupt_member is not None:
            fail(f"Corrupt projectFiles ZIP member: {corrupt_member}")
        members = set(archive.namelist())
        project_file = "SafeDial-Tutorial/safe-dial.xcodeproj/project.pbxproj"
        readme = "SafeDial-Tutorial/README.md"
        for required_member in (project_file, readme):
            if required_member not in members:
                fail(f"projectFiles ZIP is missing {required_member}")
        project_source = archive.read(project_file).decode("utf-8")
        if project_source.count(
            "PRODUCT_BUNDLE_IDENTIFIER = com.spatiallab.sketch007o;"
        ) != 2:
            fail("projectFiles ZIP does not contain both 007o bundle identifiers")
        learner_readme = archive.read(readme).decode("utf-8")
        if "com.spatiallab.sketch007o" not in learner_readme:
            fail("projectFiles ZIP README does not describe the 007o bundle identifier")

    ignore_rule = (
        "!safe-dial/SafeDial.docc/Resources/Downloads/"
        f"{PROJECT_FILES_NAME}"
    )
    ignore_file = ROOT / ".gitignore"
    if not ignore_file.is_file() or ignore_rule not in ignore_file.read_text(
        encoding="utf-8"
    ).splitlines():
        fail(f"Missing exact .gitignore tracking exception: {ignore_rule}")


def validate_image_pairs(section_bases: list[str], hero_bases: list[str]) -> None:
    section_bases = [
        base
        for expected_bases in EXPECTED_SECTION_MEDIA.values()
        for base in expected_bases
    ]
    expected_section_files = {
        filename
        for base in section_bases
        for filename in (f"{base}.png", f"{base}~dark.png")
    }
    actual_section_files = {
        path.name for path in IMAGES.glob("tutorial-section-*.png") if path.is_file()
    }
    if actual_section_files != expected_section_files:
        missing = sorted(expected_section_files - actual_section_files)
        unexpected = sorted(actual_section_files - expected_section_files)
        fail(f"Section media file set differs; missing={missing}, unexpected={unexpected}")

    bases = section_bases + hero_bases
    if len(set(bases)) != len(bases):
        fail("Media base names must be unique")

    for base in bases:
        expected_size = SECTION_SIZE if base in section_bases else HERO_SIZE
        for filename in (f"{base}.png", f"{base}~dark.png"):
            path = IMAGES / filename
            if not path.is_file():
                fail(f"Missing light/dark media pair member: {path.relative_to(ROOT)}")
            dimensions = png_size(path)
            if dimensions != expected_size:
                fail(
                    f"{path.relative_to(ROOT)}: expected {expected_size[0]}x"
                    f"{expected_size[1]}, found {dimensions[0]}x{dimensions[1]}"
                )
            if path.stat().st_size >= MAX_FILE_BYTES:
                fail(f"Media file must be smaller than 50MB: {path.relative_to(ROOT)}")


def validate_repository_media_policy() -> None:
    forbidden_videos: list[Path] = []
    forbidden_video_references: list[Path] = []
    oversized_files: list[Path] = []

    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        if path.suffix.lower() in {".mp4", ".mov"}:
            forbidden_videos.append(path.relative_to(ROOT))
        if path.stat().st_size >= MAX_FILE_BYTES:
            oversized_files.append(path.relative_to(ROOT))

    tutorial_sources = [CATALOG / "SafeDial.tutorial", *TUTORIALS.glob("*.tutorial")]
    video_reference = re.compile(
        r'\b(?:source|poster)\s*:\s*"[^"]+\.(?:mp4|mov)"',
        re.IGNORECASE,
    )
    for source_path in tutorial_sources:
        if video_reference.search(source_path.read_text(encoding="utf-8")):
            forbidden_video_references.append(source_path.relative_to(ROOT))

    if forbidden_videos:
        fail(f"MP4/MOV files are not allowed in this sketch: {forbidden_videos}")
    if forbidden_video_references:
        fail(
            "MP4/MOV references are not allowed in current tutorial sources: "
            f"{forbidden_video_references}"
        )
    if oversized_files:
        fail(f"Files must be smaller than 50MB: {oversized_files}")


def main() -> None:
    validate_tutorial_header_contract()
    validate_project_files_archive()
    section_bases = validate_tutorial_references()
    hero_bases = validate_hero_references()
    validate_image_pairs(section_bases, hero_bases)
    validate_repository_media_policy()
    print(
        "Tutorial media validation passed: 8 unique ContentAndMedia images, "
        "5 light/dark 1600x900 hero pairs and 8 light/dark 1400x1400 "
        "section pairs, files under 50MB, "
        "no MP4/MOV files or tutorial references, valid 007o projectFiles ZIP, "
        "Xcode 26.4 or later header contract."
    )


if __name__ == "__main__":
    main()
