---
name: media-upload-pipeline
description: Build a photo upload pipeline for a mobile app with private storage. Covers resizing and re encoding on the device, stripping every metadata segment from a JPEG so location never reaches storage, verifying again on the server by walking the whole file, binding the check to the stored object's version, treating a failed download as a refusal, short lived signed URLs, clearing image caches when access ends, and simulator or emulator upload pitfalls. Load when users upload photos or files, when media must not reveal location, or when a private bucket serves images.
---

# Media upload pipeline

## When to use this
- Users upload photos, and the photos are shown to other people or kept private.
- Photos come from a phone camera, which often writes location into the file.
- A private storage bucket serves images through signed links.
- Access to a set of photos can end (a shared space closes, an account is removed).

## Rules
1. **Re encode on the device before upload.** Resize the long edge and encode again as JPEG. Why: re encoding drops most metadata, and a smaller file uploads faster.
2. **Strip every metadata segment byte by byte, even after re encoding.** Why: an encoder can keep some segments, and a file can carry a second image after its end marker.
3. **Verify again on the server, by walking the whole file.** Do not trust the client's strip. Why: the server is the last place that can refuse a photo, and the client may be an old build.
4. **Bind the check to the exact bytes stored.** Read the object's version, size and etag before and after the download, and refuse if they changed. Why: otherwise someone can swap the file between the check and the registration.
5. **Treat a failed read as a refusal, never as a pass.** A missing object or a storage error is a retry or a refusal. Why: a fallback to "allow" lets an unchecked file through.
6. **Keep the bucket private, and sign links per request.** Sign with the user's own session, in small batches, and cache per path for less than the link's life. Why: a public bucket or a long link outlives the access that allowed it.
7. **Never save short lived signed links to disk.** Why: a restored link is expired or, worse, still valid after access ended.
8. **Clear the image cache and the signed links when access ends.** Why: the photos would still draw on the device after the owner lost access.
9. **Never log image content, metadata or location.** Log the refusal code, not the file.

## How to do it

### 1. On the device
```ts
export async function preparePhoto(uri: string, width: number, height: number) {
  const target = fitLongEdge(width, height, 1440);           // never upscales
  const ctx = ImageManipulator.manipulate(uri);
  if (target.width !== width) ctx.resize(target);
  const ref = await ctx.renderAsync();
  return ref.saveAsync({ format: SaveFormat.JPEG, compress: 0.8 });
}
```

Then strip the bytes in a pure function shared with the server, so both use one walk:

```ts
const bytes = new Uint8Array(await new File(saved.uri).arrayBuffer()); // not base64 + atob
const clean = stripJpegMetadata(bytes);                                  // throws not_a_jpeg
```

Keep what changes how the picture looks: the JFIF segment, the colour profile (an APP2 segment whose payload starts with `ICC_PROFILE`), and the Adobe colour segment (APP14). Remove everything else: EXIF and XMP (APP1), IPTC (APP13), other APPn segments, comments, and every byte after the end of image.

### 2. Upload and register
- Upload with `upsert: false`, a content type of `image/jpeg`, and the path `<bucket>/<user id>/<uuid>.jpg`. Own folder only.
- Prepare and upload two photos at once, but register them one at a time. Registration picks the lowest free position, so parallel registrations race.
- Show each tile's stage: waiting, preparing, uploading, saving.

### 3. Verify on the server
The register function does this, in order:
1. Read the object's version, size and etag.
2. Download the bytes.
3. Read the version again. If it changed, return a retryable busy response.
4. Walk every segment from start to end of image. Refuse with a not-a-JPEG code if the walk fails. Refuse with a metadata code if any segment that should be gone is present, and delete the object at once.
5. The database write checks the version it was given. If the object is no longer that version, refuse.
6. A missing object is a not-found refusal. Any other storage error is a retryable server error. Nothing passes by default.

The walk needs to handle: several scan segments in a progressive file, stuffed zero bytes and restart markers inside entropy coded data, fill bytes, and a truncated file that has no end marker.

### 4. Signed links
```ts
const { data } = await supabase.storage.from(bucket).createSignedUrls(paths, ttlSeconds);
```

- Group requests made in the same short window (about 15 ms) into one call, capped at 50 paths.
- Cache by path. Refresh a bit before the link expires, and never more than five minutes early.
- Keep the link's time in the cache key, or in the bucket name, so each bucket has its own lifetime.
- Use a shorter life for sensitive buckets, and make the life a row in the database so it can change without a release.

## Gotchas
- **Upload arrives as zero bytes.** In an early test, a base64 string decoded with `atob` produced empty uploads. The cause was not pinned down in the notes; whitespace in the base64 string is the suspect (hypothesis). Fix: read the file as bytes and upload the bytes, then check the byte count on the server.
- **Photo frame blank until it draws.** Cause: the image loads after the layout. Fix: a quiet placeholder until the image's load event. A photo the user just took shows its local file while the signed link loads.
- **Parallel registrations race for one slot.** Cause: the server picks the lowest free position on each call, so two calls at once can pick the same one. Fix: one register call at a time, in pick order, while the bytes still upload in parallel.
- **A photo survives the owner's removal.** Cause: a cached signed link or image in the device's cache. Fix: on removal or on the end of access, drop the query entries, the signed links and the just uploaded local files.
- **A file passes after the download fails.** Cause: a fallback to "accept" on a storage error. Fix: a retryable error, and no registration.
- **A file with a second image after the end marker.** The walk must stop at the end marker and refuse or cut what follows. A check that only reads the header misses it.
- **Bundled sample photos fail the server's metadata check.** Cause: a sample image shipped with the app or the test fixtures still carried metadata segments, so the server refused it. Fix: strip every metadata segment from each bundled sample before it is committed, and run the same server check on the samples in tests. A sample that the server refuses is a fixture bug, not a server bug.
- **A registration accepted a path nobody uploaded for that request.** Cause: the register call trusted any object name in the account's folder. Fix: issue and consume paths server side, as in [supabase-storage-private-media](../supabase-storage-private-media/SKILL.md) rule 11.
- **A stray orphan upload.** An upload that is never registered stays in storage. Fix: a scheduled job removes uploads older than a set age (one day in this project's design).

## Checklist
- [ ] Photos are re encoded and stripped on the device before upload.
- [ ] The server walks the whole file and refuses any leftover metadata.
- [ ] The check and the database write use the same object version.
- [ ] A failed read is a refusal or a retry, never a pass.
- [ ] The bucket is private, and links are signed per request and short lived.
- [ ] No signed link is saved to disk.
- [ ] Access ending clears the cache, the links and the local copies.
- [ ] Logs carry codes, not content or location.
- [ ] On a simulator or emulator, a real photo uploads with the same byte count as the file on disk.

## Tests that prove it
- Unit tests of the strip on fixture files: a file with EXIF (with GPS), a file with a colour profile that must survive, a progressive file, a file with bytes after the end marker, a truncated file, and a non JPEG.
- A test that the server refuses a file that still carries a metadata segment, and deletes it.
- A test that the registration refuses when the object version changed after the check.
- A test that a missing object and a storage error are not treated as a pass.
- A test that signed link requests in one window are one call, and that the cache refreshes before expiry.
- A test that clearing access empties the cache and the local copies.

## Related skills
- `react-query-in-react-native`: the cache that holds signed links, and clearing it.
- `expo-app-start-performance`: why signed links are never saved to the start copy.
- `expo-local-android-builds`: check the upload on a release build as well as in development.
