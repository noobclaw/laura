export const SHOP_PRODUCTS = Object.freeze([
  Object.freeze({
    id: 'cozy.toolbox.welcome',
    unlock: 5,
    kind: 'starter',
    contents: Object.freeze({
      sweep: 2,
      return: 2,
      scan: 3,
      rub: 1
    })
  }),
  Object.freeze({
    id: 'cozy.toolbox.helpers',
    unlock: 9,
    kind: 'helpers',
    contents: Object.freeze({
      sweep: 5,
      return: 5,
      scan: 5,
      rub: 3
    })
  }),
  Object.freeze({
    id: 'cozy.space.bundle',
    unlock: 10,
    kind: 'spacePack',
    contents: Object.freeze({
      bay: 3,
      tray: 3
    })
  }),
  Object.freeze({
    id: 'cozy.energy.refill',
    unlock: 8,
    kind: 'energyPack',
    contents: Object.freeze({
      stamina: 5
    })
  })
]);
export function shopProducts(frontier, kind) {
  return SHOP_PRODUCTS.filter(product => frontier >= product.unlock && (!kind || (product.contents[kind] ?? 0) > 0));
}
// The Web preview has no payment gateway. Only a connected storefront may supply localized prices.
export function productPresentation(product, storefront) {
  const offer = storefront?.get(product.id);
  return {
    ...product,
    displayPrice: offer?.displayPrice ?? null,
    purchasable: Boolean(offer?.available && offer?.displayPrice)
  };
}
