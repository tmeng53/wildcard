# Coaches

The AI coaches' characters, one folder per coach id as the API names it (`xiaohun` is 毛头, the sleepy apricot cat in a red coach's jacket with a whistle on a lanyard). A coach is the same kind of character as a member: it stands on members' rig (`../Placeholder/rig.json`) and plays members' moves, in a fixed look.

- `look.json`: `version`, the `persona` whose idle and cheer it plays, the `species` whose accent moves play on top (an `editor.json` species id, optional), `look` (a variant per slot, as a member's look) and `colors` (a `#rrggbb` per slot, for parts whose `tones.json` allows it).
- `art/<slot>/<variant>/`: parts only this coach wears, in the members' SVG subset and 240×320 canvas. Any slot it doesn't have here comes from members' art. These folders sit outside `../Placeholder/art`, so the character editor and random looks never offer them.

Being fired plays 注销账号's teary loop. A coach without a folder here has no character in this build, and the app shows a stand-in.
