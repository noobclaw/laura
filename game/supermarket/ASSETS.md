# 素材來源登記

| 素材 | 來源 | 授權 | 取得方式 | 用在 |
|---|---|---|---|---|
| KayKit Restaurant Bits 1.0（28 個模型 + 貼圖） | github.com/KayKit-Game-Assets/KayKit-Restaurant-Bits-1.0，作者 Kay Lousberg | CC0（包內 LICENSE.txt） | git clone，2026-11-23 | 食材箱、櫃檯、冰櫃、烤箱、罐子 |
| KayKit City Builder Bits 1.0（13 個） | github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0 | CC0 | 同上 | 汽車、建築、路燈、灌木、長椅 |
| KayKit Furniture Bits 1.0（13 個） | github.com/KayKit-Game-Assets/KayKit-Furniture-Bits-1.0 | CC0 | 同上 | 貨架、櫃子、地毯、燈、沙發 |
| KayKit Prototype Bits 1.0（7 個） | github.com/KayKit-Game-Assets/KayKit-Prototype-Bits-1.0 | CC0 | 同上 | 箱子、棧板、木桶、金幣 |
| Changa Bold 字體 | github.com/google/fonts → ofl/changa（由可變字體取 700 字重） | SIL OFL 1.1（OFL.txt 隨字體放在 Resources/Font） | git sparse checkout，2026-11-23 | 全部介面文字（拉丁 + 阿拉伯） |
| 人物、介面圖形、圖示、特效、音效、音樂、App 圖示 | 自己用程式生成 | 原創 | — | — |

沒有使用：用戶購買的 `idle_supermarket` 包裡的任何圖片、音效、文字、程式碼。
模型檔放在 `unity/Assets/Resources/Kit/`，檔名前綴 r／c／f／p 對應上面四個包。

## 2026-11-23 — realistic American supermarket look (replaces the KayKit low-poly set, which is removed)

| Where in the project | Source | Author | Licence | What we did to it |
|---|---|---|---|---|
| `unity/Assets/Resources/Mk/*.obj` (76 models), `unity/Assets/Art/MkTex/*` (151 textures) | Fab: "Neighborhood Market Kit - Realistic" (glTF download, listing 3b43168e-9116-4c94-87ae-c6d5331f9336; listing states it is AI-generated and uses fictional brands only) | Gridwright | Fab Standard License (commercial use in any engine; raw files may not be redistributed, so this repository must stay private) | Chose 76 of 256 models; converted glTF to OBJ with one group per material; thinned heavy meshes by vertex clustering (cars 68k to about 19k triangles); textures resized to 1024/512 and the occlusion-roughness-metal map repacked for Unity (R metal, G occlusion, A smoothness). Script: kept outside the repo, described in SPEC.md §10 |
| `unity/Assets/Art/Ground/*` | Poly Haven: large_floor_tiles_02, interior_tiles, clean_asphalt, concrete_floor_02, white_plaster_02 (1k colour + normal) | Poly Haven | CC0 | none |
| `unity/Assets/Resources/People/Walking.fbx`, `Idle.fbx` | Mixamo: character "Remy", animations "Walking" (in place) and "Breathing Idle" | Adobe | Mixamo terms: free for use in games incl. commercial; raw files may not be redistributed | none; shirt and trouser colours are tinted at run time |

Not used in this build although downloaded: Poly Haven fruit and bread scans (too heavy for many shelf copies).
