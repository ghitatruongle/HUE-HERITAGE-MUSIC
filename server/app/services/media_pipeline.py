from ..ai import basic_pitch_amt as bp_amt
from ..audio_dsp import post_quantizer
from ..storage import manager
from . import amt_service, midi_service, musicxml_service, pitch_service, restoration_service


def extract_notes(data, bpm, engine="basic_pitch"):
    samples, sr = pitch_service.read_mono_wav(data, max_seconds=300.0)
    used = "dsp"
    engine_error = None
    notes = None
    if engine == "basic_pitch" and bp_amt.available():
        try:
            notes = bp_amt.transcribe(samples, sr)
            used = "basic_pitch"
        except Exception as e:
            notes = None
            engine_error = str(e)
    elif engine == "basic_pitch":
        engine_error = "basic_pitch unavailable"
    if notes is None:
        times, f0s = pitch_service.estimate_f0(samples, sr)
        notes = amt_service.segment_notes(times, f0s)
    return post_quantizer.quantize(notes, bpm), used, engine_error


def write_artifacts(data, notes, bpm, source_stem):
    digest = manager.sha256_bytes(data)
    stem = f"{digest}_{int(bpm)}"
    mid = manager.midi_dir() / (stem + ".mid")
    mid.write_bytes(midi_service.write_midi(notes, bpm))
    xm = manager.xml_dir() / (stem + ".musicxml")
    xm.write_text(musicxml_service.build_musicxml(notes, bpm, source_stem), encoding="utf-8")
    return digest, stem, mid, xm


def restore_audio(data):
    out, report = restoration_service.restore(data)
    digest = manager.sha256_bytes(data)
    dest = manager.restored_dir() / (digest + "_restored.wav")
    if not dest.exists():
        dest.write_bytes(out)
    report["sha"] = digest
    return report, dest
