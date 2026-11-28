import visualLabels from '../presentation/american-v1/category-labels.json' with { type: 'json' };
import labels from '../data/request-labels.json' with { type: 'json' };

export function requestLabel(group, locale = 'en') {
  const visual=visualLabels[labels[group]?.en];
  if(visual)return visual[locale]??visual.en;
  const adapted={Mahjong:{'zh-CN':'多米诺骨牌','zh-TW':'多米諾骨牌',en:'Dominoes'},Staples:{'zh-CN':'主食','zh-TW':'主食',en:'Staple Foods'}}[labels[group]?.en];
  if(adapted)return adapted[locale]??adapted.en;
  return labels[group]?.[locale] ?? labels[group]?.en ?? ({ 'zh-CN': '物品', 'zh-TW': '物品', en: 'Items' }[locale] ?? 'Items');
}

export function requestPictures(payload, group) {
  return [...new Set(payload.stage.specimens.filter(token => token.group === group)
    .map(token => payload.scene.sprites[token.form]))];
}

export function requestExamples(pictures, count = 3) {
  if (pictures.length <= count) return [...pictures];
  return Array.from({ length: count }, (_, index) => pictures[Math.round(index * (pictures.length - 1) / (count - 1))]);
}
