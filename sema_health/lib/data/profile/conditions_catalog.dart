/// Pre-existing-condition slugs the bio-profile sheet can collect. Each
/// slug here is what `profile.conditions_contains` rules in
/// `assets/triage/rules.yaml` match against — keep these in sync.
///
/// New conditions added here without a corresponding rule are still
/// safe to ship: they sit in the profile until a rule references them.
/// The reverse — a rule using an unknown slug — is caught by triage
/// engine tests that assert every `conditions_contains` value is one
/// of these.
class ConditionOption {
  const ConditionOption({
    required this.slug,
    required this.label,
    required this.description,
  });

  /// Slug used in `BioProfile.conditions` and matched by
  /// `profile.conditions_contains` predicates.
  final String slug;

  /// Short user-facing label shown on the chip.
  final String label;

  /// One-line clarifier shown beneath / on long-press.
  final String description;
}

/// The catalog. Order shown in the UI = order here.
const List<ConditionOption> kConditionsCatalog = [
  ConditionOption(
    slug: 'asthma',
    label: 'Asthma',
    description: 'Wheezing, rescue inhaler — relevant for breathing rules.',
  ),
  ConditionOption(
    slug: 'epilepsy',
    label: 'Epilepsy',
    description: 'History of seizures.',
  ),
  ConditionOption(
    slug: 'diabetes',
    label: 'Diabetes',
    description: 'Type 1 or 2.',
  ),
  ConditionOption(
    slug: 'hypertension',
    label: 'High blood pressure',
    description: 'Hypertension; on medication or not.',
  ),
  ConditionOption(
    slug: 'heart-disease',
    label: 'Heart condition',
    description: 'Any diagnosed cardiac condition.',
  ),
  ConditionOption(
    slug: 'severe-allergies',
    label: 'Severe allergies',
    description: 'EpiPen carrier, anaphylaxis history.',
  ),
  ConditionOption(
    slug: 'sickle-cell',
    label: 'Sickle cell',
    description: 'Sickle-cell disease or trait.',
  ),
];
