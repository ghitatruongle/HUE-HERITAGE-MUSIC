import argparse
import gc
import os
import shutil
import torch

os.environ["PYTORCH_MPS_HIGH_WATERMARK_RATIO"] = "0.0"

from acestep.handler import AceStepHandler
from acestep.llm_inference import LLMHandler
from acestep.inference import GenerationConfig, GenerationParams, generate_music

PROMPTS = {
    "nhanhac": {
        "caption": (
            "Hue royal court music (Nha nhac), ceremonial court ensemble of dan nguyet moon "
            "lute, dan tam three-string lute, truc sao bamboo flute, dan bau monochord, "
            "ken bau oboe, trong chien and chanh bell drums, stately processional tempo, "
            "Nam ai pentatonic mode, dignified ritual atmosphere of the Nguyen dynasty court orchestra, "
            "UNESCO intangible heritage, authentic traditional Vietnamese palace music, instrumental"
        ),
        "lyrics": "",
        "instrumental": True,
        "mode_str": "nhanhac",
    },
    "cahue": {
        "caption": (
            "Cheerful Hue folk song Ly Muoi Thuong in Ly mode, bright female vocal "
            "with sao truc bamboo flute, dan tranh, dan bau, trong com drum and song loan clappers, "
            "traditional Hue folk music"
        ),
        "lyrics": """[Verse 1]
Một thương tóc xõa ngang vai,
Hai thương đi đứng vẻ người có duyên.
Ô tang ô tang tình tang,
Tình tang tình ô tang tình.

[Verse 2]
Ba thương ăn nói dịu hiền,
Bốn thương mơ mộng mắt huyền thêm xinh.
Ô tang ô tang tình tang,
Tình tang tình ô tang tình.

[Verse 3]
Năm thương dáng điệu thanh thanh,
Sáu thương nón Huế những vành nên thơ.
Ô tang ô tang tình tang,
Tình tang tình ô tang tình.

[Verse 4]
Bảy thương những phút mong chờ,
Tám thương bến đợi Hương Giang hữu tình.
Ô tang ô tang tình tang,
Tình tang tình ô tang tình.

[Verse 5]
Chín thương em bước nhẹ nhàng,
Mười thương tà áo dịu dàng bay xa.
Ô tang ô tang tình tang,
Tình tang tình ô tang tình.""",
        "instrumental": False,
        "mode_str": "cahue",
    },
    "lynguao": {
        "caption": (
            "Upbeat Hue folk song Ly Ngua O, bright female lead vocal with strong drum beats, "
            "dan nhi fiddle, mo tre woodblock mimicking horse hooves and dan tranh arpeggios, "
            "festive call-and-response energy, traditional Hue music"
        ),
        "lyrics": """[Verse 1]
Ngựa ô ơi ngựa ô,
Cám cảnh dưới hồ bắt lên mà thắng.
Tính tang lông căng xinh, tính tang lông căng xinh.
Thiếp đưa chàng chinh lại về dinh,
Thiếp đưa chàng chinh lại về dinh.

[Verse 2]
Ngựa ô ơi ngựa ô,
Em sắm kiệu vàng em ra cửa Bắc,
Hồ lục làng trong ghép bộ để rước tình thăng.
Tính tang lông căng xinh, tính tang lông căng xinh.
Thiếp đưa chàng chinh lại về dinh,
Thiếp đưa chàng chinh lại về dinh.

[Verse 3]
Ngựa ô ơi ngựa ô,
Cám cảnh dưới hồ bắt lên mà thắng...
Thiếp đưa chàng chinh lại về dinh.""",
        "instrumental": False,
        "mode_str": "lynguao",
    },
}


def cleanup_memory(dit=None):
    if dit is not None and hasattr(dit, "unload_lora"):
        try:
            dit.unload_lora()
        except Exception:
            pass
    gc.collect()
    if hasattr(torch, "mps") and torch.backends.mps.is_available():
        torch.mps.empty_cache()


