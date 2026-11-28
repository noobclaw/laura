// Only explicitly identified save-data failures may trigger recovery. Resource
// loading, programming errors and unknown schema versions keep the original save.
export class InvalidSaveError extends TypeError {}

export function parseStoredSave(raw) {
  if (raw === null || raw === undefined) return undefined;
  try {
    const record = JSON.parse(raw);
    if (!record || typeof record !== 'object' || Array.isArray(record)) throw new InvalidSaveError('Invalid saved record');
    return record;
  } catch (cause) {
    if (!(cause instanceof SyntaxError)) throw cause;
    throw new InvalidSaveError('Invalid saved JSON', { cause });
  }
}

export async function restoreSavedGame({ raw, key, storage, boot }) {
  try {
    return { game: await boot(parseStoredSave(raw)), recovered: false };
  } catch (error) {
    if (raw === null || raw === undefined || !(error instanceof InvalidSaveError)) throw error;
    if (storage.getItem(key) !== raw) throw new Error('Save changed in another tab. Reload this page.');
    const backupKey = `${key}-damaged`;
    // A failed or unverifiable backup must never lead to deleting the main save.
    storage.setItem(backupKey, raw);
    if (storage.getItem(backupKey) !== raw) throw new Error('Could not verify save backup. Original save retained.');
    if (storage.getItem(key) !== raw) throw new Error('Save changed in another tab. Reload this page.');
    const game = await boot(undefined);
    // Leave the original key in place until the caller durably saves the fresh
    // game. A failed initialization/write leaves that original byte-for-byte.
    return { game, recovered: true };
  }
}
