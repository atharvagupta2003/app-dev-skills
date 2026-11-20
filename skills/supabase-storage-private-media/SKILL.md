---
name: supabase-storage-private-media
description: How to store user photos and other private media in Supabase Storage. Covers private buckets created by migration with one policy per command, uploader-owned folder paths, read access tied to a live link that ends at once, short signed URL lifetimes, no update policy, issue once and consume once upload paths, registration bound to the scanned object version, metadata stripping, an admin-only evidence bucket, cleanup of never-registered uploads, and purges that delete objects before rows. Load when adding an upload, a bucket, a storage policy or a signed URL.
---

# Supabase storage for private media

## When to use this
- You are adding an upload flow for photos, audio, documents or any file a member should not see publicly.
- You are writing a storage policy, a signed URL helper or a bucket.
- A feature shows another member's file, and access must end when a link or membership ends.
- A member deletes an account, a space ends, or a report needs its evidence kept.

## Rules
1. **Create every private bucket in a migration, with its policies.** The bucket's settings (private, size limit, allowed types) and its policies are declared in the schema files. A bucket made by hand in a dashboard was missing from the repository and its policies were absent from the code.
2. **Write one policy per command.** Insert, select and delete each get their own policy. Do not write one policy for all commands. Leave out update entirely, so an object cannot be replaced in place.
3. **Put each upload in the uploader's own folder.** The path is `<user id>/<random id>.<ext>`. Policies check `(storage.foldername(name))[1] = auth.uid()::text`. A user cannot write into another user's folder.
4. **Tie read access to a live link, and end it at once.** Another member can read an object only while the link that grants it is live: a live pairing, an open shared space, a visible item. When the link ends, freezes or the item is rejected, the same policy returns false on the next request.
5. **Keep signed URLs to minutes.** A signed link keeps working until it expires, even after access ends. A link valid for seven days is a bearer capability that survives a block or a deletion. Use minutes (for example 300 seconds for a view, 900 for a download). Sign with the caller's session where the policy can answer, and with the service role only for export and purge.
6. **Bind registration to the bytes that were scanned.** Before a file is registered, the function reads the object's version, size and etag, downloads and checks it, then reads them again. If anything changed in between, refuse with a retryable busy response. The registration in SQL also checks the version. Otherwise an uploader can swap the file after the scan.
7. **Strip metadata before upload, and check it again on the server.** Photos carry location and device data in metadata segments. The app re-encodes and strips the segments, and the registration function refuses any file that still has them, deleting it at once.
8. **Keep reported media in an evidence bucket with no member policy.** When a member reports a photo, copy it to a private evidence bucket that only the service role can reach. The report then holds its own copy, so the uploader removing the photo or deleting the account does not destroy the evidence. An admin reads it through the admin function with a short signed link.
9. **Remove uploads that were never registered.** An upload that never reaches the registration step is an orphan. A worker deletes objects older than a set number of hours that no row names.
10. **In a purge, delete the objects first, then the rows, and refuse to delete rows while objects remain.** If an object delete fails, the rows stay, and the next run finishes the job. Deleting rows first leaves photos with no row to find them by.
11. **Issue, consume once, then check.** Record every upload path the server issues, with the account and an expiry. A registration accepts only a path that was issued to the same account, is not yet consumed and has not expired. It consumes the path when the check starts, whether the check passes or fails, and refuses any path that is already registered. Why: an "add photo" action accepted any existing object path in the account's folder. Pointing it at an already registered photo made the server's byte check delete that object.

## How to do it
A private bucket and its three policies, in one migration or a declarative file:

```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('member-media', 'member-media', false, 10485760, array['image/jpeg'])
on conflict (id) do nothing;

create policy "member media insert own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'member-media'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "member media select own folder" on storage.objects
  for select to authenticated
  using (bucket_id = 'member-media'
         and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "member media select live link" on storage.objects
  for select to authenticated
  using (bucket_id = 'member-media'
         and public.is_linked_member((storage.foldername(name))[1]));

create policy "member media delete own folder" on storage.objects
  for delete to authenticated
  using (bucket_id = 'member-media'
         and (storage.foldername(name))[1] = (select auth.uid())::text);
-- No update policy: objects are immutable.
```