def resolve_model_path(name, root, lokr_dir):
    if name == "none":
        return None
    if os.path.exists(name):
        return os.path.abspath(name)
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if name in ("dot2.1_ep40", "dot2.1_epoch40"):
        for sub in ("dot2-old/dot2.1", "dot2.1"):
            p = os.path.join(base_dir, "models", sub, "epoch40")
            if os.path.exists(p):
                return p
    if name.startswith("dot2.1_"):
        ep = name.replace("dot2.1_", "").replace("ep", "epoch")
        for sub in ("dot2-old/dot2.1", "dot2.1"):
            p = os.path.join(base_dir, "models", sub, ep)
            if os.path.exists(p):
                return p
    if name.startswith("dot2.2_"):
        ep = name.replace("dot2.2_", "").replace("ep", "epoch")
        for sub in ("dot2-old/dot2.2", "dot2.2"):
            p = os.path.join(base_dir, "models", sub, ep)
            if os.path.exists(p):
                return p
    if name.startswith("ep"):
        ep = name.replace("ep", "epoch")
        for sub in ("dot2-old/dot2.2", "dot2.2", "dot2-old/dot2.1", "dot2.1"):
            p = os.path.join(base_dir, "models", sub, ep)
            if os.path.exists(p):
                return p
    p = os.path.join(root, lokr_dir, name)
    if os.path.exists(p):
        return p
    return name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--suite",
        choices=["dual", "nhanhac", "cahue", "lynguao"],
        default="dual"
    )
    ap.add_argument(
        "--models",
        nargs="+",
        default=[
            "none", "dot2.1_ep40",
            "ep10", "ep20", "ep30", "ep40", "ep50",
            "ep60", "ep70", "ep80", "ep90", "ep100"
        ]
    )
    ap.add_argument("--out", default="storage/test_outputs/dot2_v2/dot2.1")
    ap.add_argument("--root", default=os.path.expanduser("~/ACE-Step-1.5"))
    ap.add_argument("--lokr_dir", default="lokr_output")
    ap.add_argument("--duration", type=int, default=120)
    ap.add_argument("--samples_per_prompt", type=int, default=2)
    ap.add_argument("--base_seed", type=int, default=42)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    cleanup_memory()

    dit = AceStepHandler()
    llm = LLMHandler()
    status, ok = dit.initialize_service(
        project_root=args.root,
        config_path="acestep-v15-base",
        device="mps",
        use_mlx_dit=False,
    )
    print("[INIT SERVICE]", status, flush=True)

    selected_suites = []
    if args.suite in ("dual", "nhanhac"):
        selected_suites.append("nhanhac")
    if args.suite in ("dual", "cahue"):
        selected_suites.append("cahue")
    if args.suite == "lynguao":
        selected_suites.append("lynguao")

    total_models = len(args.models)

    for idx, m in enumerate(args.models, 1):
        clean_name = m.replace("/", "_")
        print(f"\n=======================================================", flush=True)
        print(f"[{idx:02d}/{total_models:02d}] PROCESSING MODEL: {m}", flush=True)
        print(f"=======================================================", flush=True)

        cleanup_memory(dit)

        target_path = resolve_model_path(m, args.root, args.lokr_dir)
        if target_path:
            load_res = dit.load_lora(target_path)
            print(f"[MODEL LOAD] LoRA path: {target_path} -> {load_res}", flush=True)
        else:
            print(f"[MODEL LOAD] Clean Base Model (none - No LoRA)", flush=True)

        for suite_name in selected_suites:
            cfg_suite = PROMPTS[suite_name]
            mode_label = cfg_suite["mode_str"]

            for s_idx in range(1, args.samples_per_prompt + 1):
                dst_file = os.path.join(
                    args.out,
                    f"{idx:02d}_{clean_name}_{mode_label}_ban{s_idx}.mp3"
                )

                if os.path.exists(dst_file) and os.path.getsize(dst_file) > 10000:
                    print(f"  -> [SKIP - EXISTS] {dst_file}", flush=True)
                    continue

                curr_seed = args.base_seed + (s_idx - 1)
                print(f"  -> [GENERATE] {mode_label} (Ban {s_idx}/{args.samples_per_prompt}) | Seed={curr_seed} | Duration={args.duration}s...", flush=True)

                params = GenerationParams(
                    caption=cfg_suite["caption"],
                    lyrics=cfg_suite["lyrics"],
                    instrumental=cfg_suite["instrumental"],
                    vocal_language="vi",
                    duration=args.duration,
                    inference_steps=32,
                    guidance_scale=7.0,
                    shift=3.0,
                    seed=curr_seed,
                    task_type="text2music",
                    thinking=False,
                )
                cfg = GenerationConfig(batch_size=1, use_random_seed=False, audio_format="mp3")
                res = generate_music(dit, llm, params, cfg, save_dir=args.out)

                audios = getattr(res, "audios", []) or []
                if audios:
                    src = audios[0].get("path") or audios[0].get("audio_path") or audios[0].get("file")
                    if src and os.path.exists(src):
                        shutil.move(src, dst_file)
                        print(f"  -> [SUCCESS] Saved to {dst_file}", flush=True)

                cleanup_memory()

        cleanup_memory(dit)

    cleanup_memory(dit)
    print("\n[ALL COMPLETED] Successfully finished batch evaluation.", flush=True)


if __name__ == "__main__":
    main()
