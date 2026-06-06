import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/services/density_service.dart';

void main() {
  const baseline = {'tomato': 950.0, 'onion': 850.0};

  test('resolves override over baseline over default', () {
    const service = DensityService(
      baseline: baseline,
      overrides: {'tomato': 700.0},
    );

    expect(service.densityFor('tomato'), 700.0); // override wins
    expect(service.densityFor('onion'), 850.0); // baseline
    expect(service.densityFor('unicorn'), kDefaultDensity); // 800 fallback
  });

  test('baselineFor ignores overrides', () {
    const service = DensityService(
      baseline: baseline,
      overrides: {'tomato': 700.0},
    );

    expect(service.baselineFor('tomato'), 950.0);
    expect(service.isOverridden('tomato'), isTrue);
    expect(service.isOverridden('onion'), isFalse);
  });

  test('densitiesFor maps a class list', () {
    const service = DensityService(baseline: baseline);
    final result = service.densitiesFor(['tomato', 'onion', 'unicorn']);

    expect(result, {'tomato': 950.0, 'onion': 850.0, 'unicorn': kDefaultDensity});
  });
}
