# Minty Pup v1 asset inspection

- Inspection date: 2026-08-29
- Runtime path: `res://assets/characters/dog/dog_mint_v1_rigged.glb`
- Source: `Meshy_AI_Minty_Pup_biped_Character_output.glb`
- Git policy: private local binary; ignored by Git

## Confirmed structure

- 1 skinned mesh: `char1`
- 4,201 triangles, 3,787 imported vertices
- AABB: approximately `1.152 × 1.700 × 0.760 m`
- Origin is at the feet; vertical axis is Godot Y
- 1 `Skeleton3D`, 24 bones
- 1 material with an embedded 2048×2048 PNG
- No blend shapes
- One 0.033333-second Meshy base clip; no autoplay

## Bone names

```text
Hips
LeftUpLeg LeftLeg LeftFoot LeftToeBase
RightUpLeg RightLeg RightFoot RightToeBase
Spine02 Spine01 Spine
LeftShoulder LeftArm LeftForeArm LeftHand
RightShoulder RightArm RightForeArm RightHand
neck Head head_end headfront
```

## Rejected alternatives

- `Meshy_AI_Minty_Pup_0829033809_texture.glb`: texture-rich reference only; no skeleton
- `Meshy_AI_Minty_Pup_biped_Animation_Walking_withSkin.glb`: contains an unwanted walking clip

Motion clips are created inside Godot from a semantic rig profile. Meshy animation clips are not used.
