# NutAnnotator

A one-photo-at-a-time bounding box annotator for iPad and Mac. Pick a folder,
draw boxes with the Apple Pencil, assign a label, tap Next. Built for labelling
in front of the television, not for a workstation session.

## Setup

1. Xcode: File > New > Project > Multiplatform > App, named `NutAnnotator`.
2. Delete the generated `ContentView.swift` and `NutAnnotatorApp.swift`.
3. Drag in the eight files from `NutAnnotator/`.
4. Deployment target iOS 17 / macOS 14 or later.
5. On macOS, Signing & Capabilities > App Sandbox > User Selected File Access:
   set to **Read/Write**. The app writes `annotations.json` back into the folder
   you pick.

No packages, no dependencies.

## Using it

**Choose folder** reads every image in it, sorted the way Finder sorts, and
remembers the choice through a security-scoped bookmark. Next launch it reopens
the same folder and jumps to the first photo that still has no boxes.

On the canvas:

| Action | Gesture |
|---|---|
| Draw a box | Drag on empty image |
| Select a box | Tap inside it |
| Move a box | Drag from inside it |
| Resize | Drag one of the four corner dots |
| Delete | Select, then the trash button (or the Delete key) |
| Change a label | Select the box, tap a label chip |
| Zoom | Pinch with two fingers |
| Pan while zoomed | Drag with two fingers |

Zoom and pan use a real `UIScrollView` under the hood, so it is the same pinch
behaviour as Photos. It only responds to two fingers, on purpose: drawing,
moving, and resizing boxes stays a one-finger (or Pencil) gesture regardless of
zoom level, so the two never fight over the same touch. Zoom resets to fit the
whole photo every time you move to a new one.

The label bar does double duty on purpose. With nothing selected, tapping a
label sets what the *next* box will be. With a box selected, it relabels *that*
box. The caption above the chips tells you which mode you are in, so there is no
hidden state.

**Renaming and deleting labels.** The pencil button at the end of the label bar
(also under More > Manage labels) opens the label list. Tap a label to rename
it in place — every box already using that name updates to match, across every
photo, immediately. Swipe a label to delete it, which also removes every box
under that name after a confirmation that says how many; the app refuses to
delete the last remaining label, since a new box always needs something to be
labelled as. Nothing here is fixed: rename "good" to whatever your own defect
categories are called, or split one label into several as your dataset grows,
without being stuck with whatever names you started the folder with.

**Apple Pencil only** is on by default, in the More menu. It reads raw
`UITouch.type` and ignores anything that is not the Pencil, which is what stops
your palm from drawing boxes while your hand rests on the screen. Turn it off if
you want to label with a finger or on a Mac.

Arrow keys work as Previous and Next if you have a keyboard attached.

## What it writes

`annotations.json` lands in the photo folder and is saved automatically, six
hundred milliseconds after your last edit and again whenever the app leaves the
foreground. It is the working file: labels plus every box, keyed by file name.
Boxes are stored normalised (0 to 1, origin top-left), so they survive any later
resizing of the source images.

**Export YOLO and COCO** writes a self-contained `dataset/` subfolder:

```
dataset/images/*      a copy of every annotated photo
dataset/labels/*.txt  YOLO: class cx cy w h, normalised
dataset/classes.txt   one label per line, index = YOLO class id
dataset/data.yaml     Ultralytics config, ready for training
dataset/coco.json     COCO detection file, pixel coordinates
```

The photos are copied, not moved or linked, because YOLO expects `images/` and
`labels/` side by side with matching file stems. Photos already JPEG are
copied byte-for-byte; anything else (PNG, HEIC, TIFF, BMP, WEBP, …) is decoded
and re-encoded as JPEG at quality 0.92, so `dataset/images/` only ever contains
one format. Photos with no boxes are left out. Re-exporting skips files that
are already there, so a second export after labelling another fifty photos is
cheap. If disk space matters, delete `dataset/images/` after you have moved
the folder to your training machine, or symlink it there instead.

`data.yaml` points both `train` and `val` at the same folder. Split it properly
before you trust a validation number.

**Export for Edge Impulse** writes the `bounding-box-labels` format:

```
edgeimpulse/training/bounding_boxes.labels
edgeimpulse/training/*.jpg
edgeimpulse/testing/bounding_boxes.labels
edgeimpulse/testing/*.jpg
```

This is not the "files" array shown on Edge Impulse's own documentation
page — that shape produced repeated "Invalid type" upload failures in
practice. This format instead mirrors an actual, confirmed-working
`bounding_boxes.labels` file exported by Edge Impulse Studio itself: a flat
dictionary keyed by file name, with no per-photo `category` (the
training/testing folder already says that), no whole-image label, and no
metadata — this format has no field for either, so neither is written:

```json
{
    "version": 1,
    "type": "bounding-box-labels",
    "boundingBoxes": {
        "IMG_1234.jpg": [
            { "label": "good", "x": 105, "y": 201, "width": 91, "height": 90 }
        ]
    }
}
```

The file is written as hand-built JSON text rather than through `JSONEncoder`,
so field order and presence are guaranteed byte-for-byte. Every string value —
each box's label and the photo's file name — has its whitespace collapsed to
underscores before it's written, since a stray space is exactly the kind of
thing a strict ingestion parser can reject outright.

Every photo is converted to JPEG the same way as the other export. Each photo
is assigned to training or testing by hashing its file name, not by a random
draw, so re-exporting after labelling more photos leaves the existing split
alone and only places the new photos — a random split would quietly reshuffle
photos you may already have trained on and invalidate whatever validation score
you had. About one in five photos lands in testing by default; that ratio is
set in `EdgeImpulseExporter.testFraction` if you want a different one.

Upload each folder separately through Edge Impulse's uploader, or point their
CLI at the `edgeimpulse/` folder directly.

The COCO file imports straight into CVAT if you ever want to move the work to a
desktop, or hand part of the labelling to someone else.

## Notes on the design

Photos are decoded through `CGImageSourceCreateThumbnailAtIndex` at 2400 px
rather than at full resolution, and the next two photos are decoded ahead of
time in the background. On a 20 megapixel source that is the difference between
Next feeling instant and Next feeling like a page load. It also applies the EXIF
rotation for you, which is the usual reason boxes end up sideways.

## Next step

When you have a few hundred labelled photos, the blob detection from the earlier
project becomes useful in the other direction: run it over new photos to
generate boxes automatically, load them here, and you only correct what is wrong
instead of drawing from scratch. The `annotations.json` format is the same, so
importing pre-labels means writing that file before you open the folder.
