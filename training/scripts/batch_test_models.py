import argparse
import os
import shutil

from acestep.handler import AceStepHandler
from acestep.llm_inference import LLMHandler
from acestep.inference import GenerationConfig, GenerationParams, generate_music

CAPTIONS = {
    "cahue": (
        "Gentle Ca Hue folk song, female vocal, dan tranh zither and dan nguyet "
        "moon lute, slow rubato, traditional Hue pentatonic melody"
    ),
    "nhanhac": (
        "Hue royal court music (Nha nhac), ceremonial ensemble of dan nguyet moon "
        "lute, dan tam three-string lute, truc sao bamboo flute, dan bau monochord, "
        "trong and chanh bell drums, stately processional tempo, Nam ai pentatonic "
        "mode, dignified ritual atmosphere of the Nguyen dynasty court orchestra, "
        "UNESCO intangible heritage"
    ),
}

LYRICS = """[Verse 1]
Ngựa ô a í a ngựa ô,
Cám cảnh dưới hồ bắt lên mà thắng.
Tình tang tình tang tính,
Tính tang tình tang tình,
Thiếp đưa chàng chinh lại về dinh,
Thiếp đưa chàng chinh lại về dinh.

[Verse 2]
Ngựa ô a í a ngựa ô,
Em sắm kiệu vàng em ra cửa Bắc,
Hồ lục làng trong ghép bộ để rước tình thăng.
Tình tang tình tang tính tình tang,
Tình tang tình a í tang tình.
Thiếp đưa chàng chinh lại về dinh,
Thiếp đưa chàng chinh lại về dinh."""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["instrumental", "vocal"], required=True)
    ap.add_argument("--caption", choices=sorted(CAPTIONS), required=True)
    ap.add_argument("--models", nargs="+", default=["none", "ep50", "ep100", "ep150", "ep200", "ep250", "ep300"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--root", default=os.path.expanduser("~/ACE-Step-1.5"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    dit = AceStepHandler()
    llm = LLMHandler()
    status, ok = dit.initialize_service(
        project_root=args.root,
        config_path="acestep-v15-base",
        device="mps",
    )
    print("[INIT]", status, flush=True)

    for m in args.models:
        if m == "none":
            if hasattr(dit, "unload_lora"):
                dit.unload_lora()
        else:
            print("[LORA]", dit.load_lora(os.path.join(args.root, "lokr_output", m)), flush=True)
        params = GenerationParams(
            caption=CAPTIONS[args.caption],
            lyrics=("" if args.mode == "instrumental" else LYRICS),
            instrumental=(args.mode == "instrumental"),
            vocal_language="vi",
            duration=60,
            inference_steps=32,
            guidance_scale=7.0,
            shift=3.0,
            seed=42,
            task_type="text2music",
            thinking=False,
        )
        cfg = GenerationConfig(batch_size=2, use_random_seed=False, audio_format="mp3")
        res = generate_music(dit, llm, params, cfg, save_dir=args.out)
        mode_dir = "sing" if args.mode == "vocal" else "instrument"
        dest_dir = os.path.join(args.out, "DOT1", m, mode_dir)
        os.makedirs(dest_dir, exist_ok=True)
        for i, a in enumerate(res.audios, 1):
            src = a.get("path") or a.get("audio_path") or a.get("file")
            dst = os.path.join(dest_dir, f"{m}_{args.caption}_{mode_dir}_{i}.mp3")
            if src and os.path.exists(src):
                shutil.move(src, dst)
            print("[DONE]", dst, flush=True)


if __name__ == "__main__":
    main()
