# Universal Bookmarker prototype review

Prototype: https://universal-bookmark.vercel.app/

Reviewed desktop at 1440px and mobile at 393px, including a search for Gatsby.
This historical review preceded repository setup. It is a review and proposed
direction, not an approved implementation spec. Screenshots and DOM measurements
are saved in [prototype-evidence](prototype-evidence/).

## Findings

1. **Saved content is below the first mobile screen.** The large promotional
   heading, URL form, descriptive copy, and collection buttons take priority
   over the actual library. A returning user should immediately see their items.
2. **Search retains unrelated content ahead of results.** Searching for Gatsby
   leaves the marketing section and collection controls above the result. The
   expanded field also crowds the brand into two lines. Search needs its own
   focused results experience.
3. **Capture supports URLs only.** The agreed product also needs screenshots,
   photos, PDFs, and files. Saving a link and importing a file should join the
   same library without requiring different organisational systems.
4. **Missing previews waste space.** All three starter cards allocate large
   image regions to “No image.” Compact title/source/type fallbacks would make
   mixed-content browsing more useful.
5. **Mobile navigation loses desktop destinations.** Desktop Home / All Items /
   Wishlist / Collections navigation disappears at the narrow width. Collection
   chips preserve some destinations, but navigation changes substantially.

These are findings about a mobile web prototype. Native Dynamic Type,
VoiceOver, native point dimensions, and actual iOS accessibility are not
verifiable from these screenshots.

## Recommended first-release flow

- Open into **Library**, with recent items and useful type/collection filters.
- Make **Search** a stable, prominent destination with immediate results.
- Keep **Collections** optional; saving must not require manual filing.
- Use a toolbar **Save** action and the iOS Share extension for quick capture.
  Offer Link, Photos, and Files routes in the app. Screenshots use the photo
  route; PDFs use the file route.
- Show capture success immediately, expose upload/sync state, and retry safely
  when connectivity returns. Keep the same private account/library on web.
- Open links, images, and documents into appropriate previews or detail views.
- Preserve the approved monochrome identity, with native system typography,
  appearance-aware colours, and the original colours in saved content previews.

## Alternatives considered

- **Library-first — recommended:** strongest fit for consolidating scattered
  saves and browsing recent captures, with search close at hand.
- **Search-first:** useful for people who already have a large established
  archive; offers less context when the library is new.
- **Board-first:** strong for visual collections and inspiration; dense document
  and mixed-file retrieval needs additional list/search treatment.

## HIG references used

Requested skill: apple-design-hig, source
https://github.com/duart-555/claude-code-setup/tree/main/skills/apple-design-hig

Read accessibility, layout, typography, color, designing-for-ios, tab-bars,
searching, lists-and-tables, and sheets from its reference directory.

- `layout.md > Visual hierarchy`: content importance should drive order.
- `layout.md > Adaptability`: preserve functionality across available sizes.
- `searching.md > Best practices`: give important search a primary position.
- `lists-and-tables.md > Best practices`: lists suit scannable text-heavy items.
- `tab-bars.md > Best practices`: tabs navigate; Save is an action.
- `sheets.md > Best practices`: short, cancellable, focused modal tasks.

The choice to make collections optional and save immediately is product
judgment based on the user's goal of reducing manual organisation.

## Delivery context

The current workspace is fresh and contains no app repository, previous logo
kit, Swift compiler, Xcode, or simulator. The approved logo remains the visual
reference from the conversation. The eventual native project needs a Mac/Xcode
build or a macOS CI run for iOS compilation and device validation.
