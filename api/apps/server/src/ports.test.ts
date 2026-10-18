import { describe, expect, it } from 'vitest';

import { PhotoPath, UserId, isOwnPhoto } from './ports.js';

const member = UserId.parse('3f0c8a52-6f39-4c39-9a51-0c7c3c4a4f1e');
const photo = '9b2e1d4c-7a8f-4e2b-8c1d-2f3a4b5c6d7e';

describe('PhotoPath', () => {
  it('takes a member folder and a photo id', () => {
    expect(PhotoPath.safeParse(`${member}/${photo}`).success).toBe(true);
  });

  it.each([
    ['no folder', photo],
    ['a nested folder', `${member}/${member}/${photo}`],
    ['a climb out of the folder', `${member}/../${photo}`],
    ['a file extension', `${member}/${photo}.jpg`],
    ['upper case', `${member}/${photo.toUpperCase()}`],
    ['a trailing line break', `${member}/${photo}\n`],
  ])('refuses %s', (_case, path) => {
    expect(PhotoPath.safeParse(path).success).toBe(false);
  });
});

describe('isOwnPhoto', () => {
  it('is true only for photos in the member’s own folder', () => {
    const other = UserId.parse('11d0042d-1e3c-4c84-9a5f-e61c0a24f8b3');
    const path = PhotoPath.parse(`${member}/${photo}`);
    expect([isOwnPhoto(path, member), isOwnPhoto(path, other)]).toStrictEqual([true, false]);
  });
});
