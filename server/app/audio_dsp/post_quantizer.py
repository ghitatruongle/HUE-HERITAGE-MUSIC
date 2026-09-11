def quantize(notes, bpm):
    beat = 60.0 / bpm if bpm > 0 else 1.0
    grid = beat / 4.0
    out = []
    for nt in notes:
        s = round(nt["start"] / grid) * grid
        e = round(nt["end"] / grid) * grid
        if e - s < grid / 2:
            e = s + grid
        out.append({
            "midi": nt["midi"],
            "freq": nt["freq"],
            "start": round(s, 3),
            "end": round(e, 3),
            "velocity": nt["velocity"],
        })
    out.sort(key=lambda x: (x["start"], x["midi"]))
    merged = []
    for nt in out:
        if merged and nt["midi"] == merged[-1]["midi"] and nt["start"] <= merged[-1]["end"] + 0.001:
            if nt["end"] > merged[-1]["end"]:
                merged[-1]["end"] = nt["end"]
        else:
            merged.append(nt)
    return merged
