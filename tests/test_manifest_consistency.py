"""
Tests that ensure the plugin's manifest and user-visible docs claim
counts that match reality on disk.

Background: this guard exists because the v1.9.7 release process suffered
two distinct skill-count drift incidents in a single release window. The
first was caught by manual reconciliation (pre-Phase-A); the second slipped
through when PR #56 merged a 21st core skill but the canonical phrasing
locked in Phase A was not re-run. v1.9.8 closes the systemic gap.

Tests run via `pytest tests/` and are wired into `.github/workflows/ci.yml`.
"""
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_JSON = REPO_ROOT / "manifest.json"
DELEGATES_DIR = REPO_ROOT / "skills" / "seo" / "references" / "delegates"
CITATION_CFF = REPO_ROOT / "CITATION.cff"


def _count_skill_dirs() -> int:
    """Count subdirectories of skills/ that contain a SKILL.md."""
    skills_dir = REPO_ROOT / "skills"
    return sum(
        1 for d in skills_dir.iterdir()
        if d.is_dir() and (d / "SKILL.md").is_file()
    )


def _count_delegate_files() -> int:
    """Count references/delegates/seo-*.md files."""
    if not DELEGATES_DIR.exists():
        return 0
    return sum(
        1 for f in DELEGATES_DIR.iterdir()
        if f.is_file() and f.suffix == ".md" and f.name.startswith("seo-")
    )


def _extract_count(text: str, unit: str) -> int:
    """Find the first occurrence of 'N <unit>' in text and return N."""
    match = re.search(rf"(\d+)\s+{re.escape(unit)}", text)
    if not match:
        raise AssertionError(f"No '{unit}' count claim found in text")
    return int(match.group(1))


def test_manifest_skill_count_matches_disk():
    """manifest.json hermes.sub_skills must equal skills/ dir count."""
    manifest = json.loads(MANIFEST_JSON.read_text())
    claimed = manifest["hermes"]["sub_skills"]
    actual = _count_skill_dirs()
    assert claimed == actual, (
        f"manifest.json claims {claimed} sub-skills "
        f"but disk has {actual}. "
        f"Update manifest.json hermes.sub_skills to match."
    )


def test_manifest_delegate_count_matches_disk():
    """manifest.json hermes.delegate_briefs must equal references/delegates/ count."""
    manifest = json.loads(MANIFEST_JSON.read_text())
    claimed = manifest["hermes"]["delegate_briefs"]
    actual = _count_delegate_files()
    assert claimed == actual, (
        f"manifest.json claims {claimed} delegate briefs "
        f"but disk has {actual}. "
        f"Update manifest.json hermes.delegate_briefs to match."
    )


def test_canonical_phrasing_in_user_visible_docs():
    """README and HERMES.md must reference the canonical sub-skills count."""
    manifest = json.loads(MANIFEST_JSON.read_text())
    canonical_count = manifest["hermes"]["sub_skills"]
    target_phrase = f"{canonical_count} sub-skills"
    for filename in ["README.md", "HERMES.md", "AGENTS.md"]:
        path = REPO_ROOT / filename
        if not path.exists():
            continue
        head = "\n".join(path.read_text().splitlines()[:120])
        assert target_phrase in head, (
            f"{filename} does not reference '{target_phrase}' in its first "
            f"120 lines. Update it to match manifest.json's canonical phrasing."
        )


def test_version_triangulation():
    """manifest.json version must equal CITATION.cff version."""
    manifest = json.loads(MANIFEST_JSON.read_text())
    citation_text = CITATION_CFF.read_text()
    citation_match = re.search(r"^version:\s*(\S+)", citation_text, re.MULTILINE)
    assert citation_match, "CITATION.cff has no 'version:' line"
    manifest_version = manifest["version"]
    citation_version = citation_match.group(1)
    assert manifest_version == citation_version, (
        f"manifest.json version is {manifest_version} but CITATION.cff has "
        f"{citation_version}. They must match every release."
    )


