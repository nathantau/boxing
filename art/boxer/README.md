# Boxer art (Mixamo)

Drop files here and the game picks them up automatically; until then it uses capsule boxers.

```
art/boxer/boxer.fbx        character, "With Skin" (used for both boxers)
art/boxer/boxer_b.fbx      optional second character for P2 ("With Skin")
art/boxer/anims/<clip>.fbx one file per clip below, "Without Skin"
```

Download every animation **with the same character selected** in Mixamo, so the bone names
match. Search Mixamo for the term in the middle column, pick the take you like, and save it
under the file name on the left. "Mirror" means tick Mixamo's *Mirror* checkbox before
downloading, to get the other side from the same take.

| File (anims/)   | Search Mixamo for                         | Needed?                      |
|-----------------|-------------------------------------------|------------------------------|
| `idle.fbx`      | boxing idle / fight idle (loop)           | yes                          |
| `jab.fbx`       | jab / lead jab                            | yes                          |
| `cross.fbx`     | same jab, **Mirror** on (right hand)      | optional → jab               |
| `hook_r.fbx`    | hook punch (right hand)                   | yes                          |
| `hook_l.fbx`    | same hook, **Mirror** on                  | yes                          |
| `uppercut.fbx`  | uppercut                                  | yes                          |
| `block.fbx`     | boxing block / center block               | yes                          |
| `dodge_l.fbx`   | dodge / dodging (to the left)             | yes                          |
| `dodge_r.fbx`   | same dodge, **Mirror** on                 | yes                          |
| `hit.fbx`       | head hit / hit reaction                   | yes                          |
| `knockdown.fbx` | knocked down / knocked out (fall)         | yes                          |
| `get_up.fbx`    | getting up                                | optional (else stays down)   |
| `ko.fbx`        | knocked out (if different from knockdown) | optional → knockdown         |
| `stagger.fbx`   | stunned / dizzy / big head hit            | optional → hit               |
| `parry.fbx`     | outward block / inward block              | optional → block             |
| `tired.fbx`     | tired / out of breath idle (loop)         | optional → idle              |

Mixamo download settings: Format **FBX Binary**, 30 fps, Skin **Without Skin** for animations
(**With Skin** for `boxer.fbx`), **In Place** ticked wherever Mixamo offers it.

No Godot import settings need changing: each animation file is read either as Godot's default
imported scene or as an Animation Library. Clips are time-stretched to the frame data in
`sim/moves.tres`; set where each clip's key moment is (fist fully out, dodge fully out) in
`game/presentation/clip_timings.tres`.
