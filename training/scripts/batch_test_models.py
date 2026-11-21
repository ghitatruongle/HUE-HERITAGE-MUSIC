import argparse
import gc
import json
import os
import shutil
import tempfile
import torch

os.environ["PYTORCH_MPS_HIGH_WATERMARK_RATIO"] = "0.0"

from acestep.handler import AceStepHandler
from acestep.llm_inference import LLMHandler
from acestep.inference import GenerationConfig, GenerationParams, generate_music

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROUND_SUBDIRS = {
    "dot2.1": ("dot2_v2/dot2.1", "dot2-old/dot2.1", "dot2.1"),
    "dot2.2": ("dot2_v2/dot2.2", "dot2-old/dot2.2", "dot2.2"),
    "dot2.3": ("dot2_v2/dot2.3", "dot2.3"),
}
CAHUE_DATASET_DIR = os.path.join(BASE_DIR, "datasets", "dot2_v2", "dot2.3", "ca_hue")
CAHUE_DEFAULT_CAPTION = (
    "Vietnamese Hue folk singing (Ca Hue), expressive solo vocal in Vietnamese with "
    "melismatic ornaments and vocables, accompanied by dan nguyet moon lute, dan tranh zither, "
    "dan nhi fiddle, sao truc bamboo flute and song loan clapper, Nam or Bac pentatonic mode, "
    "intimate traditional chamber atmosphere, authentic Hue heritage music"
)
WEIGHTS_FILE = "lokr_weights.safetensors"
EMA_WEIGHTS_FILE = "lokr_weights_ema.safetensors"

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


def _round_epoch_path(round_name, epoch_dir):
    for sub in ROUND_SUBDIRS[round_name]:
        p = os.path.join(BASE_DIR, "models", sub, epoch_dir)
        if os.path.exists(p):
            return p
    return None


def _epoch_dir_name(token):
    return token.replace("epoch", "ep").replace("ep", "epoch")


def resolve_model_path(name, root, lokr_dir):
    if name == "none":
        return None
    if os.path.exists(name):
        return os.path.abspath(name)
    if name in ("dot2.1_ep40", "dot2.1_epoch40"):
        for sub in ("dot2-old/dot2.1", "dot2.1"):
            p = os.path.join(BASE_DIR, "models", sub, "epoch40")
            if os.path.exists(p):
                return p
    for round_name in ROUND_SUBDIRS:
        prefix = round_name + "_"
        if name.startswith(prefix):
            p = _round_epoch_path(round_name, _epoch_dir_name(name[len(prefix):]))
            if p:
                return p
            raise FileNotFoundError(f"Checkpoint not found for {name}")
    if name.startswith("ep"):
        ep = _epoch_dir_name(name)
        found = {}
        for round_name in ROUND_SUBDIRS:
            p = _round_epoch_path(round_name, ep)
            if p:
                found[round_name] = p
        if len(found) > 1:
            options = ", ".join(f"{r}_{name}" for r in found)
            raise ValueError(f"Ambiguous model name '{name}' exists in several rounds; use one of: {options}")
        if found:
            return next(iter(found.values()))
    p = os.path.join(root, lokr_dir, name)
    if os.path.exists(p):
        return p
    return name


def apply_weights_variant(path, variant, tmp_root):
    if not path or variant == "main":
        return path
    src_dir = path if os.path.isdir(path) else os.path.dirname(path)
    ema_file = os.path.join(src_dir, EMA_WEIGHTS_FILE)
    if not os.path.isfile(ema_file):
        raise FileNotFoundError(f"EMA weights not found: {ema_file}")
    link_dir = os.path.join(tmp_root, os.path.basename(os.path.normpath(src_dir)) + "_ema")
    os.makedirs(link_dir, exist_ok=True)
    link = os.path.join(link_dir, WEIGHTS_FILE)
    if os.path.lexists(link):
        os.remove(link)
    os.symlink(os.path.abspath(ema_file), link)
    return link_dir


def _read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip()


def _read_json(path):
    if not path or not os.path.isfile(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}


def _vocal_suite(mode_str, caption, lyrics, meta):
    lyrics = (lyrics or "").strip()
    if not lyrics or lyrics == "[Instrumental]":
        raise ValueError(f"Suite {mode_str} needs real lyrics, got empty or [Instrumental]")
    bpm = meta.get("bpm")
    return {
        "caption": caption,
        "lyrics": lyrics,
        "instrumental": False,
        "mode_str": mode_str,
        "language": meta.get("language") or "vi",
        "bpm": int(bpm) if isinstance(bpm, (int, float)) and bpm > 0 else None,
        "keyscale": meta.get("keyscale") or "",
        "timesignature": str(meta.get("timesignature") or ""),
    }


def build_cahue_train_suites(dataset_dir, songs):
    if not songs:
        songs = sorted(
            os.path.splitext(f)[0]
            for f in os.listdir(dataset_dir)
            if f.endswith(".wav") and os.path.isfile(os.path.join(dataset_dir, os.path.splitext(f)[0] + ".lyrics.txt"))
        )
    if not songs:
        raise FileNotFoundError(f"No songs with .lyrics.txt found in {dataset_dir}")
    suites = {}
    for song in songs:
        song = os.path.splitext(os.path.basename(song))[0]
        lyrics_path = os.path.join(dataset_dir, song + ".lyrics.txt")
        if not os.path.isfile(lyrics_path):
            raise FileNotFoundError(f"Missing lyrics for {song}: {lyrics_path}")
        meta = _read_json(os.path.join(dataset_dir, song + ".json"))
        caption = (meta.get("caption") or "").strip() or CAHUE_DEFAULT_CAPTION
        key = f"cahue_train_{song}"
        suites[key] = _vocal_suite(key, caption, _read_text(lyrics_path), meta)
    return suites


