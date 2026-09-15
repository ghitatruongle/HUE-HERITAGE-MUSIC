import xml.etree.ElementTree as ET

NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
DIVISIONS = 480
BEATS_PER_BAR = 4
TYPES = {4.0: "whole", 2.0: "half", 1.0: "quarter", 0.5: "eighth", 0.25: "16th",
         6.0: "whole", 3.0: "half", 1.5: "quarter", 0.75: "eighth", 0.375: "16th"}
DOTTED = {6.0, 3.0, 1.5, 0.75, 0.375}


def midi_to_step(midi):
    name = NAMES[midi % 12]
    step = name[0]
    alter = 1 if len(name) > 1 else 0
    octave = midi // 12 - 1
    return step, alter, octave


def seconds_to_beats(notes, bpm):
    b = bpm if bpm > 0 else 60.0
    out = []
    for nt in notes:
        out.append({
            "midi": nt["midi"],
            "start": nt["start"] * b / 60.0,
            "end": nt["end"] * b / 60.0,
        })
    return out


def duration_type(beats):
    for key in sorted(TYPES.keys(), reverse=True):
        if abs(beats - key) < 0.0001:
            return TYPES[key], key in DOTTED
    return None, False


def append_rest(m, dur_div):
    if dur_div <= 0:
        return
    n = ET.SubElement(m, "note")
    ET.SubElement(n, "rest")
    ET.SubElement(n, "duration").text = str(dur_div)
    t, dots = duration_type(dur_div / DIVISIONS)
    if t:
        ET.SubElement(n, "type").text = t
        for _ in range(1 if dots else 0):
            ET.SubElement(n, "dot")


def split_bars(notes):
    bars = []
    cur = []
    idx = 0
    for nt in notes:
        s = nt["start"]
        e = nt["end"]
        while (idx + 1) * BEATS_PER_BAR <= s + 0.000001:
            bars.append(cur)
            cur = []
            idx += 1
        while s < e - 0.000001:
            edge = (idx + 1) * BEATS_PER_BAR
            cut = e if e <= edge else edge
            cur.append({"midi": nt["midi"], "pos": s - idx * BEATS_PER_BAR, "dur": cut - s})
            s = cut
            if s >= edge - 0.000001:
                bars.append(cur)
                cur = []
                idx += 1
    if cur:
        bars.append(cur)
    if not bars:
        bars.append([])
    return bars


def build_musicxml(notes, bpm, title):
    bnotes = seconds_to_beats(notes, bpm)
    bars = split_bars(bnotes)
    score = ET.Element("score-partwise", version="3.1")
    work = ET.SubElement(score, "work")
    ET.SubElement(work, "work-title").text = title
    plist = ET.SubElement(score, "part-list")
    sp = ET.SubElement(plist, "score-part", id="P1")
    ET.SubElement(sp, "part-name").text = "Hue"
    part = ET.SubElement(score, "part", id="P1")
    for bi, bar in enumerate(bars):
        m = ET.SubElement(part, "measure", number=str(bi + 1))
        if bi == 0:
            attr = ET.SubElement(m, "attributes")
            ET.SubElement(attr, "divisions").text = str(DIVISIONS)
            key = ET.SubElement(attr, "key")
            ET.SubElement(key, "fifths").text = "0"
            tm = ET.SubElement(attr, "time")
            ET.SubElement(tm, "beats").text = str(BEATS_PER_BAR)
            ET.SubElement(tm, "beat-type").text = "4"
            clef = ET.SubElement(attr, "clef")
            ET.SubElement(clef, "sign").text = "G"
            ET.SubElement(clef, "line").text = "2"
        used = 0
        bar_len = DIVISIONS * BEATS_PER_BAR
        if not bar:
            append_rest(m, bar_len)
            continue
        by_onset = {}
        for nt in bar:
            key = int(round(nt["pos"] * DIVISIONS))
            by_onset.setdefault(key, []).append(nt)
        for pos_div in sorted(by_onset):
            if pos_div > used:
                append_rest(m, min(pos_div, bar_len) - used)
                used = pos_div
            if used >= bar_len:
                break
            chord = by_onset[pos_div]
            for ci, nt in enumerate(chord):
                step, alter, octave = midi_to_step(nt["midi"])
                dur = max(1, int(round(nt["dur"] * DIVISIONS)))
                if used + dur > bar_len:
                    dur = bar_len - used
                n = ET.SubElement(m, "note")
                if ci > 0:
                    ET.SubElement(n, "chord")
                p = ET.SubElement(n, "pitch")
                ET.SubElement(p, "step").text = step
                if alter:
                    ET.SubElement(p, "alter").text = "1"
                ET.SubElement(p, "octave").text = str(octave)
                ET.SubElement(n, "duration").text = str(dur)
                t, dots = duration_type(dur / DIVISIONS)
                if t:
                    ET.SubElement(n, "type").text = t
                    for _ in range(1 if dots else 0):
                        ET.SubElement(n, "dot")
            used += max(1, int(round(max(nt["dur"] for nt in chord) * DIVISIONS)))
            if used > bar_len:
                used = bar_len
        remain = bar_len - used
        if remain > 0:
            append_rest(m, remain)
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(score, encoding="unicode")
