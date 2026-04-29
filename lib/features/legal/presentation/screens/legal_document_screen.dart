import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';

/// Renders a markdown legal document bundled in `assets/legal/`. Used for
/// the Privacy Policy and Terms of Use screens — both load from disk via
/// `rootBundle.loadString` so the canonical text lives in `docs/` (synced
/// to `assets/legal/`) and updating the legal copy is one file edit.
///
/// Why not host externally and use `url_launcher`: keeping the docs inside
/// the app lets users review them offline, makes them part of every release
/// (versioned by the build), and avoids a second domain in the CSP.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  /// Privacy Policy.
  factory LegalDocumentScreen.privacy({Key? key}) =>
      LegalDocumentScreen(
        key: key,
        title: 'Privacy Policy',
        assetPath: 'assets/legal/privacy-policy.md',
      );

  /// Terms of Use.
  factory LegalDocumentScreen.terms({Key? key}) =>
      LegalDocumentScreen(
        key: key,
        title: 'Terms of Use',
        assetPath: 'assets/legal/terms-of-use.md',
      );

  final String title;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EqAppBar(title: title),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Padding(
              padding: const EdgeInsets.all(EqSpacing.lg),
              child: Text(
                'Could not load this document. Please try again later.',
                style: EqTypography.bodyM.copyWith(color: EqColours.error),
              ),
            );
          }
          return Markdown(
            data: snapshot.data!,
            padding: const EdgeInsets.all(EqSpacing.lg),
            selectable: true,
            styleSheet: _markdownStyle(context),
          );
        },
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    // Apply EQ brand: Plus Jakarta Sans, ink for text, sky for links.
    return base.copyWith(
      p: EqTypography.bodyM,
      h1: EqTypography.headingXL.copyWith(height: 1.2),
      h2: EqTypography.headingL.copyWith(height: 1.25),
      h3: EqTypography.headingM.copyWith(height: 1.3),
      strong: EqTypography.bodyM.copyWith(fontWeight: FontWeight.w700),
      em: EqTypography.bodyM.copyWith(fontStyle: FontStyle.italic),
      a: EqTypography.bodyM.copyWith(
        color: EqColours.deep,
        decoration: TextDecoration.underline,
      ),
      blockquote: EqTypography.bodyM.copyWith(color: EqColours.grey),
      blockquoteDecoration: BoxDecoration(
        color: EqColours.ice,
        border: const Border(
          left: BorderSide(color: EqColours.sky, width: 4),
        ),
      ),
      code: EqTypography.bodyM.copyWith(
        fontFamily: 'monospace',
        backgroundColor: EqColours.ice,
      ),
      tableHead: EqTypography.bodyM.copyWith(fontWeight: FontWeight.w700),
      tableBody: EqTypography.bodyM,
      tableBorder: TableBorder.all(color: EqColours.border),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: EqSpacing.sm,
        vertical: EqSpacing.xs,
      ),
      listBullet: EqTypography.bodyM,
      h1Padding: const EdgeInsets.only(top: EqSpacing.lg, bottom: EqSpacing.sm),
      h2Padding: const EdgeInsets.only(top: EqSpacing.lg, bottom: EqSpacing.sm),
      h3Padding: const EdgeInsets.only(top: EqSpacing.md, bottom: EqSpacing.xs),
      blockSpacing: EqSpacing.md,
    );
  }
}
