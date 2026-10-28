import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_backend.dart';

/// The home hero photo must keep its proportions and the same crop on every
/// phone width (narrow Android, iPhone, Pro Max, tablet). Flutter also fails a test on any
/// overflow.
void main() {
  const photoAspect = 1200 / 801;

  for (final width in [320.0, 360.0, 390.0, 430.0, 600.0, 820.0]) {
    {
      testWidgets('hero fits at ${width.toInt()}dp', (tester) async {
        await pumpApp(
          tester,
          FakeBackend(baseRoutes()),
          size: Size(width, 844),
        );
        await settle(tester, frames: 3);

        final photo = find.byType(Image).first;
        final box = tester.getSize(photo);
        final card = tester.getSize(
          find.ancestor(of: photo, matching: find.byType(ClipRRect)).first,
        );

        // The photo is never zoomed in vertically: its box is at most as wide
        // as the photo is at the card height, so cover only trims the sides.
        expect(box.height, card.height);
        expect(box.width / box.height, lessThanOrEqualTo(photoAspect + .001));
        expect(card.height, inInclusiveRange(196, 232));

        // The text stays in its own 60% of the card, clear of the photo.
        final column = tester.getSize(
          find
              .ancestor(
                of: find.text('MARKETPLACE'),
                matching: find.byType(Column),
              )
              .first,
        );
        expect(column.width, lessThanOrEqualTo(card.width * .6 + .01));

        // Title, line and button all sit inside the card.
        final cardRect = tester.getRect(
          find.ancestor(of: photo, matching: find.byType(ClipRRect)).first,
        );
        for (final f in [
          find.text('Shop now'),
          find.text('Local sellers · Mobile money'),
        ]) {
          expect(cardRect.contains(tester.getCenter(f)), isTrue);
        }
      });
    }
  }
}
