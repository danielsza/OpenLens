# Aperture Test-Data Checklist (for Daniel)

Goal: produce a **small** Aperture library (10–20 photos is plenty) that
exercises every feature, so OpenLens has real samples of each on-disk format to
reverse-engineer. **Variety matters far more than volume — do NOT copy the
500 GB library.** A fresh library with a handful of photos is ideal.

When done: drop a **copy** of the whole `.aplibrary` into the connected folder
(or zip it). Work on a copy so your originals are never at risk.

> Tip: where it says "one adjustment per photo", that's so each edit's data can
> be isolated. Use a different photo for each so the `RKImageAdjustment` blobs
> don't overlap.

## 1. Adjustments — TOP PRIORITY (this unblocks rendering)
Apply **one adjustment to its own photo** for as many of these as you can:

- [ ] Exposure (move the Exposure slider)
- [ ] White Balance (change temperature/tint)
- [ ] Contrast
- [ ] Saturation / Vibrancy
- [ ] Highlights & Shadows
- [ ] Levels
- [ ] Curves
- [ ] Definition
- [ ] Black & White (convert one)
- [ ] Color (selective color)
- [ ] Crop (use a specific aspect ratio, e.g. 16:9)
- [ ] Straighten (rotate a couple degrees)
- [ ] Sharpen / Edge Sharpen
- [ ] Noise Reduction
- [ ] Vignette
- [ ] Red-Eye
- [ ] Retouch / Spot & Patch (heal a spot)
- [ ] Then: **one photo with MANY adjustments stacked** (exposure + WB + crop +
      curves + sharpen) so I can see how multiple edits coexist and order.
- [ ] **One adjustment applied with a brush** (e.g. brush in some exposure) so a
      mask is created.

## 2. Ratings, flags, labels
- [ ] Rate photos 1★, 2★, 3★, 4★, 5★ (at least one each)
- [ ] Reject one photo (the ⌫ / "X" rating)
- [ ] Flag two or three photos
- [ ] Apply each color label once (red, orange, yellow, green, blue, purple, gray)

## 3. Keywords
- [ ] Assign several keywords to a few photos
- [ ] Use a **hierarchical** keyword (parent > child, e.g. Travel > Beach)
- [ ] One photo with 4–5 keywords at once

## 4. Organization
- [ ] Create a 2nd and 3rd **project**
- [ ] Create a **folder** and put projects inside it (test nesting)
- [ ] Create a regular **Album** and add photos
- [ ] Create a **Smart Album** with a rule (e.g. rating ≥ 4)
- [ ] Make a **Stack** from 3 photos and set the pick; try auto-stack too
- [ ] Reorder photos in a project (custom **sort order**)

## 5. Versions & masters
- [ ] **Duplicate a version** (so one master has Version-1 and Version-2)
- [ ] Import a few photos as **Referenced** (Store Files: "In their current
      location") so the master lives outside the library
- [ ] Rotate one photo 90°

## 6. File types
- [ ] Import a **RAW** file (CR2/CR3/NEF/ARW) — and edit it
- [ ] Import a **RAW+JPEG pair**
- [ ] Import a short **video** clip
- [ ] (If easy) a PNG and a TIFF, for format coverage

## 7. Metadata, places, faces, notes
- [ ] Edit IPTC on a photo: Caption, Title, Byline, Copyright
- [ ] Assign a **location/place** to a photo (Places / map)
- [ ] Name a **face** on a photo
- [ ] Add a **note** to a photo; add an **attachment** if possible

## 8. Trash
- [ ] Move 1–2 photos to the Aperture **Trash** (don't empty it — leave them in
      trash so I get `isInTrash` samples)

## 9. External editor
- [ ] "Edit with External Editor" on one photo, make a change, save (creates an
      externally-edited master/version)

---

### Minimum viable set (if you're short on time)
Even just these would unblock the biggest items:
1. 6–8 photos each with **one different adjustment** (exposure, WB, crop,
   curves, B&W, sharpen) + 1 photo with **many** adjustments.
2. A few **ratings + color labels + keywords**.
3. One **RAW** photo (edited) and one **stack**.

That's enough for me to decode the adjustment/RAW/stack formats and start on
real rendering.
