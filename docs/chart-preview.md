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

## Which charts may be previewed

This is the one engine behaviour in this document that is not just a quirk but an
abort, so the theme guards it in one place: `Scripts/01 ChartEligibility.lua`.
Nothing else in the theme decides which chart types are safe.

Pump registers seven styles. Dumped from their static objects in this build:

| style | chart type | engine style type | columns/player |
|---|---|---|---|
| `single` | pump_single | 0 `OnePlayerOneSide` | 5 |
| `versus` | pump_single | 1 `TwoPlayersTwoSides` | 5 |
| `halfdouble` | pump_halfdouble | 2 `OnePlayerTwoSides` | 6 |
| `double` | pump_double | 2 `OnePlayerTwoSides` | 10 |
| `couple` | pump_couple | 1 `TwoPlayersTwoSides` | 5 |
| `couple-edit` | pump_couple | 2 `OnePlayerTwoSides` | 10 |
| `routine` | pump_routine | 3 `TwoPlayersSharedSides` | 10 |

The engine's compatible-style filter accepts style types 0 and 2 for one player and
1 and 3 for two players, and only styles whose eligible flag is set. `couple-edit`
is the one style with that flag cleared in this build, which means **one player has
no couple style at all** and the engine never offers couple charts. `ChangeReload`
then resolves the style from the chart's own type and the number of **human**
players, and builds one column per track in the chart. A couple chart has 10
tracks, so:

- one player has no compatible couple style; the engine returns no playable couple
  chart and nothing can select one;
- two players resolve to `couple` (5 columns per player) and abort at column 5.

Therefore one player may use single/halfdouble/double, two players may use single
only, and couple and routine are never offered. The difficulty
list, the song wheel, the group list and every preview build ask
`ChartEligibility`; `PreviewField.BuildCommand` refuses a rejected chart as the last
line of defence in front of the loader. Do not reintroduce a fallback that
"loads all charts again when the filtered list is empty" — that is how a couple
chart reaches the loader with two players.

The module reads only the joined-side count. It deliberately does not read
`AutoSetStyle`, the current style, or style types, so flipping an engine setting
cannot change which charts are considered safe.

## Scroll normalization for X mods

A menu `NoteField` draws through the engine's shared `PlayerState`, whose
scroll/displayed-beat map is only rebuilt by `Player::Load()` when gameplay starts. A
preview field never triggers that, so on the select screen the map is empty (identity)
or left over from the last chart played. With an identity map the chart's `#SCROLLS`
ratios collapse to 1, which is why charts authored on a rescaled grid (`#BPMS`÷N with
`#SCROLLS`×N — Gotta Go S2/S4/S9) preview N× too dense while ordinary charts (Hanky
Panky, ratio 1) look correct.

The theme corrects this itself instead of relying on the engine map: `PreviewField`'s
`SpeedTickCommand` reads the chart's `TimingData:GetScrolls(true)`, takes the ratio at
the current `GetSongBeatVisible()`, and multiplies the field's Current X mod by it. It
only runs for plain X mods (C mods ignore segments already; M/A mods are untouched) and
only sets the mod when the value changes, so there is no reload, no note-data rewrite
and no per-frame actor work. `Cache.RefreshSpeed` (cache path) and
`NotefieldPreview.HeartbeatCommand` (fallback) tick it from the existing 50 ms poll;
`BuildCommand` also ticks once so the first frame after a build is correct. Nothing is
logged: the correction is silent.

Known limits / things to check when touching this:

- **Timing data:** if `GetScrolls(true)` returns song-level ratios because the chart's
  split timing is not loaded, the tick is inert (every chart resolves to `ratio=1`,
  including charts that have `#SCROLLS`). That points at the timing source, not the
  math.
- **Engine map:** the correction assumes the select screen's displayed-beat map is
  identity. If it is stale from the last played chart, spacing is off by that chart's
  ratio; the symptom is previews changing after playing a chart with scroll segments
  (e.g. Hanky Panky becoming ~8× too spread after playing Gotta Go S4).
- Negative scroll ratios are treated as 1, ramped `#SPEEDS` segments are left to the
  engine, and M/A-mod previews are not normalized.

## Architecture

- `Scripts/01 ChartEligibility.lua` — the rule: which chart types the current number
  of joined sides may offer and preview. Every list, the song wheel, the group list
  and every preview build ask it; it is the only place that reads the player count.
- `BGAnimations/ScreenChartPreviewCache overlay.lua` — a dedicated overlay screen
  (registered in `[Common] OverlayScreens`). Overlay screens are created once per theme
  load and updated/drawn every frame, which is what lets the fields outlive the wheel
  screen. It owns the render targets and one field per (player, StepsType), pre-creates
  them hidden for the types `ChartEligibility` allows for the current number of joined
  sides, and exposes `Show/Hide/SetShown/Build/Ensure/RefreshSpeed` through the
  `InfinitesimalPreviewCache` global.
- `BGAnimations/PreviewCacheAFT.lua` — one render target, width part of its name so a
  player-count change cannot collide with the previous texture name.
- `BGAnimations/PreviewCacheKeeper.lua` — the reference holder above.
- `BGAnimations/PreviewCacheClient.lua` — wheel-side sprites bound to the render target
  by name; writes requests, never creates fields. Looks sprites up with `GetChild`
  because `Def.Sprite{...}` is a definition, not a live actor, and `GetChild` only
  searches direct children. Its heartbeat also calls `RefreshSpeed`.
- `BGAnimations/PreviewField.lua` — the field itself, shared by the cache and the
  in-screen fallback. Owns the `SpeedTick` scroll normalization.
- `BGAnimations/NotefieldPreview.lua` + `ScreenSelectMusic underlay/SongPreview.lua` —
  unchanged fallback path, used when the host is absent or when
  `SessionPreviewCache=false` in `Save/OutFoxPrefs.ini`. `NotefieldPreview` implements
  `Heartbeat` to tick the same `SpeedTick` for the visible field.

Costs measured in this install: creating a field ~120–200 ms warm, ~570 ms cold;
reloading an existing field 11–28 ms plus 1.6–16 ms for the note data; the first wheel
entry of a session pays the creation, later entries pay only the reload.
