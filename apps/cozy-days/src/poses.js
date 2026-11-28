// Rendering, input geometry, hints and flight origins share one resolved pose.
// Stage indices and original placement records remain stable for saved rounds.
export function resolvePose(placement, form, tokenId) {
  const at=form.locations?.[tokenId];
  return at ? {...placement,at} : placement;
}