def test_pyproject_version_matches_manifest():
    """pyproject.toml version must equal manifest.json version."""
    manifest = json.loads(MANIFEST_JSON.read_text())
    pyproject_text = (REPO_ROOT / "pyproject.toml").read_text()
    pyproject_match = re.search(
        r'^version\s*=\s*"([^"]+)"', pyproject_text, re.MULTILINE
    )
    assert pyproject_match, "pyproject.toml has no 'version = \"...\"' line"
    manifest_version = manifest["version"]
    pyproject_version = pyproject_match.group(1)
    assert manifest_version == pyproject_version, (
        f"manifest.json version is {manifest_version} but pyproject.toml has "
        f"{pyproject_version}. Bump pyproject.toml on every release."
    )


def test_install_scripts_default_tag_is_set():
    """install.sh must declare a HERMES_SEO_TAG default."""
    sh_text = (REPO_ROOT / "install.sh").read_text()
    sh_match = re.search(
        r'REPO_TAG="\$\{HERMES_SEO_TAG:-([^}]+)\}"', sh_text
    )
    assert sh_match, "install.sh has no recognizable REPO_TAG default"


def _extract_section(text: str, heading: str) -> str:
    """Return the body of a `## <heading>` section, up to the next H2 heading or EOF."""
    pattern = rf"^## {re.escape(heading)}\b.*?(?=^## |\Z)"
    m = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    return m.group(0) if m else ""


def test_orchestrator_sub_skills_list_matches_disk():
    """skills/seo/SKILL.md Sub-Skills numbered list must equal set(skills/*) minus orchestrator itself.

    Background: v1.9.8 CI guard checks README/CLAUDE/AGENTS but not the orchestrator's
    own canonical-phrasing source. PR #92 surfaced that the orchestrator had stale "21
    specialized" claims and the list included seo-firecrawl (extension-only). This
    guard closes that gap.
    """
    text = (REPO_ROOT / "skills" / "seo" / "SKILL.md").read_text()
    section = _extract_section(text, "Sub-Skills")
    listed_list = re.findall(r"^\d+\.\s+\*\*(seo-[a-z-]+)\*\*", section, re.MULTILINE)
    assert len(listed_list) == len(set(listed_list)), (
        f"Duplicate entries in Sub-Skills list: "
        f"{[n for n in listed_list if listed_list.count(n) > 1]}"
    )
    listed = set(listed_list)
    on_disk = {
        d.name for d in (REPO_ROOT / "skills").iterdir()
        if d.is_dir() and (d / "SKILL.md").is_file()
    }
    # The orchestrator (`seo`) does not list itself.
    # seo-firecrawl is documented separately in an Optional Extensions subsection
    # because it lives only in extensions/, not in skills/.
    expected = on_disk - {"seo"}
    assert listed == expected, (
        f"Sub-Skills list != skills/ dir. "
        f"Missing from list: {sorted(expected - listed)}. "
        f"Extra in list: {sorted(listed - expected)}."
    )


def test_orchestrator_delegates_list_matches_disk():
    """skills/seo/SKILL.md Subagents bullet list must equal references/delegates/seo-*.md."""
    text = (REPO_ROOT / "skills" / "seo" / "SKILL.md").read_text()
    section = _extract_section(text, "Subagents")
    listed_list = re.findall(r"^- `(seo-[a-z-]+)`", section, re.MULTILINE)
    assert len(listed_list) == len(set(listed_list)), (
        f"Duplicate entries in Subagents list: "
        f"{[n for n in listed_list if listed_list.count(n) > 1]}"
    )
    listed = set(listed_list)
    on_disk = {
        p.stem for p in DELEGATES_DIR.iterdir()
        if p.is_file() and p.suffix == ".md" and p.name.startswith("seo-")
    }
    assert listed == on_disk, (
        f"Subagents list != references/delegates/ dir. "
        f"Missing from list: {sorted(on_disk - listed)}. "
        f"Extra in list: {sorted(listed - on_disk)}."
    )


def _extract_frontmatter(text: str) -> str:
    """Return the YAML frontmatter block (between the first two `---` lines).

    Returns the body between the delimiters (exclusive), or empty string if no
    frontmatter present. Scoping the regex search to this block prevents a
    fenced code example or later doc snippet from satisfying a metadata check.
    """
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    return m.group(1) if m else ""


