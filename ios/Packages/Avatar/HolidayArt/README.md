# Holiday art, for upload

Pieces for the holiday-limited stores (TURKEY TROT `trot-…`, JINGLE JOG `jingle-…`), at the paths
the app downloads them to. They are not bundled: an admin puts each file with the `put_art`
admin tool at its path here (`avatar/art/<slot>/<piece>/<part>.svg`, and each store's window model
at `avatar/stores/<store>.json`), and the stores and unlock
rules that open them are data too. `ArtTreeTests` reads every file here the way a phone would
before it is used, so a file that fails would fail there first.

The openings that play on a takeover day are drawn by `../OpeningArt/openings.mjs` into the
bundled `Sources/AvatarArt/Openings/<scene id>/`, and uploaded the same way under
`openings/<scene id>/`.
