import 'package:flutter/material.dart';

import '../../theme/tokens/extensions.dart';
import 'admin_compact_scaffold.dart';
import 'admin_operations_pages.dart';
import 'ai_eval_admin_page.dart';
import 'ai_marketplace_settings_page.dart';
import 'ai_models_admin_page.dart';
import 'ai_plans_admin_page.dart';
import 'ai_prompts_admin_page.dart';
import 'ai_provider_credentials_admin_page.dart';
import 'ai_settings_page.dart';
import 'ai_skills_admin_page.dart';
import 'ai_voice_models_admin_page.dart';

/// یک ورودی برای همهٔ تنظیمات AI. کلید API فقط در زبانهٔ اعتبارنامه است.
class AIAdminHubPage extends StatelessWidget {
  final int initialIndex;

  const AIAdminHubPage({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    final hub = context.settingsHub;
    final tabs = [
      adminTx(context, 'تنظیمات', 'Settings'),
      adminTx(context, 'کلیدها', 'Keys'),
      adminTx(context, 'مدل‌ها', 'Models'),
      adminTx(context, 'صدا', 'Voice'),
      adminTx(context, 'پلن‌ها', 'Plans'),
      adminTx(context, 'پرامپت', 'Prompts'),
      adminTx(context, 'مهارت', 'Skills'),
      adminTx(context, 'بازارچه', 'Marketplace'),
      adminTx(context, 'ارزیابی', 'Evaluation'),
    ];
    final index = initialIndex.clamp(0, tabs.length - 1);
    return DefaultTabController(
      key: ValueKey(index),
      length: tabs.length,
      initialIndex: index,
      child: AdminCompactScaffold(
        title: adminTx(context, 'هوش مصنوعی', 'Artificial intelligence'),
        subtitle: adminTx(
          context,
          'کلید فقط در زبانهٔ اعتبارنامه نگه داشته می‌شود',
          'API keys live only on the credentials tab',
        ),
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hub.pagePadding.left, 4, hub.pagePadding.right, 0),
              child: const AiOpsMetricsBanner(),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: hub.cardTitleStyle(
                Theme.of(context).textTheme,
                color: Theme.of(context).colorScheme.primary,
              ),
              tabs: [for (final label in tabs) Tab(text: label)],
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  AISettingsPage(embedded: true),
                  AIProviderCredentialsAdminPage(embedded: true),
                  AIModelsAdminPage(embedded: true),
                  AIVoiceModelsAdminPage(embedded: true),
                  AIPlansAdminPage(embedded: true),
                  AIPromptsAdminPage(embedded: true),
                  AISkillsAdminPage(embedded: true),
                  AIMarketplaceSettingsPage(embedded: true),
                  AIEvalAdminPage(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