def test_skill_metadata_versions_match_manifest():
    """Every SKILL.md metadata.version must equal manifest.json version (with community allowlist)."""
    COMMUNITY_OVERRIDES = {"seo-content-brief": "1.0.0"}

    manifest = json.loads(MANIFEST_JSON.read_text())
    expected_default = manifest["version"]
    errors = []

    candidates = list((REPO_ROOT / "skills").glob("*/SKILL.md")) + list(
        (REPO_ROOT / "extensions").glob("*/skills/*/SKILL.md")
    )
    for skill_md in candidates:
        skill_name = skill_md.parent.name
        rel = skill_md.relative_to(REPO_ROOT)
        text = skill_md.read_text()
        frontmatter = _extract_frontmatter(text)
        if not frontmatter:
            errors.append(f"{rel} has no YAML frontmatter block")
            continue
        # metadata.version is nested under `metadata:` and indented by 2 spaces
        match = re.search(
            r'^  version:\s*"([^"]+)"', frontmatter, re.MULTILINE
        )
        if not match:
            errors.append(f"{rel} has no metadata.version in frontmatter")
            continue
        actual = match.group(1)
        expected = COMMUNITY_OVERRIDES.get(skill_name, expected_default)
        if actual != expected:
            errors.append(f"{rel}: version is {actual}, expected {expected}")

    assert not errors, "Skill metadata.version drift:\n  " + "\n  ".join(errors)


def test_manifest_description_counts():
    """manifest.json description must mention sub-skills and delegate briefs."""
    manifest = json.loads(MANIFEST_JSON.read_text())
    desc = manifest["description"]
    assert re.search(r"\d+\s+sub-skills", desc), "manifest description missing sub-skills count"
    assert re.search(r"\d+\s+delegate", desc), "manifest description missing delegate brief count"
    assert manifest["hermes"]["sub_skills"] == _count_skill_dirs()
    assert manifest["hermes"]["delegate_briefs"] == _count_delegate_files()


def test_reference_files_have_at_least_one_link():
    """Every skills/*/references/*.md file must be cited somewhere in the repo.

    Guards against orphan reference files — docs on disk that no SKILL.md,
    agent, top-level doc, or other reference file actually links to. Catches
    drift like the v2.0.0-era incident where llmstxt-evidence.md landed in
    references/ but was reachable only through a sibling cross-link, not
    through its parent SKILL.md.

    Cross-skill references are legitimate (e.g. skills/seo/references/
    backlink-quality.md is cited from seo-backlinks/SKILL.md) so the search
    is repo-wide rather than per-parent-skill.

    Searches the full filename (`name.md`) and the Obsidian-style wikilink
    form (`[[name]]`) across: every SKILL.md, every agent .md, every doc/*.md,
    top-level README/CHANGELOG/CLAUDE/AGENTS/CONTRIBUTING, and every other
    reference file. Each reference is excluded from its own search.
    """
    ref_files = list((REPO_ROOT / "skills").glob("*/references/*.md"))
    if not ref_files:
        return  # no references at all — nothing to check

    search_paths: list[Path] = []
    search_paths += list((REPO_ROOT / "skills").glob("*/SKILL.md"))
    search_paths += list(DELEGATES_DIR.glob("*.md"))
    search_paths += list((REPO_ROOT / "docs").glob("*.md"))
    for doc in ("README.md", "CHANGELOG.md", "HERMES.md",
                "AGENTS.md", "CONTRIBUTING.md"):
        candidate = REPO_ROOT / doc
        if candidate.exists():
            search_paths.append(candidate)
    # Reference files can cite each other (e.g. via [[wikilink]]).
    search_paths += ref_files

    text_by_path = {p: p.read_text() for p in search_paths}

    orphans = []
    for ref in ref_files:
        slug = ref.stem  # 'llmstxt-evidence'
        filename = ref.name  # 'llmstxt-evidence.md'
        wikilink = f"[[{slug}]]"
        found = False
        for other_path, text in text_by_path.items():
            if other_path == ref:
                continue
            if filename in text or wikilink in text:
                found = True
                break
        if not found:
            orphans.append(str(ref.relative_to(REPO_ROOT)))

    assert not orphans, (
        "Orphan reference files (on disk, not cited anywhere repo-wide):\n  "
        + "\n  ".join(orphans)
        + "\n\nFix: link the file from its parent SKILL.md, a related "
          "reference doc, or a top-level doc — or delete if obsolete."
    )
