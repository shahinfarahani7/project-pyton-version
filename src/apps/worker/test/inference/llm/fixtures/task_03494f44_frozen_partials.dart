import 'dart:convert';

import 'package:edgemint_worker/inference/llm/reduce_partial_envelope.dart';
import 'package:edgemint_worker/validation/json_output_validator.dart';

import 'task_e98fbaac_map_response.dart';

/// Provenance label for fixtures that are not byte-exact device captures.
enum Phase1FixtureProvenance {
  /// Reassembled from INFERENCE RESPONSE blocks with matching END sha256.
  byteExact,

  /// Semantically reconstructed from supplied run observations; not byte-exact.
  semanticReconstruction,
}

/// Observed metadata for task `tsk_dev_03494f44` (supplied; not in repo logs).
const task03494f44ObservedInputChars = 13769;
const task03494f44ObservedMap2ResponseChars = 1068;
const task03494f44ObservedModelCalls = 3;
const task03494f44ObservedDurationSeconds = 47.6;

/// Map partial 1 — semantic reconstruction aligned with Map-1 analogue
/// ([taskE98fbaacMapResponseCore]). Device SHA `bf6e1f2e…` applies to the
/// captured Map-1 response, not necessarily this JSON encoding.
const task03494f44Map1Provenance =
    Phase1FixtureProvenance.semanticReconstruction;

Map<String, dynamic> task03494f44Map1Partial() {
  final extract = JsonOutputValidator.extractJsonObject(
    taskE98fbaacMapResponseCore,
  );
  if (extract.ok && extract.object != null) {
    return Map<String, dynamic>.from(extract.object!);
  }
  return {
    'summary':
        'A customer reports a delayed delivery and an incorrect substitution in their grocery order.',
    'keyPoints': [
      'Delayed delivery of order B410 by 40 minutes.',
      'Incorrect substitution of regular milk in order B426.',
      'Pending refund for incorrect milk in B426.',
      'Uncertainty about the substitution approval process in B426.',
    ],
    'mainComplaint':
        'Delayed delivery and incorrect substitution in grocery orders.',
    'suggestedImprovement':
        'Provide clear and accurate delivery estimates and support for substitution decisions.',
    'missingOrUnclear': [
      'Pending refund for incorrect milk in B426.',
      'Uncertainty about the substitution approval process in B426.',
    ],
  };
}

/// Map partial 2 — semantic reconstruction from supplied `03494f44` observations.
///
/// Supplied facts encoded here:
/// - Banking/refund resolved in this chunk.
/// - Explicit customer priority: substitution + unsupported approval claim.
/// - Does NOT re-list pending refund for B426.
const task03494f44Map2Provenance =
    Phase1FixtureProvenance.semanticReconstruction;

Map<String, dynamic> task03494f44Map2Partial() => {
  'summary':
      'Payment and refund issues were resolved; substitution approval dispute remains.',
  'keyPoints': [
    r'Pending $72.40 authorization was released; one $72.40 payment remains.',
    r'$6 refund was received on day 4 within five business days.',
    'The temporary banking question and the refund are now resolved.',
    'Customer priority is the unexplained substitution and unsupported approval claim.',
  ],
  'mainComplaint':
      'The unexplained substitution and the unsupported claim that I approved it.',
  'suggestedImprovement': '',
  'missingOrUnclear': [
    'Substitution cause and approval record remain unresolved.',
  ],
};

List<Map<String, dynamic>> task03494f44FrozenPartials() => [
  task03494f44Map1Partial(),
  task03494f44Map2Partial(),
];

List<ReducePartialEnvelope> task03494f44FrozenEnvelopes() =>
    ReducePartialEnvelope.wrapLegacyPartials(task03494f44FrozenPartials());

String task03494f44FrozenPartialsJson() =>
    jsonEncode(task03494f44FrozenPartials());
