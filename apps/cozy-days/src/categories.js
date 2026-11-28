import equivalence from '../data/category-equivalence.json' with { type: 'json' };

export function normalizeCategories(payload) {
  const pairs = equivalence[payload.stage.number];
  if (!pairs) return payload;
  const aliases = new Map(pairs), category = group => aliases.get(group) ?? group;
  return {
    ...payload,
    stage: {
      ...payload.stage,
      specimens: payload.stage.specimens.map(token => ({ ...token, group: category(token.group) })),
      shipments: payload.stage.shipments.map(request => ({ ...request, group: category(request.group) }))
    }
  };
}
