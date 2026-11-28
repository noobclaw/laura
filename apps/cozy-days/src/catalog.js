export async function readStage(number, reader = async url => {
  const response = await fetch(url);
  if (!response.ok) throw new Error('Stage data unavailable');
  return response.json();
}) {
  if (!Number.isInteger(number) || number < 1 || number > 160) throw new RangeError('Unknown stage');
  return reader(new URL(`../data/stage-${String(number).padStart(3,'0')}.json`, import.meta.url));
}
export async function readCatalog(reader = async url => (await fetch(url)).json()) {
  return reader(new URL('../data/catalog.json', import.meta.url));
}
