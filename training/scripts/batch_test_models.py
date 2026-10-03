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
    "dannguyet": {
        "caption": (
            "Solo Dan Nguyet moon lute piece Luu Thuy, traditional Hue court music, "
            "flowing ornamental bends and tremolo techniques, elegant mood, "
            "authentic Vietnamese heritage, instrumental"
        ),
        "lyrics": "[Instrumental]",
        "instrumental": True,
        "mode_str": "dannguyet",
    },
    "kenbop": {
        "caption": (
            "Solo Ken Bop double-reed shawm melody, traditional Hue royal court music, "
            "melodic ornamentation, expressive sustained tones, solemn courtly atmosphere, "
            "authentic Vietnamese heritage, instrumental"
        ),
        "lyrics": "[Instrumental]",
        "instrumental": True,
        "mode_str": "kenbop",
    },
    "nhanhac": {
        "caption": (
            "Hue royal court music (Nha nhac), ceremonial court ensemble of dan nguyet moon "
            "lute, dan tam three-string lute, truc sao bamboo flute, dan bau monochord, "
            "ken bau oboe, trong chien and chanh bell drums, stately processional tempo, "
            "Nam ai pentatonic mode, dignified ritual atmosphere of the Nguyen dynasty court orchestra, "
            "UNESCO intangible heritage, authentic traditional Vietnamese palace music, instrumental"
        ),
        "lyrics": "[Instrumental]",
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
        for sub in ("dot2_v2/dot2.1", "dot2-old/dot2.1", "dot2.1"):
            p = os.path.join(base_dir, "models", sub, ep)
            if os.path.exists(p):
                return p
    if name.startswith("dot2.2_"):
        ep = name.replace("dot2.2_", "").replace("ep", "epoch")
        for sub in ("dot2_v2/dot2.2", "dot2-old/dot2.2", "dot2.2"):
            p = os.path.join(base_dir, "models", sub, ep)
            if os.path.exists(p):
                return p
    if name.startswith("ep"):
        ep = name.replace("ep", "epoch")
        for sub in ("dot2_v2/dot2.2", "dot2_v2/dot2.1", "dot2-old/dot2.2", "dot2.2", "dot2-old/dot2.1", "dot2.1"):
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
        choices=["instruments", "dannguyet", "kenbop", "dual", "nhanhac", "cahue", "lynguao"],
        default="dannguyet"
    )
    ap.add_argument(
        "--models",
        nargs="+",
        default=[
            "none",
            "ep5", "ep10", "ep15", "ep20", "ep25",
            "ep30", "ep35", "ep40", "ep45", "ep50"
        ]
    )
    ap.add_argument("--out", default="storage/test_outputs/dot2_v2/dot2.1")
    ap.add_argument("--root", default=os.path.expanduser("~/ACE-Step-1.5"))
    ap.add_argument("--lokr_dir", default="lokr_output")
    ap.add_argument("--duration", type=int, default=120)
    ap.add_argument("--samples_per_prompt", type=int, default=2)
    ap.add_argument("--base_seed", type=int, default=42)
    ap.add_argument("--src_audio", default=None)
    ap.add_argument("--cover_strength", type=float, default=0.75)
    ap.add_argument("--cover_noise_strength", type=float, default=0.5)
    ap.add_argument("--guidance_scale", type=float, default=4.0)
    ap.add_argument("--cfg_interval_start", type=float, default=0.0)
    ap.add_argument("--cfg_interval_end", type=float, default=1.0)
    ap.add_argument("--inference_steps", type=int, default=32)
    ap.add_argument("--sampler_mode", choices=["euler", "heun"], default="heun")
    ap.add_argument("--mlx_vae_chunk_size", type=int, default=1024)
    ap.add_argument("--use_mlx_dit", action="store_true", default=False)
    ap.add_argument("--task_type", choices=["text2music", "cover"], default="text2music")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    cleanup_memory()

    dit = AceStepHandler()
    llm = LLMHandler()
    status, ok = dit.initialize_service(
        project_root=args.root,
        config_path="acestep-v15-base",
        device="mps",
        use_mlx_dit=args.use_mlx_dit,
    )
    dit.mlx_vae_chunk_size = args.mlx_vae_chunk_size
    dit.use_mlx_vae = True
    print("[INIT SERVICE]", status, flush=True)

    selected_suites = []
    if args.suite == "dannguyet":
        selected_suites.append("dannguyet")
    elif args.suite == "kenbop":
        selected_suites.append("kenbop")
    elif args.suite == "instruments":
        selected_suites.extend(["dannguyet", "kenbop"])
    elif args.suite in ("dual", "nhanhac"):
        selected_suites.append("nhanhac")
    if args.suite in ("dual", "cahue"):
        selected_suites.append("cahue")
    if args.suite == "lynguao":
        selected_suites.append("lynguao")

    total_models = len(args.models)

    for idx, m in enumerate(args.models, 1):
        clean_name = os.path.basename(m.rstrip("/")) if ("/" in m and not m.startswith("none")) else m.replace("/", "_")
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
                suffix = "cover" if args.src_audio or args.task_type == "cover" else "gen"
                sub_out = os.path.join(args.out, clean_name)
                os.makedirs(sub_out, exist_ok=True)
                dst_file = os.path.join(
                    sub_out,
                    f"{idx:02d}_{clean_name}_{mode_label}_{suffix}_ban{s_idx}.mp3"
                )

                if os.path.exists(dst_file) and os.path.getsize(dst_file) > 10000:
                    print(f"  -> [SKIP - EXISTS] {dst_file}", flush=True)
                    continue

                curr_seed = args.base_seed + (s_idx - 1)
                eff_task = "cover" if args.src_audio or args.task_type == "cover" else "text2music"
                print(f"  -> [GENERATE] {mode_label} [{eff_task}] (Ban {s_idx}/{args.samples_per_prompt}) | Seed={curr_seed} | Duration={args.duration}s...", flush=True)

                params = GenerationParams(
                    caption=cfg_suite["caption"],
                    lyrics=cfg_suite["lyrics"],
                    instrumental=cfg_suite["instrumental"],
                    vocal_language="vi",
                    duration=args.duration,
                    inference_steps=args.inference_steps,
                    guidance_scale=args.guidance_scale,
                    cfg_interval_start=args.cfg_interval_start,
                    cfg_interval_end=args.cfg_interval_end,
                    shift=3.0,
                    seed=curr_seed,
                    task_type=eff_task,
                    src_audio=args.src_audio,
                    audio_cover_strength=args.cover_strength,
                    cover_noise_strength=args.cover_noise_strength,
                    sampler_mode=args.sampler_mode,
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
