class_name InputBits
## One tick of one player's input, packed into a single int.
## Every bit means "held this tick". The sim finds new presses by comparing with
## the previous tick, so touch swipes are sent as a one-tick pulse.

const JAB := 1 << 0
const HOOK_L := 1 << 1
const HOOK_R := 1 << 2
const UPPERCUT := 1 << 3
const BLOCK := 1 << 4
const DODGE_L := 1 << 5
const DODGE_R := 1 << 6

const ALL := JAB | HOOK_L | HOOK_R | UPPERCUT | BLOCK | DODGE_L | DODGE_R