def build_cahue_moi_suites(lyrics_files, lyrics_map, caption_override):
    entries = []
    if lyrics_map:
        data = _read_json(lyrics_map)
        base = os.path.dirname(os.path.abspath(lyrics_map))
        for name, item in data.items():
            if isinstance(item, str):
                item = {"lyrics_file": item}
            path = item.get("lyrics_file")
            if item.get("lyrics"):
                lyrics = item["lyrics"]
            elif path:
                lyrics = _read_text(path if os.path.isabs(path) else os.path.join(base, path))
            else:
                lyrics = ""
            entries.append((name, lyrics, item))
    for path in lyrics_files or []:
        name = os.path.basename(path).split(".")[0]
        meta = _read_json(os.path.join(os.path.dirname(path), name + ".json"))
        entries.append((name, _read_text(path), meta))
    if not entries:
        raise ValueError("cahue_moi needs --lyrics_file or --lyrics_map")
    suites = {}
    for name, lyrics, meta in entries:
        caption = caption_override or (meta.get("caption") or "").strip() or CAHUE_DEFAULT_CAPTION
        key = f"cahue_moi_{name}"
        suites[key] = _vocal_suite(key, caption, lyrics, meta)
    return suites


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--suite",
        choices=["instruments", "dannguyet", "kenbop", "dual", "nhanhac", "cahue", "lynguao", "cahue_train", "cahue_moi", "dot2_3"],
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
    ap.add_argument("--weights_variant", choices=["main", "ema"], default="main")
    ap.add_argument("--dataset_dir", default=CAHUE_DATASET_DIR)
    ap.add_argument("--train_songs", nargs="*", default=None)
    ap.add_argument("--lyrics_file", nargs="*", default=None)
    ap.add_argument("--lyrics_map", default=None)
    ap.add_argument("--caption", default=None)
    ap.add_argument("--dry_run", action="store_true", default=False)
    args = ap.parse_args()

    prompts = dict(PROMPTS)
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
    if args.suite in ("cahue_train", "dot2_3"):
        extra = build_cahue_train_suites(args.dataset_dir, args.train_songs)
        prompts.update(extra)
        selected_suites.extend(extra.keys())
    if args.suite == "cahue_moi" or (args.suite == "dot2_3" and (args.lyrics_file or args.lyrics_map)):
        extra = build_cahue_moi_suites(args.lyrics_file, args.lyrics_map, args.caption)
        prompts.update(extra)
        selected_suites.extend(extra.keys())

    resolved_models = [(m, resolve_model_path(m, args.root, args.lokr_dir)) for m in args.models]
    tmp_root = tempfile.mkdtemp(prefix="lokr_variant_")
    try:
        resolved_models = [(m, apply_weights_variant(p, args.weights_variant, tmp_root)) for m, p in resolved_models]
    except Exception:
        shutil.rmtree(tmp_root, ignore_errors=True)
        raise

    if args.dry_run:
        for m, p in resolved_models:
            print(f"[MODEL] {m} -> {p}", flush=True)
        for name in selected_suites:
            s = prompts[name]
            print(
                f"[SUITE] {name} | instrumental={s['instrumental']} | lang={s.get('language', 'vi')} | "
                f"bpm={s.get('bpm')} | key={s.get('keyscale', '')} | lyrics_lines={len(s['lyrics'].splitlines())}",
                flush=True,
            )
            print(f"        caption: {s['caption'][:160]}", flush=True)
        shutil.rmtree(tmp_root, ignore_errors=True)
        return

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

    total_models = len(resolved_models)
    variant_tag = "_ema" if args.weights_variant == "ema" else ""

    try:
        for idx, (m, target_path) in enumerate(resolved_models, 1):
            clean_name = os.path.basename(m.rstrip("/")) if ("/" in m and not m.startswith("none")) else m.replace("/", "_")
            if target_path:
                clean_name += variant_tag
            print(f"\n=======================================================", flush=True)
            print(f"[{idx:02d}/{total_models:02d}] PROCESSING MODEL: {m}", flush=True)
            print(f"=======================================================", flush=True)

            cleanup_memory(dit)

            if target_path:
                load_res = dit.load_lora(target_path)
                print(f"[MODEL LOAD] LoRA path: {target_path} -> {load_res}", flush=True)
            else:
                print(f"[MODEL LOAD] Clean Base Model (none - No LoRA)", flush=True)

            for suite_name in selected_suites:
                cfg_suite = prompts[suite_name]
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
                        vocal_language=cfg_suite.get("language", "vi"),
                        bpm=cfg_suite.get("bpm"),
                        keyscale=cfg_suite.get("keyscale", ""),
                        timesignature=cfg_suite.get("timesignature", ""),
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
    finally:
        cleanup_memory(dit)
        shutil.rmtree(tmp_root, ignore_errors=True)
    print("\n[ALL COMPLETED] Successfully finished batch evaluation.", flush=True)


if __name__ == "__main__":
    main()