`is_linked_member` is a security definer function that returns true only for a live link. It belongs with the other access functions (see [supabase-rls-and-function-access](../supabase-rls-and-function-access/SKILL.md)).

The upload sequence:
1. The app uploads to the caller's folder under a random name.
2. The app calls the register action with the object name.
3. The function reads version, size and etag, downloads, checks the file type and metadata, reads the version again, and refuses on any change.
4. The function inserts the row, which names the object. Only a named object is readable by others.
5. A worker deletes any object that no row names after the set number of hours.

## Gotchas
- **Symptom:** any signed-in user can read any file in the bucket. **Cause:** a select policy checked only that the user was signed in. **Fix:** scope every select policy to the owner or to a live link, and test a stranger.
- **Symptom:** a former counterpart still sees a photo for a few minutes after the link ended. **Cause:** a signed link made earlier is still valid. **Fix:** keep the link lifetime to minutes, and clear the client's cache when the link ends.
- **Symptom:** a photo changes after it was approved. **Cause:** the bucket allowed overwrites, or the registration did not bind to a version. **Fix:** no update policy, and a version check in the registration.
- **Symptom:** a photo with a location is visible to others. **Cause:** metadata was not stripped on the device, and the server did not check. **Fix:** strip in the app and refuse on the server.
- **Symptom:** an add photo call deleted a photo that was already registered. **Cause:** the registration accepted any object path in the account's folder, and the failed byte check deleted the object it was given. **Fix:** rule 11. Accept only issued, unconsumed, unexpired paths, consume on every outcome, and refuse registered paths. Keep deletes to objects that the upload flow itself issued.
- **Symptom:** storage fills up with photos no row points to. **Cause:** uploads that never reached registration. **Fix:** the orphan sweep.
- **Symptom:** a purge deleted rows, and some objects can no longer be found. **Cause:** rows were removed before objects. **Fix:** objects first, and a row delete that refuses while any object of the owner remains.
- **Symptom:** a delete of a member's account fails halfway. **Cause:** a storage call failed and the rest ran. **Fix:** every step is a no-op when done, storage is cleared before the rows, and any storage error aborts the whole step so a retry can finish it.

## Checklist
- [ ] The bucket is created in a migration with size and type limits and `public = false`.
- [ ] Each command has its own policy. There is no update policy.
- [ ] Paths start with the uploader's id.
- [ ] Read access follows a live link and ends with it.
- [ ] Signed links last minutes, not days.
- [ ] Registration checks version, size and etag before and after the download.
- [ ] Metadata is stripped on the device and refused on the server.
- [ ] Reported media is copied to the evidence bucket.
- [ ] An orphan sweep and a purge order (objects, then rows) exist.
- [ ] Registration accepts only issued, unconsumed, unexpired paths for the same account, and refuses registered ones.

## Tests that prove it
- Policy tests as the owner, as a live counterpart, as a former counterpart, as a stranger and as `anon`. The owner and the live counterpart read; the others get nothing.
- An update attempt is refused.
- A registration test that changes the object between the check and the read, and expects `busy_retry`.
- A test that a file with metadata is refused and removed.
- A test that registering an already registered path is refused, and that the registered object still exists afterwards. Also test an unissued path, a path issued to another account, an expired path, and a second use of an issued path.
- A purge test that a failed object delete leaves the rows in place.
- Upload-side details are in [media-upload-pipeline](../media-upload-pipeline/SKILL.md).

## Related skills
- [supabase-rls-and-function-access](../supabase-rls-and-function-access/SKILL.md): the access functions the policies call.
- [data-lifecycle-export-purge-deletion](../data-lifecycle-export-purge-deletion/SKILL.md): deletion and purge order in full.
- [media-upload-pipeline](../media-upload-pipeline/SKILL.md): the app side of the upload.
- [background-jobs-and-sweeps](../background-jobs-and-sweeps/SKILL.md): the orphan sweep.
