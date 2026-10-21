# Chart preview: engine behaviour and design notes

Notes for whoever touches the difficulty-stage chart preview next. Everything here was
established empirically against this OutFox build (20250907), because several things
behave differently from what the StepMania 5 documentation implies.

## Two halves are needed to draw a chart

`NoteField:ChangeReload(Steps)` rebuilds the columns, receptors and noteskin and loads
the chart, but on a menu note field it **does not refresh the drawn note rows**: the
receptors update, the notes stay blank.

`NoteField:SetNoteDataFromLua(entries)` is what makes the rows refresh. Alone it leaves
the previous chart's rows in place.

So every build does both: `ChangeReload`, then `SetNoteDataFromLua`. A freshly created
field is the exception — its first `ChangeReload` draws correctly — which is why the
old "create a field per chart change" design appeared to work.

## Note data sources are not interchangeable

- `Steps:GetNoteData()` returns the chart's notes and is non-empty in every build we
  logged. This is the primary source.
- `Song:GetNoteData(iChart)` is **lazily populated**: it returns an empty table for a
  chart the song has not decoded yet, and the same chart returns its notes on a later
  call. Using it alone silently produced a blank preview. It is only a fallback, resolved
  by chart key so an index mismatch cannot show another chart.

## A cached field must not update while another screen runs

A `NoteField` owns a `Player` internally, and `Player::Update` was crashing in
`NoteField::DidHoldHead` (std::out_of_range) when the cached field updated against
gameplay's player state. Hiding the render target alone is not enough: a hidden
`ActorFrame` still updates its children. `hibernate()` short-circuits before children
update, so the cache hibernates its render target whenever the wheel is not showing the
preview.

## Menu note fields must use `FieldID=0`

With `FieldID=1` the cached field interfered with gameplay input:
`ScreenGameplay::Input → Player::Step → FlashGhostRow → NoteField::DidTapNote` threw
out_of_range when a note was hit. `FieldID=0` is what other themes use for menu fields
that coexist with a live gameplay field for the same player (alphav-dance's player
options screen keeps one alive while gameplay updates underneath), and it is what this
theme uses.

## Render targets are reference counted

`ActorFrameTexture:Create` registers its render target with `TEXTUREMAN` under
`SetTextureName`. `RageTexture` starts with a refcount of one, sprites increment it on
load, and the texture is deleted when the count reaches zero. The wheel's sprite is the
only normal reference, and it dies with the wheel screen — which deleted the render
target while the cache host still owned the AFT. The next bind then tried to load the
name from disk and fell back to a blank texture (black preview after playing a song).

`BGAnimations/PreviewCacheKeeper.lua` holds one reference for the life of the host, and
it takes that reference with an explicit `Load` in `InitCommand`; a hidden sprite that
only sets `Texture=` is not enough.

## Global style flips

`ChangeReload` calls `SetCurrentStyle`, so building fields for several chart types at
wheel load leaves the global style wherever the last build put it. Nothing on the select
screen reads it, `BigPreviewBall` is nil-guarded, and gameplay re-derives the style in
`StyleForSelection`, so this is safe — but it is worth knowing before adding code that
reads `GAMESTATE:GetCurrentStyle()` to the select screen.

`ArrowEffects::SetCurrentOptions` is a file-static, but `NoteField::DrawPrimitives`
re-sets it per field before drawing, so several cached fields cannot corrupt each
other's rendering.

## Architecture

- `BGAnimations/ScreenChartPreviewCache overlay.lua` — a dedicated overlay screen
  (registered in `[Common] OverlayScreens`). Overlay screens are created once per theme
  load and updated/drawn every frame, which is what lets the fields outlive the wheel
  screen. It owns the render targets and one field per (player, StepsType), pre-creates
  them hidden for the chart types the game offers for the current number of joined
  sides, and exposes `Show/Hide/SetShown/Build/Ensure` through the
  `InfinitesimalPreviewCache` global.
- `BGAnimations/PreviewCacheAFT.lua` — one render target, width part of its name so a
  player-count change cannot collide with the previous texture name.
- `BGAnimations/PreviewCacheKeeper.lua` — the reference holder above.
- `BGAnimations/PreviewCacheClient.lua` — wheel-side sprites bound to the render target
  by name; writes requests, never creates fields. Looks sprites up with `GetChild`
  because `Def.Sprite{...}` is a definition, not a live actor, and `GetChild` only
  searches direct children.
- `BGAnimations/PreviewField.lua` — the field itself, shared by the cache and the
  in-screen fallback.
- `BGAnimations/NotefieldPreview.lua` + `ScreenSelectMusic underlay/SongPreview.lua` —
  unchanged fallback path, used when the host is absent or when
  `SessionPreviewCache=false` in `Save/OutFoxPrefs.ini`.

Costs measured in this install: creating a field ~120–200 ms warm, ~570 ms cold;
reloading an existing field 11–28 ms plus 1.6–16 ms for the note data; the first wheel
entry of a session pays the creation, later entries pay only the reload.
