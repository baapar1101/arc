"""تست انتخاب مهارت برای پرسش (SKL-01)."""
from app.services.ai.ai_skill_runtime import SkillMetadata, select_skills_for_query


def _meta(slug: str, description: str = "") -> SkillMetadata:
    return SkillMetadata(
        install_id=1,
        package_id=1,
        skill_slug=slug,
        description=description,
        allowed_tool_names=[],
        source_type="portable",
        anthropic_skill_id=None,
    )


def test_select_skills_matches_slug_substring():
    picked = select_skills_for_query(
        "با hscript-docs یک اسکریپت بنویس",
        [_meta("hscript-docs"), _meta("unrelated")],
    )
    assert [m.skill_slug for m in picked] == ["hscript-docs"]


def test_select_skills_matches_persian_description_tokens():
    picked = select_skills_for_query(
        "تحلیل بدهکاران را شروع کن",
        [_meta("en-slug", "تحلیل بدهکاران و مطالبات")],
    )
    assert picked and picked[0].skill_slug == "en-slug"
