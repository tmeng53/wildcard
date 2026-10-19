import { describe, expect, it } from 'vitest';

import { MemberId } from './check-in.js';
import { PhotoPath, Photos, isOwnPhoto } from './photos.js';

const member = MemberId.parse('3f0c8a52-6f39-4c39-9a51-0c7c3c4a4f1e');
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
    const other = MemberId.parse('11d0042d-1e3c-4c84-9a5f-e61c0a24f8b3');
    const path = PhotoPath.parse(`${member}/${photo}`);
    expect([isOwnPhoto(path, member), isOwnPhoto(path, other)]).toStrictEqual([true, false]);
  });
});

describe('Photos', () => {
  const ref = (id: string) => ({ path: `${member}/${id}` });
  const second = '11d0042d-1e3c-4c84-9a5f-e61c0a24f8b3';
  const third = '22e1153e-2f4d-4d95-8a6f-f72d1b35a9c4';
  const fourth = '33f2264f-3a5e-4ea6-9b7a-a83e2c46bad5';

  it('takes 1 to 3 different photos, in order', () => {
    expect(Photos.parse([ref(second), ref(photo)])).toStrictEqual([ref(second), ref(photo)]);
  });

  it.each([
    ['none', []],
    ['four', [ref(photo), ref(second), ref(third), ref(fourth)]],
    ['a repeat', [ref(photo), ref(photo)]],
    ['a path that isn’t a photo', [{ path: 'avatar.png' }]],
    ['other fields', [{ ...ref(photo), url: 'https://example.com' }]],
  ])('refuses %s', (_case, photos) => {
    expect(Photos.safeParse(photos).success).toBe(false);
  });
});
