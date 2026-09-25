import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/widgets/ai/ai_activated_skill_chips.dart';

void main() {
  test('extracts activated skills from function_results', () {
    final skills = extractActivatedSkillsFromResults({
      kActivatedSkillsStorageKey: [
        {'slug': 'hscript-docs', 'description': 'راهنمای اسکریپت'},
      ],
    });
    expect(skills, hasLength(1));
    expect(skills.first.slug, 'hscript-docs');
  });
}
